import CoreGraphics
import CoreML
import XCTest
@testable import WithoutBGCore

final class StrokeEditTests: XCTestCase {
    private func fixture(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/edit/\(name)", withExtension: "png"))
        return try XCTUnwrap(ImageUtilities.cgImage(from: url))
    }

    func testCombineRemoveWins() {
        let s = StrokeEdit.combine(keep: [true, true, false], remove: [false, true, false], count: 3)
        XCTAssertEqual(s, [StrokeEdit.keep, StrokeEdit.remove, StrokeEdit.untouched])
        XCTAssertEqual(StrokeEdit.netClamp(s), [StrokeEdit.untouched, StrokeEdit.remove, StrokeEdit.untouched])
    }

    func testDilateIsSquare() {
        var m = [Bool](repeating: false, count: 49)
        m[3 * 7 + 3] = true
        let d = StrokeEdit.dilate(m, width: 7, height: 7, radius: 2)
        XCTAssertEqual(d.filter { $0 }.count, 25)
        XCTAssertTrue(d[1 * 7 + 1] && d[5 * 7 + 5] && !d[0])
    }

    func testLabelsAreEightConnected() {
        // Two diagonal pixels touch (8-connected); a far one does not.
        let m: [Bool] = [true, false, false, false,
                         false, true, false, true]
        let l = StrokeEdit.labels(m, width: 4, height: 2)
        XCTAssertEqual(l[0], l[5])
        XCTAssertNotEqual(l[0], l[7])
        XCTAssertEqual(l[1], 0)
    }

    func testDistanceMatchesOpenCVChamfer() {
        // cv2.distanceTransform(DIST_L2, 5) on a 5×7 ones image with one zero at (2, 3).
        var m = [Bool](repeating: true, count: 35)
        m[2 * 7 + 3] = false
        let d = StrokeEdit.distanceInside(m, width: 7, height: 5)
        let expected: [Float] = [3.597, 2.8, 2.197, 2, 2.197, 2.8, 3.597,
                                 3.197, 2.197, 1.4, 1, 1.4, 2.197, 3.197,
                                 3, 2, 1, 0, 1, 2, 3]
        for (i, e) in expected.enumerated() { XCTAssertEqual(d[i], e, accuracy: 1e-3) }
    }

    func testMarksReadLightOpaquePixels() throws {
        let marks = try XCTUnwrap(ImageUtilities.maskMarks(try fixture("remove"), width: 320, height: 240))
        XCTAssertEqual(marks.filter { $0 }.count, 30 * 80)
        XCTAssertNil(ImageUtilities.maskMarks(try fixture("remove"), width: 10, height: 10))
    }

    /// Core ML edit vs the Python SDK (ONNX) on the same inputs.
    func testBundledEditMatchesPythonSDK() async throws {
        let processor = CoreMLProcessor()
        XCTAssertTrue(processor.supportsEdit)
        let image = try fixture("image")
        let keep = ImageUtilities.maskMarks(try fixture("keep"), width: 320, height: 240)
        let remove = ImageUtilities.maskMarks(try fixture("remove"), width: 320, height: 240)
        let result = try await processor.edit(preparedImage: image, keep: keep, remove: remove,
                                              matte: try fixture("matte"))
        XCTAssertEqual(result.route?.pipeline, "edit")
        let got = try XCTUnwrap(ImageUtilities.grayPixels(result.alphaMatte, width: 320, height: 240))
        let want = try XCTUnwrap(ImageUtilities.grayPixels(try fixture("expected"), width: 320, height: 240))
        let diffs = zip(got, want).map { abs(Int($0) - Int($1)) }
        let mae = Double(diffs.reduce(0, +)) / Double(diffs.count)
        let bad = diffs.filter { $0 > 8 }.count
        XCTAssertLessThan(mae, 0.5, "MAE \(mae)")
        XCTAssertLessThan(Double(bad) / Double(diffs.count), 0.002, "\(bad) pixels off by > 8")
        // Remove strokes are clamped to 0.
        for y in 100..<130 { for x in 10..<90 { XCTAssertEqual(got[y * 320 + x], 0) } }
    }

    // MARK: - Edit context

    func testEditContextTokenRoundTrip() throws {
        let size = 448
        let depth = (0..<(size * size)).map { Float(($0 * 7919) % 10007) / 10007 }
        let ctx = EditContext(category: "hard_opaque", fingerprint: "0123456789abcdef", depth: depth, size: size)
        let token = try XCTUnwrap(ctx.token)
        XCTAssertTrue(token.hasPrefix("wbgctx1.hard_opaque.0123456789abcdef."))
        let back = try XCTUnwrap(EditContext(token: token, categories: ["fine_strand", "hard_opaque"], size: size))
        XCTAssertEqual(back.category, "hard_opaque")
        XCTAssertEqual(back.fingerprint, "0123456789abcdef")
        let err = zip(back.depth, depth).map { abs($0 - $1) }.max() ?? 1
        XCTAssertLessThanOrEqual(err, 0.5 / 65535 + 1e-6)
        XCTAssertNil(EditContext(token: token, categories: ["fine_strand"], size: size))
        XCTAssertNil(EditContext(token: token, categories: ["hard_opaque"], size: 64))
        XCTAssertNil(EditContext(token: "garbage", categories: ["hard_opaque"], size: size))
        XCTAssertNil(EditContext(token: "wbgctx1.hard_opaque.0123456789abcdef.!!", categories: ["hard_opaque"], size: size))
    }

    private final class CountingGraph: RoutedGraph {
        let inner: RoutedGraph
        let name: String
        let counts: Counts
        init(_ inner: RoutedGraph, _ name: String, _ counts: Counts) {
            (self.inner, self.name, self.counts) = (inner, name, counts)
        }
        func prediction(from input: MLFeatureProvider, options: MLPredictionOptions) throws -> MLFeatureProvider {
            counts.values[name, default: 0] += 1
            return try inner.prediction(from: input, options: options)
        }
    }

    private final class Counts { var values: [String: Int] = [:] }

    /// Bundled Core ML pipeline with every graph call counted.
    private func countingPipeline() throws -> (RoutedPipeline, Counts) {
        let root = try XCTUnwrap(WithoutBGCoreResources.bundle.resourceURL).resolvingSymlinksInPath()
        let manifest = try RoutedManifest.load(from: root)
        let cache = CompiledModelCache()
        let counts = Counts()
        let pipeline = RoutedPipeline(manifest: manifest) { graph in
            let (file, sha) = switch graph {
            case .router: (manifest.router.file, manifest.router.sha256)
            case .coarse: (manifest.coarse.file, manifest.coarse.sha256)
            case .birefnet: (manifest.birefnet.file, manifest.birefnet.sha256)
            case .strokeEdit: (manifest.stroke_edit!.file, manifest.stroke_edit!.sha256)
            }
            let model = try cache.model(package: root.appendingPathComponent(file), sha256: sha)
            return CountingGraph(model, graph.rawValue, counts)
        }
        return (pipeline, counts)
    }

    func testBundledEditWithContextRunsOnlyStrokeEdit() throws {
        let (pipeline, counts) = try countingPipeline()
        let image = try fixture("image")
        let keep = ImageUtilities.maskMarks(try fixture("keep"), width: 320, height: 240)
        let remove = ImageUtilities.maskMarks(try fixture("remove"), width: 320, height: 240)
        let matte = try XCTUnwrap(ImageUtilities.grayPixels(try fixture("matte"), width: 320, height: 240))

        let first = try pipeline.edit(image, keep: keep, remove: remove, matte: matte)
        XCTAssertEqual(counts.values["router"], 1)
        XCTAssertEqual(counts.values["coarse"], 1)
        let ctx = try XCTUnwrap(first.editContext)
        XCTAssertEqual(ctx.category, first.route?.category)

        // Through the token, as the Local API does.
        let token = try XCTUnwrap(ctx.token)
        let manifest = pipeline.manifest
        let parsed = try XCTUnwrap(EditContext(token: token, categories: manifest.router.categories,
                                               size: manifest.stroke_edit!.size))
        counts.values = [:]
        let second = try pipeline.edit(image, keep: keep, remove: remove, matte: matte, context: parsed)
        XCTAssertEqual(counts.values, ["strokeEdit": 1])
        XCTAssertEqual(second.editContext?.fingerprint, ctx.fingerprint)
        XCTAssertEqual(second.route, first.route)
        let a = try XCTUnwrap(ImageUtilities.grayPixels(first.alphaMatte, width: 320, height: 240))
        let b = try XCTUnwrap(ImageUtilities.grayPixels(second.alphaMatte, width: 320, height: 240))
        XCTAssertLessThanOrEqual(zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 0, 1)

        // Stale (other image's fingerprint) and matte-less edits recompute.
        counts.values = [:]
        let stale = EditContext(category: ctx.category, fingerprint: "0000000000000000", depth: ctx.depth, size: ctx.size)
        let third = try pipeline.edit(image, keep: keep, remove: remove, matte: matte, context: stale)
        XCTAssertEqual(counts.values["router"], 1)
        XCTAssertEqual(third.editContext?.fingerprint, ctx.fingerprint)
        counts.values = [:]
        _ = try pipeline.edit(image, keep: keep, remove: remove, matte: nil, context: ctx)
        XCTAssertEqual(counts.values["router"], 1)
    }
}

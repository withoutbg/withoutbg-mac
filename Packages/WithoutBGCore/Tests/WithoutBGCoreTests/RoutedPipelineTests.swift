import CoreGraphics
import CoreML
import XCTest
@testable import WithoutBGCore

/// Pipeline logic with stub graphs: routing, feature reuse, validation, sizes.
final class RoutedPipelineTests: XCTestCase {
    private final class StubGraph: RoutedGraph {
        var inputs: [MLFeatureProvider] = []
        let respond: (MLFeatureProvider) throws -> [String: MLFeatureValue]

        init(_ respond: @escaping (MLFeatureProvider) throws -> [String: MLFeatureValue]) {
            self.respond = respond
        }

        func prediction(from input: MLFeatureProvider, options: MLPredictionOptions) throws -> MLFeatureProvider {
            inputs.append(input)
            return try MLDictionaryFeatureProvider(dictionary: respond(input))
        }
    }

    private struct Harness {
        let pipeline: RoutedPipeline
        let router: StubGraph
        let coarse: StubGraph
        let birefnet: StubGraph
        let features: [String: MLFeatureValue]
    }

    private static func array(_ shape: [Int], fill: Float) -> MLMultiArray {
        let array = try! MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
        array.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
            for i in buffer.indices { buffer[i] = fill }
        }
        return array
    }

    private func harness(logits: [Float], alphaShape: [Int]? = nil, alpha: Float = 1) -> Harness {
        let features = Dictionary(uniqueKeysWithValues: ["f0", "f1", "f2", "f3"].map {
            ($0, MLFeatureValue(multiArray: Self.array([1, 2, 2, 2], fill: 0.5)))
        })
        let logitsArray = Self.array([1, logits.count], fill: 0)
        for (i, value) in logits.enumerated() { logitsArray[i] = NSNumber(value: value) }
        let router = StubGraph { _ in features.merging(["route_logits": MLFeatureValue(multiArray: logitsArray)]) { a, _ in a } }
        let coarse = StubGraph { _ in
            ["coarse_alpha": MLFeatureValue(multiArray: Self.array(alphaShape ?? [1, 1, 16, 16], fill: alpha))]
        }
        let birefnet = StubGraph { _ in
            ["alpha": MLFeatureValue(multiArray: Self.array(alphaShape ?? [1, 1, 32, 32], fill: alpha))]
        }
        let pipeline = RoutedPipeline(manifest: TestManifest.manifest()) { graph in
            switch graph {
            case .router: router
            case .coarse: coarse
            case .birefnet: birefnet
            }
        }
        return Harness(pipeline: pipeline, router: router, coarse: coarse, birefnet: birefnet, features: features)
    }

    private func image(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    func testEachCategoryRunsOnlyItsBranch() throws {
        for (index, category) in TestManifest.categories.enumerated() {
            var logits = [Float](repeating: 0, count: 6)
            logits[index] = 5
            let h = harness(logits: logits)
            let result = try h.pipeline.process(image(width: 40, height: 30))
            let expected = TestManifest.birefnetCategories.contains(category) ? "birefnet" : "matting"
            XCTAssertEqual(result.route, RouteDecision(category: category, pipeline: expected))
            XCTAssertEqual(h.router.inputs.count, 1)
            XCTAssertEqual(h.coarse.inputs.count, expected == "matting" ? 1 : 0, category)
            XCTAssertEqual(h.birefnet.inputs.count, expected == "birefnet" ? 1 : 0, category)
        }
    }

    func testMattingReusesRouterInputAndFeatures() throws {
        let h = harness(logits: [3, 0, 0, 0, 0, 0])
        _ = try h.pipeline.process(image(width: 40, height: 30))
        let routerInput = try XCTUnwrap(h.router.inputs.first?.featureValue(for: "rgb_matting")?.multiArrayValue)
        let coarseInput = try XCTUnwrap(h.coarse.inputs.first)
        XCTAssertTrue(coarseInput.featureValue(for: "rgb_matting")?.multiArrayValue === routerInput)
        for (name, value) in h.features {
            XCTAssertTrue(coarseInput.featureValue(for: name)?.multiArrayValue === value.multiArrayValue, name)
        }
        let depth = try XCTUnwrap(coarseInput.featureValue(for: "rgb_depth")?.multiArrayValue)
        XCTAssertEqual(depth.shape, [1, 3, 18, 18])
        XCTAssertEqual(routerInput.shape, [1, 3, 16, 16])
    }

    func testTieGoesToFirstCategory() throws {
        let h = harness(logits: [0, 0, 0, 7, 7, 0])
        XCTAssertEqual(try h.pipeline.process(image(width: 20, height: 20)).route?.category, "hard_opaque")
    }

    func testRejectsInvalidOutputs() throws {
        let img = try image(width: 20, height: 20)
        XCTAssertThrowsError(try harness(logits: [0, .nan, 0, 0, 0, 0]).pipeline.process(img))
        XCTAssertThrowsError(try harness(logits: [0, 1, 0]).pipeline.process(img))
        XCTAssertThrowsError(try harness(logits: [1, 0, 0, 0, 0, 0], alphaShape: [1, 1, 8, 8]).pipeline.process(img))
        XCTAssertThrowsError(try harness(logits: [1, 0, 0, 0, 0, 0], alpha: .infinity).pipeline.process(img))
    }

    func testLargeImageIsFittedAndMatteKeepsOriginalSize() throws {
        let h = harness(logits: [0, 0, 0, 0, 0, 1], alpha: 0.5)
        let result = try h.pipeline.process(image(width: 500, height: 30))
        XCTAssertEqual(result.alphaMatte.width, 500)
        XCTAssertEqual(result.alphaMatte.height, 30)
        XCTAssertEqual(result.processed.width, 500)
        let data = try XCTUnwrap(result.alphaMatte.dataProvider?.data as Data?)
        XCTAssertEqual(data.first, 128) // clip(0.5 * 255 + 0.5) = 128
    }
}

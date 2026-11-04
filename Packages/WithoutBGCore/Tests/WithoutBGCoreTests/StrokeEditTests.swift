import CoreGraphics
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
}

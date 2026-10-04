import CoreGraphics
import CoreML
import XCTest
@testable import WithoutBGCore

/// Opt-in end-to-end parity against the Python SDK on the published ONNX bundle.
/// Generate references with model-pro `scripts/make_mac_parity_reference.py`, then
/// run with `WBG_PARITY_DIR=<output> swift test --filter RoutedParityTests`.
final class RoutedParityTests: XCTestCase {
    private struct Route: Decodable {
        let category: String
        let pipeline: String
    }

    func testMatchesPythonSDKOnCPU() async throws {
        try await check(computeUnits: .cpuOnly)
    }

    func testMatchesPythonSDKOnAllComputeUnits() async throws {
        try await check(computeUnits: .all)
    }

    private func check(computeUnits: MLComputeUnits) async throws {
        guard let dir = ProcessInfo.processInfo.environment["WBG_PARITY_DIR"] else {
            throw XCTSkip("Set WBG_PARITY_DIR to run SDK parity.")
        }
        let root = URL(fileURLWithPath: dir)
        let routes = try JSONDecoder().decode(
            [String: Route].self, from: Data(contentsOf: root.appendingPathComponent("routes.json"))
        )
        let processor = CoreMLProcessor(computeUnits: computeUnits)
        for name in routes.keys.sorted() {
            let expected = routes[name]!
            let image = try XCTUnwrap(ImageUtilities.cgImage(from: root.appendingPathComponent(name)), name)
            let stem = (name as NSString).deletingPathExtension
            let reference = try XCTUnwrap(
                ImageUtilities.cgImage(from: root.appendingPathComponent("\(stem).matte.png")), name
            )
            let start = Date()
            let result = try await processor.process(preparedImage: image)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            XCTAssertEqual(result.route, RouteDecision(category: expected.category, pipeline: expected.pipeline), name)

            let a = try gray(result.alphaMatte), b = try gray(reference)
            XCTAssertEqual(a.count, b.count, name)
            let diffs = zip(a, b).map { abs(Int($0) - Int($1)) }.sorted()
            let mean = Double(diffs.reduce(0, +)) / Double(max(diffs.count, 1))
            let p99 = diffs[min(diffs.count - 1, Int(Double(diffs.count) * 0.99))]
            let worst = diffs.last ?? 0
            print("\(name) [\(expected.pipeline)] \(ms) ms  mean \(String(format: "%.3f", mean))  p99 \(p99)  max \(worst)")
            XCTAssertLessThanOrEqual(mean, 0.5, name)
            XCTAssertLessThanOrEqual(p99, 2, name)
            XCTAssertLessThanOrEqual(worst, 8, name)
        }
    }

    /// Raw 8-bit values (no colour matching) so PNG gamma tags can't shift them.
    private func gray(_ image: CGImage) throws -> [UInt8] {
        if image.bitsPerPixel == 8, image.bitsPerComponent == 8,
           let data = image.dataProvider?.data as Data? {
            var pixels = [UInt8]()
            pixels.reserveCapacity(image.width * image.height)
            for y in 0..<image.height {
                let row = y * image.bytesPerRow
                pixels += data[row..<(row + image.width)]
            }
            return pixels
        }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }
}

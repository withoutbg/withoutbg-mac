import XCTest
@testable import WithoutBGCore

/// Swift resizes against golden outputs of the SDK's `withoutbg.routed` helpers and PIL
/// (model-pro `scripts/make_mac_resample_fixtures.py`).
final class ResamplingTests: XCTestCase {
    private struct Plane: Decodable {
        let width: Int?
        let height: Int?
        let size: Int?
        let values: [Double]
    }

    private struct Fixtures: Decodable {
        let rgb8: Plane
        let fit_max_size: [String: Plane]
        let torch_bilinear: [String: Plane]
        let bicubic_antialias: [String: Plane]
        let matte: Plane
        let matte_bilinear: [String: Plane]
    }

    private static let fixtures: Fixtures = {
        let url = Bundle.module.url(forResource: "Fixtures/resampling", withExtension: "json")!
        return try! JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }()

    private var source: Resampling.RGB8 {
        let p = Self.fixtures.rgb8
        return Resampling.RGB8(pixels: p.values.map { UInt8($0) }, width: p.width!, height: p.height!)
    }

    func testFitMaxSizeMatchesPILBicubicExactly() {
        for (key, expected) in Self.fixtures.fit_max_size {
            let dims = key.split(separator: "x").map { Int($0)! }
            let out = Resampling.fitMaxSize(source, maxWidth: dims[0], maxHeight: dims[1])
            XCTAssertEqual(out.width, expected.width, key)
            XCTAssertEqual(out.height, expected.height, key)
            XCTAssertEqual(out.pixels, expected.values.map { UInt8($0) }, key)
        }
    }

    func testTorchBilinearMatchesReference() {
        let rgb = Resampling.planarFloat(source)
        for (key, expected) in Self.fixtures.torch_bilinear {
            let (oh, ow) = (expected.height!, expected.width!)
            var out = [Float](repeating: 0, count: 3 * oh * ow)
            rgb.withUnsafeBufferPointer { src in
                out.withUnsafeMutableBufferPointer { dst in
                    Resampling.torchBilinear(src.baseAddress!, channels: 3, height: source.height,
                                             width: source.width, toHeight: oh, width: ow,
                                             into: dst.baseAddress!)
                }
            }
            assertClose(out, expected.values, tolerance: 1e-6, key)
        }
    }

    func testBicubicAntialiasMatchesPILFloat() {
        let rgb = Resampling.planarFloat(source)
        for (key, expected) in Self.fixtures.bicubic_antialias {
            let size = expected.size!
            var out = [Float](repeating: 0, count: 3 * size * size)
            rgb.withUnsafeBufferPointer { src in
                out.withUnsafeMutableBufferPointer { dst in
                    Resampling.bicubicAntialias(src.baseAddress!, height: source.height,
                                                width: source.width, size: size, into: dst.baseAddress!)
                }
            }
            assertClose(out, expected.values, tolerance: 1e-5, key)
        }
    }

    func testMatteBilinearMatchesPILExactly() {
        let matte = Self.fixtures.matte
        let pixels = matte.values.map { UInt8($0) }
        for (key, expected) in Self.fixtures.matte_bilinear {
            let out = Resampling.PIL.resize8(pixels, width: matte.width!, height: matte.height!, channels: 1,
                                             toWidth: expected.width!, height: expected.height!,
                                             filter: .bilinear)
            XCTAssertEqual(out, expected.values.map { UInt8($0) }, key)
        }
    }

    private func assertClose(_ actual: [Float], _ expected: [Double], tolerance: Float, _ key: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, key, file: file, line: line)
        let worst = zip(actual, expected).map { abs($0 - Float($1)) }.max() ?? 0
        XCTAssertLessThanOrEqual(worst, tolerance, key, file: file, line: line)
    }
}

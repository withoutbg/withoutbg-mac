import CoreGraphics
import XCTest
@testable import WithoutBGCore

final class CommunityGatewayTests: XCTestCase {
    func testBundledGatewayProcessesRectangularImage() async throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fillEllipse(in: CGRect(x: 100, y: 20, width: 120, height: 140))
        let image = try XCTUnwrap(context.makeImage())
        let root = try XCTUnwrap(WithoutBGCoreResources.bundle.resourceURL)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("community-gateway.json").path
        ))
        let result = try await CoreMLProcessor().process(preparedImage: image)
        XCTAssertEqual(result.processed.width, 320)
        XCTAssertEqual(result.processed.height, 180)
        XCTAssertEqual(result.alphaMatte.width, 320)
        XCTAssertEqual(result.alphaMatte.height, 180)
    }
}

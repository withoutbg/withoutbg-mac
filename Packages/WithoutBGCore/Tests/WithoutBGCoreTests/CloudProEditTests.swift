import CoreGraphics
import Foundation
import XCTest
@testable import WithoutBGCore

/// Pro Smart brush: the upload carries the photo plus every stroke, nothing else.
final class CloudProEditTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func solid(width: Int, height: Int, gray: UInt8) -> CGImage {
        ImageUtilities.grayImage([UInt8](repeating: gray, count: width * height), width: width, height: height)!
    }

    func testMaskDownscalesNearestToBinaryPNG() throws {
        // 4x2 marks: left half marked on the top row only.
        let marks: [Bool] = [
            true, true, false, false,
            false, false, false, false,
        ]
        let png = try CloudProcessor.maskPNG(marks, width: 4, height: 2, toWidth: 2, height: 1)
        let image = try XCTUnwrap(ImageUtilities.cgImage(from: png))
        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 1)
        XCTAssertEqual(ImageUtilities.maskMarks(image, width: 2, height: 1), [true, false])
    }

    func testMaskRejectsSizeMismatch() {
        XCTAssertThrowsError(
            try CloudProcessor.maskPNG([true, false, true], width: 2, height: 2, toWidth: 2, height: 2)
        )
    }

    func testMultipartBodyNamesEachPart() throws {
        let parts = [
            CloudProcessor.MaskPart(name: "file", data: Data("PHOTO".utf8)),
            CloudProcessor.MaskPart(name: "keep_mask", data: Data("KEEP".utf8)),
        ]
        let body = CloudProcessor.multipartBody(boundary: "B", parts: parts)
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(text.contains("name=\"file\"; filename=\"image.png\""))
        XCTAssertTrue(text.contains("name=\"keep_mask\"; filename=\"keep_mask.png\""))
        XCTAssertTrue(text.hasSuffix("--B--\r\n"))
        XCTAssertFalse(text.contains("matte"))
    }

    func testEditSendsOnlyStrokeMasksAtProxySize() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.responseBody = ImageUtilities.pngData(from: solid(width: 512, height: 256, gray: 200))!

        let source = solid(width: 2048, height: 1024, gray: 90)
        let keep = [Bool](repeating: false, count: 2048 * 1024)
        let result = try await CloudProcessor(apiKey: "sk-test", session: session())
            .edit(preparedImage: source, keep: keep, remove: nil)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/v1.0/alpha-channel")
        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"keep_mask\""))
        XCTAssertFalse(text.contains("name=\"remove_mask\""))
        XCTAssertFalse(text.contains("edit_context"))
        XCTAssertEqual(result.processed.width, 2048)
    }

    func testEditWithoutStrokesThrows() async {
        do {
            _ = try await CloudProcessor(apiKey: "sk-test", session: session())
                .edit(preparedImage: solid(width: 8, height: 8, gray: 0), keep: nil, remove: nil)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("keep or remove"))
        }
    }
}

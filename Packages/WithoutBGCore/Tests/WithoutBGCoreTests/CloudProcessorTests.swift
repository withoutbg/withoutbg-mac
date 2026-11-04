import CoreGraphics
import Foundation
import XCTest
@testable import WithoutBGCore

/// Serves canned responses and records the last request.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var responseBody = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

final class CloudProcessorTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func solid(width: Int, height: Int, gray: UInt8) -> CGImage {
        ImageUtilities.grayImage([UInt8](repeating: gray, count: width * height), width: width, height: height)!
    }

    func testProcessSendsKeyAndUserAgentAndComposesAtFullSize() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.responseBody = ImageUtilities.pngData(from: solid(width: 512, height: 256, gray: 200))!

        let source = solid(width: 2048, height: 1024, gray: 90)
        let result = try await CloudProcessor(apiKey: "sk-test", session: session())
            .process(preparedImage: source)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/v1.0/alpha-channel")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "sk-test")
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("withoutbg-mac/") == true)
        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        XCTAssertNotNil(body.range(of: Data("name=\"file\"".utf8)))

        XCTAssertEqual(result.processed.width, 2048)
        XCTAssertEqual(result.processed.height, 1024)
        XCTAssertEqual(result.alphaMatte.width, 2048)
    }

    func testOutOfCreditsMapsToFriendlyError() async {
        StubURLProtocol.status = 402
        StubURLProtocol.responseBody = Data()
        do {
            _ = try await CloudProcessor(apiKey: "sk-test", session: session())
                .process(preparedImage: solid(width: 8, height: 8, gray: 0))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Out of withoutBG Pro credits.")
        }
    }

    func testCreditsDecode() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.responseBody = Data(#"{"credit": 138, "expiration_date": "2027-01-01 00:00:00"}"#.utf8)
        let credits = try await CloudProcessor(apiKey: "k", session: session()).credits()
        XCTAssertEqual(credits, ProCredits(credit: 138, expirationDate: "2027-01-01 00:00:00"))
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/available-credit")
    }

    func testUserAgentFormat() {
        let ua = ClientIdentity.userAgent
        XCTAssertNotNil(ua.range(of: #"^withoutbg-mac/\S+ \(macOS \d+\.\d+(\.\d+)?; (arm64|x86_64)\)$"#,
                                 options: .regularExpression), ua)
    }
}

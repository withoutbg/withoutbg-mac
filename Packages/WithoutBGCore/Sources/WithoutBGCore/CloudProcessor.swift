import CoreGraphics
import Foundation

/// Which engine new removals use. Open weights (on-device) is the default;
/// Pro is opt-in and only offered once an API key is saved.
public enum ProcessingEngine: String, CaseIterable, Identifiable, Sendable {
    case openWeights = "open"
    case pro

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .openWeights: return "Open weights (on this Mac)"
        case .pro: return "withoutBG Pro (cloud)"
        }
    }

    /// The engine to use right now: Pro only when chosen *and* a key exists.
    public static var effective: ProcessingEngine {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.processingEngine)
        guard ProcessingEngine(rawValue: raw ?? "") == .pro, APIKeyStore.hasKey else {
            return .openWeights
        }
        return .pro
    }
}

/// Credit balance for a withoutBG Pro API key (`GET /available-credit`).
public struct ProCredits: Decodable, Sendable, Equatable {
    public let credit: Int
    public let expirationDate: String

    enum CodingKeys: String, CodingKey {
        case credit
        case expirationDate = "expiration_date"
    }
}

/// withoutBG Pro via the hosted API. Uploads a ≤1024 px proxy, gets the alpha
/// matte back and composes the cutout locally at the original size.
public struct CloudProcessor: BackgroundRemovalProcessor {
    public static let defaultBaseURL = URL(string: "https://api.withoutbg.com")!
    /// Pro inference resolution; a bigger upload only costs bandwidth.
    public static let maxUploadSide: CGFloat = 1024

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    public init(apiKey: String, baseURL: URL = CloudProcessor.defaultBaseURL, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    public func process(preparedImage: CGImage) async throws -> ProcessorResult {
        let start = Date()
        let proxy = ImageUtilities.resized(preparedImage, maxPx: Self.maxUploadSide).image
        guard let png = ImageUtilities.pngData(from: proxy) else { throw ProcessorError.invalidImage }

        let boundary = UUID().uuidString
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"image.png\"\r\n".utf8))
        body.append(Data("Content-Type: image/png\r\n\r\n".utf8))
        body.append(png)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = request(path: "v1.0/alpha-channel")
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data = try await send(request)
        guard let matte = ImageUtilities.cgImage(from: data),
              let fullMatte = ImageUtilities.resizedMatte(matte, toWidth: preparedImage.width,
                                                          height: preparedImage.height),
              let cutout = ImageUtilities.cutout(from: preparedImage, matte: fullMatte)
        else {
            throw ProcessorError.processingFailed("withoutBG Pro returned an unreadable matte.")
        }
        return ProcessorResult(
            processed: cutout,
            alphaMatte: fullMatte,
            latencyMs: Int(Date().timeIntervalSince(start) * 1000)
        )
    }

    /// Credit balance for the key. Free; also validates the key.
    public func credits() async throws -> ProCredits {
        let data = try await send(request(path: "available-credit"))
        return try JSONDecoder().decode(ProCredits.self, from: data)
    }

    private func request(path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(ClientIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProcessorError.processingFailed("Cannot reach withoutBG Pro: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProcessorError.processingFailed("withoutBG Pro sent no HTTP response.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProcessorError.processingFailed(Self.message(for: http.statusCode))
        }
        return data
    }

    static func message(for status: Int) -> String {
        switch status {
        case 401: return "withoutBG Pro rejected the API key. Check it in Settings."
        case 402: return "Out of withoutBG Pro credits."
        case 403: return "This API key cannot use withoutBG Pro (credits expired?)."
        case 429: return "withoutBG Pro rate limit reached. Try again shortly."
        default: return "withoutBG Pro returned HTTP \(status)."
        }
    }
}

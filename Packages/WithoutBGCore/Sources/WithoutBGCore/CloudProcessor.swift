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
        try await send(preparedImage: preparedImage, masks: [])
    }

    /// Smart brush on Pro: the photo plus every stroke so far, 1 credit per call.
    ///
    /// Stateless: nothing is kept between calls, so the caller passes all strokes
    /// made on the cutout each time. Marks are original-size, row-major, and are
    /// downscaled to the upload size here. Any matte from an earlier edit is not sent.
    public func edit(preparedImage: CGImage, keep: [Bool]?, remove: [Bool]?) async throws -> ProcessorResult {
        let proxy = Self.proxySize(of: preparedImage)
        var masks: [MaskPart] = []
        if let keep {
            masks.append(MaskPart(name: "keep_mask", data: try Self.maskPNG(
                keep, width: preparedImage.width, height: preparedImage.height,
                toWidth: proxy.width, height: proxy.height)))
        }
        if let remove {
            masks.append(MaskPart(name: "remove_mask", data: try Self.maskPNG(
                remove, width: preparedImage.width, height: preparedImage.height,
                toWidth: proxy.width, height: proxy.height)))
        }
        guard !masks.isEmpty else {
            throw ProcessorError.processingFailed("Smart brush needs a keep or remove stroke.")
        }
        return try await send(preparedImage: preparedImage, masks: masks)
    }

    /// One mask part of the upload (`keep_mask` / `remove_mask`).
    struct MaskPart: Equatable {
        let name: String
        let data: Data
    }

    private func send(preparedImage: CGImage, masks: [MaskPart]) async throws -> ProcessorResult {
        let start = Date()
        let proxy = ImageUtilities.resized(preparedImage, maxPx: Self.maxUploadSide).image
        guard let png = ImageUtilities.pngData(from: proxy) else { throw ProcessorError.invalidImage }

        let boundary = UUID().uuidString
        let parts = [MaskPart(name: "file", data: png)] + masks
        var request = request(path: "v1.0/alpha-channel")
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(boundary: boundary, parts: parts)

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

    /// Upload size of the photo (longest side capped at `maxUploadSide`).
    static func proxySize(of image: CGImage) -> (width: Int, height: Int) {
        let proxy = ImageUtilities.resized(image, maxPx: maxUploadSide).image
        return (proxy.width, proxy.height)
    }

    /// Marks at (`w`, `h`) downscaled to (`pw`, `ph`) by nearest sample, as a binary PNG.
    static func maskPNG(_ marks: [Bool], width w: Int, height h: Int,
                        toWidth pw: Int, height ph: Int) throws -> Data {
        guard w > 0, h > 0, pw > 0, ph > 0, marks.count == w * h else {
            throw ProcessorError.processingFailed("Smart brush mask does not match the image size.")
        }
        var pixels = [UInt8](repeating: 0, count: pw * ph)
        for y in 0..<ph {
            let sy = min(h - 1, y * h / ph)
            for x in 0..<pw {
                let sx = min(w - 1, x * w / pw)
                pixels[y * pw + x] = marks[sy * w + sx] ? 255 : 0
            }
        }
        guard let image = ImageUtilities.grayImage(pixels, width: pw, height: ph),
              let png = ImageUtilities.pngData(from: image)
        else { throw ProcessorError.invalidImage }
        return png
    }

    /// multipart/form-data body: each part is a PNG named by its field.
    static func multipartBody(boundary: String, parts: [MaskPart]) -> Data {
        var body = Data()
        for part in parts {
            let filename = part.name == "file" ? "image.png" : "\(part.name).png"
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\r\n".utf8))
            body.append(Data("Content-Type: image/png\r\n\r\n".utf8))
            body.append(part.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
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

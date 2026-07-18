import Foundation
import WithoutBGCore

enum ProductUpdatesResult: Sendable {
    case success
    case alreadyRegistered
    case invalidEmail
    case networkError
}

/// Posts opt-in product-update requests directly to the withoutBG API.
enum ProductUpdatesService {
    private struct RequestBody: Encodable {
        let email: String
        let source: String
        let platform: String
        let appVersion: String
        let consent: Bool
    }

    static func register(email: String) async -> ProductUpdatesResult {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), trimmed.count >= 5 else {
            return .invalidEmail
        }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

        let url = ProductLinks.shared.productUpdates
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            RequestBody(
                email: trimmed,
                source: "mac-unified",
                platform: "macos",
                appVersion: version,
                consent: true
            )
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .networkError
            }

            switch http.statusCode {
            case 200...299:
                return .success
            case 409:
                return .alreadyRegistered
            case 400:
                return .invalidEmail
            default:
                _ = data
                return .networkError
            }
        } catch {
            return .networkError
        }
    }
}

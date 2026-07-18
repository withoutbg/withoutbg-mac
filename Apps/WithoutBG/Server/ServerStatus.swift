import Foundation
import WithoutBGCore

/// Observable state the menu bar UI and settings observe.
@MainActor
@Observable
final class ServerStatus {
    var isRunning: Bool = false
    var port: Int = 8000
    var requestCount: Int = 0
    var lastError: String? = nil
    var runningSince: Date? = nil

    var boundURL: String {
        "http://127.0.0.1:\(port)"
    }

    var openAPIURL: String {
        "\(boundURL)/openapi.json"
    }

    var statusLabel: String {
        isRunning ? "Local API Running — \(boundURL)" : "Local API Stopped"
    }

    var modelLabel: String {
        "withoutBG Open Weights v\(CoreMLProcessor.modelVersion)"
    }
}

import Foundation

/// A single recorded HTTP request for the activity list.
struct ActivityEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let method: String
    let path: String
    let statusCode: Int
    let latencyMs: Int?
    let detail: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        method: String,
        path: String,
        statusCode: Int,
        latencyMs: Int?,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.method = method
        self.path = path
        self.statusCode = statusCode
        self.latencyMs = latencyMs
        self.detail = detail
    }

    var isSuccess: Bool {
        (200..<300).contains(statusCode)
    }

    var lastRequestSummary: String {
        var summary = "\(method) \(statusCode)"
        if let latencyMs {
            summary += " (\(latencyMs) ms)"
        }
        if let detail, !isSuccess {
            summary += " — \(detail)"
        }
        return summary
    }
}

/// In-memory ring buffer of recent HTTP requests (newest first).
@MainActor
@Observable
final class RecentActivity {
    private let capacity = 20
    private(set) var entries: [ActivityEntry] = []

    var lastEntry: ActivityEntry? {
        entries.first
    }

    /// Rolling mean latency over recent successful inference requests.
    var averageLatencyMs: Int? {
        let latencies = entries.compactMap(\.latencyMs).filter { $0 > 0 }
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / latencies.count
    }

    func record(_ entry: ActivityEntry) {
        entries.insert(entry, at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }

    func clear() {
        entries.removeAll()
    }
}

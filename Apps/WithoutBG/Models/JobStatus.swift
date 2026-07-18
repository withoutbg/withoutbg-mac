import Foundation

/// Lifecycle state of a queue item. Mirrors web `JobStatus`.
enum JobStatus: String, Sendable {
    case queued
    case processing
    case done
    case error
}

import CoreGraphics
import Foundation

/// Output of a background-removal pass. Mirrors web `ProcessorResult`.
struct ProcessorResult: Sendable {
    /// Transparent PNG cutout.
    let processed: CGImage
    /// Grayscale RGB matte — white = subject, black = background.
    let alphaMatte: CGImage
    /// Server-side latency in ms (nil for purely local processing display).
    let latencyMs: Int?
}

/// Errors a processor may surface.
enum ProcessorError: LocalizedError {
    case notImplemented
    case invalidImage
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "CoreML processor is not implemented yet."
        case .invalidImage:
            return "The image could not be read."
        case .processingFailed(let message):
            return message
        }
    }
}

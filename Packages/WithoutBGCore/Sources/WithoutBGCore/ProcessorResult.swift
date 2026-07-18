import CoreGraphics
import Foundation

/// Output of a background-removal pass.
public struct ProcessorResult: Sendable {
    /// Transparent PNG cutout.
    public let processed: CGImage
    /// Grayscale RGB matte — white = subject, black = background.
    public let alphaMatte: CGImage
    /// Processing latency in ms (nil for display-only paths).
    public let latencyMs: Int?

    public init(processed: CGImage, alphaMatte: CGImage, latencyMs: Int?) {
        self.processed = processed
        self.alphaMatte = alphaMatte
        self.latencyMs = latencyMs
    }
}

/// Errors a processor may surface.
public enum ProcessorError: LocalizedError {
    case notImplemented
    case invalidImage
    case processingFailed(String)

    public var errorDescription: String? {
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

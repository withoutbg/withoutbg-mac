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
    /// Router decision (nil for processors that don't route).
    public let route: RouteDecision?

    public init(processed: CGImage, alphaMatte: CGImage, latencyMs: Int?, route: RouteDecision? = nil) {
        self.processed = processed
        self.alphaMatte = alphaMatte
        self.latencyMs = latencyMs
        self.route = route
    }
}

/// Which router category an image fell into and the branch that produced its matte.
public struct RouteDecision: Sendable, Equatable {
    /// Router category, e.g. `fine_strand` or `vehicle`.
    public let category: String
    /// `matting` (withoutBG matting) or `birefnet`.
    public let pipeline: String

    public init(category: String, pipeline: String) {
        self.category = category
        self.pipeline = pipeline
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

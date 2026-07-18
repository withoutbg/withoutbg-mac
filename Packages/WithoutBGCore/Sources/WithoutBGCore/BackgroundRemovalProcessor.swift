import CoreGraphics

/// The single seam between the UI and the inference engine.
public protocol BackgroundRemovalProcessor: Sendable {
    /// Run background removal on the given image at its native resolution.
    func process(preparedImage: CGImage) async throws -> ProcessorResult
}

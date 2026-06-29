import CoreGraphics

/// The single seam between the UI and the inference engine.
///
/// `ProcessingQueue` depends only on this protocol, so swapping `MockProcessor`
/// for `CoreMLProcessor` is a one-line change at app init — no UI changes.
protocol BackgroundRemovalProcessor: Sendable {
    /// Run background removal on the source image at its native resolution.
    /// Implementations may downscale internally for inference, then upscale the
    /// alpha matte and composite onto the full-resolution source.
    func process(preparedImage: CGImage) async throws -> ProcessorResult
}

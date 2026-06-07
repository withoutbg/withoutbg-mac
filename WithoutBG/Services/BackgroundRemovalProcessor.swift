import CoreGraphics

/// The single seam between the UI and the inference engine.
///
/// `ProcessingQueue` depends only on this protocol, so swapping `MockProcessor`
/// for `CoreMLProcessor` is a one-line change at app init — no UI changes.
protocol BackgroundRemovalProcessor: Sendable {
    /// Run background removal on an already-prepared (resized) image.
    func process(preparedImage: CGImage) async throws -> ProcessorResult
}

import CoreGraphics

/// Serializes all inference through a single processor instance so desktop
/// batch jobs and Local API requests share one loaded model and one GPU queue.
public actor SharedInferenceCoordinator {
    private let processor: any BackgroundRemovalProcessor

    public init(processor: any BackgroundRemovalProcessor) {
        self.processor = processor
    }

    public func process(preparedImage: CGImage) async throws -> ProcessorResult {
        try await processor.process(preparedImage: preparedImage)
    }
}

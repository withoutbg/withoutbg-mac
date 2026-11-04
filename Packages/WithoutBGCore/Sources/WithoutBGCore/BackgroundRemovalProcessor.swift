import CoreGraphics

/// The single seam between the UI and the inference engine.
public protocol BackgroundRemovalProcessor: Sendable {
    /// Run background removal on the given image at its native resolution.
    func process(preparedImage: CGImage) async throws -> ProcessorResult

    /// Whether `edit` can run (the model ships the Smart brush graph).
    var supportsEdit: Bool { get }

    /// Smart brush: fix a cutout with brush marks (`width × height` of the image,
    /// row-major). *matte* is the previous result's matte, or nil to start fresh.
    func edit(preparedImage: CGImage, keep: [Bool]?, remove: [Bool]?, matte: CGImage?) async throws -> ProcessorResult
}

public extension BackgroundRemovalProcessor {
    var supportsEdit: Bool { false }

    func edit(preparedImage: CGImage, keep: [Bool]?, remove: [Bool]?, matte: CGImage?) async throws -> ProcessorResult {
        throw ProcessorError.notImplemented
    }
}

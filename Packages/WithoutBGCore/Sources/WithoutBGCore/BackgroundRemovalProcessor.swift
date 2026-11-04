import CoreGraphics

/// The single seam between the UI and the inference engine.
public protocol BackgroundRemovalProcessor: Sendable {
    /// Run background removal on the given image at its native resolution.
    func process(preparedImage: CGImage) async throws -> ProcessorResult

    /// Whether `edit` can run (the model ships the Smart brush graph).
    var supportsEdit: Bool { get }

    /// Smart brush: fix a cutout with brush marks (`width × height` of the image,
    /// row-major). *matte* is the previous result's matte, or nil to start fresh.
    /// *context* is the previous edit's `editContext` for this image (skips the
    /// router and coarse graphs when it still matches).
    func edit(preparedImage: CGImage, keep: [Bool]?, remove: [Bool]?, matte: CGImage?,
              context: EditContext?) async throws -> ProcessorResult
}

public extension BackgroundRemovalProcessor {
    var supportsEdit: Bool { false }

    func edit(preparedImage: CGImage, keep: [Bool]?, remove: [Bool]?, matte: CGImage?,
              context: EditContext?) async throws -> ProcessorResult {
        throw ProcessorError.notImplemented
    }

    func edit(preparedImage: CGImage, keep: [Bool]?, remove: [Bool]?, matte: CGImage?) async throws -> ProcessorResult {
        try await edit(preparedImage: preparedImage, keep: keep, remove: remove, matte: matte, context: nil)
    }
}

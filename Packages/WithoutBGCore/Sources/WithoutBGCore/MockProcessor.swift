import CoreGraphics
import Foundation

/// Mock implementation for UI development without the bundled model.
public struct MockProcessor: BackgroundRemovalProcessor {
    public init() {}

    public func process(preparedImage: CGImage) async throws -> ProcessorResult {
        try await Task.sleep(nanoseconds: 1_000_000_000)

        guard let matte = ImageUtilities.mockAlphaMatte(for: preparedImage) else {
            throw ProcessorError.invalidImage
        }
        guard let processed = ImageUtilities.cutout(from: preparedImage, matte: matte) else {
            throw ProcessorError.processingFailed("Could not composite cutout.")
        }

        let latencyMs = 800 + Int.random(in: 0..<400)
        return ProcessorResult(processed: processed, alphaMatte: matte, latencyMs: latencyMs)
    }
}

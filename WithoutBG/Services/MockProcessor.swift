import CoreGraphics
import Foundation

/// Mock implementation that fabricates a plausible cutout with an elliptical
/// matte, plus artificial latency to mimic server-side processing. Mirrors the
/// web `mockProcessor` in `useProcessingQueue.ts`.
struct MockProcessor: BackgroundRemovalProcessor {
    func process(preparedImage: CGImage) async throws -> ProcessorResult {
        // ~1000ms inside the processor (the queue adds ~800ms before this).
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

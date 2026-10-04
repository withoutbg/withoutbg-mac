import CoreGraphics
import CoreML
import Foundation

/// Real, on-device background removal backed by the bundled withoutBG Open Weights
/// routed bundle (Core ML, ML Program, fp32): router → withoutBG matting or BiRefNet.
public final class CoreMLProcessor: BackgroundRemovalProcessor, @unchecked Sendable {
    private static let manifest: RoutedManifest? = WithoutBGCoreResources.bundle.resourceURL
        .flatMap { try? RoutedManifest.load(from: $0) }

    public static let modelName = "withoutbg-openweights-\(manifest?.variant ?? "oss")"
    public static let modelVersion = manifest?.model_version ?? "unknown"

    private let cache: CompiledModelCache
    private let lock = NSLock()
    private var pipeline: RoutedPipeline?

    public convenience init() {
        self.init(computeUnits: .all)
    }

    init(computeUnits: MLComputeUnits) {
        cache = CompiledModelCache(computeUnits: computeUnits)
        Task.detached(priority: .utility) { [weak self] in
            try? self?.loadPipeline().preload()
        }
    }

    public func process(preparedImage: CGImage) async throws -> ProcessorResult {
        try await Task.detached(priority: .userInitiated) { [self] in
            try loadPipeline().process(preparedImage)
        }.value
    }

    private func loadPipeline() throws -> RoutedPipeline {
        lock.lock()
        defer { lock.unlock() }
        if let pipeline { return pipeline }
        guard let root = WithoutBGCoreResources.bundle.resourceURL else {
            throw ProcessorError.processingFailed("WithoutBGCore resources were not found.")
        }
        let loaded = try RoutedPipeline(root: root, cache: cache)
        pipeline = loaded
        return loaded
    }
}

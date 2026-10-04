import CoreGraphics
import CoreML
import Foundation

/// A Core ML graph the pipeline can run; `MLModel` conforms, tests inject stubs.
protocol RoutedGraph {
    func prediction(from input: MLFeatureProvider, options: MLPredictionOptions) throws -> MLFeatureProvider
}

extension MLModel: RoutedGraph {}

/// Routed open-weights pipeline (schema 3), matching `withoutbg.routed.RoutedPipeline`:
/// a shared ConvNeXt backbone at 448² yields router logits and features. Fine strands,
/// soft detail and transparency go to the withoutBG matting graph (which reuses those
/// features); hard opaque objects, flat scenes and vehicles go to BiRefNet at 1024².
/// Only the selected branch runs; its alpha is bilinearly upsampled to native size.
final class RoutedPipeline {
    enum Graph: String, CaseIterable {
        case router, coarse, birefnet
    }

    let manifest: RoutedManifest
    private let loader: (Graph) throws -> RoutedGraph
    private var graphs: [Graph: RoutedGraph] = [:]
    private let lock = NSLock()

    init(manifest: RoutedManifest, loader: @escaping (Graph) throws -> RoutedGraph) {
        self.manifest = manifest
        self.loader = loader
    }

    convenience init(root: URL, cache: CompiledModelCache = CompiledModelCache()) throws {
        let root = root.resolvingSymlinksInPath()
        let manifest = try RoutedManifest.load(from: root)
        self.init(manifest: manifest) { graph in
            let (file, sha) = switch graph {
            case .router: (manifest.router.file, manifest.router.sha256)
            case .coarse: (manifest.coarse.file, manifest.coarse.sha256)
            case .birefnet: (manifest.birefnet.file, manifest.birefnet.sha256)
            }
            return try cache.model(package: root.appendingPathComponent(file), sha256: sha)
        }
    }

    /// Resolve, verify and load every graph so both branches are ready.
    func preload() throws {
        lock.lock()
        defer { lock.unlock() }
        for graph in Graph.allCases { _ = try load(graph) }
    }

    private func load(_ graph: Graph) throws -> RoutedGraph {
        if let loaded = graphs[graph] { return loaded }
        let loaded = try loader(graph)
        graphs[graph] = loaded
        return loaded
    }

    func process(_ image: CGImage) throws -> ProcessorResult {
        let start = Date()
        guard let original = Resampling.rgb8(from: image) else { throw ProcessorError.invalidImage }
        let work = Resampling.fitMaxSize(
            original, maxWidth: manifest.max_inference_size[0], maxHeight: manifest.max_inference_size[1]
        )
        let (w, h) = (work.width, work.height)
        let rgb = Resampling.planarFloat(work)

        lock.lock()
        let route: RouteDecision
        let alpha: MLMultiArray
        let outputSize: Int
        do {
            defer { lock.unlock() }
            let router = manifest.router
            let rgbMatting = try Self.tensor(rgb, width: w, height: h, spec: router.inputs["rgb_matting"]!)
            let routed = try load(.router).prediction(
                from: MLDictionaryFeatureProvider(dictionary: ["rgb_matting": rgbMatting]),
                options: MLPredictionOptions()
            )
            let category = router.categories[try Self.argmax(
                routed.featureValue(for: router.logits_name)?.multiArrayValue, count: router.categories.count
            )]
            let pipeline = router.birefnet_categories.contains(category) ? "birefnet" : "matting"
            route = RouteDecision(category: category, pipeline: pipeline)

            let (graph, feeds, outputName): (Graph, [String: MLFeatureValue], String)
            if pipeline == "birefnet" {
                let spec = manifest.birefnet
                graph = .birefnet
                feeds = ["rgb": try Self.tensor(rgb, width: w, height: h, spec: spec.inputs["rgb"]!)]
                outputName = spec.output_name
                outputSize = spec.output_size
            } else {
                let spec = manifest.coarse
                var coarseFeeds = [
                    // The backbone already resized rgb_matting identically; reuse it.
                    "rgb_matting": rgbMatting,
                    "rgb_depth": try Self.tensor(rgb, width: w, height: h, spec: spec.inputs["rgb_depth"]!),
                ]
                for name in spec.feature_names {
                    guard let feature = routed.featureValue(for: name) else {
                        throw ProcessorError.processingFailed("Router output is missing \(name).")
                    }
                    coarseFeeds[name] = feature
                }
                graph = .coarse
                feeds = coarseFeeds
                outputName = spec.output_name
                outputSize = spec.output_size
            }
            let result = try load(graph).prediction(
                from: MLDictionaryFeatureProvider(dictionary: feeds), options: MLPredictionOptions()
            )
            guard let output = result.featureValue(for: outputName)?.multiArrayValue else {
                throw ProcessorError.processingFailed("\(pipeline) graph returned no \(outputName).")
            }
            alpha = output
        }

        let matte = try Self.matte(alpha, size: outputSize, pipeline: route.pipeline,
                                   workWidth: w, workHeight: h,
                                   width: original.width, height: original.height)
        guard let matteImage = ImageUtilities.grayImage(matte, width: original.width, height: original.height),
              let cutout = ImageUtilities.cutout(from: image, matte: matteImage) else {
            throw ProcessorError.processingFailed("Could not build the cutout.")
        }
        return ProcessorResult(processed: cutout, alphaMatte: matteImage,
                               latencyMs: Int(Date().timeIntervalSince(start) * 1000), route: route)
    }

    // MARK: - Tensors

    /// `routed.graph_inputs` for one input: a square stretch of the working image.
    static func tensor(_ rgb: [Float], width w: Int, height h: Int,
                       spec: RoutedManifest.GraphInput) throws -> MLFeatureValue {
        let size = spec.size
        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: size), NSNumber(value: size)],
                                     dataType: .float32)
        array.withUnsafeMutableBufferPointer(ofType: Float.self) { dst, strides in
            precondition(strides == [3 * size * size, size * size, size, 1])
            rgb.withUnsafeBufferPointer { src in
                if spec.interpolation == "bicubic" {
                    Resampling.bicubicAntialias(src.baseAddress!, height: h, width: w, size: size,
                                                into: dst.baseAddress!)
                } else {
                    Resampling.torchBilinear(src.baseAddress!, channels: 3, height: h, width: w,
                                             toHeight: size, width: size, into: dst.baseAddress!)
                }
            }
        }
        return MLFeatureValue(multiArray: array)
    }

    /// `np.argmax` over finite `[1, count]` logits (first index wins ties).
    static func argmax(_ logits: MLMultiArray?, count: Int) throws -> Int {
        guard let logits, logits.shape.map(\.intValue) == [1, count] else {
            throw ProcessorError.processingFailed("Router output must be [1, \(count)] logits.")
        }
        var best = 0
        var bestScore = -Float.infinity
        for i in 0..<count {
            let score = logits[[0, NSNumber(value: i)]].floatValue
            guard score.isFinite else { throw ProcessorError.processingFailed("Router returned invalid logits.") }
            if score > bestScore { (best, bestScore) = (i, score) }
        }
        return best
    }

    /// Upsample `[1, 1, S, S]` alpha to the working size like torch bilinear, quantize
    /// as `clip(a * 255 + 0.5)`, then PIL-bilinear to the original size if it differs.
    static func matte(_ alpha: MLMultiArray, size: Int, pipeline: String,
                      workWidth w: Int, workHeight h: Int, width: Int, height: Int) throws -> [UInt8] {
        guard alpha.shape.map(\.intValue) == [1, 1, size, size] else {
            throw ProcessorError.processingFailed("\(pipeline) output must be [1, 1, \(size), \(size)] alpha.")
        }
        var coarse = [Float](repeating: 0, count: size * size)
        let rowStride = alpha.strides[2].intValue, colStride = alpha.strides[3].intValue
        if alpha.dataType == .float32 {
            alpha.withUnsafeBufferPointer(ofType: Float.self) { src in
                for y in 0..<size {
                    for x in 0..<size { coarse[y * size + x] = src[y * rowStride + x * colStride] }
                }
            }
        } else {
            for y in 0..<size {
                for x in 0..<size {
                    coarse[y * size + x] = alpha[[0, 0, NSNumber(value: y), NSNumber(value: x)]].floatValue
                }
            }
        }
        guard coarse.allSatisfy(\.isFinite) else {
            throw ProcessorError.processingFailed("\(pipeline) output must be finite alpha.")
        }
        var upsampled = [Float](repeating: 0, count: w * h)
        coarse.withUnsafeBufferPointer { src in
            upsampled.withUnsafeMutableBufferPointer { dst in
                Resampling.torchBilinear(src.baseAddress!, channels: 1, height: size, width: size,
                                         toHeight: h, width: w, into: dst.baseAddress!)
            }
        }
        let gray = upsampled.map { value -> UInt8 in
            let scaled = min(max(value, 0), 1) * 255 + 0.5
            return UInt8(min(max(scaled, 0), 255))
        }
        if (w, h) == (width, height) { return gray }
        return Resampling.PIL.resize8(gray, width: w, height: h, channels: 1,
                                      toWidth: width, height: height, filter: .bilinear)
    }
}

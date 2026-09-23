import CoreGraphics
import CoreML
import CryptoKit
import Foundation

/// Native implementation of the versioned community gateway bundle contract.
/// Normalization is embedded in the graphs. Only the selected branch predicts.
final class CommunityGateway {
    struct ModelSpec: Decodable {
        let file: String
        let sha256: String
        let canvas_size: Int
        let resize: String
        let interpolation: String
        let input_name: String
        let output_name: String
    }

    struct Manifest: Decodable {
        let schema_version: Int
        let categories: [String]
        let router: ModelSpec
        let matting: ModelSpec
        let birefnet: ModelSpec
    }

    static let segmentationCategories: Set<String> = ["hard_opaque", "flat_scene", "vehicle"]
    static let categories: Set<String> = [
        "fine_strand", "soft_detail", "transparency", "hard_opaque", "flat_scene", "vehicle"
    ]
    private let root: URL
    private let manifest: Manifest
    private var models: [String: MLModel] = [:]
    private let lock = NSLock()

    init(root: URL) throws {
        self.root = root.resolvingSymlinksInPath()
        manifest = try JSONDecoder().decode(
            Manifest.self, from: Data(contentsOf: root.appendingPathComponent("community-gateway.json"))
        )
        guard manifest.schema_version == 1,
              manifest.categories.count == 6,
              Set(manifest.categories) == Self.categories else {
            throw ProcessorError.processingFailed("Invalid community gateway categories or version.")
        }
        for spec in [manifest.router, manifest.matting, manifest.birefnet] {
            guard !spec.file.hasPrefix("/"), !spec.file.split(separator: "/").contains(".."),
                  !spec.file.isEmpty, spec.canvas_size > 0,
                  ["stretch", "letterbox"].contains(spec.resize),
                  ["bilinear", "bicubic"].contains(spec.interpolation),
                  spec.sha256.count == 64 else {
                throw ProcessorError.processingFailed("Invalid community model specification.")
            }
        }
    }

    private func load(_ spec: ModelSpec) throws -> MLModel {
        if let model = models[spec.file] { return model }
        let url = root.appendingPathComponent(spec.file).resolvingSymlinksInPath()
        // Verify the source package before Core ML compiles it.
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])
        let files = (enumerator?.allObjects as? [URL] ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.path < $1.path }
        var hasher = SHA256()
        for file in files {
            let relative = file.resolvingSymlinksInPath().pathComponents.dropFirst(url.pathComponents.count).joined(separator: "/")
            hasher.update(data: Data(relative.utf8))
            hasher.update(data: try Data(contentsOf: file, options: .mappedIfSafe))
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == spec.sha256 else {
            throw ProcessorError.processingFailed("Community model checksum mismatch: \(spec.file), expected \(spec.sha256), got \(digest)")
        }
        let compiled = try MLModel.compileModel(at: url)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model = try MLModel(contentsOf: compiled, configuration: configuration)
        models[spec.file] = model
        return model
    }

    private func predict(_ spec: ModelSpec, image: CGImage) throws -> (MLMultiArray, Int, Int) {
        guard let (tensor, width, height) = ImageUtilities.letterboxTensor(
            image, canvas: spec.canvas_size, stretch: spec.resize == "stretch",
            interpolation: spec.interpolation == "bicubic" ? .high : .medium
        ) else { throw ProcessorError.invalidImage }
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            spec.input_name: MLFeatureValue(multiArray: tensor)
        ])
        let result = try load(spec).prediction(from: provider)
        guard let output = result.featureValue(for: spec.output_name)?.multiArrayValue else {
            throw ProcessorError.processingFailed("Missing community model output: \(spec.output_name)")
        }
        return (output, width, height)
    }

    func process(_ image: CGImage) throws -> ProcessorResult {
        lock.lock()
        defer { lock.unlock() }
        let start = Date()
        let (logits, _, _) = try predict(manifest.router, image: image)
        guard logits.shape.map({ $0.intValue }) == [1, 6] else {
            throw ProcessorError.processingFailed("Router must return six logits.")
        }
        let scores = (0..<6).map { logits[$0].doubleValue }
        guard scores.allSatisfy({ $0.isFinite }) else {
            throw ProcessorError.processingFailed("Router returned invalid logits.")
        }
        let index = (0..<6).max { scores[$0] < scores[$1] }!
        let spec = Self.segmentationCategories.contains(manifest.categories[index])
            ? manifest.birefnet : manifest.matting
        let (alpha, width, height) = try predict(spec, image: image)
        let shape = alpha.shape.map { $0.intValue }
        guard shape.count == 4, shape[0] == 1, shape[1] == 1, shape[2] == shape[3] else {
            throw ProcessorError.processingFailed("Invalid community alpha output shape.")
        }
        let outputCanvas = shape[2]
        let validW = max(1, Int((Double(width * outputCanvas) / Double(spec.canvas_size)).rounded()))
        let validH = max(1, Int((Double(height * outputCanvas) / Double(spec.canvas_size)).rounded()))
        guard let matte = CoreMLProcessor.makeMatte(
            from: alpha, canvas: outputCanvas, validW: validW, validH: validH,
            targetW: image.width, targetH: image.height
        ), let cutout = ImageUtilities.cutout(from: image, matte: matte) else {
            throw ProcessorError.processingFailed("Could not build community cutout.")
        }
        return ProcessorResult(processed: cutout, alphaMatte: matte,
                               latencyMs: Int(Date().timeIntervalSince(start) * 1000))
    }
}

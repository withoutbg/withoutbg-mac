import Foundation

/// Core ML mirror of the open-weights `routed` sidecar (schema 3). Written by
/// model-pro `scripts/export_openweights_routed.py` from the published ONNX sidecar.
struct RoutedManifest: Decodable {
    struct GraphInput: Decodable, Equatable {
        let size: Int
        let resize: String
        let interpolation: String
        let antialias: Bool
    }

    struct Router: Decodable {
        let file: String
        let sha256: String
        let inputs: [String: GraphInput]
        let logits_name: String
        let feature_names: [String]
        let categories: [String]
        let birefnet_categories: [String]
    }

    struct Coarse: Decodable {
        let file: String
        let sha256: String
        let inputs: [String: GraphInput]
        let feature_names: [String]
        let output_name: String
        let output_size: Int
    }

    struct BiRefNet: Decodable {
        let file: String
        let sha256: String
        let inputs: [String: GraphInput]
        let output_name: String
        let output_size: Int
    }

    static let fileName = "withoutbg-open-weights.coreml.json"

    let schema_version: Int
    let pipeline: String
    let variant: String
    let model_version: String
    let format: String
    let max_inference_size: [Int]
    let router: Router
    let coarse: Coarse
    let birefnet: BiRefNet

    static func load(from root: URL) throws -> RoutedManifest {
        try decode(Data(contentsOf: root.appendingPathComponent(fileName)))
    }

    /// Decode and reject anything but a well-formed open-weights Core ML bundle
    /// (mirrors `withoutbg.routed.validate_sidecar`).
    static func decode(_ data: Data) throws -> RoutedManifest {
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if raw["pipeline"] as? String == "routed_edge_refine" || raw["refiner"] != nil {
            throw invalid("Edge-refine bundles are withoutBG Enterprise and not supported.")
        }
        let manifest = try JSONDecoder().decode(RoutedManifest.self, from: data)
        try manifest.validate()
        return manifest
    }

    private func validate() throws {
        guard schema_version == 3 else { throw Self.invalid("Unsupported open-weights bundle schema.") }
        guard pipeline == "routed" else { throw Self.invalid("Unsupported open-weights pipeline: \(pipeline).") }
        guard format == "coreml" else { throw Self.invalid("Bundle is not a Core ML bundle.") }
        guard max_inference_size.count == 2, max_inference_size.allSatisfy({ $0 > 0 }) else {
            throw Self.invalid("Invalid max_inference_size.")
        }
        for (file, digest) in [(router.file, router.sha256), (coarse.file, coarse.sha256),
                               (birefnet.file, birefnet.sha256)] {
            guard !file.isEmpty, !file.hasPrefix("/"), !file.split(separator: "/").contains("..") else {
                throw Self.invalid("Bundle model paths must be relative to the bundle.")
            }
            guard digest.count == 64, digest.allSatisfy({ "0123456789abcdef".contains($0) }) else {
                throw Self.invalid("Bundle models require SHA256 checksums.")
            }
        }
        guard !router.categories.isEmpty,
              Set(router.birefnet_categories).isSubset(of: router.categories) else {
            throw Self.invalid("BiRefNet categories must be router categories.")
        }
        guard !router.feature_names.isEmpty, router.feature_names == coarse.feature_names else {
            throw Self.invalid("Router and coarse feature names differ.")
        }
        guard router.inputs.count == 1, router.inputs["rgb_matting"] != nil,
              coarse.inputs.keys.sorted() == ["rgb_depth", "rgb_matting"],
              coarse.inputs["rgb_matting"] == router.inputs["rgb_matting"],
              birefnet.inputs.count == 1, birefnet.inputs["rgb"] != nil else {
            throw Self.invalid("Unexpected graph inputs.")
        }
        for input in Array(router.inputs.values) + Array(coarse.inputs.values) + Array(birefnet.inputs.values) {
            let supported = input.resize == "stretch" && input.size > 0
                && ((input.interpolation == "bicubic" && input.antialias)
                    || (input.interpolation == "bilinear" && !input.antialias))
            guard supported else { throw Self.invalid("Unsupported resize: \(input).") }
        }
        guard coarse.output_size > 0, birefnet.output_size > 0 else {
            throw Self.invalid("Invalid output sizes.")
        }
    }

    private static func invalid(_ message: String) -> ProcessorError {
        .processingFailed(message)
    }
}

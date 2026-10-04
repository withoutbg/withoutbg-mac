import XCTest
@testable import WithoutBGCore

/// Small, valid schema-3 Core ML manifest shared by the routed tests.
enum TestManifest {
    static let categories = ["fine_strand", "soft_detail", "transparency", "hard_opaque", "flat_scene", "vehicle"]
    static let birefnetCategories = ["hard_opaque", "flat_scene", "vehicle"]

    static func json(_ edit: (inout [String: Any]) -> Void = { _ in }) -> Data {
        let sha = String(repeating: "a", count: 64)
        var object: [String: Any] = [
            "schema_version": 3,
            "pipeline": "routed",
            "variant": "oss",
            "model_version": "10.8.0",
            "format": "coreml",
            "max_inference_size": [64, 64],
            "router": [
                "file": "withoutbg-open-weights-backbone.mlpackage", "sha256": sha,
                "inputs": ["rgb_matting": ["size": 16, "resize": "stretch", "interpolation": "bilinear", "antialias": false]],
                "logits_name": "route_logits",
                "feature_names": ["f0", "f1", "f2", "f3"],
                "categories": categories,
                "birefnet_categories": birefnetCategories,
            ],
            "coarse": [
                "file": "withoutbg-open-weights.mlpackage", "sha256": sha,
                "inputs": [
                    "rgb_depth": ["size": 18, "resize": "stretch", "interpolation": "bicubic", "antialias": true],
                    "rgb_matting": ["size": 16, "resize": "stretch", "interpolation": "bilinear", "antialias": false],
                ],
                "feature_names": ["f0", "f1", "f2", "f3"],
                "output_name": "coarse_alpha", "output_size": 16,
            ],
            "birefnet": [
                "file": "birefnet-general.mlpackage", "sha256": sha,
                "inputs": ["rgb": ["size": 32, "resize": "stretch", "interpolation": "bilinear", "antialias": false]],
                "output_name": "alpha", "output_size": 32,
            ],
        ]
        edit(&object)
        return try! JSONSerialization.data(withJSONObject: object)
    }

    static func manifest() -> RoutedManifest {
        try! RoutedManifest.decode(json())
    }
}

final class RoutedManifestTests: XCTestCase {
    func testBundledManifestIsValid() throws {
        let root = try XCTUnwrap(WithoutBGCoreResources.bundle.resourceURL)
        let manifest = try RoutedManifest.load(from: root)
        XCTAssertEqual(manifest.router.categories, TestManifest.categories)
        XCTAssertEqual(Set(manifest.router.birefnet_categories), Set(TestManifest.birefnetCategories))
        for file in [manifest.router.file, manifest.coarse.file, manifest.birefnet.file] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path), file)
        }
    }

    func testTestManifestIsValid() {
        XCTAssertNoThrow(try RoutedManifest.decode(TestManifest.json()))
    }

    func testRejectsMalformedBundles() {
        func set(_ graph: String, _ key: String, _ value: Any) -> (inout [String: Any]) -> Void {
            { object in
                var spec = object[graph] as! [String: Any]
                spec[key] = value
                object[graph] = spec
            }
        }
        let mutations: [String: (inout [String: Any]) -> Void] = [
            "schema 2": { $0["schema_version"] = 2 },
            "edge refine": { $0["pipeline"] = "routed_edge_refine" },
            "refiner key": { $0["refiner"] = [:] },
            "onnx format": { $0["format"] = "onnx" },
            "absolute path": set("router", "file", "/tmp/x.mlpackage"),
            "parent path": set("coarse", "file", "../x.mlpackage"),
            "uppercase sha": set("birefnet", "sha256", String(repeating: "A", count: 64)),
            "short sha": set("router", "sha256", "abc"),
            "birefnet not subset": set("router", "birefnet_categories", ["hard_opaque", "cats"]),
            "feature mismatch": set("coarse", "feature_names", ["f0", "f1"]),
            "bilinear antialias": set("birefnet", "inputs", [
                "rgb": ["size": 32, "resize": "stretch", "interpolation": "bilinear", "antialias": true],
            ]),
            "letterbox": set("birefnet", "inputs", [
                "rgb": ["size": 32, "resize": "letterbox", "interpolation": "bilinear", "antialias": false],
            ]),
            "bad max size": { $0["max_inference_size"] = [0, 64] },
        ]
        for (name, mutate) in mutations {
            XCTAssertThrowsError(try RoutedManifest.decode(TestManifest.json(mutate)), name)
        }
    }
}

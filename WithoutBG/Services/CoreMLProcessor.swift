import CoreGraphics
import CoreML
import Foundation

/// Real, on-device background removal backed by the bundled WBGNet Core ML
/// model (`wbgnet_oss_fp16.mlpackage`, ML Program, fp16, Neural Engine eligible).
///
/// Pipeline mirrors `scripts/serve_wbgnet_coreml.py`:
/// letterbox → tensor (1×3×1024×1024, [0,1] NCHW) → model → alpha
/// (1×1×1024×1024) → crop valid region → resize to source → composite cutout.
///
/// The model is exported with `--input-kind tensor`, so the input is an
/// `MLMultiArray` (not a `CVPixelBuffer`); normalization (`scale=1/255`) is
/// internal to the graph.
final class CoreMLProcessor: BackgroundRemovalProcessor, @unchecked Sendable {
    /// Resource name of the bundled model (Xcode compiles `.mlpackage` →
    /// `.mlmodelc` at build time).
    static let modelName = "wbgnet_oss_fp16"
    private static let canvas = 1024
    private static let inputName = "rgb"
    private static let outputName = "alpha"

    private let lock = NSLock()
    private var cachedModel: MLModel?

    init() {
        // Preload weights/compile off the main thread so the first real image
        // does not pay the full load + compile cost.
        Task.detached(priority: .utility) { [weak self] in
            _ = try? self?.loadModel()
        }
    }

    func process(preparedImage: CGImage) async throws -> ProcessorResult {
        try await Task.detached(priority: .userInitiated) { [self] in
            try runInference(on: preparedImage)
        }.value
    }

    // MARK: - Model loading

    private func loadModel() throws -> MLModel {
        lock.lock()
        defer { lock.unlock() }
        if let cachedModel { return cachedModel }

        guard let url = Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc") else {
            throw ProcessorError.processingFailed(
                "Bundled model \(Self.modelName).mlmodelc was not found in the app bundle."
            )
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let model = try MLModel(contentsOf: url, configuration: config)
        cachedModel = model
        return model
    }

    // MARK: - Inference

    private func runInference(on image: CGImage) throws -> ProcessorResult {
        let start = Date()
        let model = try loadModel()

        guard let (rgba, newW, newH) = ImageUtilities.letterbox(image, canvas: Self.canvas) else {
            throw ProcessorError.invalidImage
        }

        let inputArray = try Self.makeInputArray(rgba: rgba, canvas: Self.canvas)
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            Self.inputName: MLFeatureValue(multiArray: inputArray)
        ])

        let output = try model.prediction(from: provider)
        guard let alpha = output.featureValue(for: Self.outputName)?.multiArrayValue else {
            throw ProcessorError.processingFailed("Model returned no \"\(Self.outputName)\" output.")
        }

        guard let matte = Self.makeMatte(
            from: alpha,
            canvas: Self.canvas,
            validW: newW,
            validH: newH,
            targetW: image.width,
            targetH: image.height
        ) else {
            throw ProcessorError.processingFailed("Could not build the alpha matte.")
        }

        guard let cutout = ImageUtilities.cutout(from: image, matte: matte) else {
            throw ProcessorError.processingFailed("Could not composite the cutout.")
        }

        let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
        return ProcessorResult(processed: cutout, alphaMatte: matte, latencyMs: latencyMs)
    }

    // MARK: - Tensor I/O

    /// Pack the letterboxed RGBA buffer into a `(1, 3, canvas, canvas)` float32
    /// NCHW tensor in `[0, 1]` (R channel first).
    private static func makeInputArray(rgba: [UInt8], canvas: Int) throws -> MLMultiArray {
        let array = try MLMultiArray(
            shape: [1, 3, NSNumber(value: canvas), NSNumber(value: canvas)],
            dataType: .float32
        )
        let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: array.count)
        let plane = canvas * canvas
        let inv: Float32 = 1.0 / 255.0
        for y in 0..<canvas {
            let row = y * canvas
            for x in 0..<canvas {
                let src = (row + x) * 4
                let idx = row + x
                ptr[idx] = Float32(rgba[src]) * inv             // R
                ptr[plane + idx] = Float32(rgba[src + 1]) * inv // G
                ptr[2 * plane + idx] = Float32(rgba[src + 2]) * inv // B
            }
        }
        return array
    }

    /// Crop the model's `(1, 1, canvas, canvas)` alpha output to the valid
    /// letterboxed region, then resize it to the source dimensions.
    private static func makeMatte(
        from alpha: MLMultiArray,
        canvas: Int,
        validW: Int,
        validH: Int,
        targetW: Int,
        targetH: Int
    ) -> CGImage? {
        guard validW > 0, validH > 0 else { return nil }
        var gray = [UInt8](repeating: 0, count: validW * validH)

        func fill(_ read: (Int) -> Float) {
            for y in 0..<validH {
                let srcRow = y * canvas
                let dstRow = y * validW
                for x in 0..<validW {
                    let v = max(0, min(1, read(srcRow + x)))
                    gray[dstRow + x] = UInt8(v * 255 + 0.5)
                }
            }
        }

        switch alpha.dataType {
        case .float32:
            let p = alpha.dataPointer.bindMemory(to: Float32.self, capacity: alpha.count)
            fill { Float(p[$0]) }
        case .float16:
            let p = alpha.dataPointer.bindMemory(to: Float16.self, capacity: alpha.count)
            fill { Float(p[$0]) }
        case .double:
            let p = alpha.dataPointer.bindMemory(to: Double.self, capacity: alpha.count)
            fill { Float(p[$0]) }
        @unknown default:
            return nil
        }

        guard let cropped = ImageUtilities.grayImage(gray, width: validW, height: validH) else {
            return nil
        }
        return ImageUtilities.resizedMatte(cropped, toWidth: targetW, height: targetH)
    }
}

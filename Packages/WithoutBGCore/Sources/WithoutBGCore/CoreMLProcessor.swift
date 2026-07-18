import CoreGraphics
import CoreML
import Foundation

/// Real, on-device background removal backed by the bundled withoutBG Open Weights Core ML
/// model (`wbgnet_oss.mlpackage`, ML Program, fp32, v10).
public final class CoreMLProcessor: BackgroundRemovalProcessor, @unchecked Sendable {
    public static let modelName = "wbgnet_oss"
    public static let modelVersion = "10.0.0"
    private static let canvas = 1024
    private static let inputName = "rgb"
    private static let outputName = "alpha"

    private let lock = NSLock()
    private var cachedModel: MLModel?

    public init() {
        Task.detached(priority: .utility) { [weak self] in
            _ = try? self?.loadModel()
        }
    }

    public func process(preparedImage: CGImage) async throws -> ProcessorResult {
        try await Task.detached(priority: .userInitiated) { [self] in
            try runInference(on: preparedImage)
        }.value
    }

    private func loadModel() throws -> MLModel {
        lock.lock()
        defer { lock.unlock() }
        if let cachedModel { return cachedModel }

        let bundle = WithoutBGCoreResources.bundle
        guard let url = bundle.url(forResource: Self.modelName, withExtension: "mlmodelc")
            ?? bundle.url(forResource: Self.modelName, withExtension: "mlpackage") else {
            throw ProcessorError.processingFailed(
                "Bundled model \(Self.modelName) was not found in WithoutBGCore resources."
            )
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let model = try MLModel(contentsOf: url, configuration: config)
        cachedModel = model
        return model
    }

    private func runInference(on image: CGImage) throws -> ProcessorResult {
        let start = Date()
        let model = try loadModel()

        guard let (tensor, newW, newH) = ImageUtilities.letterboxTensor(
            image,
            canvas: Self.canvas
        ) else {
            throw ProcessorError.invalidImage
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: [
            Self.inputName: MLFeatureValue(multiArray: tensor)
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

import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pure CoreGraphics image helpers — decoding, resizing, mock matte synthesis,
/// cutout compositing and PNG export. Mirrors the web `mock-alpha.ts` math so
/// the native result is visually identical.
public enum ImageUtilities {
    public static let maxDimension: CGFloat = 1024
    /// Side length cap for grid card thumbnails — small enough to keep
    /// 20-card grids cheap, large enough for 2x retina tiles.
    public static let thumbnailDimension: CGFloat = 340

    // MARK: - Decode

    /// Decode arbitrary image data (JPEG/PNG/WebP/HEIC) to a CGImage.
    public static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageSourceShouldCache: true]
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    public static func cgImage(from url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return cgImage(from: data)
    }

    // MARK: - Resize

    /// Resize so the longest side is at most `maxPx`, preserving aspect ratio.
    /// Returns the resized image and its width/height aspect ratio.
    public static func resized(
        _ image: CGImage,
        maxPx: CGFloat = maxDimension
    ) -> (image: CGImage, aspectRatio: CGFloat) {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let scale = min(1, maxPx / max(w, h))
        let newW = max(1, Int((w * scale).rounded()))
        let newH = max(1, Int((h * scale).rounded()))
        let aspect = CGFloat(newW) / CGFloat(newH)

        if scale >= 1 {
            return (image, aspect)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (image, aspect)
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return (ctx.makeImage() ?? image, aspect)
    }

    // MARK: - Letterbox (model input prep)

    /// Letterbox `image` onto a `canvas`×`canvas` black square as a 32BGRA
    /// `CVPixelBuffer`, anchored top-left, preserving aspect ratio (longest side
    /// → `canvas`). Use for Core ML models exported with `--input-kind image`:
    /// Core ML normalizes the uint8 pixels to `[0,1]` and reorders BGRA → RGB
    /// internally. Returns the buffer plus the scaled content size.
    public static func letterboxPixelBuffer(
        _ image: CGImage,
        canvas: Int = Int(maxDimension)
    ) -> (pixelBuffer: CVPixelBuffer, newW: Int, newH: Int)? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0, canvas > 0 else { return nil }

        let newW: Int
        let newH: Int
        if h >= w {
            newH = canvas
            newW = max(1, Int((Double(w) * Double(canvas) / Double(h)).rounded()))
        } else {
            newW = canvas
            newH = max(1, Int((Double(h) * Double(canvas) / Double(w)).rounded()))
        }

        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            canvas,
            canvas,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let pixelBuffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // 32BGRA = premultipliedFirst + little-endian byte order.
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: base,
            width: canvas,
            height: canvas,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        // Fresh CVPixelBuffer memory is not guaranteed zeroed; paint the black
        // padding explicitly before compositing the content.
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
        ctx.interpolationQuality = .high
        // CGContext drawing uses a bottom-left origin, but the bitmap row 0 in
        // memory is the top scanline. This y offset top-anchors the content in
        // the buffer (matching PIL paste at (0, 0) in serve_wbgnet_coreml.py).
        ctx.draw(image, in: CGRect(x: 0, y: canvas - newH, width: newW, height: newH))
        return (pixelBuffer, newW, newH)
    }

    /// Letterbox `image` onto a `canvas`×`canvas` black square as an NCHW
    /// float32 tensor `(1, 3, canvas, canvas)` in `[0, 1]`. Use for Core ML
    /// models exported with `--input-kind tensor`. Returns the tensor plus the
    /// scaled content size.
    public static func letterboxTensor(
        _ image: CGImage,
        canvas: Int = Int(maxDimension)
    ) -> (tensor: MLMultiArray, newW: Int, newH: Int)? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0, canvas > 0 else { return nil }

        let newW: Int
        let newH: Int
        if h >= w {
            newH = canvas
            newW = max(1, Int((Double(w) * Double(canvas) / Double(h)).rounded()))
        } else {
            newW = canvas
            newH = max(1, Int((Double(h) * Double(canvas) / Double(w)).rounded()))
        }

        var rgba = [UInt8](repeating: 0, count: canvas * canvas * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba,
            width: canvas,
            height: canvas,
            bitsPerComponent: 8,
            bytesPerRow: canvas * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
        ctx.interpolationQuality = .high
        // Same top-left anchor as letterboxPixelBuffer (see draw call above).
        ctx.draw(image, in: CGRect(x: 0, y: canvas - newH, width: newW, height: newH))

        guard let tensor = try? MLMultiArray(
            shape: [1, 3, canvas, canvas] as [NSNumber],
            dataType: .float32
        ) else {
            return nil
        }

        let ptr = tensor.dataPointer.bindMemory(to: Float32.self, capacity: tensor.count)
        let planeSize = canvas * canvas
        // Bitmap rows are already top-first; map row y directly into NCHW.
        for y in 0..<canvas {
            let rowBase = y * canvas
            let rgbaBase = rowBase * 4
            for x in 0..<canvas {
                let dstIdx = rowBase + x
                let rgbaIdx = rgbaBase + x * 4
                ptr[dstIdx] = Float32(rgba[rgbaIdx]) / 255
                ptr[planeSize + dstIdx] = Float32(rgba[rgbaIdx + 1]) / 255
                ptr[2 * planeSize + dstIdx] = Float32(rgba[rgbaIdx + 2]) / 255
            }
        }

        return (tensor, newW, newH)
    }

    /// Build a grayscale CGImage from a top-first row-major 8-bit buffer.
    public static func grayImage(_ pixels: [UInt8], width w: Int, height h: Int) -> CGImage? {
        guard w > 0, h > 0, pixels.count >= w * h else { return nil }
        // Bitmap contexts created with an explicit data buffer store row 0 as the
        // top scanline on macOS — write top-first pixels directly (no flip).
        var data = pixels
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &data,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        return ctx.makeImage()
    }

    /// High-quality resize of a (grayscale) matte to an exact pixel size.
    public static func resizedMatte(_ image: CGImage, toWidth w: Int, height h: Int) -> CGImage? {
        guard w > 0, h > 0 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - Mock alpha matte

    /// Synthetic grayscale matte: soft elliptical radial gradient centered at
    /// 50% / 47% (portrait bias). White center → black edge. Matches
    /// `generateMockAlphaMatte` in the web prototype.
    public static func mockAlphaMatte(for image: CGImage) -> CGImage? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: w * h)
        let cx = Double(w) * 0.5
        let cy = Double(h) * 0.47
        let rx = Double(w) * 0.38
        let ry = Double(h) * 0.44

        for y in 0..<h {
            let dy = (Double(y) - cy) / ry
            let dySq = dy * dy
            let rowBase = y * w
            for x in 0..<w {
                let dx = (Double(x) - cx) / rx
                let dist = (dx * dx + dySq).squareRoot()
                let t = max(0, 1 - dist)
                let value = smoothstep(0, 1, t * 1.25) * 255
                buffer[rowBase + x] = UInt8(max(0, min(255, value)))
            }
        }

        return grayImage(buffer, width: w, height: h)
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    // MARK: - Cutout compositing

    /// Apply the grayscale matte's luminance as the alpha channel of `image`,
    /// producing a transparent cutout. Mirrors `compositeCutout`.
    public static func cutout(from image: CGImage, matte: CGImage) -> CGImage? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }

        // 1. Rasterize the source into a known RGBA layout.
        guard let rgba = rgbaBuffer(from: image, width: w, height: h) else { return nil }

        // 2. Rasterize the matte (scaled to match) into a grayscale buffer.
        guard let matteBuffer = grayBuffer(from: matte, width: w, height: h) else { return nil }

        // 3. Replace alpha with matte luminance (matte is opaque, so RGB is
        //    already straight here because the source alpha was 255).
        var out = rgba
        for i in 0..<(w * h) {
            out[i * 4 + 3] = matteBuffer[i]
        }

        // 4. Emit a non-premultiplied RGBA CGImage so PNG export keeps colors.
        return makeRGBAImage(out, width: w, height: h, premultiplied: false)
    }

    // MARK: - Background compositing (export)

    /// Composite a transparent cutout over a solid background. Pass `nil` to
    /// keep transparency.
    public static func composited(_ cutout: CGImage, over background: CGColor?) -> CGImage? {
        guard let background else { return cutout }
        let w = cutout.width
        let h = cutout.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return cutout
        }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.setFillColor(background)
        ctx.fill(rect)
        ctx.draw(cutout, in: rect)
        return ctx.makeImage()
    }

    // MARK: - PNG export

    public static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    // MARK: - Buffer helpers

    private static func rgbaBuffer(from image: CGImage, width w: Int, height h: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &buffer,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buffer
    }

    private static func grayBuffer(from image: CGImage, width w: Int, height h: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: w * h)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &buffer,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buffer
    }

    private static func makeRGBAImage(
        _ buffer: [UInt8],
        width w: Int,
        height h: Int,
        premultiplied: Bool
    ) -> CGImage? {
        var data = buffer
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let alphaInfo: CGImageAlphaInfo = premultiplied ? .premultipliedLast : .last
        let bitmapInfo = CGBitmapInfo(rawValue: alphaInfo.rawValue)
        guard let provider = CGDataProvider(
            data: Data(bytes: &data, count: data.count) as CFData
        ) else {
            return nil
        }
        return CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

import Accelerate
import CoreGraphics
import Foundation

/// Bit-faithful ports of the resizes the reference host (`withoutbg.routed`) uses,
/// so the graphs see the same pixels on macOS as under the Python SDK and Docker.
/// CoreGraphics / vImage scaling use different kernels and are deliberately avoided.
enum Resampling {
    // MARK: - Pixels

    /// Straight (unpremultiplied) 8-bit RGB, row-major, interleaved. Like PIL's
    /// `convert("RGB")`, alpha is dropped and no colour matching is applied.
    struct RGB8 {
        var pixels: [UInt8]
        let width: Int
        let height: Int
    }

    static func rgb8(from image: CGImage) -> RGB8? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let format = vImage_CGImageFormat(
            bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        ), let buffer = try? vImage_Buffer(cgImage: image, format: format) else { return nil }
        defer { buffer.free() }
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        let src = buffer.data.assumingMemoryBound(to: UInt8.self)
        rgb.withUnsafeMutableBufferPointer { dst in
            for y in 0..<h {
                let row = src + y * buffer.rowBytes
                for x in 0..<w {
                    let o = (y * w + x) * 3
                    dst[o] = row[x * 4]
                    dst[o + 1] = row[x * 4 + 1]
                    dst[o + 2] = row[x * 4 + 2]
                }
            }
        }
        return RGB8(pixels: rgb, width: w, height: h)
    }

    /// `routed.fit_max_size`: PIL default (bicubic) downscale to fit, `int()` sizes.
    static func fitMaxSize(_ image: RGB8, maxWidth: Int, maxHeight: Int) -> RGB8 {
        var w = image.width, h = image.height
        let ar = Double(w) / Double(h)
        var resize = false
        if w > maxWidth { (w, h, resize) = (maxWidth, Int(Double(maxWidth) / ar), true) }
        if h > maxHeight { (h, w, resize) = (maxHeight, Int(Double(maxHeight) * ar), true) }
        guard resize else { return image }
        let out = PIL.resize8(image.pixels, width: image.width, height: image.height, channels: 3,
                              toWidth: w, height: h, filter: .bicubic)
        return RGB8(pixels: out, width: w, height: h)
    }

    /// `np.asarray(rgb, float32) / 255.0` as planar CHW.
    static func planarFloat(_ image: RGB8) -> [Float] {
        let n = image.width * image.height
        var out = [Float](repeating: 0, count: 3 * n)
        image.pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for i in 0..<n {
                    dst[i] = Float(src[i * 3]) / 255
                    dst[n + i] = Float(src[i * 3 + 1]) / 255
                    dst[2 * n + i] = Float(src[i * 3 + 2]) / 255
                }
            }
        }
        return out
    }

    // MARK: - torch bilinear (align_corners=False, no antialias)

    /// Port of `routed._bilinear_axis`.
    static func bilinearAxis(_ src: Int, _ dst: Int) -> (i0: [Int], i1: [Int], l: [Float]) {
        var i0 = [Int](repeating: 0, count: dst), i1 = i0, l = [Float](repeating: 0, count: dst)
        let scale = Double(src) / Double(dst)
        for i in 0..<dst {
            let pos = max((Double(i) + 0.5) * scale - 0.5, 0)
            i0[i] = Int(pos)
            i1[i] = min(i0[i] + 1, src - 1)
            l[i] = Float(pos - Double(i0[i]))
        }
        return (i0, i1, l)
    }

    /// Port of `routed.resize_bilinear`: planar `channels×h×w` → `channels×outH×outW`,
    /// rows first then columns, in Float like the NumPy reference.
    static func torchBilinear(
        _ src: UnsafePointer<Float>, channels: Int, height h: Int, width w: Int,
        toHeight outH: Int, width outW: Int, into dst: UnsafeMutablePointer<Float>
    ) {
        if h == outH, w == outW {
            dst.update(from: src, count: channels * h * w)
            return
        }
        let (r0, r1, rl) = bilinearAxis(h, outH)
        let (c0, c1, cl) = bilinearAxis(w, outW)
        DispatchQueue.concurrentPerform(iterations: channels * outH) { job in
            let c = job / outH, y = job % outH
            let a = src + (c * h + r0[y]) * w, b = src + (c * h + r1[y]) * w
            let wb = rl[y], wa = 1 - wb
            let out = dst + (c * outH + y) * outW
            for x in 0..<outW {
                let left = a[c0[x]] * wa + b[c0[x]] * wb
                let right = a[c1[x]] * wa + b[c1[x]] * wb
                out[x] = left * (1 - cl[x]) + right * cl[x]
            }
        }
    }

    // MARK: - PIL (libImaging Resample.c)

    enum PIL {
        enum Filter {
            case bilinear, bicubic

            var support: Double { self == .bilinear ? 1 : 2 }

            func callAsFunction(_ value: Double) -> Double {
                let x = abs(value)
                switch self {
                case .bilinear:
                    return x < 1 ? 1 - x : 0
                case .bicubic:
                    let a = -0.5
                    if x < 1 { return ((a + 2) * x - (a + 3)) * x * x + 1 }
                    if x < 2 { return (((x - 5) * x + 8) * x - 4) * a }
                    return 0
                }
            }
        }

        struct Coefficients {
            let ksize: Int
            let bounds: [(min: Int, count: Int)]
            let weights: [Double]
        }

        /// `precompute_coeffs` for the whole-image box.
        static func coefficients(_ inSize: Int, _ outSize: Int, _ filter: Filter) -> Coefficients {
            let scale = Double(inSize) / Double(outSize)
            let filterScale = max(scale, 1)
            let support = filter.support * filterScale
            let ksize = Int(support.rounded(.up)) * 2 + 1
            var bounds = [(min: Int, count: Int)]()
            bounds.reserveCapacity(outSize)
            var weights = [Double](repeating: 0, count: outSize * ksize)
            let ss = 1 / filterScale
            for xx in 0..<outSize {
                let center = (Double(xx) + 0.5) * scale
                var xmin = Int(center - support + 0.5)
                if xmin < 0 { xmin = 0 }
                var xmax = Int(center + support + 0.5)
                if xmax > inSize { xmax = inSize }
                xmax -= xmin
                var ww = 0.0
                for x in 0..<xmax {
                    let w = filter((Double(x + xmin) - center + 0.5) * ss)
                    weights[xx * ksize + x] = w
                    ww += w
                }
                if ww != 0 {
                    for x in 0..<xmax { weights[xx * ksize + x] /= ww }
                }
                bounds.append((xmin, xmax))
            }
            return Coefficients(ksize: ksize, bounds: bounds, weights: weights)
        }

        private static let precisionBits = 32 - 8 - 2

        /// `normalize_coeffs_8bpc`: fixed point, rounded half away from zero.
        static func fixedPoint(_ weights: [Double]) -> [Int32] {
            let one = Double(1 << precisionBits)
            return weights.map { $0 < 0 ? Int32(-0.5 + $0 * one) : Int32(0.5 + $0 * one) }
        }

        @inline(__always) private static func clip8(_ value: Int32) -> UInt8 {
            let v = value >> Int32(precisionBits)
            return v < 0 ? 0 : v > 255 ? 255 : UInt8(v)
        }

        /// `Image.resize` on an 8-bit image (`L` or `RGB`): horizontal then vertical
        /// pass, each skipped when that axis is unchanged.
        static func resize8(
            _ src: [UInt8], width w: Int, height h: Int, channels: Int,
            toWidth outW: Int, height outH: Int, filter: Filter
        ) -> [UInt8] {
            var image = src, curW = w
            if outW != w {
                let co = coefficients(w, outW, filter)
                let k = fixedPoint(co.weights)
                var out = [UInt8](repeating: 0, count: outW * h * channels)
                image.withUnsafeBufferPointer { inp in
                    out.withUnsafeMutableBufferPointer { dst in
                        let inBase = inp.baseAddress!, outBase = dst.baseAddress!
                        DispatchQueue.concurrentPerform(iterations: h) { y in
                            let row = inBase + y * w * channels
                            let orow = outBase + y * outW * channels
                            for xx in 0..<outW {
                                let (xmin, count) = co.bounds[xx]
                                for c in 0..<channels {
                                    var ss: Int32 = 1 << Int32(precisionBits - 1)
                                    for x in 0..<count {
                                        ss &+= Int32(row[(xmin + x) * channels + c]) &* k[xx * co.ksize + x]
                                    }
                                    orow[xx * channels + c] = clip8(ss)
                                }
                            }
                        }
                    }
                }
                image = out
                curW = outW
            }
            if outH != h {
                let co = coefficients(h, outH, filter)
                let k = fixedPoint(co.weights)
                let stride = curW * channels
                var out = [UInt8](repeating: 0, count: outH * stride)
                image.withUnsafeBufferPointer { inp in
                    out.withUnsafeMutableBufferPointer { dst in
                        let inBase = inp.baseAddress!, outBase = dst.baseAddress!
                        DispatchQueue.concurrentPerform(iterations: outH) { yy in
                            let (ymin, count) = co.bounds[yy]
                            let orow = outBase + yy * stride
                            for i in 0..<stride {
                                var ss: Int32 = 1 << Int32(precisionBits - 1)
                                for y in 0..<count {
                                    ss &+= Int32(inBase[(ymin + y) * stride + i]) &* k[yy * co.ksize + y]
                                }
                                orow[i] = clip8(ss)
                            }
                        }
                    }
                }
                image = out
            }
            return image
        }

        /// `Image.resize` on a mode `F` (float32) single-channel image.
        static func resizeF(
            _ src: UnsafePointer<Float>, width w: Int, height h: Int,
            toWidth outW: Int, height outH: Int, filter: Filter,
            into dst: UnsafeMutablePointer<Float>
        ) {
            var temp = [Float]()
            var current = src, curW = w
            if outW != w {
                let co = coefficients(w, outW, filter)
                temp = [Float](repeating: 0, count: outW * h)
                temp.withUnsafeMutableBufferPointer { out in
                    let outBase = out.baseAddress!
                    DispatchQueue.concurrentPerform(iterations: h) { y in
                        let row = src + y * w
                        for xx in 0..<outW {
                            let (xmin, count) = co.bounds[xx]
                            var ss = 0.0
                            for x in 0..<count {
                                ss += Double(row[xmin + x]) * co.weights[xx * co.ksize + x]
                            }
                            outBase[y * outW + xx] = Float(ss)
                        }
                    }
                }
                curW = outW
            }
            temp.withUnsafeBufferPointer { tbuf in
                if outW != w { current = tbuf.baseAddress! }
                if outH == h {
                    dst.update(from: current, count: curW * h)
                    return
                }
                let co = coefficients(h, outH, filter)
                let input = current
                DispatchQueue.concurrentPerform(iterations: outH) { yy in
                    let (ymin, count) = co.bounds[yy]
                    for x in 0..<curW {
                        var ss = 0.0
                        for y in 0..<count {
                            ss += Double(input[(ymin + y) * curW + x]) * co.weights[yy * co.ksize + y]
                        }
                        dst[yy * curW + x] = Float(ss)
                    }
                }
            }
        }
    }

    /// `routed.resize_bicubic_antialias`: per-channel PIL "F" bicubic, planar in/out.
    static func bicubicAntialias(
        _ src: UnsafePointer<Float>, height h: Int, width w: Int, size: Int,
        into dst: UnsafeMutablePointer<Float>
    ) {
        for c in 0..<3 {
            PIL.resizeF(src + c * h * w, width: w, height: h, toWidth: size, height: size,
                        filter: .bicubic, into: dst + c * size * size)
        }
    }
}

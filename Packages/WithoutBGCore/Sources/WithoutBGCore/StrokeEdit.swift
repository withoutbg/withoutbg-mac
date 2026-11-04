import CoreGraphics
import Foundation

/// Keep / Remove edit (Open Weights v4, sidecar `stroke_edit`): a port of
/// withoutbg-python `withoutbg/edit.py` (the withoutBG reference host).
///
/// Strokes are one `{0, 0.5, 1}` map (remove, untouched, keep). The stroke-edit graph
/// maps RGB + matte + strokes + depth at 448² to an edited matte; it is upsampled and
/// blended in only around the strokes and the pieces they touch. Only Remove is clamped.
enum StrokeEdit {
    static let remove: Float = 0
    static let untouched: Float = 0.5
    static let keep: Float = 1
    static let markedMin: UInt8 = 128
    static let strokeRadiusFrac = 0.02
    static let strokeRadiusMin = 8
    static let changeMin: Float = 0.1

    // MARK: - Masks

    /// Marks of a Keep / Remove mask image: light, opaque pixels (`>= 128` composited
    /// onto black, PIL `L` luma). Nil when the mask does not match `width × height`.
    static func marks(from mask: CGImage, width w: Int, height h: Int) -> [Bool]? {
        guard mask.width == w, mask.height == h else { return nil }
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Premultiplied onto a cleared (black, transparent) buffer = composited onto black.
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))
        var out = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) {
            let r = Int(rgba[4 * i]), g = Int(rgba[4 * i + 1]), b = Int(rgba[4 * i + 2])
            let luma = (r * 299 + g * 587 + b * 114) / 1000
            out[i] = luma >= Int(markedMin)
        }
        return out
    }

    /// `combine_masks`: Remove wins where both mark a pixel.
    static func combine(keep: [Bool]?, remove: [Bool]?, count: Int) -> [Float] {
        var out = [Float](repeating: untouched, count: count)
        if let keep { for i in 0..<count where keep[i] { out[i] = Self.keep } }
        if let remove { for i in 0..<count where remove[i] { out[i] = Self.remove } }
        return out
    }

    /// `net_clamp`: the strokes the edit clamps (Keep marks become untouched).
    static func netClamp(_ strokes: [Float]) -> [Float] {
        strokes.map { $0 == keep ? untouched : $0 }
    }

    static func applyStrokes(_ alpha: inout [Float], clamp: [Float]) {
        for i in alpha.indices {
            if clamp[i] == keep { alpha[i] = 1 } else if clamp[i] == remove { alpha[i] = 0 }
        }
    }

    /// `resize_nearest` (index rule of `F.interpolate(mode="nearest")`).
    static func resizeNearest(_ src: [Float], width iw: Int, height ih: Int, toWidth w: Int, height h: Int) -> [Float] {
        if (iw, ih) == (w, h) { return src }
        let rows = (0..<h).map { min(Int(Double($0) * (Double(ih) / Double(h))), ih - 1) }
        let cols = (0..<w).map { min(Int(Double($0) * (Double(iw) / Double(w))), iw - 1) }
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { out[y * w + x] = src[rows[y] * iw + cols[x]] } }
        return out
    }

    // MARK: - Graph input

    /// `resize_area` on one `h × w` plane → `size × size` (adaptive average pool).
    static func resizeArea(_ plane: [Float], width w: Int, height h: Int, size: Int) -> [Float] {
        func axisRanges(_ n: Int) -> [(Int, Int)] {
            (0..<size).map { i in ((i * n) / size, ((i + 1) * n + size - 1) / size) }  // floor, ceil
        }
        let rows = axisRanges(h), cols = axisRanges(w)
        // Columns first (axis 2 after axis 1 in numpy is order-independent for sums).
        var tmp = [Double](repeating: 0, count: h * size)
        for y in 0..<h {
            var csum = [Double](repeating: 0, count: w + 1)
            for x in 0..<w { csum[x + 1] = csum[x] + Double(plane[y * w + x]) }
            for (j, (s, e)) in cols.enumerated() { tmp[y * size + j] = (csum[e] - csum[s]) / Double(e - s) }
        }
        var out = [Float](repeating: 0, count: size * size)
        for j in 0..<size {
            var csum = [Double](repeating: 0, count: h + 1)
            for y in 0..<h { csum[y + 1] = csum[y] + tmp[y * size + j] }
            for (i, (s, e)) in rows.enumerated() { out[i * size + j] = Float((csum[e] - csum[s]) / Double(e - s)) }
        }
        return out
    }

    /// `soften_hard_strokes`: `[1, 2, 1] / 4` tent (edge-replicated) when the marks have no partial pixels.
    static func softenHard(_ planes: [[Float]], size s: Int) -> [[Float]] {
        if planes.contains(where: { $0.contains { $0 > 0 && $0 < 1 } }) { return planes }
        return planes.map { p in
            var h = [Float](repeating: 0, count: s * s)
            for y in 0..<s {
                for x in 0..<s {
                    let l = p[y * s + max(x - 1, 0)], c = p[y * s + x], r = p[y * s + min(x + 1, s - 1)]
                    h[y * s + x] = (l + 2 * c + r) / 4
                }
            }
            var v = [Float](repeating: 0, count: s * s)
            for y in 0..<s {
                for x in 0..<s {
                    let u = h[max(y - 1, 0) * s + x], c = h[y * s + x], d = h[min(y + 1, s - 1) * s + x]
                    v[y * s + x] = (u + 2 * c + d) / 4
                }
            }
            return v
        }
    }

    /// `stroke_edit_input`: `[1, 7, S, S]` planes (r, g, b, matte, keep, remove, depth).
    static func input(rgbPlanar rgb: [Float], matte: [Float], strokes: [Float], depth: [Float],
                      width w: Int, height h: Int, size: Int) -> [Float] {
        let n = w * h
        var planes: [[Float]] = (0..<3).map { c in resizeArea(Array(rgb[(c * n)..<((c + 1) * n)]), width: w, height: h, size: size) }
        planes.append(resizeArea(matte.map { min(max($0, 0), 1) }, width: w, height: h, size: size))
        let marks = softenHard([
            resizeArea(strokes.map { $0 == keep ? 1 : 0 }, width: w, height: h, size: size),
            resizeArea(strokes.map { $0 == remove ? 1 : 0 }, width: w, height: h, size: size),
        ], size: size)
        planes += marks
        planes.append(depth.map { min(max($0, 0), 1) })
        return planes.flatMap { $0 }
    }

    // MARK: - Edit region

    static func strokeRadius(width w: Int, height h: Int) -> Int {
        max(strokeRadiusMin, Int((strokeRadiusFrac * Double(max(w, h))).rounded()))
    }

    /// Square dilation by `r` (cv2.dilate with a `(2r+1)²` ones kernel), separable.
    static func dilate(_ mask: [Bool], width w: Int, height h: Int, radius r: Int) -> [Bool] {
        guard r > 0, mask.contains(true) else { return mask }
        var tmp = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            var last = -Int.max / 2  // last marked x seen so far
            var next = [Int](repeating: Int.max / 2, count: w)
            var nx = Int.max / 2
            for x in stride(from: w - 1, through: 0, by: -1) { if mask[y * w + x] { nx = x }; next[x] = nx }
            for x in 0..<w {
                if mask[y * w + x] { last = x }
                tmp[y * w + x] = x - last <= r || next[x] - x <= r
            }
        }
        var out = [Bool](repeating: false, count: w * h)
        for x in 0..<w {
            var last = -Int.max / 2
            var next = [Int](repeating: Int.max / 2, count: h)
            var ny = Int.max / 2
            for y in stride(from: h - 1, through: 0, by: -1) { if tmp[y * w + x] { ny = y }; next[y] = ny }
            for y in 0..<h {
                if tmp[y * w + x] { last = y }
                out[y * w + x] = y - last <= r || next[y] - y <= r
            }
        }
        return out
    }

    /// 8-connected component labels (0 = background), union-find.
    static func labels(_ mask: [Bool], width w: Int, height h: Int) -> [Int32] {
        var parent = [Int32](repeating: 0, count: w * h + 1)
        var label = [Int32](repeating: 0, count: w * h)
        var count: Int32 = 0
        func find(_ a: Int32) -> Int32 {
            var a = a
            while parent[Int(a)] != a { parent[Int(a)] = parent[Int(parent[Int(a)])]; a = parent[Int(a)] }
            return a
        }
        for y in 0..<h {
            for x in 0..<w where mask[y * w + x] {
                var best: Int32 = 0
                for (dx, dy) in [(-1, 0), (-1, -1), (0, -1), (1, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < w, ny >= 0 else { continue }
                    let l = label[ny * w + nx]
                    guard l != 0 else { continue }
                    if best == 0 { best = find(l) } else {
                        let a = find(best), b = find(l)
                        if a != b { parent[Int(max(a, b))] = min(a, b); best = min(a, b) }
                    }
                }
                if best == 0 { count += 1; parent[Int(count)] = count; best = count }
                label[y * w + x] = best
            }
        }
        for i in label.indices where label[i] != 0 { label[i] = find(label[i]) }
        return label
    }

    /// cv2.distanceTransform(DIST_L2, 5): distance to the nearest outside pixel (5×5 chamfer).
    static func distanceInside(_ mask: [Bool], width w: Int, height h: Int) -> [Float] {
        let a: Float = 1, b: Float = 1.4, c: Float = 2.1969
        let big: Float = 1e9
        var d = mask.map { $0 ? big : 0 }
        let fwd: [(Int, Int, Float)] = [(-1, 0, a), (0, -1, a), (-1, -1, b), (1, -1, b),
                                        (-2, -1, c), (-1, -2, c), (1, -2, c), (2, -1, c)]
        func at(_ x: Int, _ y: Int) -> Float {
            // Like cv2, pixels beyond the image border never count as outside the region.
            (x < 0 || y < 0 || x >= w || y >= h) ? big : d[y * w + x]
        }
        for y in 0..<h {
            for x in 0..<w where d[y * w + x] > 0 {
                var v = d[y * w + x]
                for (dx, dy, cost) in fwd { v = min(v, at(x + dx, y + dy) + cost) }
                d[y * w + x] = v
            }
        }
        for y in stride(from: h - 1, through: 0, by: -1) {
            for x in stride(from: w - 1, through: 0, by: -1) where d[y * w + x] > 0 {
                var v = d[y * w + x]
                for (dx, dy, cost) in fwd { v = min(v, at(x - dx, y - dy) + cost) }
                d[y * w + x] = v
            }
        }
        return d
    }

    /// `stroke_region` blend weight: 1 well inside the edit region, feathered to 0 at its edge.
    static func regionWeight(matte: [Float], guided: [Float], strokes: [Float], width w: Int, height h: Int) -> [Float] {
        let r = strokeRadius(width: w, height: h)
        let seeds = dilate(strokes.map { $0 != untouched }, width: w, height: h, radius: r)
        guard seeds.contains(true) else { return [Float](repeating: 0, count: w * h) }
        var grow = seeds
        for i in grow.indices where abs(guided[i] - matte[i]) > changeMin { grow[i] = true }
        let lab = labels(grow, width: w, height: h)
        var touched = Set<Int32>()
        for i in seeds.indices where seeds[i] { touched.insert(lab[i]) }
        let picked = lab.indices.map { grow[$0] && touched.contains(lab[$0]) }
        let region = dilate(picked, width: w, height: h, radius: r)
        let inside = distanceInside(region, width: w, height: h)
        let feather = max(1, Float(r) / 2)
        return inside.map { min(max($0 / feather, 0), 1) }
    }

    /// `edit_alpha` without a refiner: edited alpha at the working size.
    static func editAlpha(rgbPlanar rgb: [Float], matte: [Float], strokes: [Float], depth: [Float],
                          width w: Int, height h: Int, size: Int,
                          runEditor: ([Float]) throws -> [Float]) throws -> [Float] {
        let matte = matte.map { min(max($0, 0), 1) }
        let coarse = try runEditor(input(rgbPlanar: rgb, matte: matte, strokes: strokes, depth: depth,
                                         width: w, height: h, size: size))
        guard coarse.count == size * size, coarse.allSatisfy(\.isFinite) else {
            throw ProcessorError.processingFailed("Non-finite stroke-edit output.")
        }
        let clipped = coarse.map { min(max($0, 0), 1) }
        var up = [Float](repeating: 0, count: w * h)
        clipped.withUnsafeBufferPointer { src in
            up.withUnsafeMutableBufferPointer { dst in
                Resampling.torchBilinear(src.baseAddress!, channels: 1, height: size, width: size,
                                         toHeight: h, width: w, into: dst.baseAddress!)
            }
        }
        let clamp = netClamp(strokes)
        var guided = up
        applyStrokes(&guided, clamp: clamp)
        let weight = regionWeight(matte: matte, guided: guided, strokes: strokes, width: w, height: h)
        var alpha = (0..<(w * h)).map { i in matte[i] + weight[i] * (min(max(up[i], 0), 1) - matte[i]) }
        applyStrokes(&alpha, clamp: clamp)
        return alpha
    }
}

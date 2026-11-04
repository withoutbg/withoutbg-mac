import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Smart brush edit context: the image-only inputs of the stroke edit.
///
/// The stroke-edit graph needs the coarse graph's `edit_depth`. It depends only
/// on the image, so the first edit computes it and later edits of the same image
/// reuse it: the router and coarse graphs (ConvNeXt, Depth Anything) are skipped
/// and only the stroke-edit graph runs. The app keeps it on the job; the Local
/// API hands it to the client as an opaque token (`token`) and takes it back.
///
/// Token: `wbgctx1.<category>.<fingerprint>.<base64 PNG>`, the PNG being the
/// `S × S` depth as 16-bit grayscale (`round(d * 65535)`), same format as the
/// Docker server. The fingerprint ties it to the working image, so a token from
/// another image or host is stale, never wrong: the pipeline recomputes.
public struct EditContext: Sendable, Equatable {
    public static let prefix = "wbgctx1"

    /// Router category of the image.
    public let category: String
    /// 16 hex chars identifying the working image (`fingerprint(of:)`).
    public let fingerprint: String
    /// Row-major `size × size` normalised inverse depth in `[0, 1]`.
    public let depth: [Float]
    public let size: Int

    public init(category: String, fingerprint: String, depth: [Float], size: Int) {
        self.category = category
        self.fingerprint = fingerprint
        self.depth = depth
        self.size = size
    }

    /// SHA256 over `"<w>x<h>:"` and the interleaved RGB8 pixels, first 16 hex chars.
    static func fingerprint(of image: Resampling.RGB8) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("\(image.width)x\(image.height):".utf8))
        image.pixels.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        return hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Token

    /// Opaque token for the Local API (`editContext` / `edit_context`).
    public var token: String? {
        guard depth.count == size * size, let png = Self.png16(depth, size: size) else { return nil }
        return "\(Self.prefix).\(category).\(fingerprint).\(png.base64EncodedString())"
    }

    /// Parse a token; nil when malformed, from an unknown category or not `size × size`.
    public init?(token: String, categories: [String], size: Int) {
        guard token.utf8.count <= 4 * 1024 * 1024 else { return nil }
        let parts = token.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == Self.prefix, categories.contains(String(parts[1])) else { return nil }
        let fp = String(parts[2])
        guard fp.count == 16, fp.allSatisfy({ "0123456789abcdef".contains($0) }),
              let data = Data(base64Encoded: String(parts[3])),
              let depth = Self.decodePNG16(data, size: size) else { return nil }
        self.init(category: String(parts[1]), fingerprint: fp, depth: depth, size: size)
    }

    static func png16(_ values: [Float], size: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: size * size * 2)
        for (i, v) in values.enumerated() {
            let q = UInt16((min(max(v, 0), 1) * 65535).rounded())
            bytes[2 * i] = UInt8(q >> 8)
            bytes[2 * i + 1] = UInt8(q & 0xff)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                  width: size, height: size, bitsPerComponent: 16, bitsPerPixel: 16,
                  bytesPerRow: size * 2, space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue
                      | CGBitmapInfo.byteOrder16Big.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// Raw 16-bit gray samples of a PNG, no color management.
    static func decodePNG16(_ data: Data, size: Int) -> [Float]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == size, image.height == size,
              image.bitsPerComponent == 16, image.bitsPerPixel == 16,
              image.colorSpace?.model == .monochrome,
              let raw = image.dataProvider?.data as Data? else { return nil }
        let little = image.bitmapInfo.contains(.byteOrder16Little)
        let row = image.bytesPerRow
        guard raw.count >= row * (size - 1) + size * 2 else { return nil }
        var out = [Float](repeating: 0, count: size * size)
        raw.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            let p = buf.bindMemory(to: UInt8.self)
            for y in 0..<size {
                for x in 0..<size {
                    let o = y * row + 2 * x
                    let q = little ? UInt16(p[o]) | UInt16(p[o + 1]) << 8 : UInt16(p[o]) << 8 | UInt16(p[o + 1])
                    out[y * size + x] = Float(q) / 65535
                }
            }
        }
        return out
    }
}

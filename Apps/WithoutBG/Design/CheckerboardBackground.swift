import CoreGraphics
import SwiftUI

/// Opaque light-gray/white transparency checkerboard (8pt squares).
///
/// A single 16×16pt tile CGImage is generated once at startup and tiled by the
/// GPU via `Image.resizable(resizingMode: .tile)` — far cheaper than redrawing
/// a Canvas path per card.
struct CheckerboardBackground: View {
    /// Side length of one square in points.
    var square: CGFloat = 8

    /// Shared tile image (16×16pt, two tones) — created once.
    private static let tile: Image = makeTile(square: 8)

    var body: some View {
        Self.tile
            .resizable(resizingMode: .tile)
            .accessibilityHidden(true)
    }

    // MARK: - Tile generation

    private static func makeTile(square: CGFloat) -> Image {
        let side = Int(square * 2)  // tile contains a 2×2 arrangement of squares
        let light: UInt8 = 0xFF
        let dark: UInt8  = 0xE8
        var pixels = [UInt8](repeating: light, count: side * side * 4)

        for row in 0..<side {
            for col in 0..<side {
                let tileRow = row / Int(square)
                let tileCol = col / Int(square)
                guard (tileRow + tileCol) % 2 != 0 else { continue }
                let i = (row * side + col) * 4
                pixels[i]     = dark
                pixels[i + 1] = dark
                pixels[i + 2] = dark
                pixels[i + 3] = light
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: side,
                height: side,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: side * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else {
            // Fallback: plain light-gray fill
            return Image(systemName: "square.fill")
        }

        return Image(decorative: cgImage, scale: 1)
    }
}

/// Convenience modifier: places a checkerboard behind any content.
extension View {
    func checkerboardBackground(square: CGFloat = 8) -> some View {
        background(CheckerboardBackground(square: square))
    }
}

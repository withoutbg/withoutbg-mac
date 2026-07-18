import SwiftUI

/// Semantic background palette — single source of truth, mirrored from the web
/// prototype's `theme-colors.ts`.
///
/// Hierarchy (dark: chrome lightest → page darkest):
///   chrome   navbars, toolbars
///   surface  cards, panels, selected items
///   workArea main selection surface — barely tinted vs page
///   page     window background
enum WBGColors {
    // MARK: Background roles

    static let chrome = adaptive(light: 0xFAFAFA, dark: 0x252427)
    static let page = adaptive(light: 0xFEFEFE, dark: 0x1F1F1E)
    /// Subtle tint for the image grid work area so empty space is visibly selectable.
    static let workArea = adaptive(light: 0xF7F7F7, dark: 0x232322)
    static let surface = adaptive(light: 0xF2F2F2, dark: 0x3A3A3A)

    // MARK: Borders (gray-200 light / gray-700 dark equivalents)

    static let border = adaptive(light: 0xE5E7EB, dark: 0x374151)
    static let borderStrong = adaptive(light: 0xD1D5DB, dark: 0x4B5563)

    // MARK: Text

    static let textPrimary = adaptive(light: 0x171717, dark: 0xEDEDED)
    static let textSecondary = adaptive(light: 0x4B5563, dark: 0x9CA3AF)
    static let textTertiary = adaptive(light: 0x9CA3AF, dark: 0x6B7280)

    // MARK: Status accents

    /// Follows the user's macOS accent / highlight color (System Settings → Appearance).
    static let accent = Color(nsColor: NSColor.controlAccentColor)
    static let accentLight = Color(nsColor: NSColor.controlAccentColor.withAlphaComponent(0.55))
    static let success = adaptive(light: 0x16A34A, dark: 0x22C55E)
    static let danger = adaptive(light: 0xEF4444, dark: 0xF87171)

    // MARK: - Helpers

    /// An NSColor-backed dynamic color that resolves per appearance.
    static func adaptive(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

extension Color {
    init(hex: Int, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

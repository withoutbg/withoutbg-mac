import SwiftUI

/// Appearance override. Defaults to following the system.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum SettingsKey {
    static let appearance = "appearanceMode"
    static let defaultExportPath = "defaultExportPath"
    static let revealAfterExport = "revealAfterExport"
}

extension UserDefaults {
    var defaultExportDirectory: URL? {
        guard let path = string(forKey: SettingsKey.defaultExportPath), !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

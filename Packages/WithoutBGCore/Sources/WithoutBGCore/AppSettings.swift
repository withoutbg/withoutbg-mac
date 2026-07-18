import Foundation
import SwiftUI

/// Appearance override. Defaults to following the system.
public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public enum SettingsKey {
    // Desktop
    public static let appearance = "appearanceMode"
    public static let defaultExportPath = "defaultExportPath"
    public static let revealAfterExport = "revealAfterExport"
    public static let productUpdatesOptedIn = "productUpdatesOptedIn"
    public static let productUpdatesEmail = "productUpdatesEmail"

    // Local API (unified keys)
    public static let localAPIEnabled = "localAPIEnabled"
    public static let localAPIPort = "localAPIPort"
    public static let localAPIStartOnLaunch = "localAPIStartOnLaunch"
    public static let localAPILogRequests = "localAPILogRequests"

    // Legacy server app keys (migration)
    public static let serverPort = "serverPort"
    public static let startOnLaunch = "startOnLaunch"
}

public extension UserDefaults {
    var defaultExportDirectory: URL? {
        guard let path = string(forKey: SettingsKey.defaultExportPath), !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    var localAPIPort: Int {
        if integer(forKey: SettingsKey.localAPIPort) > 0 {
            return integer(forKey: SettingsKey.localAPIPort)
        }
        let legacy = integer(forKey: SettingsKey.serverPort)
        return legacy > 0 ? legacy : 8000
    }

    var localAPIStartOnLaunch: Bool {
        if object(forKey: SettingsKey.localAPIStartOnLaunch) != nil {
            return bool(forKey: SettingsKey.localAPIStartOnLaunch)
        }
        return bool(forKey: SettingsKey.startOnLaunch)
    }

    var localAPILogRequests: Bool {
        if object(forKey: SettingsKey.localAPILogRequests) != nil {
            return bool(forKey: SettingsKey.localAPILogRequests)
        }
        return true
    }

    /// Migrate legacy server settings on first read.
    func migrateLegacyServerSettingsIfNeeded() {
        if object(forKey: SettingsKey.localAPIPort) == nil,
           integer(forKey: SettingsKey.serverPort) > 0 {
            set(integer(forKey: SettingsKey.serverPort), forKey: SettingsKey.localAPIPort)
        }
        if object(forKey: SettingsKey.localAPIStartOnLaunch) == nil,
           object(forKey: SettingsKey.startOnLaunch) != nil {
            set(bool(forKey: SettingsKey.startOnLaunch), forKey: SettingsKey.localAPIStartOnLaunch)
        }
    }
}

public enum SettingsDefaults {
    public static let values: [String: Any] = [
        SettingsKey.localAPIPort: 8000,
        SettingsKey.localAPIStartOnLaunch: false,
        SettingsKey.localAPIEnabled: false,
        SettingsKey.localAPILogRequests: true,
        SettingsKey.serverPort: 8000,
        SettingsKey.startOnLaunch: false,
    ]
}

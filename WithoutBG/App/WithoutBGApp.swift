import SwiftUI

@main
struct WithoutBGApp: App {
    // The shared model is owned by the AppDelegate so AppKit entry points
    // (Quick Look, Continuity Camera, Finder Services) feed the same queue the
    // window shows. Real on-device inference runs via the bundled Core ML model.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var model: AppModel { appDelegate.model }

    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 640, minHeight: 480)
                .preferredColorScheme(appearance.colorScheme)
        }
        .defaultSize(width: 900, height: 700)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model) }

        Window("About withoutBG", id: "about") {
            AboutView()
                .preferredColorScheme(appearance.colorScheme)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

import SwiftUI

@main
struct WithoutBGApp: App {
    // ── Processor injection ──────────────────────────────────────────────────
    // Real on-device inference via the bundled WBGNet Core ML model.
    // Swap back to `MockProcessor()` to run the UI without the model.
    @State private var model = AppModel(processor: CoreMLProcessor())

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

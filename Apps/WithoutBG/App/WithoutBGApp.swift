import SwiftUI
import WithoutBGCore

@main
struct WithoutBGApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var model: AppModel { appDelegate.model }

    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    init() {
        UserDefaults.standard.register(defaults: SettingsDefaults.values)
        ProductLinks.configure(utmSource: "withoutbg-mac-unified")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(appDelegate.status)
                .environment(appDelegate.activity)
                .environment(\.serverController, appDelegate.serverController)
                .frame(minWidth: 640, minHeight: 480)
                .preferredColorScheme(appearance.colorScheme)
        }
        .defaultSize(width: 900, height: 700)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model, appDelegate: appDelegate) }

        MenuBarExtra {
            UnifiedMenuBarView()
                .environment(appDelegate.status)
                .environment(appDelegate.activity)
                .environment(\.serverController, appDelegate.serverController)
        } label: {
            MenuBarStatusIcon(isRunning: appDelegate.status.isRunning)
                .help(appDelegate.status.statusLabel)
        }
        .menuBarExtraStyle(.window)

        Window("About withoutBG", id: "about") {
            AboutView(serverStatus: appDelegate.status)
                .preferredColorScheme(appearance.colorScheme)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environment(appDelegate.status)
                .environment(appDelegate.activity)
                .environment(\.serverController, appDelegate.serverController)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

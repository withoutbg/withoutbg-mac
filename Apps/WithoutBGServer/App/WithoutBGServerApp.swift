import AppKit
import SwiftUI
import WithoutBGCore

@main
struct WithoutBGServerApp: App {
    @NSApplicationDelegateAdaptor(ServerAppDelegate.self) private var appDelegate

    init() {
        UserDefaults.standard.register(defaults: SettingsDefaults.values)
        ProductLinks.configure(utmSource: "withoutbg-mac-server")
    }

    var body: some Scene {
        MenuBarExtra {
            HeadlessMenuBarView()
                .environment(appDelegate.status)
                .environment(appDelegate.activity)
                .environment(\.serverController, appDelegate.serverController)
        } label: {
            MenuBarStatusIcon(isRunning: appDelegate.status.isRunning)
                .help(appDelegate.status.statusLabel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            HeadlessSettingsView()
                .environment(appDelegate.status)
                .environment(appDelegate.activity)
                .environment(\.serverController, appDelegate.serverController)
        }
    }
}

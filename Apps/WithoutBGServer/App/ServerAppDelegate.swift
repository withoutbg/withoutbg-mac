import AppKit
import WithoutBGCore

@MainActor
final class ServerAppDelegate: NSObject, NSApplicationDelegate {
    let inferenceCoordinator = SharedInferenceCoordinator(processor: CoreMLProcessor())
    let status = ServerStatus()
    let activity = RecentActivity()
    lazy var serverController = ServerController(
        status: status,
        activity: activity,
        coordinator: inferenceCoordinator
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProductLinks.configure(utmSource: "withoutbg-mac-server")
        UserDefaults.standard.migrateLegacyServerSettingsIfNeeded()

        let shouldStart = UserDefaults.standard.localAPIStartOnLaunch
            || ProcessInfo.processInfo.arguments.contains("--start")
        let port = Self.parseCLIPort() ?? UserDefaults.standard.localAPIPort

        if shouldStart {
            Task { await serverController.start(port: port) }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard status.isRunning else { return .terminateNow }
        Task {
            await serverController.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

extension ServerAppDelegate {
    static func parseCLIPort() -> Int? {
        let args = ProcessInfo.processInfo.arguments
        for (index, arg) in args.enumerated() {
            if arg == "--port", index + 1 < args.count, let port = Int(args[index + 1]) {
                return port
            }
            if arg.hasPrefix("--port="), let port = Int(arg.dropFirst(7)) {
                return port
            }
        }
        return nil
    }
}

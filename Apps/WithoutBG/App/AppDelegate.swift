import AppKit
import Quartz
import WithoutBGCore

/// App delegate bridging SwiftUI to AppKit surfaces and owning shared services:
/// inference coordinator, desktop queue, and optional Local API server.
final class AppDelegate: NSResponder, NSApplicationDelegate, NSServicesMenuRequestor {
    let inferenceCoordinator = SharedInferenceCoordinator(processor: CoreMLProcessor())
    let status = ServerStatus()
    let activity = RecentActivity()
    lazy var serverController = ServerController(
        status: status,
        activity: activity,
        coordinator: inferenceCoordinator
    )
    lazy var model = AppModel(coordinator: inferenceCoordinator)

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProductLinks.configure(utmSource: "withoutbg-mac-unified")
        UserDefaults.standard.migrateLegacyServerSettingsIfNeeded()

        NSApp.servicesProvider = self
        NotificationService.shared.requestAuthorization()

        if UserDefaults.standard.localAPIStartOnLaunch {
            let port = UserDefaults.standard.localAPIPort
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

    // MARK: - Quick Look control (responder chain)

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel) {
        panel.dataSource = QuickLookController.shared
        panel.delegate = QuickLookController.shared
        panel.currentPreviewItemIndex = QuickLookController.shared.startIndex
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    // MARK: - Continuity Camera (import from iPhone/iPad)

    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        if let returnType, NSImage.imageTypes.contains(returnType.rawValue) {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    nonisolated func readSelection(from pasteboard: NSPasteboard) -> Bool {
        MainActor.assumeIsolated {
            guard let image = NSImage(pasteboard: pasteboard),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return false }
            NSApp.activate(ignoringOtherApps: true)
            model.enqueue([("Imported Image.png", cg)])
            return true
        }
    }

    nonisolated func writeSelection(
        to pasteboard: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> Bool { false }

    // MARK: - Finder Services (Services ▸ Remove Background)

    @objc nonisolated func removeBackground(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>?
    ) {
        MainActor.assumeIsolated {
            let urls = (pboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL]) ?? []
            let loaded = ImageIngestion.load(from: urls)
            guard !loaded.isEmpty else { return }
            NSApp.activate(ignoringOtherApps: true)
            model.enqueue(loaded)
        }
    }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}

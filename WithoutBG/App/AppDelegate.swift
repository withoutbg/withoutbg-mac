import AppKit
import Quartz

/// App delegate that bridges the SwiftUI app to AppKit-only native surfaces:
///
/// - **Quick Look**: lives in the responder chain (as an `NSResponder`) so the
///   shared `QLPreviewPanel` can find us and pull data from `QuickLookController`.
/// - **Continuity Camera**: conforms to `NSServicesMenuRequestor`, which makes
///   macOS offer "Import from iPhone or iPad" automatically when a device is near.
/// - **Services**: registered as the system services provider so users can select
///   images in Finder and choose Services ▸ Remove Background.
///
/// The single shared `AppModel` is owned here so all of these entry points feed
/// the same queue the windows display.
final class AppDelegate: NSResponder, NSApplicationDelegate, NSServicesMenuRequestor {
    let model = AppModel(processor: CoreMLProcessor())

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NotificationService.shared.requestAuthorization()
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
}

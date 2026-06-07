import AppKit
import Quartz

/// Drives the system Quick Look panel (`QLPreviewPanel`) for the grid.
///
/// The panel finds its controller through the responder chain — `AppDelegate`
/// implements `acceptsPreviewPanelControl(_:)` / `beginPreviewPanelControl(_:)`
/// and points the panel here for its data. This gives us the genuine Quick Look
/// chrome (share, open, full screen, item index) instead of a custom overlay.
@MainActor
final class QuickLookController: NSObject {
    static let shared = QuickLookController()

    /// File URLs the panel pages through (one per previewable job).
    private(set) var urls: [URL] = []
    /// Item to focus when the panel first opens.
    private(set) var startIndex = 0

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists()
            && (QLPreviewPanel.shared()?.isVisible ?? false)
    }

    func present(urls: [URL], startIndex: Int) {
        guard !urls.isEmpty else { return }
        self.urls = urls
        self.startIndex = startIndex
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.reloadData()
            panel.currentPreviewItemIndex = startIndex
        } else {
            // `beginPreviewPanelControl` (on AppDelegate) wires the data source
            // and applies `startIndex` once the panel takes control.
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        guard isVisible, let panel = QLPreviewPanel.shared() else { return }
        panel.orderOut(nil)
    }
}

extension QuickLookController: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> any QLPreviewItem {
        urls[index] as NSURL
    }
}

extension QuickLookController: QLPreviewPanelDelegate {
    /// Match Finder/Photos: a second Space bar press dismisses the preview.
    func previewPanel(_ panel: QLPreviewPanel, handle event: NSEvent) -> Bool {
        if event.type == .keyDown, event.charactersIgnoringModifiers == " " {
            panel.orderOut(nil)
            return true
        }
        return false
    }
}

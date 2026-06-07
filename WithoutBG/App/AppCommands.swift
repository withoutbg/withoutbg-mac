import SwiftUI

/// Native menu bar commands. No web-style header nav — ecosystem links live in
/// Help and About only.
struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var links: ProductLinks { ProductLinks.shared }
    private var issuesURL: URL {
        links.github.appendingPathComponent("issues")
    }

    var body: some Commands {
        // App menu — About
        CommandGroup(replacing: .appInfo) {
            Button("About withoutBG…") { openWindow(id: "about") }
        }

        // File menu — Open / Export All
        CommandGroup(replacing: .newItem) {
            Button("Open…") { model.openFilePanel() }
                .keyboardShortcut("o", modifiers: .command)
        }
        CommandGroup(after: .saveItem) {
            Button("Export All…") { model.exportAll() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!model.canExportAll)
        }

        // Edit menu — paste images from the clipboard (⌘V)
        CommandGroup(replacing: .pasteboard) {
            Button("Paste") { model.paste() }
                .keyboardShortcut("v", modifiers: .command)
        }

        // Help menu — ecosystem links
        CommandGroup(replacing: .help) {
            Link("withoutBG Website", destination: links.website)
            Link("API Documentation", destination: links.api)
            Link("Benchmarks", destination: links.benchmarks)
            Divider()
            Link("GitHub Repository", destination: links.github)
            Link("Report an Issue", destination: issuesURL)
        }
    }
}

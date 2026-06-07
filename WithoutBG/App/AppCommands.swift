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

        // Edit menu — Undo/Redo (forgiveness instead of confirmation dialogs).
        CommandGroup(replacing: .undoRedo) {
            Button(model.undoTitle) { model.performUndo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)
            Button(model.redoTitle) { model.performRedo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
        }

        // Edit menu — selection + clipboard actions, all discoverable with their
        // shortcuts (Copy, Paste, Delete, Select All, Rename).
        CommandGroup(replacing: .pasteboard) {
            Button("Copy") { model.copySelection() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(model.queue.doneJobs.isEmpty)
            Button("Paste") { model.paste() }
                .keyboardShortcut("v", modifiers: .command)
            Divider()
            Button("Delete") { model.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!model.hasSelection)
            Button("Rename") {
                if let id = model.singleSelection { model.beginRename(id) }
            }
            .disabled(model.singleSelection == nil)
            Divider()
            Button("Select All") { model.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(!model.queue.hasJobs)
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

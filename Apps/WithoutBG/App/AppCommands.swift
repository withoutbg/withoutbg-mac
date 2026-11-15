import SwiftUI
import WithoutBGCore

/// Native menu bar commands. No web-style header nav — ecosystem links live in
/// Help and About only.
struct AppCommands: Commands {
    let model: AppModel
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    /// Set while the Smart Brush window is key: Undo acts on its strokes and the
    /// queue's pasteboard / selection commands are off.
    @FocusedValue(\.brushEditor) private var brushEditor

    private var links: ProductLinks { ProductLinks.shared }
    private var issuesURL: URL {
        links.github.appendingPathComponent("issues")
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About withoutBG…") { openWindow(id: "about") }
        }

        CommandGroup(replacing: .newItem) {
            Button("Open…") { model.openFilePanel() }
                .keyboardShortcut("o", modifiers: .command)
        }
        CommandGroup(after: .saveItem) {
            Button("Export All…") { model.exportAll() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!model.canExportAll)
        }

        CommandGroup(replacing: .undoRedo) {
            if let brushEditor {
                Button("Undo Stroke") { brushEditor.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!brushEditor.canUndo)
                Button("Redo") {}
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(true)
            } else {
                Button(model.undoTitle) { model.performUndo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!model.canUndo)
                Button(model.redoTitle) { model.performRedo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo)
            }
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Copy") { model.copySelection() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(model.queue.doneJobs.isEmpty || brushEditor != nil)
            Button("Paste") { model.paste() }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(brushEditor != nil)
            Divider()
            Button("Delete") { model.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!model.hasSelection || brushEditor != nil)
            Button("Rename") {
                if let id = model.singleSelection { model.beginRename(id) }
            }
            .disabled(model.singleSelection == nil || brushEditor != nil)
            Divider()
            Button("Select All") { model.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(!model.queue.hasJobs || brushEditor != nil)
        }

        CommandGroup(after: .toolbar) {
            Button(appDelegate.status.isRunning ? "Stop Local API" : "Start Local API") {
                Task {
                    if appDelegate.status.isRunning {
                        await appDelegate.serverController.stop()
                    } else {
                        await appDelegate.serverController.start(port: UserDefaults.standard.localAPIPort)
                    }
                }
            }
            Button("Copy Local API URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(appDelegate.status.boundURL, forType: .string)
            }
            .disabled(!appDelegate.status.isRunning)
        }

        CommandGroup(replacing: .help) {
            Link("withoutBG Website", destination: links.website)
            Link("Documentation", destination: links.documentation)
            Link("Local API Documentation", destination: links.localAPIDocs)
            Link("Cloud API Documentation", destination: links.api)
            Link("Benchmarks", destination: links.benchmarks)
            Divider()
            Link("GitHub Repository", destination: links.github)
            Link("Local API on GitHub", destination: links.localAPIGitHub)
            Link("Commercial Licensing", destination: links.enterprise)
            Link("Report an Issue", destination: issuesURL)
        }
    }
}

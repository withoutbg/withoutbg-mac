import SwiftUI
import WithoutBGCore

/// Native menu bar commands. No web-style header nav — ecosystem links live in
/// Help and About only.
struct AppCommands: Commands {
    let model: AppModel
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

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
            Button(model.undoTitle) { model.performUndo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)
            Button(model.redoTitle) { model.performRedo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
        }

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

import AppKit
import SwiftUI
import WithoutBGCore

/// Menu bar operational center for the Local API.
struct UnifiedMenuBarView: View {
    @Environment(ServerStatus.self) private var status
    @Environment(RecentActivity.self) private var activity
    @Environment(\.serverController) private var controller

    @State private var showCopiedEndpoint = false
    @State private var showCopiedOpenAPI = false
    @State private var showNotices = false
    @State private var showActivity = false

    private var links: ProductLinks { ProductLinks.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            appHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            statusHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            if !status.isRunning {
                desktopPromo
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider()

            Group {
                toggleButton
                copyEndpointButton
                    .disabled(!status.isRunning)
                copyOpenAPIButton
                    .disabled(!status.isRunning)
                openDocsButton
                requestLogButton
            }
            .padding(.vertical, 2)

            Divider()
                .padding(.vertical, 4)

            Group {
                openDesktopButton
                settingsButton
                licenseButton
                quitButton
            }
            .padding(.vertical, 2)

            Spacer(minLength: 10)
        }
        .frame(width: 300)
        .sheet(isPresented: $showNotices) {
            ThirdPartyNoticesView()
        }
        .sheet(isPresented: $showActivity) {
            ActivitySheet()
                .environment(activity)
        }
    }

    private var appHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("withoutBG")
                .font(.headline)
            Text("Local background removal on your Mac")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(status.isRunning ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(status.isRunning ? "Local API Running" : "Local API Stopped")
                    .font(.subheadline.weight(.semibold))
            }

            if status.isRunning {
                Button { copyEndpoint() } label: {
                    Text(status.boundURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                operationalDetails
            } else if let error = status.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            if let last = activity.lastEntry {
                Text("Last: \(last.lastRequestSummary)")
                    .font(.caption2)
                    .foregroundStyle(last.isSuccess ? Color.secondary.opacity(0.6) : Color.red)
                    .lineLimit(2)
            }
        }
    }

    private var operationalDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            detailRow("Port", value: "\(status.port)")
            detailRow("Requests Served", value: "\(status.requestCount)")
            if let avg = activity.averageLatencyMs {
                detailRow("Average Latency", value: "\(avg) ms")
            }
            detailRow("Model", value: status.modelLabel)
            if let since = status.runningSince {
                detailRow("Running Since", value: since.formatted(date: .omitted, time: .shortened))
            }
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var desktopPromo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Need manual editing?")
                .font(.caption.weight(.medium))
            Text("Drag & drop, preview, and batch export in the desktop window.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Open Desktop →") {
                NSApp.sendAction(#selector(AppDelegate.openMainWindowAction), to: nil, from: nil)
            }
            .controlSize(.small)
        }
    }

    private var toggleButton: some View {
        menuItem(
            label: status.isRunning ? "Stop Local API" : "Start Local API",
            systemImage: status.isRunning ? "stop.circle" : "play.circle"
        ) {
            guard let controller else { return }
            Task {
                if status.isRunning {
                    await controller.stop()
                } else {
                    await controller.start(port: UserDefaults.standard.localAPIPort)
                }
            }
        }
    }

    private var copyEndpointButton: some View {
        menuItem(
            label: showCopiedEndpoint ? "Copied!" : "Copy Endpoint URL",
            systemImage: showCopiedEndpoint ? "checkmark" : "doc.on.doc"
        ) { copyEndpoint() }
    }

    private var copyOpenAPIButton: some View {
        menuItem(
            label: showCopiedOpenAPI ? "Copied!" : "Copy OpenAPI URL",
            systemImage: showCopiedOpenAPI ? "checkmark" : "curlybraces"
        ) { copyOpenAPI() }
    }

    private var openDocsButton: some View {
        menuItem(label: "Open API Documentation", systemImage: "book") {
            NSWorkspace.shared.open(links.localAPIDocs)
        }
    }

    private var requestLogButton: some View {
        menuItem(label: "Request Log…", systemImage: "list.bullet.rectangle") {
            showActivity = true
        }
    }

    private var openDesktopButton: some View {
        menuItem(label: "Open Desktop", systemImage: "macwindow") {
            NSApp.sendAction(#selector(AppDelegate.openMainWindowAction), to: nil, from: nil)
        }
    }

    private var settingsButton: some View {
        SettingsLink {
            Label("Settings…", systemImage: "gear")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            NSApp.activate(ignoringOtherApps: true)
        })
    }

    private var licenseButton: some View {
        menuItem(label: "License & Notices…", systemImage: "doc.text") {
            showNotices = true
        }
    }

    private var quitButton: some View {
        menuItem(label: "Quit withoutBG", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func menuItem(
        label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func copyEndpoint() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(status.boundURL, forType: .string)
        showCopiedEndpoint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopiedEndpoint = false }
    }

    private func copyOpenAPI() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(status.openAPIURL, forType: .string)
        showCopiedOpenAPI = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopiedOpenAPI = false }
    }
}

private struct ActivitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RecentActivity.self) private var activity

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Request Log")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            ActivityListView()
                .environment(activity)
        }
        .frame(width: 420, height: 320)
    }
}

/// Renders a fixed 18×18 pt template icon for the menu bar.
struct MenuBarStatusIcon: View {
    let isRunning: Bool

    var body: some View {
        Image(nsImage: Self.image(isRunning: isRunning))
    }

    static func image(isRunning: Bool) -> NSImage {
        let name = isRunning ? "MenuIconRunning" : "MenuIconStopped"
        guard let source = NSImage(named: name) else {
            return NSImage(size: NSSize(width: 18, height: 18))
        }

        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        image.lockFocus()
        source.draw(
            in: NSRect(x: 0, y: 0, width: 18, height: 18),
            from: NSRect(origin: .zero, size: source.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        image.unlockFocus()
        return image
    }
}

extension AppDelegate {
    @objc func openMainWindowAction() {
        openMainWindow()
    }
}

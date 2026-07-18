import AppKit
import SwiftUI
import WithoutBGCore

/// Headless distribution menu bar — no desktop window affordances.
struct HeadlessMenuBarView: View {
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
            VStack(alignment: .leading, spacing: 2) {
                Text("WithoutBG Server")
                    .font(.headline)
                Text("Headless Local API for automation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            statusBlock
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            Group {
                toggleButton
                copyEndpointButton.disabled(!status.isRunning)
                copyOpenAPIButton.disabled(!status.isRunning)
                openDocsButton
                requestLogButton
            }
            .padding(.vertical, 2)

            Divider().padding(.vertical, 4)

            Group {
                settingsButton
                licenseButton
                quitButton
            }
            .padding(.vertical, 2)

            Spacer(minLength: 10)
        }
        .frame(width: 300)
        .sheet(isPresented: $showNotices) { ThirdPartyNoticesView() }
        .sheet(isPresented: $showActivity) {
            VStack(spacing: 0) {
                HStack {
                    Text("Request Log").font(.headline)
                    Spacer()
                    Button("Done") { showActivity = false }
                }
                .padding()
                ActivityListView().environment(activity)
            }
            .frame(width: 420, height: 320)
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(status.isRunning ? Color.green : Color.secondary).frame(width: 8, height: 8)
                Text(status.isRunning ? "Running" : "Stopped").font(.subheadline.weight(.semibold))
            }
            if status.isRunning {
                Text(status.boundURL).font(.caption.monospaced()).foregroundStyle(.secondary)
                if let avg = activity.averageLatencyMs {
                    Text("Average latency: \(avg) ms").font(.caption2).foregroundStyle(.tertiary)
                }
                Text("\(status.requestCount) request\(status.requestCount == 1 ? "" : "s") served")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var toggleButton: some View {
        menuRow(status.isRunning ? "Stop Local API" : "Start Local API", "play.circle") {
            guard let controller else { return }
            Task {
                if status.isRunning { await controller.stop() }
                else { await controller.start(port: UserDefaults.standard.localAPIPort) }
            }
        }
    }

    private var copyEndpointButton: some View {
        menuRow(showCopiedEndpoint ? "Copied!" : "Copy Endpoint URL", "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(status.boundURL, forType: .string)
            showCopiedEndpoint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopiedEndpoint = false }
        }
    }

    private var copyOpenAPIButton: some View {
        menuRow(showCopiedOpenAPI ? "Copied!" : "Copy OpenAPI URL", "curlybraces") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(status.openAPIURL, forType: .string)
            showCopiedOpenAPI = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopiedOpenAPI = false }
        }
    }

    private var openDocsButton: some View {
        menuRow("Open API Documentation", "book") { NSWorkspace.shared.open(links.localAPIDocs) }
    }

    private var requestLogButton: some View {
        menuRow("Request Log…", "list.bullet.rectangle") { showActivity = true }
    }

    private var settingsButton: some View {
        SettingsLink {
            Label("Settings…", systemImage: "gear").frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.vertical, 5)
        .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
    }

    private var licenseButton: some View {
        menuRow("License & Notices…", "doc.text") { showNotices = true }
    }

    private var quitButton: some View {
        menuRow("Quit WithoutBG Server", "power") { NSApplication.shared.terminate(nil) }
    }

    private func menuRow(_ label: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

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
        source.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18), from: NSRect(origin: .zero, size: source.size), operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        image.unlockFocus()
        return image
    }
}

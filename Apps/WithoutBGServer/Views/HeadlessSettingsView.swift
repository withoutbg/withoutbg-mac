import ServiceManagement
import SwiftUI
import WithoutBGCore

/// Settings for the headless server distribution.
struct HeadlessSettingsView: View {
    @Environment(ServerStatus.self) private var status
    @Environment(RecentActivity.self) private var activity
    @Environment(\.serverController) private var controller

    @AppStorage(SettingsKey.localAPIPort) private var savedPort: Int = 8000
    @AppStorage(SettingsKey.localAPIStartOnLaunch) private var startOnLaunch: Bool = false
    @AppStorage(SettingsKey.localAPILogRequests) private var logRequests: Bool = true

    @State private var portText = ""
    @State private var portError: String?
    @State private var openAtLogin = false
    @State private var showNotices = false

    private var links: ProductLinks { ProductLinks.shared }

    var body: some View {
        Form {
            Section {
                Text("Install withoutBG Desktop for drag-and-drop editing. This headless build is for automation and CI environments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Download withoutBG Desktop", destination: links.macApp)
            }

            Section("Local API") {
                LabeledContent("Status") {
                    Text(status.isRunning ? "Running" : "Stopped")
                }
                if status.isRunning {
                    LabeledContent("Endpoint") {
                        Text(status.boundURL).font(.body.monospaced()).textSelection(.enabled)
                    }
                }
                HStack {
                    TextField("Port", text: $portText).frame(width: 80)
                    Button("Apply") { applyPort() }
                }
                Toggle("Start server when app launches", isOn: $startOnLaunch)
                Toggle("Log API requests", isOn: $logRequests)
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, enabled in setLoginItem(enabled: enabled) }
            }

            Section("Recent Activity") {
                ActivityListView(style: .embedded)
                    .frame(minHeight: activity.entries.isEmpty ? 120 : 180)
            }

            Section("License") {
                Button("Third-Party Notices…") { showNotices = true }
                Link("Documentation", destination: links.localAPIDocs)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding()
        .sheet(isPresented: $showNotices) { ThirdPartyNoticesView() }
        .onAppear {
            portText = String(savedPort)
            openAtLogin = (try? SMAppService.mainApp.status == .enabled) ?? false
        }
    }

    private func applyPort() {
        guard let newPort = Int(portText), (1024...65535).contains(newPort) else {
            portError = "Must be 1024 – 65535"
            return
        }
        portError = nil
        savedPort = newPort
        guard status.isRunning, let controller else { return }
        Task { await controller.restart(port: newPort) }
    }

    private func setLoginItem(enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            openAtLogin = !enabled
        }
    }
}

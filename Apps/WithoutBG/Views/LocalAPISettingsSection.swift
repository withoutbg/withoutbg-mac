import ServiceManagement
import SwiftUI
import WithoutBGCore

/// Local API configuration in the unified settings window.
struct LocalAPISettingsSection: View {
    @Environment(ServerStatus.self) private var status
    @Environment(RecentActivity.self) private var activity
    @Environment(\.serverController) private var controller

    @AppStorage(SettingsKey.localAPIPort) private var savedPort: Int = 8000
    @AppStorage(SettingsKey.localAPIStartOnLaunch) private var startOnLaunch: Bool = false
    @AppStorage(SettingsKey.localAPILogRequests) private var logRequests: Bool = true

    @State private var portText: String = ""
    @State private var portError: String? = nil
    @State private var openAtLogin: Bool = false

    private var links: ProductLinks { ProductLinks.shared }

    var body: some View {
        Section("Local API") {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.isRunning ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(status.isRunning ? "Running" : "Stopped")
                }
            }

            if status.isRunning {
                LabeledContent("Endpoint") {
                    HStack(spacing: 6) {
                        Text(status.boundURL)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(status.boundURL, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if let avg = activity.averageLatencyMs {
                    LabeledContent("Average Latency") {
                        Text("\(avg) ms")
                    }
                }

                LabeledContent("Model") {
                    Text(status.modelLabel)
                        .font(.caption)
                }
            }

            HStack {
                TextField("Port", text: $portText)
                    .frame(width: 80)
                    .onSubmit { applyPort() }
                Button("Apply") { applyPort() }
                    .disabled(portError != nil)
                if let error = portError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Toggle("Start Local API when app launches", isOn: $startOnLaunch)
            Toggle("Log API requests", isOn: $logRequests)
            Toggle("Open at login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { _, enabled in
                    setLoginItem(enabled: enabled)
                }

            HStack {
                Button(status.isRunning ? "Stop Local API" : "Start Local API") {
                    guard let controller else { return }
                    Task {
                        if status.isRunning {
                            await controller.stop()
                        } else {
                            await controller.start(port: savedPort)
                        }
                    }
                }
                Spacer()
                Link("Documentation", destination: links.localAPIDocs)
            }
        }
        .onAppear { onAppearSetup() }

        Section("API Activity") {
            ActivityListView(style: .embedded)
                .frame(minHeight: activity.entries.isEmpty ? 100 : 160)
        }

        Section("API Usage") {
            Text(usageSnippet)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
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
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            openAtLogin = !enabled
        }
    }

    private var usageSnippet: String {
        let url = status.isRunning ? status.boundURL : "http://127.0.0.1:\(savedPort)"
        return """
        curl -X POST \\
          --data-binary @photo.jpg \\
          -H "Content-Type: image/jpeg" \\
          \(url)/v1/remove-background \\
          -o result.png
        """
    }

    func onAppearSetup() {
        portText = String(savedPort)
        openAtLogin = (try? SMAppService.mainApp.status == .enabled) ?? false
    }
}

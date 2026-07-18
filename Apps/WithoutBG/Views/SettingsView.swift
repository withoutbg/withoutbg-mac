import AppKit
import SwiftUI
import WithoutBGCore

/// App settings. Mirrors the spec's Settings scene.
struct SettingsView: View {
    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage(SettingsKey.defaultExportPath) private var exportPath = ""
    @AppStorage(SettingsKey.revealAfterExport) private var revealAfterExport = false

    private var appearance: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Export") {
                LabeledContent("Default location") {
                    HStack(spacing: 8) {
                        Text(exportPath.isEmpty ? "Ask every time" : exportPath)
                            .foregroundStyle(exportPath.isEmpty ? WBGColors.textTertiary : WBGColors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…", action: chooseFolder)
                        if !exportPath.isEmpty {
                            Button("Reset") { exportPath = "" }
                        }
                    }
                }
                Toggle("Reveal in Finder after export", isOn: $revealAfterExport)
            }

            Section("Appearance") {
                Picker("Appearance", selection: appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            LocalAPISettingsSection()

            Section("Privacy") {
                PrivacyBadge()
                Text("Runs locally on your Mac. Images are not uploaded.")
                    .font(.system(size: 12))
                    .foregroundStyle(WBGColors.textSecondary)
            }

            Section("Ecosystem") {
                CommercialLicensingSection()
                ProductUpdatesSection()
                GPUFundSection()
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 720)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            exportPath = url.path
        }
    }
}

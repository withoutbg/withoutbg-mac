import SwiftUI
import WithoutBGCore

/// Optional withoutBG Pro (hosted model). Off by default; the engine picker is
/// enabled only once an API key is saved. The key lives in the Keychain.
struct ProSettingsSection: View {
    @AppStorage(SettingsKey.processingEngine) private var engineRaw = ProcessingEngine.openWeights.rawValue

    @State private var keyText = ""
    @State private var hasKey = APIKeyStore.hasKey
    @State private var status: String?
    @State private var isError = false
    @State private var isChecking = false

    private var links: ProductLinks { ProductLinks.shared }

    private var engine: Binding<ProcessingEngine> {
        Binding(
            get: { hasKey ? (ProcessingEngine(rawValue: engineRaw) ?? .openWeights) : .openWeights },
            set: { engineRaw = $0.rawValue }
        )
    }

    var body: some View {
        Section("withoutBG Pro (optional)") {
            Picker("Engine", selection: engine) {
                ForEach(ProcessingEngine.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .disabled(!hasKey)

            if hasKey {
                LabeledContent("API key") {
                    HStack(spacing: 8) {
                        Text("Saved in Keychain")
                            .foregroundStyle(WBGColors.textSecondary)
                        Spacer()
                        Button(isChecking ? "Checking…" : "Check credits", action: checkCredits)
                            .disabled(isChecking)
                        Button("Remove", role: .destructive, action: removeKey)
                    }
                }
            } else {
                LabeledContent("API key") {
                    HStack(spacing: 8) {
                        SecureField("sk_…", text: $keyText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveKey)
                        Button("Save", action: saveKey)
                            .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty || isChecking)
                    }
                }
            }

            if let status {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(isError ? Color.red : WBGColors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Pro uploads each image to api.withoutbg.com and uses 1 credit. Open weights stay on this Mac. Smart brush always runs on this Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(WBGColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !hasKey {
                    Link("Get an API key", destination: links.api)
                        .font(.system(size: 12))
                }
            }
        }
    }

    private func saveKey() {
        let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isChecking = true
        status = nil
        Task {
            defer { isChecking = false }
            do {
                // Validate before storing; /available-credit is free.
                let credits = try await CloudProcessor(apiKey: key).credits()
                guard APIKeyStore.save(key) else {
                    show("Could not save the key to the Keychain.", error: true)
                    return
                }
                keyText = ""
                hasKey = true
                show("Key saved. \(credits.credit) credits available.", error: false)
            } catch {
                show(error.localizedDescription, error: true)
            }
        }
    }

    private func checkCredits() {
        guard let key = APIKeyStore.load() else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                let credits = try await CloudProcessor(apiKey: key).credits()
                show("\(credits.credit) credits available.", error: false)
            } catch {
                show(error.localizedDescription, error: true)
            }
        }
    }

    private func removeKey() {
        APIKeyStore.delete()
        hasKey = false
        engineRaw = ProcessingEngine.openWeights.rawValue
        show("Key removed. Using open weights.", error: false)
    }

    private func show(_ message: String, error: Bool) {
        status = message
        isError = error
    }
}

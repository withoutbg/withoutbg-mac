import SwiftUI
import WithoutBGCore

/// Optional product-updates opt-in for Settings.
struct ProductUpdatesSection: View {
    @AppStorage(SettingsKey.productUpdatesOptedIn) private var hasOptedIn = false
    @AppStorage(SettingsKey.productUpdatesEmail) private var registeredEmail = ""

    @State private var email = ""
    @State private var consent = false
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var isError = false

    private var links: ProductLinks { ProductLinks.shared }

    var body: some View {
        if hasOptedIn {
            registeredView
        } else {
            optInView
        }
    }

    private var registeredView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You'll receive product updates at this address.")
                .font(.system(size: 12))
                .foregroundStyle(WBGColors.textSecondary)
            if !registeredEmail.isEmpty {
                Text(registeredEmail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(WBGColors.textTertiary)
            }
        }
    }

    private var optInView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Get occasional updates about new models, desktop releases and important announcements.")
                .font(.system(size: 12))
                .foregroundStyle(WBGColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Email address", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .disabled(isSubmitting)

            Toggle(isOn: $consent) {
                Text("I agree to receive product updates.")
                    .font(.system(size: 12))
            }
            .disabled(isSubmitting)

            HStack(spacing: 4) {
                Text("See our")
                    .font(.system(size: 11))
                    .foregroundStyle(WBGColors.textTertiary)
                Link("Privacy Policy", destination: links.privacyPolicy)
                    .font(.system(size: 11))
            }

            Text("No spam. Unsubscribe anytime.")
                .font(.system(size: 11))
                .foregroundStyle(WBGColors.textTertiary)

            HStack(spacing: 8) {
                Button("Get updates", action: register)
                    .disabled(!canSubmit)
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(isError ? WBGColors.danger : WBGColors.success)
            }
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && consent
            && !isSubmitting
            && email.contains("@")
    }

    private func register() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit else { return }

        isSubmitting = true
        message = nil
        isError = false

        Task {
            let result = await ProductUpdatesService.register(email: trimmed)
            isSubmitting = false

            switch result {
            case .success:
                hasOptedIn = true
                registeredEmail = trimmed
                message = nil
            case .alreadyRegistered:
                hasOptedIn = true
                registeredEmail = trimmed
                message = "You're already on the product updates list."
                isError = false
            case .invalidEmail:
                message = "Please enter a valid email address."
                isError = true
            case .networkError:
                message = "Couldn't register. Check your connection and try again."
                isError = true
            }
        }
    }
}

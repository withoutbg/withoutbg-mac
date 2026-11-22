import SwiftUI
import WithoutBGCore

/// Compact engine chip. Open weights: privacy value proposition. withoutBG
/// Pro (cloud): green dot plus the remaining credit balance.
struct PrivacyBadge: View {
    @AppStorage(SettingsKey.processingEngine) private var engineRaw = ProcessingEngine.openWeights.rawValue

    @State private var credits: Int?

    /// Pro only when chosen and a key exists (reads `engineRaw` so edits redraw).
    private var isPro: Bool {
        ProcessingEngine(rawValue: engineRaw) == .pro && APIKeyStore.hasKey
    }

    var body: some View {
        HStack(spacing: 6) {
            if isPro {
                Circle()
                    .fill(WBGColors.success)
                    .frame(width: 7, height: 7)
                Text(proLabel)
            } else {
                Text("Private · Offline · Open Weights")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(WBGColors.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(WBGColors.surface.opacity(0.8))
        )
        .task(id: isPro) { await loadCredits() }
    }

    private var proLabel: String {
        guard let credits else { return "withoutBG Cloud · Pro model" }
        return "withoutBG Cloud · Pro model · \(credits) credits"
    }

    private func loadCredits() async {
        guard isPro, let key = APIKeyStore.load() else {
            credits = nil
            return
        }
        credits = try? await CloudProcessor(apiKey: key).credits().credit
    }
}

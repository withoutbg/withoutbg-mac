import SwiftUI
import WithoutBGCore

/// GPU fund link with research-focused messaging.
struct GPUFundSection: View {
    private var links: ProductLinks { ProductLinks.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Help fund future open models.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WBGColors.textPrimary)
            Text("GPU funding helps us train better open-weight models and continue releasing them for everyone.")
                .font(.system(size: 12))
                .foregroundStyle(WBGColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: links.gpuFund) {
                Text("GPU Fund")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(WBGColors.accent)
        }
    }
}

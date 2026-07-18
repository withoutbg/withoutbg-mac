import SwiftUI

/// Compact privacy value proposition chip.
struct PrivacyBadge: View {
    var body: some View {
        Text("Private · Offline · Open Weights")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(WBGColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(WBGColors.surface.opacity(0.8))
            )
    }
}

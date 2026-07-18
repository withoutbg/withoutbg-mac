import SwiftUI

/// Branding line beneath the drop zone.
struct BrandingLine: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Powered by withoutBG Open Weights")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WBGColors.textSecondary)
            Text("Runs locally. Images never leave your Mac.")
                .font(.system(size: 11))
                .foregroundStyle(WBGColors.textTertiary)
        }
        .multilineTextAlignment(.center)
    }
}

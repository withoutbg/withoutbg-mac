import SwiftUI
import WithoutBGCore

/// Contextual Local API promo beneath the drop zone.
struct APIPromoSection: View {
    @Environment(ServerStatus.self) private var status
    @Environment(\.serverController) private var controller

    private var links: ProductLinks { ProductLinks.shared }

    var body: some View {
        VStack(spacing: 8) {
            Text("Need automation?")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WBGColors.textPrimary)
            Text("Run the Local API to integrate withoutBG with scripts and desktop applications.")
                .font(.system(size: 12))
                .foregroundStyle(WBGColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if status.isRunning {
                Text(status.boundURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WBGColors.textSecondary)
            } else {
                Button("Start Local API") {
                    guard let controller else { return }
                    Task {
                        await controller.start(port: UserDefaults.standard.localAPIPort)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Link("Learn More →", destination: links.localAPIDocs)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: 400)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WBGColors.surface.opacity(0.6))
        )
    }
}

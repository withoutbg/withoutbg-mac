import SwiftUI

/// About window content.
struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showNotices = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(colorScheme == .dark ? "logo-light" : "logo")
                .resizable()
                .scaledToFit()
                .frame(height: 40)

            VStack(spacing: 4) {
                Text("withoutBG")
                    .font(.system(size: 20, weight: .semibold))
                Text("Version \(version) (\(build))")
                    .font(.system(size: 12))
                    .foregroundStyle(WBGColors.textSecondary)
                Text("Model: withoutBG Open Weights · Core ML fp32")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(WBGColors.textTertiary)
            }

            Text("This app runs withoutBG Open Weights locally on your Mac.")
                .font(.system(size: 12))
                .foregroundStyle(WBGColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            attributionLine

            HStack(spacing: 14) {
                Link("Website", destination: ProductLinks.shared.website)
                Link("GitHub", destination: ProductLinks.shared.github)
                Link("License", destination: ProductLinks.shared.license)
                Button("Notices") { showNotices = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WBGColors.accent)
            }
            .font(.system(size: 12, weight: .medium))

            Link(destination: ProductLinks.shared.support) {
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                    Text("Support this project")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WBGColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .frame(width: 400)
        .background(WBGColors.page)
        .sheet(isPresented: $showNotices) {
            ThirdPartyNoticesView()
        }
    }

    private var attributionLine: some View {
        VStack(spacing: 4) {
            Text("withoutBG Open Weights was developed using Meta DINOv3 as an upstream model.")
                .font(.system(size: 11))
                .foregroundStyle(WBGColors.textTertiary)
                .multilineTextAlignment(.center)
            Text("DINOv3 is © Meta and used under the DINOv3 License.")
                .font(.system(size: 11))
                .foregroundStyle(WBGColors.textTertiary)
            HStack(spacing: 8) {
                Link("DINOv3", destination: ProductLinks.shared.dinov3Repo)
                Text("·")
                    .foregroundStyle(WBGColors.textTertiary)
                Link("DINOv3 License", destination: ProductLinks.shared.dinov3License)
            }
            .font(.system(size: 11))
        }
    }

}

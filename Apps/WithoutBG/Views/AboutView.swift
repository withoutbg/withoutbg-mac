import SwiftUI
import WithoutBGCore

/// About window content.
struct AboutView: View {
    var serverStatus: ServerStatus? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var showNotices = false

    private var links: ProductLinks { ProductLinks.shared }

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
                Text("Model: withoutBG Open Weights v\(CoreMLProcessor.modelVersion) · Core ML fp32")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(WBGColors.textTertiary)
            }

            if let serverStatus, serverStatus.isRunning {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Local API running at \(serverStatus.boundURL)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(WBGColors.textSecondary)
                }
            }

            Text("This app runs withoutBG Open Weights locally on your Mac.")
                .font(.system(size: 12))
                .foregroundStyle(WBGColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            attributionLine

            VStack(spacing: 8) {
                HStack(spacing: 14) {
                    Link("Website", destination: links.website)
                    Link("GitHub", destination: links.github)
                    Link("Documentation", destination: links.documentation)
                }
                HStack(spacing: 14) {
                    Link("Local API", destination: links.localAPIDocs)
                    Link("Cloud API", destination: links.api)
                    Link("Enterprise", destination: links.enterprise)
                }
                HStack(spacing: 14) {
                    Link("GPU Fund", destination: links.gpuFund)
                    Link("License", destination: links.license)
                    Link("Privacy", destination: links.privacyPolicy)
                    Button("Notices") { showNotices = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(WBGColors.accent)
                }
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(28)
        .frame(width: 420)
        .background(WBGColors.page)
        .sheet(isPresented: $showNotices) {
            ThirdPartyNoticesView()
        }
    }

    private var attributionLine: some View {
        VStack(spacing: 4) {
            Text("Built with DINOv3 ConvNeXt. withoutBG Open Weights also incorporates Depth Anything V2 (small variant) (Apache-2.0).")
                .font(.system(size: 11))
                .foregroundStyle(WBGColors.textTertiary)
                .multilineTextAlignment(.center)
            Text("DINOv3 is © Meta and used under the DINOv3 License.")
                .font(.system(size: 11))
                .foregroundStyle(WBGColors.textTertiary)
            HStack(spacing: 8) {
                Link("DINOv3", destination: links.dinov3Repo)
                Text("·")
                    .foregroundStyle(WBGColors.textTertiary)
                Link("DINOv3 License", destination: links.dinov3License)
            }
            .font(.system(size: 11))
        }
    }
}

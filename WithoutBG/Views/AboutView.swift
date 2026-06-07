import SwiftUI

/// About window content.
struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme

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
                Text("Model: WBGNet OSS · Core ML fp16")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(WBGColors.textTertiary)
            }

            Text("This app runs withoutBG OSS locally on your Mac.")
                .font(.system(size: 12))
                .foregroundStyle(WBGColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Link("Website", destination: ProductLinks.shared.website)
                Link("GitHub", destination: ProductLinks.shared.github)
                Link("License", destination: ProductLinks.shared.license)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(28)
        .frame(width: 360)
        .background(WBGColors.page)
    }
}

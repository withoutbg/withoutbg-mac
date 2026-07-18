import SwiftUI
import WithoutBGCore

/// Enterprise licensing section for Settings.
struct CommercialLicensingSection: View {
    private var links: ProductLinks { ProductLinks.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            bullet("OEM licensing")
            bullet("On-premise deployment")
            bullet("Priority support")
        }
        .font(.system(size: 12))
        .foregroundStyle(WBGColors.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)

        Link(destination: links.enterprise) {
            Text("Contact us")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("·")
            Text(text)
        }
    }
}

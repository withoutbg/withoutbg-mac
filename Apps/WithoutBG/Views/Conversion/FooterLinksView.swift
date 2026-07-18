import SwiftUI
import WithoutBGCore

/// Lightweight ecosystem footer links for the empty state.
struct FooterLinksView: View {
    private var links: ProductLinks { ProductLinks.shared }

    var body: some View {
        let items: [(String, URL)] = [
            ("Open Weights", links.openWeights),
            ("Local API", links.localAPIDocs),
            ("GitHub", links.github),
            ("Documentation", links.documentation),
            ("Cloud API", links.api),
            ("Enterprise", links.enterprise),
            ("GPU Fund", links.gpuFund),
        ]

        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Text("·")
                        .foregroundStyle(WBGColors.textTertiary)
                }
                Link(item.0, destination: item.1)
                    .foregroundStyle(WBGColors.textSecondary)
                    .underline()
            }
        }
        .font(.system(size: 11))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// Simple wrapping layout for footer link rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

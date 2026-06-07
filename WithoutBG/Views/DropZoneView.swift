import SwiftUI

/// Empty-state drop zone.
struct DropZoneView: View {
    let onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 40) {
            dropZone
            servingLine
        }
    }

    private var dropZone: some View {
        Button(action: onOpen) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(WBGColors.surface)
                        .frame(width: 64, height: 64)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(hovering ? WBGColors.accent : WBGColors.textTertiary)
                }
                .animation(.easeInOut(duration: 0.15), value: hovering)

                VStack(spacing: 6) {
                    Text("Drop images, click, or paste ⌘V")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WBGColors.textPrimary)
                    Text("JPG, PNG, WEBP · up to \(ProcessingQueue.maxBatch) images")
                        .font(.system(size: 12))
                        .foregroundStyle(WBGColors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 280)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(WBGColors.surface.opacity(hovering ? 1 : 0.5))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var servingLine: some View {
        HStack(spacing: 6) {
            Text("Serving")
                .foregroundStyle(WBGColors.textTertiary)
            Link("withoutBG Open Weights", destination: ProductLinks.shared.openWeights)
                .foregroundStyle(WBGColors.textSecondary)
            Text("·")
                .foregroundStyle(WBGColors.textTertiary)
            Link("GitHub", destination: ProductLinks.shared.github)
                .foregroundStyle(WBGColors.textSecondary)
            Text("·")
                .foregroundStyle(WBGColors.textTertiary)
            Link("License", destination: ProductLinks.shared.license)
                .foregroundStyle(WBGColors.textSecondary)
        }
        .font(.system(size: 11))
    }
}

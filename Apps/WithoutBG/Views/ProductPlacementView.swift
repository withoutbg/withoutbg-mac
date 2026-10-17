import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Placeholder Product Placement workspace. Upload shows the image only —
/// no processing yet.
struct ProductPlacementView: View {
    @State private var image: NSImage?
    @State private var fileName: String?

    var body: some View {
        Group {
            if let image {
                imagePreview(image)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WBGColors.page)
        .navigationTitle("Product Placement")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: openFilePanel) {
                    Label("Add Image", systemImage: "plus")
                }
                .help("Add an image")
            }
            if image != nil {
                ToolbarItem(placement: .automatic) {
                    Button(action: clear) {
                        Label("Clear", systemImage: "trash")
                    }
                    .help("Remove the image")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(WBGColors.surface)
                    .frame(width: 64, height: 64)
                Image(systemName: "cube.transparent")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(WBGColors.textTertiary)
            }

            VStack(spacing: 6) {
                Text("Product Placement")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WBGColors.textPrimary)
                Text("Coming soon — upload an image to preview it here.")
                    .font(.system(size: 12))
                    .foregroundStyle(WBGColors.textTertiary)
                    .multilineTextAlignment(.center)
            }

            Button(action: openFilePanel) {
                Label("Add Image", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func imagePreview(_ image: NSImage) -> some View {
        VStack(spacing: 16) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 640, maxHeight: 480)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(WBGColors.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

            if let fileName {
                Text(fileName)
                    .font(.system(size: 12))
                    .foregroundStyle(WBGColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let loaded = ImageIngestion.load(from: [url])
        guard let first = loaded.first else { return }
        image = NSImage(
            cgImage: first.image,
            size: NSSize(width: first.image.width, height: first.image.height)
        )
        fileName = first.fileName
    }

    private func clear() {
        image = nil
        fileName = nil
    }
}

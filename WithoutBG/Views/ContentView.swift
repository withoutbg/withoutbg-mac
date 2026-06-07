import SwiftUI
import UniformTypeIdentifiers

/// Root content. Switches between the empty drop zone and the active grid,
/// handles window-wide drag-and-drop + paste, and hosts the preview overlay.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    private var queue: ProcessingQueue { model.queue }

    var body: some View {
        @Bindable var model = model

        GeometryReader { viewport in
            ScrollView {
                if !queue.hasJobs {
                    DropZoneView(onOpen: model.openFilePanel)
                        .padding(24)
                        .frame(minHeight: viewport.size.height)
                } else {
                    QueueGridView(model: model)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .frame(minHeight: viewport.size.height)
                }
            }
        }
        .background(WBGColors.page)
        .toolbar { toolbarContent }
        .onDrop(of: [.fileURL, .image], isTargeted: $model.isDragOver) { providers in
            model.handleDrop(providers)
        }
        .overlay {
            if model.isDragOver && !model.isDraggingOut { dragOverlay }
        }
        .animation(.easeInOut(duration: 0.15), value: model.isDragOver)
        .overlay {
            if let job = model.previewJob {
                ImagePreviewOverlay(model: model, job: job)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.previewJobID != nil)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Leading: Add more / limit indicator
        ToolbarItem(placement: .primaryAction) {
            Button(action: model.openFilePanel) {
                Label("Add Images", systemImage: "plus")
            }
            .disabled(queue.atLimit)
            .help(queue.atLimit
                  ? "Maximum of \(ProcessingQueue.maxBatch) images reached"
                  : "Add images (⌘O)")
        }

        // Center: Status / selection summary
        ToolbarItem(placement: .status) {
            statusView
        }

        // Trailing: contextual actions
        ToolbarItemGroup(placement: .automatic) {
            if model.hasSelection {
                Button("Deselect") { model.clearSelection() }
                    .help("Clear selection")
            } else {
                if queue.doneJobs.count >= 2 {
                    Button(action: model.exportAll) {
                        Label("Download All", systemImage: "arrow.down.circle")
                    }
                    .help("Download all results as a ZIP (⇧⌘E)")
                }
                if queue.hasJobs {
                    Button(action: model.clear) {
                        Label("Clear", systemImage: "trash")
                    }
                    .help("Remove all images")
                }
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if model.hasSelection {
            Text("\(model.selection.count) selected")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else if queue.processingCount > 0 {
            HStack(spacing: 6) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                Text("Processing…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        } else if !queue.doneJobs.isEmpty {
            HStack(spacing: 6) {
                if queue.errorCount > 0 {
                    Text("\(queue.errorCount) failed")
                        .foregroundStyle(.red)
                }
                Text("\(queue.doneJobs.count) done")
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                if queue.queuedCount > 0 {
                    Text("· \(queue.queuedCount) queued")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
        }
    }

    // MARK: - Drag overlay

    private var dragOverlay: some View {
        ZStack {
            WBGColors.surface.opacity(0.92)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    WBGColors.accent,
                    style: StrokeStyle(lineWidth: 3, dash: [10, 6])
                )
                .padding(12)
            Text("Drop images to remove backgrounds")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WBGColors.textPrimary)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

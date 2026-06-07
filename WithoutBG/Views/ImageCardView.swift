import AppKit
import SwiftUI

/// A single thumbnail in the queue grid. Behaves like a photo in Photos:
/// click to select (⌘/⇧ for multi), drag out to Finder, right-click for
/// actions, Space for Quick Look preview.
struct ImageCardView: View {
    let model: AppModel
    let job: Job
    let isSelected: Bool
    var onFrameChange: (UUID, CGRect) -> Void = { _, _ in }

    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var renameFieldFocused: Bool
    @State private var lastClickTime: Date?
    @State private var lastClickJobID: UUID?

    private var isDone: Bool { job.status == .done }

    var body: some View {
        if isDone {
            card.dragOut(items: { model.dragItems(for: job) }) { dragging in
                model.isDraggingOut = dragging
            }
        } else {
            card
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            thumbnailArea
            footer
        }
        .background(WBGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? WBGColors.accent : WBGColors.border,
                        lineWidth: isSelected ? 2 : 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WBGColors.accent.opacity(isSelected ? 0.12 : 0))
        )
        .background(frameReporter)
        .fadeInUp()
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: handlePrimaryClick)
        .contextMenu { contextMenu }
    }

    /// Finder-style click handling without stacking single + double `onTapGesture`
    /// (that pairing delays every click ~300 ms while SwiftUI waits for a second tap).
    private func handlePrimaryClick() {
        let now = Date()
        if isDone,
           lastClickJobID == job.id,
           let last = lastClickTime,
           now.timeIntervalSince(last) < 0.35 {
            model.openPreview(job.id)
            lastClickTime = nil
            lastClickJobID = nil
            return
        }
        model.handleClick(job.id, modifiers: Self.currentModifiers())
        lastClickTime = now
        lastClickJobID = job.id
    }

    /// Publishes this card's frame in the grid coordinate space for marquee
    /// hit-testing. macOS 14-compatible replacement for `onGeometryChange`; the
    /// reports are coalesced by `CardFrameStore` so they never trigger SwiftUI's
    /// "preference tried to update multiple times per frame" warning.
    private var frameReporter: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(WBGGridSpace.name))
            Color.clear
                .onAppear { onFrameChange(job.id, frame) }
                .onChange(of: frame) { _, newFrame in onFrameChange(job.id, newFrame) }
        }
    }

    private static func currentModifiers() -> EventModifiers {
        let flags = NSEvent.modifierFlags
        var mods: EventModifiers = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        return mods
    }

    // MARK: - Thumbnail

    private var displayImage: CGImage? {
        if isDone, let processed = job.processedImage { return processed }
        return job.thumbnail ?? job.preparedImage ?? job.beforeImage
    }

    private var thumbnailArea: some View {
        ZStack {
            if isDone {
                CheckerboardBackground()
            } else {
                WBGColors.page
            }

            if let img = displayImage {
                Image(decorative: img, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .opacity(job.status == .queued ? 0.4 : 1)
            }

            if job.status == .processing { processingOverlay }
            if job.status == .queued { queuedBadge }
            if job.status == .error { errorOverlay }
        }
        .aspectRatio(job.aspectRatio ?? 1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(.white)
        }
    }

    private var queuedBadge: some View {
        VStack {
            HStack {
                Text("Queued")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                Spacer()
            }
            Spacer()
        }
        .padding(6)
    }

    private var errorOverlay: some View {
        ZStack {
            WBGColors.danger.opacity(0.18)
            Text("Failed")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(WBGColors.danger, in: RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 4) {
            if isRenaming {
                renameField
            } else {
                Text(job.fileName)
                    .font(.system(size: 11))
                    .foregroundStyle(WBGColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(job.fileName)
                    .onTapGesture(count: 2) { beginRename() }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var renameField: some View {
        TextField("Name", text: $draftName)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(WBGColors.textPrimary)
            .focused($renameFieldFocused)
            .onSubmit(commitRename)
            .onExitCommand { isRenaming = false }
            .onChange(of: renameFieldFocused) { _, focused in
                if !focused { commitRename() }
            }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        if model.selection.count > 1, isSelected {
            Button("Preview") { model.openPreviewForSelection() }
            if !model.selectedDoneJobs.isEmpty {
                Button("Download…") { model.downloadSelection() }
                Button("Copy") { model.copySelection() }
            }
            Divider()
            Button("Delete", role: .destructive) { model.confirmRemoveSelection() }
        } else {
            Button("Preview") { model.openPreview(job.id) }
            if isDone {
                Button("Download…") { model.download(job) }
                Button("Copy") { model.copy(job) }
                Divider()
            }
            Button("Rename…") { beginRename() }
            if job.status == .error {
                Button("Retry") { model.queue.retryJob(job.id) }
            }
            Divider()
            Button("Delete", role: .destructive) { model.confirmRemove(job.id) }
        }
    }

    // MARK: - Rename

    private func beginRename() {
        draftName = job.baseName
        isRenaming = true
        DispatchQueue.main.async { renameFieldFocused = true }
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        model.rename(job.id, to: draftName)
    }
}

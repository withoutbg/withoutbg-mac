import AppKit
import SwiftUI

/// Named coordinate space shared by the grid and its cards so marquee math and
/// per-card frames agree.
enum WBGGridSpace {
    static let name = "wbgGrid"
    /// Uniform square thumbnails — matches Photos / Finder icon grids.
    static let thumbnailAspectRatio: CGFloat = 1
}

/// Batches per-card geometry reports so marquee hit-testing updates at most
/// once per run loop (avoids "preference tried to update multiple times per frame").
@MainActor
private final class CardFrameStore {
    private(set) var frames: [UUID: CGRect] = [:]
    private var pending: [UUID: CGRect] = [:]
    private var flushScheduled = false

    func report(id: UUID, frame: CGRect) {
        if frames[id] == frame { return }
        pending[id] = frame
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            self.frames.merge(self.pending) { _, new in new }
            self.pending.removeAll()
        }
    }
}

/// Responsive grid of image cards with a trailing "add more" tile. Mirrors web
/// `QueueGrid.tsx`, and adds Finder-style selection + keyboard navigation.
struct QueueGridView: View {
    let model: AppModel

    @State private var columnCount = 3
    @FocusState private var focused: Bool

    @State private var frameStore = CardFrameStore()
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var marqueeAdditive = false
    @State private var marqueeBase: Set<UUID> = []

    private let spacing: CGFloat = 12
    private let minItem: CGFloat = 170

    private var queue: ProcessingQueue { model.queue }

    var body: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: spacing),
            count: max(1, columnCount)
        )

        ZStack(alignment: .topLeading) {
            workAreaBackdrop
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(queue.jobs) { job in
                    ImageCardView(
                        model: model,
                        job: job,
                        isSelected: model.isSelected(job.id),
                        onFrameChange: { frameStore.report(id: $0, frame: $1) }
                    )
                }

                if !queue.atLimit {
                    AddMoreTile(action: model.openFilePanel)
                }
            }
            .background(columnWidthReader)
        }
        .overlay(marqueeOverlay)
        .coordinateSpace(.named(WBGGridSpace.name))
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(action: handleKey)
    }

    /// Fills the work area so marquee selection and empty-space clicks work
    /// below the last grid row, not only in gaps between cards.
    private var workAreaBackdrop: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { model.clearSelection() }
            .gesture(marqueeGesture)
    }

    /// Tracks grid width for responsive column count and hosts marquee
    /// selection in empty gaps between cards (cards sit above this layer).
    private var columnWidthReader: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.clearSelection() }
                .gesture(marqueeGesture)
                .onAppear { columnCount = computeColumns(geo.size.width) }
                .onChange(of: geo.size.width) { _, width in
                    columnCount = computeColumns(width)
                }
        }
    }

    // MARK: - Marquee (area selection)

    private var marqueeRect: CGRect? {
        guard let start = marqueeStart, let current = marqueeCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
    }

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(WBGGridSpace.name))
            .onChanged { value in
                if marqueeStart == nil {
                    marqueeStart = value.startLocation
                    let flags = NSEvent.modifierFlags
                    marqueeAdditive = flags.contains(.command) || flags.contains(.shift)
                    marqueeBase = marqueeAdditive ? model.selection : []
                }
                marqueeCurrent = value.location
                updateMarqueeSelection()
            }
            .onEnded { _ in
                marqueeStart = nil
                marqueeCurrent = nil
                marqueeBase = []
            }
    }

    private func updateMarqueeSelection() {
        guard let rect = marqueeRect else { return }
        let hits = frameStore.frames.compactMap { $0.value.intersects(rect) ? $0.key : nil }
        model.setSelection(marqueeAdditive ? marqueeBase.union(hits) : Set(hits))
    }

    @ViewBuilder
    private var marqueeOverlay: some View {
        if let rect = marqueeRect, rect.width > 1 || rect.height > 1 {
            Rectangle()
                .fill(WBGColors.accent.opacity(0.15))
                .overlay(Rectangle().stroke(WBGColors.accent.opacity(0.8), lineWidth: 1))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
        }
    }

    private func computeColumns(_ width: CGFloat) -> Int {
        guard width > 0 else { return columnCount }
        return max(1, Int((width + spacing) / (minItem + spacing)))
    }

    // MARK: - Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let extend = press.modifiers.contains(.shift)
        switch press.key {
        case .leftArrow:
            model.moveSelection(by: -1, extend: extend); return .handled
        case .rightArrow:
            model.moveSelection(by: 1, extend: extend); return .handled
        case .upArrow:
            model.moveSelection(by: -columnCount, extend: extend); return .handled
        case .downArrow:
            model.moveSelection(by: columnCount, extend: extend); return .handled
        case .space:
            if model.canPreviewSelection {
                model.togglePreview()
                return .handled
            }
            return .ignored
        case .return:
            // Finder convention: Return on a single selection starts a rename.
            if let id = model.singleSelection {
                model.beginRename(id); return .handled
            }
            return .ignored
        case .delete, .deleteForward:
            // ⌘⌫ deletes (undoable). Bare Delete is ignored to avoid surprises.
            if press.modifiers.contains(.command) {
                model.deleteSelection(); return .handled
            }
            return .ignored
        case .escape:
            model.clearSelection(); return .handled
        default:
            break
        }

        if press.modifiers.contains(.command) {
            switch press.key {
            case "a": model.selectAll(); return .handled
            case "c": model.copySelection(); return .handled
            default: break
            }
        }
        return .ignored
    }
}

/// "+" tile shown inline in the grid after the last card.
private struct AddMoreTile: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(hovering ? WBGColors.accent.opacity(0.12) : WBGColors.surface)
                            .frame(width: 40, height: 40)
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(hovering ? WBGColors.accent : WBGColors.textSecondary)
                    }
                    .animation(.easeInOut(duration: 0.15), value: hovering)

                    Text("Add more")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(hovering ? WBGColors.accent : WBGColors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(WBGGridSpace.thumbnailAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)

                // Match ImageCardView footer height so the tile aligns with cards.
                Color.clear.frame(height: 30)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WBGColors.surface.opacity(hovering ? 1 : 0.5))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Add more images")
    }
}

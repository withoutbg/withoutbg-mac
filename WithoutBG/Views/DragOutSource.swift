import AppKit
import SwiftUI

/// One file participating in a native drag-out session: the staged PNG on disk
/// plus an image used for the drag preview.
struct DragOutItem {
    let url: URL
    let image: NSImage?
}

/// Bridges SwiftUI to AppKit's `NSDraggingSession`. Unlike SwiftUI's `.onDrag`
/// (which can only vend a single item), this drags an arbitrary number of files
/// out to Finder / other apps in one session — so a multi-selection drops as
/// multiple files, with the standard macOS item-count badge.
@MainActor
final class DragOutCoordinator {
    fileprivate weak var view: DragOutSourceView?

    /// Start a drag if one isn't already in flight and the current AppKit event
    /// is a mouse drag we can hand to `beginDraggingSession`.
    func begin(items provider: () -> [DragOutItem]) {
        guard let view, !view.isDragging else { return }
        guard let event = NSApp.currentEvent,
              event.type == .leftMouseDragged || event.type == .leftMouseDown
        else { return }

        let items = provider()
        guard !items.isEmpty else { return }

        let bounds = view.bounds
        let draggingItems: [NSDraggingItem] = items.enumerated().map { index, item in
            let dragItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            // Stack additional items slightly so the multi-item drag reads as a pile.
            let offset = CGFloat(index) * 6
            let frame = CGRect(x: offset, y: offset, width: bounds.width, height: bounds.height)
            dragItem.setDraggingFrame(frame, contents: item.image)
            return dragItem
        }
        view.start(draggingItems: draggingItems, event: event)
    }
}

/// Invisible source view. It opts out of hit-testing so SwiftUI keeps handling
/// clicks, double-clicks and the context menu drawn on top of it; the view only
/// exists to own the dragging session.
final class DragOutSourceView: NSView, NSDraggingSource {
    var onDragStateChange: ((Bool) -> Void)?
    private(set) var isDragging = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func start(draggingItems: [NSDraggingItem], event: NSEvent) {
        guard !isDragging, !draggingItems.isEmpty else { return }
        isDragging = true
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        isDragging = true
        // Defer so SwiftUI state updates don't re-enter AppKit drag IPC.
        DispatchQueue.main.async { [weak self] in self?.onDragStateChange?(true) }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDragging = false
        DispatchQueue.main.async { [weak self] in self?.onDragStateChange?(false) }
    }
}

private struct DragOutSourceRepresentable: NSViewRepresentable {
    let coordinator: DragOutCoordinator
    let onDragStateChange: (Bool) -> Void

    func makeNSView(context: Context) -> DragOutSourceView {
        let view = DragOutSourceView()
        view.onDragStateChange = onDragStateChange
        coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: DragOutSourceView, context: Context) {
        nsView.onDragStateChange = onDragStateChange
        coordinator.view = nsView
    }
}

private struct DragOutModifier: ViewModifier {
    let items: () -> [DragOutItem]
    let onDragStateChange: (Bool) -> Void
    @State private var coordinator = DragOutCoordinator()

    func body(content: Content) -> some View {
        content
            .background(
                DragOutSourceRepresentable(
                    coordinator: coordinator,
                    onDragStateChange: onDragStateChange
                )
            )
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in coordinator.begin(items: items) }
            )
    }
}

extension View {
    /// Make the view a native drag source vending `items` as real files. A short
    /// drag threshold keeps clicks / double-clicks working. `onDragStateChange`
    /// reports when a session begins/ends so callers can suppress in-window drop
    /// affordances during an internal drag-out.
    func dragOut(
        items: @escaping () -> [DragOutItem],
        onDragStateChange: @escaping (Bool) -> Void
    ) -> some View {
        modifier(DragOutModifier(items: items, onDragStateChange: onDragStateChange))
    }
}

import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// App-wide controller. Owns the processing queue and exposes the user intents
/// shared between the main views and the menu bar commands.
///
/// The processor is injected here — swapping `MockProcessor()` for
/// `CoreMLProcessor()` is the single change needed when the model ships.
@MainActor
@Observable
final class AppModel {
    let queue: ProcessingQueue

    /// Job currently shown in the Quick Look-style preview overlay.
    var previewJobID: UUID?
    /// True while files are dragged over the window.
    var isDragOver = false
    /// True while the user is dragging cards *out* of the app, so we can suppress
    /// the in-window drop affordance (otherwise dragging out loops back as a drop).
    var isDraggingOut = false

    /// Finder-style multi-selection of cards (any status).
    var selection: Set<UUID> = []
    /// Anchor used for shift-range selection and arrow-key navigation.
    private var selectionAnchorID: UUID?

    init(processor: any BackgroundRemovalProcessor = MockProcessor()) {
        self.queue = ProcessingQueue(processor: processor)
    }

    // MARK: - Derived

    var previewJob: Job? {
        guard let id = previewJobID else { return nil }
        return queue.jobs.first { $0.id == id }
    }

    /// Jobs navigable in the preview overlay — selected jobs when multiple are
    /// selected, otherwise the full queue (including a single selected item).
    var previewableJobs: [Job] {
        let selected = queue.jobs.filter { selection.contains($0.id) }
        return selected.count > 1 ? selected : queue.jobs
    }

    var canExportAll: Bool { queue.doneJobs.count >= 2 }

    /// Selected jobs that have a finished cutout (export/copy targets).
    var selectedDoneJobs: [Job] {
        queue.jobs.filter { selection.contains($0.id) && $0.status == .done }
    }

    var hasSelection: Bool { !selection.isEmpty }

    func isSelected(_ id: UUID) -> Bool { selection.contains(id) }

    // MARK: - Settings access

    private var defaultExportDirectory: URL? {
        UserDefaults.standard.defaultExportDirectory
    }

    private var revealAfterExport: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.revealAfterExport)
    }

    // MARK: - Ingestion intents

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        enqueue(ImageIngestion.load(from: panel.urls))
    }

    func paste() {
        enqueue(ImageIngestion.loadFromPasteboard())
    }

    func enqueue(_ loaded: [(fileName: String, image: CGImage)]) {
        guard !loaded.isEmpty else { return }
        queue.enqueue(loaded)
    }

    /// Handle a SwiftUI drop of file URLs / images. Returns true if accepted.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // Ignore our own cards being dragged out and dropped back on the window.
        guard !isDraggingOut else { return false }
        var handledAny = false
        let group = DispatchGroup()
        let collector = DropCollector()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handledAny = true
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url, ImageIngestion.isSupported(url) {
                        collector.append(ImageIngestion.load(from: [url]))
                    }
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                handledAny = true
                group.enter()
                _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                    if let image = object as? NSImage,
                       let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        collector.append([("Dropped Image.png", cg)])
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.enqueue(collector.drain())
        }
        return handledAny
    }

    // MARK: - Selection

    private var orderedIDs: [UUID] { queue.jobs.map(\.id) }

    /// Click handling that mirrors Finder: plain click selects one, ⌘ toggles,
    /// ⇧ extends a range from the anchor.
    func handleClick(_ id: UUID, modifiers: EventModifiers) {
        if modifiers.contains(.command) {
            toggle(id)
        } else if modifiers.contains(.shift) {
            extendSelection(to: id)
        } else {
            selection = [id]
            selectionAnchorID = id
        }
    }

    func toggle(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
        selectionAnchorID = id
    }

    func extendSelection(to id: UUID) {
        let ids = orderedIDs
        guard let anchor = selectionAnchorID ?? selection.first ?? ids.first,
              let start = ids.firstIndex(of: anchor),
              let end = ids.firstIndex(of: id)
        else {
            selection = [id]
            selectionAnchorID = id
            return
        }
        let range = start <= end ? start...end : end...start
        selection = Set(ids[range])
    }

    func selectAll() {
        selection = Set(orderedIDs)
        selectionAnchorID = orderedIDs.last
    }

    /// Replace the selection wholesale (used by area/marquee selection). Keeps
    /// the existing anchor when it stays selected so arrow-keys resume sensibly.
    func setSelection(_ ids: Set<UUID>) {
        selection = ids
        if let anchor = selectionAnchorID, ids.contains(anchor) { return }
        selectionAnchorID = ids.first
    }

    func clearSelection() {
        selection = []
        selectionAnchorID = nil
    }

    /// Move the selection cursor by `delta` items (±1 horizontal, ±columns
    /// vertical). With `extend`, grows the range instead of replacing it.
    func moveSelection(by delta: Int, extend: Bool) {
        let ids = orderedIDs
        guard !ids.isEmpty else { return }
        let cursor = selectionAnchorID ?? selection.first ?? ids[0]
        let current = ids.firstIndex(of: cursor) ?? 0
        let next = min(max(0, current + delta), ids.count - 1)
        let nextID = ids[next]
        if extend {
            extendSelection(to: nextID)
        } else {
            selection = [nextID]
            selectionAnchorID = nextID
        }
    }

    // MARK: - Selection actions

    func copySelection() {
        let jobs = selectedDoneJobs
        ExportService.copyToPasteboard(jobs.isEmpty ? queue.doneJobs : jobs)
    }

    func copy(_ job: Job) {
        ExportService.copyToPasteboard([job])
    }

    func downloadSelection() {
        let jobs = selectedDoneJobs
        if jobs.count == 1 {
            download(jobs[0])
        } else if jobs.count >= 2 {
            ExportService.saveAll(
                jobs: jobs,
                background: .transparent,
                defaultDirectory: defaultExportDirectory,
                revealInFinder: revealAfterExport
            )
        }
    }

    func remove(_ id: UUID) {
        queue.removeJob(id)
        if previewJobID == id { previewJobID = nil }
        selection.remove(id)
        if selectionAnchorID == id { selectionAnchorID = selection.first }
    }

    func confirmRemove(_ id: UUID) {
        guard confirmDeletion(count: 1) else { return }
        remove(id)
    }

    func removeSelection() {
        guard !selection.isEmpty else { return }
        if let preview = previewJobID, selection.contains(preview) { previewJobID = nil }
        for id in selection { queue.removeJob(id) }
        clearSelection()
    }

    func confirmRemoveSelection() {
        guard !selection.isEmpty, confirmDeletion(count: selection.count) else { return }
        removeSelection()
    }

    func rename(_ id: UUID, to newBaseName: String) {
        queue.rename(id, to: newBaseName)
    }

    /// Files to drag out when the user starts dragging `job`. If the card is part
    /// of a multi-selection, all selected finished cards come along (Finder-style);
    /// otherwise just this card, which also becomes the selection.
    func dragItems(for job: Job) -> [DragOutItem] {
        dragJobs(for: job).compactMap { candidate in
            guard let url = ExportService.stagedFileURL(for: candidate) else { return nil }
            let image = candidate.processedImage.map {
                NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
            }
            return DragOutItem(url: url, image: image)
        }
    }

    private func dragJobs(for job: Job) -> [Job] {
        guard job.status == .done else { return [] }
        if selection.contains(job.id) {
            let done = selectedDoneJobs
            return done.count > 1 ? done : [job]
        }
        // Dragging an unselected card selects just it, like Finder.
        selection = [job.id]
        selectionAnchorID = job.id
        return [job]
    }

    // MARK: - Preview overlay

    func openPreview(_ id: UUID) {
        guard queue.jobs.contains(where: { $0.id == id }) else { return }
        previewJobID = id
    }

    func closePreview() { previewJobID = nil }

    /// Toggle Quick Look-style preview for the current selection.
    func togglePreview() {
        if previewJobID != nil {
            closePreview()
        } else {
            openPreviewForSelection()
        }
    }

    func openPreviewForSelection() {
        let jobs = previewableJobs
        guard !jobs.isEmpty else { return }
        previewJobID = jobs[0].id
    }

    func movePreview(by delta: Int) {
        let jobs = previewableJobs
        guard !jobs.isEmpty, let current = previewJobID,
              let idx = jobs.firstIndex(where: { $0.id == current })
        else { return }
        let next = min(max(0, idx + delta), jobs.count - 1)
        previewJobID = jobs[next].id
    }

    // MARK: - Export intents

    func exportAll() {
        ExportService.saveAll(
            jobs: queue.jobs,
            background: .transparent,
            defaultDirectory: defaultExportDirectory,
            revealInFinder: revealAfterExport
        )
    }

    func download(_ job: Job, background: ExportBackground = .transparent) {
        ExportService.saveSingle(
            job: job,
            background: background,
            defaultDirectory: defaultExportDirectory,
            revealInFinder: revealAfterExport
        )
    }

    func clear() {
        queue.reset()
        previewJobID = nil
        clearSelection()
    }

    // MARK: - Destructive action confirmation

    private func confirmDeletion(count: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = count == 1 ? "Delete this image?" : "Delete \(count) images?"
        alert.informativeText = "This removes the image\(count == 1 ? "" : "s") from the current batch."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Thread-safe accumulator for asynchronous drop callbacks.
private final class DropCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(fileName: String, image: CGImage)] = []

    func append(_ new: [(fileName: String, image: CGImage)]) {
        lock.lock(); items.append(contentsOf: new); lock.unlock()
    }

    func drain() -> [(fileName: String, image: CGImage)] {
        lock.lock(); defer { items.removeAll(); lock.unlock() }
        return items
    }
}

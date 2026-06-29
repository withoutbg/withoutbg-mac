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

    /// True while files are dragged over the window.
    var isDragOver = false
    /// True while the user is dragging cards *out* of the app, so we can suppress
    /// the in-window drop affordance (otherwise dragging out loops back as a drop).
    var isDraggingOut = false

    /// Finder-style multi-selection of cards (any status).
    var selection: Set<UUID> = []
    /// Anchor used for shift-range selection and arrow-key navigation.
    private var selectionAnchorID: UUID?

    /// Job that should enter inline-rename mode. Set by the Return key / menu so
    /// the matching card focuses its text field; cleared once the card consumes it.
    var renamingJobID: UUID?

    /// Drives the Undo/Redo menu items. `UndoManager` isn't observable, so we
    /// mirror its state into these properties after every mutation.
    let undoManager = UndoManager()
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var undoTitle = "Undo"
    private(set) var redoTitle = "Redo"

    /// Tracks how many jobs were still active (queued/processing) on the previous
    /// progress tick, so we can detect the moment a whole batch finishes.
    private var lastActiveCount = 0

    init(processor: any BackgroundRemovalProcessor = MockProcessor()) {
        self.queue = ProcessingQueue(processor: processor)
    }

    // MARK: - Derived

    /// Finished jobs with a cutout — the only items Quick Look can show.
    var previewableJobs: [Job] {
        queue.jobs.filter { $0.status == .done && $0.processedImage != nil }
    }

    /// Whether the current selection (or the full queue when nothing is selected)
    /// has at least one finished cutout to preview.
    var canPreviewSelection: Bool {
        !previewJobsForSelection().jobs.isEmpty
    }

    var canExportAll: Bool { queue.doneJobs.count >= 2 }

    /// Selected jobs that have a finished cutout (export/copy targets).
    var selectedDoneJobs: [Job] {
        queue.jobs.filter { selection.contains($0.id) && $0.status == .done }
    }

    var hasSelection: Bool { !selection.isEmpty }

    /// The single selected job's id, or nil when zero or many are selected.
    var singleSelection: UUID? { selection.count == 1 ? selection.first : nil }

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

    /// Delete a single job. Undoable (⌘Z restores it), matching Finder/Photos —
    /// no confirmation dialog.
    func delete(_ id: UUID) {
        deleteJobs([id])
    }

    /// Delete the current selection. Undoable.
    func deleteSelection() {
        guard !selection.isEmpty else { return }
        deleteJobs(orderedIDs.filter { selection.contains($0) })
    }

    /// Capture the jobs (and their grid positions) about to be removed, delete
    /// them, and register an Undo that restores them. The redo is registered
    /// automatically when the Undo runs.
    private func deleteJobs(_ ids: [UUID]) {
        let removed: [(offset: Int, job: Job)] = ids.compactMap { id in
            guard let idx = queue.jobs.firstIndex(where: { $0.id == id }) else { return nil }
            return (offset: idx, job: queue.jobs[idx])
        }
        guard !removed.isEmpty else { return }
        applyDelete(removed)
        refreshUndoState()
    }

    private func applyDelete(_ removed: [(offset: Int, job: Job)]) {
        let ids = Set(removed.map { $0.job.id })
        for id in ids { queue.removeJob(id) }
        QuickLookController.shared.close()
        selection.subtract(ids)
        if let anchor = selectionAnchorID, ids.contains(anchor) {
            selectionAnchorID = selection.first
        }
        undoManager.registerUndo(withTarget: self) { model in
            model.applyRestore(removed)
        }
        undoManager.setActionName(removed.count == 1 ? "Delete Image" : "Delete Images")
    }

    private func applyRestore(_ removed: [(offset: Int, job: Job)]) {
        queue.restore(removed)
        selection = Set(removed.map { $0.job.id })
        selectionAnchorID = removed.first?.job.id
        undoManager.registerUndo(withTarget: self) { model in
            model.applyDelete(removed)
        }
        undoManager.setActionName(removed.count == 1 ? "Delete Image" : "Delete Images")
    }

    func rename(_ id: UUID, to newBaseName: String) {
        guard let old = queue.jobs.first(where: { $0.id == id })?.fileName else { return }
        queue.rename(id, to: newBaseName)
        guard let new = queue.jobs.first(where: { $0.id == id })?.fileName, new != old else { return }
        registerRenameUndo(id: id, from: new, to: old)
        undoManager.setActionName("Rename")
        refreshUndoState()
    }

    private func registerRenameUndo(id: UUID, from current: String, to previous: String) {
        undoManager.registerUndo(withTarget: self) { model in
            model.queue.setFileName(id, previous)
            model.registerRenameUndo(id: id, from: previous, to: current)
            model.undoManager.setActionName("Rename")
        }
    }

    /// Ask the focused card matching `id` to begin inline rename (Return key / menu).
    func beginRename(_ id: UUID) {
        renamingJobID = id
    }

    // MARK: - Undo / Redo

    func performUndo() {
        undoManager.undo()
        refreshUndoState()
    }

    func performRedo() {
        undoManager.redo()
        refreshUndoState()
    }

    private func refreshUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
        undoTitle = undoManager.canUndo ? "Undo \(undoManager.undoActionName)" : "Undo"
        redoTitle = undoManager.canRedo ? "Redo \(undoManager.redoActionName)" : "Redo"
    }

    // MARK: - Share

    /// File URLs for the active share target — selected finished jobs, or all
    /// finished jobs when nothing relevant is selected. Used by `ShareLink`.
    var shareURLs: [URL] {
        let jobs = selectedDoneJobs.isEmpty ? queue.doneJobs : selectedDoneJobs
        return jobs.compactMap { ExportService.stagedFileURL(for: $0) }
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

    // MARK: - Quick Look preview

    /// Open the system Quick Look panel focused on `id`, paging through finished
    /// cutouts (selection or the whole queue).
    func openPreview(_ id: UUID) {
        guard previewableJobs.contains(where: { $0.id == id }) else { return }
        let jobs = previewableJobs
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        presentQuickLook(jobs: jobs, startIndex: idx)
    }

    func closePreview() { QuickLookController.shared.close() }

    /// Toggle Quick Look for the current selection (Space bar).
    func togglePreview() {
        if QuickLookController.shared.isVisible {
            QuickLookController.shared.close()
        } else {
            openPreviewForSelection()
        }
    }

    func openPreviewForSelection() {
        let bundle = previewJobsForSelection()
        guard !bundle.jobs.isEmpty else { return }
        presentQuickLook(jobs: bundle.jobs, startIndex: bundle.startIndex)
    }

    private struct PreviewBundle {
        let jobs: [Job]
        let startIndex: Int
    }

    /// Jobs to page through in Quick Look, and which item to focus first.
    private func previewJobsForSelection() -> PreviewBundle {
        let all = previewableJobs
        guard !all.isEmpty else { return PreviewBundle(jobs: [], startIndex: 0) }

        let selectedDone = all.filter { selection.contains($0.id) }
        if selectedDone.count > 1 {
            let focusID = selectionAnchorID ?? selection.first
            let idx = focusID.flatMap { id in selectedDone.firstIndex(where: { $0.id == id }) } ?? 0
            return PreviewBundle(jobs: selectedDone, startIndex: idx)
        }

        let focusID = selectionAnchorID ?? selection.first
        if let focusID, selection.contains(focusID) {
            guard let idx = all.firstIndex(where: { $0.id == focusID }) else {
                return PreviewBundle(jobs: [], startIndex: 0)
            }
            return PreviewBundle(jobs: all, startIndex: idx)
        }

        if selection.isEmpty {
            return PreviewBundle(jobs: all, startIndex: 0)
        }

        return PreviewBundle(jobs: [], startIndex: 0)
    }

    private func presentQuickLook(jobs: [Job], startIndex: Int) {
        let urls = jobs.compactMap { ExportService.previewFileURL(for: $0) }
        guard !urls.isEmpty else { return }
        QuickLookController.shared.present(urls: urls, startIndex: min(max(0, startIndex), urls.count - 1))
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

    /// Remove every job. Undoable — ⌘Z brings the whole batch back.
    func clear() {
        let removed = queue.jobs.enumerated().map { (offset: $0.offset, job: $0.element) }
        guard !removed.isEmpty else { return }
        applyDelete(removed)
        undoManager.setActionName("Clear")
        refreshUndoState()
    }

    // MARK: - Batch progress (Dock + notifications)

    /// Recompute Dock progress and fire a completion notification when a batch
    /// finishes. Call whenever queue counts change.
    func handleQueueProgress() {
        let total = queue.jobs.count
        let active = queue.queuedCount + queue.processingCount
        let done = queue.doneJobs.count

        if active > 0 {
            let fraction = total > 0 ? Double(total - active) / Double(total) : 0
            DockProgress.shared.update(progress: fraction, badge: active)
        } else {
            DockProgress.shared.clear()
        }

        // Transition from "work in flight" to "all settled" => batch finished.
        if lastActiveCount > 0 && active == 0 && done > 0 {
            NotificationService.shared.notifyBatchFinished(
                done: done,
                failed: queue.errorCount
            )
        }
        lastActiveCount = active
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

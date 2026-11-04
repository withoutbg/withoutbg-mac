import CoreGraphics
import Observation
import SwiftUI
import WithoutBGCore

/// Sequential, single-worker processing queue. Mirrors web `useProcessingQueue`.
///
/// Inference runs through a shared coordinator so desktop batch jobs and the
/// Local API serialize on one loaded model.
@MainActor
@Observable
final class ProcessingQueue {
    static let maxBatch = 20

    private(set) var jobs: [Job] = []
    private(set) var completedCount = 0

    private let coordinator: SharedInferenceCoordinator
    private var isWorking = false

    init(coordinator: SharedInferenceCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Derived summaries

    var doneJobs: [Job] { jobs.filter { $0.status == .done } }
    var queuedCount: Int { jobs.filter { $0.status == .queued }.count }
    var processingCount: Int { jobs.filter { $0.status == .processing }.count }
    var errorCount: Int { jobs.filter { $0.status == .error }.count }
    var hasJobs: Bool { !jobs.isEmpty }
    var atLimit: Bool { jobs.count >= Self.maxBatch }
    var remainingSlots: Int { max(0, Self.maxBatch - jobs.count) }

    // MARK: - Mutations

    /// Append new jobs, respecting the batch limit (overflow is silently
    /// truncated), then kick the worker.
    func enqueue(_ items: [(fileName: String, image: CGImage)]) {
        guard remainingSlots > 0, !items.isEmpty else { return }
        let accepted = items.prefix(remainingSlots).map {
            var job = Job(fileName: $0.fileName, beforeImage: $0.image)
            job.aspectRatio = CGFloat($0.image.width) / CGFloat($0.image.height)
            return job
        }
        jobs.append(contentsOf: accepted)

        // Generate small thumbnails off the main thread for newly queued cards.
        for job in accepted {
            let id = job.id
            guard let source = job.beforeImage else { continue }
            Task { await self.generateThumbnail(id: id, source: source) }
        }

        startWorkerIfNeeded()
    }

    func removeJob(_ id: UUID) {
        jobs.removeAll { $0.id == id }
    }

    /// Re-insert previously removed jobs at their original offsets. Used by Undo
    /// to restore a deletion. Offsets are clamped so out-of-range values append.
    func restore(_ items: [(offset: Int, job: Job)]) {
        for item in items.sorted(by: { $0.offset < $1.offset }) {
            let idx = min(max(0, item.offset), jobs.count)
            jobs.insert(item.job, at: idx)
        }
    }

    /// Set a job's display name verbatim (no extension handling). Used by Undo to
    /// restore the exact previous file name after a rename.
    func setFileName(_ id: UUID, _ fileName: String) {
        patch(id) { $0.fileName = fileName }
    }

    /// Rename a job, preserving its original extension. `newBaseName` is the
    /// base name without extension; empty input is ignored.
    func rename(_ id: UUID, to newBaseName: String) {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        patch(id) { job in
            let ext = job.fileExtension
            job.fileName = ext.isEmpty ? trimmed : "\(trimmed).\(ext)"
        }
    }

    func retryJob(_ id: UUID) {
        patch(id) { job in
            job.status = .queued
            job.error = nil
        }
        startWorkerIfNeeded()
    }

    func reset() {
        jobs.removeAll()
        completedCount = 0
    }

    // MARK: - Worker

    private func startWorkerIfNeeded() {
        guard !isWorking, jobs.contains(where: { $0.status == .queued }) else { return }
        isWorking = true
        Task { await runWorker() }
    }

    private func runWorker() async {
        defer { isWorking = false }
        while let next = jobs.first(where: { $0.status == .queued }) {
            await process(jobID: next.id)
        }
    }

    private func process(jobID: UUID) async {
        guard let before = job(jobID)?.beforeImage else { return }
        patch(jobID) { $0.status = .processing }

        do {
            let result: ProcessorResult
            let engine: ProcessingEngine
            if ProcessingEngine.effective == .pro, let key = APIKeyStore.load() {
                // Opt-in withoutBG Pro: hosted, so it skips the shared on-device queue.
                engine = .pro
                result = try await CloudProcessor(apiKey: key).process(preparedImage: before)
            } else {
                engine = .openWeights
                result = try await coordinator.process(preparedImage: before)
            }
            patch(jobID) {
                $0.alphaMatte = result.alphaMatte
                $0.editContext = nil
                $0.engine = engine
                $0.proKeep = nil
                $0.proRemove = nil
                $0.processedImage = result.processed
                $0.latencyMs = result.latencyMs
                $0.status = .done
            }
            completedCount += 1

            // Pre-stage the transparent PNG to temp storage off the main thread
            // so drag-out and copy can reuse the file without encoding on demand.
            let cutout = result.processed
            Task { await self.stageResult(jobID: jobID, image: cutout) }
        } catch {
            patch(jobID) {
                $0.status = .error
                $0.error = error.localizedDescription
            }
        }
    }

    // MARK: - Smart brush

    var supportsEdit: Bool { coordinator.supportsEdit }

    /// Apply Smart brush marks (original-size, row-major) to a finished job's result.
    func edit(_ jobID: UUID, keep: [Bool]?, remove: [Bool]?) async throws {
        guard let job = job(jobID), job.status == .done, let original = job.beforeImage else {
            throw ProcessorError.processingFailed("This image can no longer be edited.")
        }
        if job.engine == .pro {
            try await editPro(jobID, job: job, original: original, keep: keep, remove: remove)
            return
        }
        let result = try await coordinator.edit(preparedImage: original, keep: keep, remove: remove,
                                                matte: job.alphaMatte, context: job.editContext)
        patch(jobID) {
            $0.alphaMatte = result.alphaMatte
            $0.editContext = result.editContext
            $0.processedImage = result.processed
            $0.latencyMs = result.latencyMs
            $0.stagedURL = nil
        }
        let cutout = result.processed
        Task { await self.stageResult(jobID: jobID, image: cutout) }
    }

    /// Pro Smart brush is stateless: every Apply sends all strokes made on this cutout.
    private func editPro(_ jobID: UUID, job: Job, original: CGImage, keep: [Bool]?, remove: [Bool]?) async throws {
        guard let key = APIKeyStore.load() else {
            throw ProcessorError.processingFailed("withoutBG Pro needs an API key. Add it in Settings.")
        }
        let keepAll = Self.union(job.proKeep, keep)
        let removeAll = Self.union(job.proRemove, remove)
        patch(jobID) {
            $0.proKeep = keepAll
            $0.proRemove = removeAll
        }
        let result = try await CloudProcessor(apiKey: key)
            .edit(preparedImage: original, keep: keepAll, remove: removeAll)
        patch(jobID) {
            $0.alphaMatte = result.alphaMatte
            $0.editContext = nil
            $0.processedImage = result.processed
            $0.latencyMs = result.latencyMs
            $0.stagedURL = nil
        }
        let cutout = result.processed
        Task { await self.stageResult(jobID: jobID, image: cutout) }
    }

    /// Strokes from earlier Applies plus the new ones (either side may be nil).
    static func union(_ a: [Bool]?, _ b: [Bool]?) -> [Bool]? {
        switch (a, b) {
        case (nil, nil): return nil
        case let (x?, nil), let (nil, x?): return x
        case let (x?, y?): return zip(x, y).map { $0 || $1 }
        }
    }

    // MARK: - Off-main work with isolated callbacks

    private func generateThumbnail(id: UUID, source: CGImage) async {
        let thumb = await Task.detached(priority: .utility) {
            ImageUtilities.resized(source, maxPx: ImageUtilities.thumbnailDimension).image
        }.value
        patch(id) { $0.thumbnail = thumb }
    }

    private func stageResult(jobID: UUID, image: CGImage) async {
        let url = await Task.detached(priority: .utility) {
            ExportService.writeStaged(image: image, jobID: jobID)
        }.value
        patch(jobID) { $0.stagedURL = url }
    }

    // MARK: - Helpers

    private func job(_ id: UUID) -> Job? {
        jobs.first { $0.id == id }
    }

    private func patch(_ id: UUID, _ mutate: (inout Job) -> Void) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[idx])
    }
}

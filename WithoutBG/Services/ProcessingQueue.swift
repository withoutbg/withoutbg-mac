import CoreGraphics
import Observation
import SwiftUI

/// Sequential, single-worker processing queue. Mirrors web `useProcessingQueue`.
///
/// The processor is injected (`any BackgroundRemovalProcessor`); the default is
/// `MockProcessor()`. Swapping to `CoreMLProcessor()` is the only change needed
/// when the model ships.
@MainActor
@Observable
final class ProcessingQueue {
    static let maxBatch = 20

    private(set) var jobs: [Job] = []
    private(set) var completedCount = 0

    private let processor: any BackgroundRemovalProcessor
    private var isWorking = false

    init(processor: any BackgroundRemovalProcessor = MockProcessor()) {
        self.processor = processor
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

        // Resize off the main thread before running inference, then free the
        // full-resolution original so the session doesn't accumulate it for
        // every image in a 20-card batch.
        let (prepared, aspect) = await Task.detached(priority: .userInitiated) {
            ImageUtilities.resized(before)
        }.value

        patch(jobID) {
            $0.preparedImage = prepared
            $0.aspectRatio = aspect
            $0.beforeImage = nil   // free the full-res original
        }

        do {
            let result = try await processor.process(preparedImage: prepared)
            patch(jobID) {
                $0.alphaMatte = result.alphaMatte
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

import AppKit
import CoreGraphics
import UniformTypeIdentifiers

/// Background choice applied at export time.
enum ExportBackground: String, CaseIterable, Identifiable {
    case transparent
    case white
    case black

    var id: String { rawValue }

    var label: String {
        switch self {
        case .transparent: return "Transparent"
        case .white: return "White"
        case .black: return "Black"
        }
    }

    /// Solid fill color, or nil to keep transparency.
    var cgColor: CGColor? {
        switch self {
        case .transparent: return nil
        case .white: return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        case .black: return CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        }
    }
}

/// File-system export — single PNG via `NSSavePanel`, batch ZIP via
/// `NSFileCoordinator`. Sandbox-friendly: the user grants access by picking the
/// destination in the panel.
@MainActor
enum ExportService {

    // MARK: - Pre-staging (off-main safe)

    /// Write a transparent PNG to the shared drag-staging directory. Safe to
    /// call from any thread. Returns the file URL on success.
    nonisolated static func writeStaged(image: CGImage, jobID: UUID) -> URL? {
        guard let data = ImageUtilities.pngData(from: image) else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wbg-drag", isDirectory: true)
            .appendingPathComponent(jobID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Use a stable name per job so repeated calls are idempotent.
        let url = dir.appendingPathComponent("result.png")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Drag out (Finder / other apps)

    /// Return a real PNG on disk for the job, reusing the pre-staged file when
    /// available (no re-encoding). Falls back to encoding on the spot.
    static func stagedFileURL(
        for job: Job,
        background: ExportBackground = .transparent
    ) -> URL? {
        // Reuse pre-staged transparent file for the common transparent case.
        if background == .transparent, let url = job.stagedURL {
            return url
        }
        guard let cutout = job.processedImage,
              let composed = ImageUtilities.composited(cutout, over: background.cgColor),
              let data = ImageUtilities.pngData(from: composed)
        else { return nil }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wbg-drag", isDirectory: true)
            .appendingPathComponent(job.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(job.exportFileName)
        do {
            try data.write(to: url)
        } catch {
            return nil
        }
        return url
    }

    // MARK: - Clipboard

    /// Copy one or more results to the general pasteboard as PNG(s).
    /// Reads from the pre-staged file when available to avoid re-encoding.
    static func copyToPasteboard(_ jobs: [Job], background: ExportBackground = .transparent) {
        let items: [NSPasteboardItem] = jobs.compactMap { job in
            let data: Data?
            if background == .transparent, let url = job.stagedURL {
                data = try? Data(contentsOf: url)
            } else {
                guard let cutout = job.processedImage,
                      let composed = ImageUtilities.composited(cutout, over: background.cgColor)
                else { return nil }
                data = ImageUtilities.pngData(from: composed)
            }
            guard let pngData = data else { return nil }
            let item = NSPasteboardItem()
            item.setData(pngData, forType: .png)
            return item
        }
        guard !items.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }

    // MARK: - Single image

    static func saveSingle(
        job: Job,
        background: ExportBackground,
        defaultDirectory: URL? = nil,
        revealInFinder: Bool = false
    ) {
        guard let cutout = job.processedImage,
              let composed = ImageUtilities.composited(cutout, over: background.cgColor),
              let data = ImageUtilities.pngData(from: composed)
        else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = job.exportFileName
        panel.canCreateDirectories = true
        if let defaultDirectory { panel.directoryURL = defaultDirectory }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            if revealInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } catch {
            presentError(error)
        }
    }

    // MARK: - Batch ZIP

    /// Export all done jobs into `withoutbg-results.zip` containing a
    /// `withoutbg-results/` folder.
    static func saveAll(
        jobs: [Job],
        background: ExportBackground = .transparent,
        defaultDirectory: URL? = nil,
        revealInFinder: Bool = false
    ) {
        let doneJobs = jobs.filter { $0.status == .done && $0.processedImage != nil }
        guard !doneJobs.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "withoutbg-results.zip"
        panel.canCreateDirectories = true
        if let defaultDirectory { panel.directoryURL = defaultDirectory }

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try writeZip(doneJobs: doneJobs, background: background, to: destination)
            if revealInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        } catch {
            presentError(error)
        }
    }

    private static func writeZip(
        doneJobs: [Job],
        background: ExportBackground,
        to destination: URL
    ) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("wbg-\(UUID().uuidString)", isDirectory: true)
        let folder = staging.appendingPathComponent("withoutbg-results", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        for job in doneJobs {
            let data: Data?
            if background == .transparent, let url = job.stagedURL {
                data = try? Data(contentsOf: url)
            } else {
                guard let cutout = job.processedImage,
                      let composed = ImageUtilities.composited(cutout, over: background.cgColor)
                else { continue }
                data = ImageUtilities.pngData(from: composed)
            }
            guard let pngData = data else { continue }
            try pngData.write(to: folder.appendingPathComponent(job.exportFileName))
        }

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }

        // NSFileCoordinator's .forUploading option produces a zip of the folder.
        var coordError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: folder,
            options: .forUploading,
            error: &coordError
        ) { zippedURL in
            do {
                try fm.copyItem(at: zippedURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordError { throw coordError }
        if let copyError { throw copyError }
    }

    // MARK: - Errors

    private static func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Export failed"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

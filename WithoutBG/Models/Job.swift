import CoreGraphics
import Foundation

/// A single image in the processing queue. Mirrors web `Job`.
struct Job: Identifiable {
    let id: UUID
    /// Display name (with extension). Mutable so cards can be renamed in place.
    var fileName: String
    var status: JobStatus

    /// Full-resolution original, held until processing completes, then nilled.
    var beforeImage: CGImage?
    var preparedImage: CGImage?
    /// Transparent PNG cutout, set when done.
    var processedImage: CGImage?
    /// Grayscale matte produced by the processor.
    var alphaMatte: CGImage?
    /// Small cached thumbnail (~340px longest side) for grid display.
    var thumbnail: CGImage?

    var latencyMs: Int?
    var aspectRatio: CGFloat?
    var error: String?
    /// Pre-staged transparent PNG on disk, ready for drag-out and copy.
    var stagedURL: URL?

    init(
        id: UUID = UUID(),
        fileName: String,
        status: JobStatus = .queued,
        beforeImage: CGImage
    ) {
        self.id = id
        self.fileName = fileName
        self.status = status
        self.beforeImage = beforeImage
    }

    /// Basename without extension, used to build export file names.
    var baseName: String {
        (fileName as NSString).deletingPathExtension
    }

    /// Original file extension (without the dot), e.g. `webp`.
    var fileExtension: String {
        (fileName as NSString).pathExtension
    }

    /// `{basename}-withoutbg.png`
    var exportFileName: String {
        "\(baseName)-withoutbg.png"
    }
}

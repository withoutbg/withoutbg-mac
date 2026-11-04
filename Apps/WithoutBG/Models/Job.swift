import CoreGraphics
import Foundation
import WithoutBGCore

/// A single image in the processing queue. Mirrors web `Job`.
struct Job: Identifiable {
    let id: UUID
    /// Display name (with extension). Mutable so cards can be renamed in place.
    var fileName: String
    var status: JobStatus

    /// Full-resolution original; kept after processing so Smart brush can edit the result.
    var beforeImage: CGImage?
    var preparedImage: CGImage?
    /// Transparent PNG cutout, set when done.
    var processedImage: CGImage?
    /// Grayscale matte produced by the processor.
    var alphaMatte: CGImage?
    /// Smart brush: depth etc. from the first edit, so later strokes skip the
    /// router and coarse graphs. In memory only; reset when the job is reprocessed.
    var editContext: EditContext?
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

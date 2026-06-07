import AppKit
import CoreGraphics
import UniformTypeIdentifiers

/// Turns user input (file URLs, pasteboard, drag-and-drop) into decoded
/// `(fileName, CGImage)` pairs. Filters to supported image types only.
enum ImageIngestion {
    /// Accepted input types: JPEG, PNG, WebP, HEIC (plus generic images).
    static let supportedTypes: [UTType] = [.jpeg, .png, .webP, .heic, .heif, .image]

    static func isSupported(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .image)
    }

    // MARK: - From file URLs

    static func load(from urls: [URL]) -> [(fileName: String, image: CGImage)] {
        urls.compactMap { url in
            guard isSupported(url) else { return nil }
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            guard let image = ImageUtilities.cgImage(from: url) else { return nil }
            return (url.lastPathComponent, image)
        }
    }

    // MARK: - From pasteboard

    static func loadFromPasteboard(
        _ pasteboard: NSPasteboard = .general
    ) -> [(fileName: String, image: CGImage)] {
        // 1. File URLs on the pasteboard.
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            let loaded = load(from: urls)
            if !loaded.isEmpty { return loaded }
        }

        // 2. Raw image data (PNG / TIFF) — typically a screenshot or copied image.
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type),
               let image = ImageUtilities.cgImage(from: data) {
                return [("Pasted Image.png", image)]
            }
        }

        // 3. NSImage fallback.
        if let image = NSImage(pasteboard: pasteboard),
           let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return [("Pasted Image.png", cg)]
        }

        return []
    }
}

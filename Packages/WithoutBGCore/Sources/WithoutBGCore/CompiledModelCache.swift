import CoreML
import CryptoKit
import Foundation

/// Loads bundled models. Xcode app builds ship precompiled `.mlmodelc`s, loaded as is.
/// SwiftPM builds ship `.mlpackage`s; those are checksummed and compiled once, and the
/// compiled `.mlmodelc` is kept in Application Support so later launches skip both.
/// Entries are keyed by package checksum and OS build (Core ML output may change
/// across OS updates); stale entries for the same model are pruned.
struct CompiledModelCache {
    let directory: URL
    let computeUnits: MLComputeUnits

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("withoutBG/CompiledModels", isDirectory: true)
    }

    init(directory: URL = Self.defaultDirectory, computeUnits: MLComputeUnits = .all) {
        self.directory = directory
        self.computeUnits = computeUnits
    }

    func model(package: URL, sha256: String) throws -> MLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let stem = package.deletingPathExtension().lastPathComponent
        let fm = FileManager.default
        // Xcode app builds compile bundled packages to .mlmodelc at build time (covered
        // by the code signature); only SwiftPM builds ship the raw .mlpackage.
        let prebuilt = package.deletingPathExtension().appendingPathExtension("mlmodelc")
        if !fm.fileExists(atPath: package.path), fm.fileExists(atPath: prebuilt.path) {
            return try MLModel(contentsOf: prebuilt, configuration: configuration)
        }
        let cached = directory.appendingPathComponent("\(stem)-\(sha256)-\(Self.osBuild).mlmodelc")
        if fm.fileExists(atPath: cached.path) {
            if let model = try? MLModel(contentsOf: cached, configuration: configuration) {
                return model
            }
            try? fm.removeItem(at: cached)
        }

        // Verify the source package before Core ML compiles it.
        let digest = try Self.packageDigest(package)
        guard digest == sha256 else {
            throw ProcessorError.processingFailed(
                "Model checksum mismatch: \(package.lastPathComponent), expected \(sha256), got \(digest)"
            )
        }
        let compiled = try MLModel.compileModel(at: package)
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let partial = directory.appendingPathComponent(UUID().uuidString + ".partial")
            try fm.moveItem(at: compiled, to: partial)
            try? fm.removeItem(at: cached)
            try fm.moveItem(at: partial, to: cached)
            prune(stem: stem, keeping: cached)
            return try MLModel(contentsOf: cached, configuration: configuration)
        } catch {
            // An unwritable cache must not block inference.
            let source = fm.fileExists(atPath: compiled.path) ? compiled : cached
            return try MLModel(contentsOf: source, configuration: configuration)
        }
    }

    private func prune(stem: String, keeping kept: URL) {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.lastPathComponent != kept.lastPathComponent {
            let name = entry.lastPathComponent
            if name.hasSuffix(".partial") || (name.hasPrefix(stem + "-") && name.hasSuffix(".mlmodelc")) {
                try? fm.removeItem(at: entry)
            }
        }
    }

    /// SHA256 over each regular file's relative path and bytes, in sorted path order
    /// (same as the exporter's `sha256(path)` for directories).
    static func packageDigest(_ package: URL) throws -> String {
        let root = package.resolvingSymlinksInPath()
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        let files = (enumerator?.allObjects as? [URL] ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.map { file in
            (file, file.resolvingSymlinksInPath().pathComponents.dropFirst(root.pathComponents.count)
                .joined(separator: "/"))
        }.sorted { $0.1 < $1.1 }
        var hasher = SHA256()
        for (file, relative) in files {
            hasher.update(data: Data(relative.utf8))
            hasher.update(data: try Data(contentsOf: file, options: .mappedIfSafe))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static let osBuild: String = {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        let build = String(cString: buffer)
        return build.isEmpty ? "unknown" : build
    }()
}

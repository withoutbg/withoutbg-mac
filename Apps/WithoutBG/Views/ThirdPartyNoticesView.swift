import AppKit
import SwiftUI

/// Scrollable third-party notices sheet (bundled `THIRD_PARTY_NOTICES.txt`).
struct ThirdPartyNoticesView: View {
    @Environment(\.dismiss) private var dismiss

    private let text: String = ThirdPartyNoticesLoader.load()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Third-Party Notices")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Open in TextEdit") { ThirdPartyNoticesLoader.openInTextEditor() }
                    .font(.system(size: 12))
                Button("Done") { dismiss() }
                    .font(.system(size: 12, weight: .medium))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(WBGColors.chrome)

            Divider()

            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WBGColors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(WBGColors.page)
        }
        .frame(width: 520, height: 440)
    }
}

enum ThirdPartyNoticesLoader {
    private static let resourceName = "THIRD_PARTY_NOTICES"
    private static let resourceExtension = "txt"

    static func load() -> String {
        guard let url = bundleURL,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else {
            return "Third-party notices could not be loaded from the app bundle."
        }
        return text
    }

    static func openInTextEditor() {
        guard let source = bundleURL else { return }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("withoutBG-THIRD_PARTY_NOTICES.txt")

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            NSWorkspace.shared.open(destination)
        } catch {
            // Fall back to showing the bundled copy if temp copy fails.
            NSWorkspace.shared.open(source)
        }
    }

    private static var bundleURL: URL? {
        Bundle.main.url(forResource: resourceName, withExtension: resourceExtension)
    }
}

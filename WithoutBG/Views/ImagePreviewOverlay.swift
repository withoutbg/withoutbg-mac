import AppKit
import SwiftUI

/// Quick Look-style full-window preview, modeled after Photos / Finder. Shows
/// the focused job large over a dimmed backdrop, with on-screen previous/next
/// controls and a close button.
///
/// Keyboard navigation (`←` / `→` to move, `Space` / `Esc` to close) is routed
/// by the focused grid in `QueueGridView.handleKey`; this view provides the
/// visuals and the click-to-navigate controls.
struct ImagePreviewOverlay: View {
    let model: AppModel
    let job: Job

    /// The set of jobs the preview can page through (multi-selection, or the
    /// whole queue when zero or one item is selected).
    private var jobs: [Job] { model.previewableJobs }
    private var index: Int { jobs.firstIndex { $0.id == job.id } ?? 0 }
    private var hasMultiple: Bool { jobs.count > 1 }
    private var canGoPrevious: Bool { index > 0 }
    private var canGoNext: Bool { index < jobs.count - 1 }

    private var displayImage: CGImage? {
        if job.status == .done, let processed = job.processedImage { return processed }
        return job.preparedImage ?? job.thumbnail ?? job.beforeImage
    }

    private var aspectRatio: CGFloat {
        if let ar = job.aspectRatio { return ar }
        guard let img = displayImage else { return 1 }
        return CGFloat(img.width) / CGFloat(img.height)
    }

    var body: some View {
        ZStack {
            backdrop
            stage
            previousControl
            nextControl
            topBar
            caption
        }
        .transition(.opacity)
    }

    // MARK: - Backdrop

    /// Dimmed background. Clicking empty space dismisses, matching Quick Look.
    private var backdrop: some View {
        Rectangle()
            .fill(.black.opacity(0.9))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { model.closePreview() }
    }

    // MARK: - Image stage

    private var stage: some View {
        ZStack {
            if job.status == .done {
                CheckerboardBackground()
            }
            if let img = displayImage {
                Image(decorative: img, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
        // Swallow taps on the image so they don't reach the dismiss backdrop.
        .contentShape(Rectangle())
        .onTapGesture {}
        .padding(.horizontal, 96)
        .padding(.top, 64)
        .padding(.bottom, 88)
    }

    // MARK: - Navigation controls

    @ViewBuilder
    private var previousControl: some View {
        if hasMultiple {
            HStack {
                NavButton(systemName: "chevron.left", enabled: canGoPrevious) {
                    model.movePreview(by: -1)
                }
                .padding(.leading, 24)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var nextControl: some View {
        if hasMultiple {
            HStack {
                Spacer()
                NavButton(systemName: "chevron.right", enabled: canGoNext) {
                    model.movePreview(by: 1)
                }
                .padding(.trailing, 24)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: model.closePreview) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close preview (Space)")
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Spacer()
        }
    }

    // MARK: - Caption

    private var caption: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Text(job.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if hasMultiple {
                    Text("\(index + 1) of \(jobs.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.5), in: Capsule())
            .padding(.bottom, 28)
        }
    }
}

/// Circular translucent paging button used either side of the preview stage.
private struct NavButton: View {
    let systemName: String
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(hovering ? 0.22 : 0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }
}

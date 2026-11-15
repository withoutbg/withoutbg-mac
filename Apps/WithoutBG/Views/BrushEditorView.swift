import AppKit
import CoreGraphics
import SwiftUI
import WithoutBGCore

/// Smart brush editor: paint green over what went missing and red over what should
/// go, then Apply. Strokes are kept in image pixels and rasterised to masks on Apply.
struct BrushEditorView: View {
    enum Mode: String { case keep, remove }

    struct Stroke: Equatable {
        var mode: Mode
        var radius: CGFloat
        var points: [CGPoint]
    }

    /// Brush radius as a fraction of the image's long side.
    static let radiusRange: ClosedRange<Double> = 0.001...0.08

    /// Opening size of the Smart Brush window: most of the screen, so the image is
    /// large on high-resolution displays. Resizing is remembered by the system.
    static var defaultWindowSize: CGSize {
        guard let frame = NSScreen.main?.visibleFrame else { return CGSize(width: 1200, height: 900) }
        return CGSize(width: max(800, frame.width * 0.85), height: max(600, frame.height * 0.9))
    }

    let model: AppModel
    let jobID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .remove
    @State private var radiusFraction: Double = 0.02
    /// Opacity of the original photo behind the cutout, adjustable while painting.
    @AppStorage("smartBrushBackgroundOpacity") private var backgroundOpacity: Double = 0.25
    @State private var strokes: [Stroke] = []
    @State private var busy = false
    @State private var error: String?
    @State private var zoom = BrushCanvasController()

    private var job: Job? { model.queue.jobs.first { $0.id == jobID } }

    var body: some View {
        VStack(spacing: 0) {
            if let job, let original = job.beforeImage, let cutout = job.processedImage {
                canvas(original: original, cutout: cutout)
            } else {
                Text("This image can no longer be edited.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            controls
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(minWidth: 720, minHeight: 520)
        .navigationTitle(job.map { "Smart Brush – \($0.fileName)" } ?? "Smart Brush")
        .focusedSceneValue(\.brushEditor, BrushEditorActions(
            canUndo: !strokes.isEmpty && !busy,
            undo: { _ = strokes.popLast() }))
    }

    // MARK: - Canvas

    private func canvas(original: CGImage, cutout: CGImage) -> some View {
        let longSide = CGFloat(max(original.width, original.height))
        return BrushCanvasView(
            original: original,
            cutout: cutout,
            strokes: strokes,
            backgroundOpacity: backgroundOpacity,
            mode: mode,
            radius: brushRadius(longSide: longSide),
            enabled: !busy,
            controller: zoom,
            onStroke: { strokes.append($0) },
            onBrushSizeStep: { step in
                let factor = step > 0 ? 1.25 : 0.8
                radiusFraction = min(max(radiusFraction * factor, Self.radiusRange.lowerBound),
                                     Self.radiusRange.upperBound)
            })
        .overlay {
            if busy {
                ZStack {
                    Color.black.opacity(0.2)
                    ProgressView().controlSize(.large)
                }
            }
        }
        .background(WBGColors.page)
    }

    private func brushRadius(longSide: CGFloat) -> CGFloat {
        max(1, CGFloat(radiusFraction) * longSide)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                brushTools
                Spacer(minLength: 12)
                zoomTools
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paint Keep over parts that went missing, Remove over parts that should go. "
                         + "Pinch or ⌘-scroll to zoom, Space-drag to pan, [ ] to resize the brush.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Link("How to paint strokes that work →", destination: ProductLinks.shared.smartBrush)
                        .font(.system(size: 11))
                        .help("Best practices and example strokes on withoutbg.com")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let error {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
                }
                if job?.engine == .pro {
                    Text("Pro: 1 credit per Apply")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(busy)
                    .fixedSize()
                Button("Apply") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(strokes.isEmpty || busy)
                    .fixedSize()
            }
        }
    }

    private var brushTools: some View {
        HStack(spacing: 10) {
            Picker("Brush", selection: $mode) {
                Label("Keep", systemImage: "plus.circle.fill").tag(Mode.keep)
                Label("Remove", systemImage: "minus.circle.fill").tag(Mode.remove)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .labelsHidden()

            HStack(spacing: 4) {
                Image(systemName: "circle.fill").font(.system(size: 6))
                // Square-root scale: more travel for the small sizes used when zoomed in.
                Slider(value: Binding(
                    get: { radiusFraction.squareRoot() },
                    set: { radiusFraction = $0 * $0 }
                ), in: Self.radiusRange.lowerBound.squareRoot()...Self.radiusRange.upperBound.squareRoot())
                .frame(width: 140)
                Image(systemName: "circle.fill").font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
            .help("Brush size ([ and ])")

            HStack(spacing: 4) {
                Image(systemName: "photo").font(.system(size: 10))
                Slider(value: $backgroundOpacity, in: 0...1).frame(width: 90)
                Image(systemName: "photo.fill").font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
            .help("Original photo opacity behind the cutout")

            Button { _ = strokes.popLast() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(strokes.isEmpty || busy)
                .help("Undo stroke (⌘Z)")
            Button { strokes.removeAll() } label: { Image(systemName: "eraser") }
                .disabled(strokes.isEmpty || busy)
                .help("Clear strokes")
        }
    }

    private var zoomTools: some View {
        HStack(spacing: 6) {
            Button { zoom.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                .keyboardShortcut("-", modifiers: .command)
                .help("Zoom out (⌘−)")
            Text("\(Int((zoom.magnification * 100).rounded()))%")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 44)
            Button { zoom.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                .keyboardShortcut("=", modifiers: .command)
                .help("Zoom in (⌘+)")
            Button("Fit") { zoom.zoomToFit() }
                .keyboardShortcut("0", modifiers: .command)
                .help("Fit to window (⌘0)")
                .fixedSize()
            Button("100%") { zoom.zoomToActualSize() }
                .keyboardShortcut("1", modifiers: .command)
                .help("Actual size (⌘1)")
                .fixedSize()
        }
    }

    // MARK: - Apply

    private func apply() {
        guard let job, let original = job.beforeImage else { return }
        let (w, h) = (original.width, original.height)
        let keep = Self.rasterize(strokes.filter { $0.mode == .keep }, width: w, height: h)
        let remove = Self.rasterize(strokes.filter { $0.mode == .remove }, width: w, height: h)
        busy = true
        error = nil
        Task {
            do {
                try await model.queue.edit(jobID, keep: keep, remove: remove)
                strokes.removeAll()
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    /// Strokes → row-major marks (nil when there are none), drawn with round caps.
    static func rasterize(_ strokes: [Stroke], width w: Int, height h: Int) -> [Bool]? {
        guard !strokes.isEmpty else { return nil }
        var buffer = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        // Image coordinates have y down; flip the context to match.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in strokes {
            ctx.setLineWidth(stroke.radius * 2)
            guard let first = stroke.points.first else { continue }
            ctx.beginPath()
            ctx.move(to: first)
            for p in stroke.points.dropFirst() { ctx.addLine(to: p) }
            if stroke.points.count == 1 { ctx.addLine(to: first) }
            ctx.strokePath()
        }
        let marks = buffer.map { $0 >= 128 }
        return marks.contains(true) ? marks : nil
    }
}

/// Lets the app menu's Undo act on Smart Brush strokes while that window is key.
struct BrushEditorActions {
    let canUndo: Bool
    let undo: () -> Void
}

private struct BrushEditorActionsKey: FocusedValueKey {
    typealias Value = BrushEditorActions
}

extension FocusedValues {
    var brushEditor: BrushEditorActions? {
        get { self[BrushEditorActionsKey.self] }
        set { self[BrushEditorActionsKey.self] = newValue }
    }
}

/// Content of the single Smart Brush window; shows the job in `AppModel.brushJobID`.
struct SmartBrushWindow: View {
    static let id = "smart-brush"

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let id = model.brushJobID {
                BrushEditorView(model: model, jobID: id).id(id)
            } else {
                Color.clear.frame(minWidth: 720, minHeight: 520)
            }
        }
        .onAppear {
            // Restored at launch with nothing to edit.
            if model.brushJobID == nil { dismiss() }
        }
        .onDisappear { model.brushJobID = nil }
    }
}

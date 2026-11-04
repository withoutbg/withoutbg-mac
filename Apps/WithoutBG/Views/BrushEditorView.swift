import CoreGraphics
import SwiftUI
import WithoutBGCore

/// Keep / Remove editor: paint green over what went missing and red over what should
/// go, then Apply. Strokes are kept in image pixels and rasterised to masks on Apply.
struct BrushEditorView: View {
    enum Mode: String { case keep, remove }

    struct Stroke {
        var mode: Mode
        var radius: CGFloat
        var points: [CGPoint]
    }

    let model: AppModel
    let jobID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .remove
    @State private var radiusFraction: Double = 0.02
    @State private var strokes: [Stroke] = []
    @State private var busy = false
    @State private var error: String?

    private var job: Job? { model.queue.jobs.first { $0.id == jobID } }

    var body: some View {
        VStack(spacing: 12) {
            header
            if let job, let original = job.beforeImage, let cutout = job.processedImage {
                canvas(original: original, cutout: cutout)
            } else {
                Text("This image can no longer be edited.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            controls
            if let error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(minWidth: 640, idealWidth: 860, minHeight: 520, idealHeight: 720)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fix with Brush").font(.system(size: 15, weight: .semibold))
                Text("Paint Keep over parts that went missing and Remove over parts that should go. "
                     + "One stroke on an object is enough; the rest of the image stays as it was.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Canvas

    private func canvas(original: CGImage, cutout: CGImage) -> some View {
        let size = CGSize(width: original.width, height: original.height)
        return GeometryReader { geo in
            let scale = min(geo.size.width / size.width, geo.size.height / size.height)
            let shown = CGSize(width: size.width * scale, height: size.height * scale)
            ZStack {
                CheckerboardBackground()
                Image(decorative: original, scale: 1).resizable().opacity(0.25)
                Image(decorative: cutout, scale: 1).resizable()
                Canvas { ctx, _ in
                    for stroke in strokes {
                        var path = Path()
                        let pts = stroke.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
                        if let first = pts.first {
                            path.move(to: first)
                            for p in pts.dropFirst() { path.addLine(to: p) }
                            if pts.count == 1 { path.addLine(to: first) }
                        }
                        ctx.stroke(path, with: .color(color(stroke.mode).opacity(0.55)),
                                   style: StrokeStyle(lineWidth: stroke.radius * 2 * scale,
                                                      lineCap: .round, lineJoin: .round))
                    }
                }
                if busy {
                    Color.black.opacity(0.2)
                    ProgressView().controlSize(.large)
                }
            }
            .frame(width: shown.width, height: shown.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !busy else { return }
                        let p = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                        if strokeOpen, !strokes.isEmpty {
                            strokes[strokes.count - 1].points.append(p)
                        } else {
                            strokeOpen = true
                            let radius = max(2, CGFloat(radiusFraction) * max(size.width, size.height))
                            strokes.append(Stroke(mode: mode, radius: radius, points: [p]))
                        }
                    }
                    .onEnded { _ in strokeOpen = false }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @State private var strokeOpen = false

    private func color(_ mode: Mode) -> Color { mode == .keep ? .green : .red }

    // MARK: - Controls

    private var controls: some View {
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
                Slider(value: $radiusFraction, in: 0.005...0.08).frame(width: 120)
                Image(systemName: "circle.fill").font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
            .help("Brush size")

            Button { _ = strokes.popLast() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(strokes.isEmpty || busy)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo stroke (⌘Z)")
            Button { strokes.removeAll() } label: { Image(systemName: "eraser") }
                .disabled(strokes.isEmpty || busy)
                .help("Clear strokes")

            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(busy)
            Button("Apply") { apply() }
                .keyboardShortcut(.defaultAction)
                .disabled(strokes.isEmpty || busy)
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

import AppKit
import SwiftUI

/// Zoom state of the Smart Brush canvas, shared between the SwiftUI controls and
/// the AppKit scroll view.
@MainActor @Observable
final class BrushCanvasController {
    /// Current magnification (1 = one image pixel per point).
    fileprivate(set) var magnification: CGFloat = 1

    @ObservationIgnored fileprivate weak var scrollView: BrushScrollView?

    func zoomIn() { scrollView?.zoom(by: 1.5) }
    func zoomOut() { scrollView?.zoom(by: 1 / 1.5) }
    func zoomToFit() { scrollView?.fitToWindow() }
    func zoomToActualSize() { scrollView?.zoom(to: 1) }
}

/// Smart Brush canvas: photo (faded), cutout and strokes in an `NSScrollView` with
/// magnification. Pinch or ⌘-scroll zooms around the pointer, scrolling pans, Space-drag
/// pans, `[` / `]` change the brush size. Coordinates are image pixels (y down).
struct BrushCanvasView: NSViewRepresentable {
    let original: CGImage
    let cutout: CGImage
    let strokes: [BrushEditorView.Stroke]
    let backgroundOpacity: Double
    let mode: BrushEditorView.Mode
    /// Brush radius in image pixels.
    let radius: CGFloat
    let enabled: Bool
    let controller: BrushCanvasController
    let onStroke: (BrushEditorView.Stroke) -> Void
    /// `+1` for `]`, `-1` for `[`.
    let onBrushSizeStep: (Int) -> Void

    func makeNSView(context: Context) -> BrushScrollView {
        let scroll = BrushScrollView(original: original, cutout: cutout)
        scroll.onMagnificationChange = { [weak controller] m in controller?.magnification = m }
        controller.scrollView = scroll
        update(scroll)
        return scroll
    }

    func updateNSView(_ scroll: BrushScrollView, context: Context) {
        controller.scrollView = scroll
        scroll.setImages(original: original, cutout: cutout)
        update(scroll)
    }

    private func update(_ scroll: BrushScrollView) {
        let paint = scroll.canvas.strokeView
        scroll.canvas.backgroundOpacity = backgroundOpacity
        paint.strokes = strokes
        paint.mode = mode
        paint.radius = radius
        paint.enabled = enabled
        paint.onStroke = onStroke
        paint.onBrushSizeStep = onBrushSizeStep
    }
}

// MARK: - Scroll view

final class BrushScrollView: NSScrollView {
    let canvas: BrushDocumentView
    var onMagnificationChange: ((CGFloat) -> Void)?

    /// Track the window size until the user zooms; Fit turns it back on.
    private var fitsWindow = true
    private var reportedMagnification: CGFloat = 0

    init(original: CGImage, cutout: CGImage) {
        canvas = BrushDocumentView(original: original, cutout: cutout)
        super.init(frame: .zero)
        contentView = CenteringClipView()
        contentView.drawsBackground = false
        contentView.postsBoundsChangedNotifications = true
        documentView = canvas
        drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        allowsMagnification = true
        maxMagnification = 32
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipBoundsChanged),
            name: NSView.boundsDidChangeNotification, object: contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setImages(original: CGImage, cutout: CGImage) {
        canvas.setImages(original: original, cutout: cutout)
    }

    /// Magnification at which the whole image fits the visible area.
    private var fitMagnification: CGFloat {
        let avail = contentView.frame.size
        let size = canvas.frame.size
        guard avail.width > 0, avail.height > 0, size.width > 0, size.height > 0 else { return 1 }
        return min(avail.width / size.width, avail.height / size.height)
    }

    override func layout() {
        super.layout()
        let fit = fitMagnification
        minMagnification = min(fit * 0.5, 1)
        if fitsWindow, abs(magnification - fit) > 0.0001 {
            magnification = fit
        }
        reportMagnification()
    }

    func fitToWindow() {
        fitsWindow = true
        magnification = fitMagnification
        reportMagnification()
    }

    func zoom(by factor: CGFloat) {
        zoom(to: magnification * factor)
    }

    /// Zoom keeping `anchor` (document coordinates; default: visible centre) under the same
    /// on-screen spot.
    func zoom(to target: CGFloat, anchor: CGPoint? = nil) {
        fitsWindow = false
        let clip = contentView
        let old = magnification
        let new = min(max(target, minMagnification), maxMagnification)
        guard abs(new - old) > 0.0001 else { return }
        let p = anchor ?? CGPoint(x: clip.bounds.midX, y: clip.bounds.midY)
        let offset = CGPoint(x: (p.x - clip.bounds.minX) * old, y: (p.y - clip.bounds.minY) * old)
        magnification = new
        var bounds = clip.bounds
        bounds.origin = CGPoint(x: p.x - offset.x / new, y: p.y - offset.y / new)
        clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
        reflectScrolledClipView(clip)
        reportMagnification()
    }

    override func magnify(with event: NSEvent) {
        fitsWindow = false
        super.magnify(with: event)
    }

    override func smartMagnify(with event: NSEvent) {
        // Two-finger double tap: toggle between Fit and 2× around the pointer.
        if fitsWindow {
            zoom(to: max(fitMagnification * 2, 1), anchor: canvas.convert(event.locationInWindow, from: nil))
        } else {
            fitToWindow()
        }
    }

    /// ⌘- or ⌥-scroll zooms around the pointer (mouse-wheel users have no pinch).
    override func scrollWheel(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.option) else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
        guard delta != 0 else { return }
        zoom(to: magnification * exp(delta), anchor: canvas.convert(event.locationInWindow, from: nil))
    }

    /// Pan by a window-space delta (Space-drag).
    func pan(by delta: CGSize) {
        let clip = contentView
        var bounds = clip.bounds
        bounds.origin.x -= delta.width / magnification
        bounds.origin.y -= delta.height / magnification
        clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
        reflectScrolledClipView(clip)
    }

    @objc private func clipBoundsChanged() {
        reportMagnification()
    }

    private func reportMagnification() {
        guard abs(magnification - reportedMagnification) > 0.0001 else { return }
        reportedMagnification = magnification
        canvas.magnificationChanged()
        onMagnificationChange?(magnification)
    }
}

/// Keeps the image centred when it is smaller than the visible area.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        if rect.width > doc.frame.width { rect.origin.x = (doc.frame.width - rect.width) / 2 }
        if rect.height > doc.frame.height { rect.origin.y = (doc.frame.height - rect.height) / 2 }
        return rect
    }
}

// MARK: - Document view

/// Image-sized document: checkerboard, faded photo, cutout, then the stroke layer.
final class BrushDocumentView: NSView {
    let strokeView = BrushStrokeView()
    private let originalView = ImageLayerView()
    private let cutoutView = ImageLayerView()

    var backgroundOpacity: Double = 0.25 {
        didSet { originalView.alphaValue = backgroundOpacity }
    }

    init(original: CGImage, cutout: CGImage) {
        super.init(frame: CGRect(x: 0, y: 0, width: original.width, height: original.height))
        wantsLayer = true
        originalView.alphaValue = 0.25
        for view in [originalView, cutoutView, strokeView] as [NSView] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        setImages(original: original, cutout: cutout)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func setImages(original: CGImage, cutout: CGImage) {
        let size = CGSize(width: original.width, height: original.height)
        if frame.size != size { setFrameSize(size) }
        originalView.image = original
        cutoutView.image = cutout
    }

    func magnificationChanged() {
        needsDisplay = true
        strokeView.needsDisplay = true
    }

    /// Checker squares stay 8 pt on screen at any zoom.
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let mag = enclosingScrollView?.magnification ?? 1
        let side = 8 / max(mag, 0.0001)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(dirtyRect)
        let c0 = Int(floor(dirtyRect.minX / side)), c1 = Int(ceil(dirtyRect.maxX / side))
        let r0 = Int(floor(dirtyRect.minY / side)), r1 = Int(ceil(dirtyRect.maxY / side))
        var rects: [CGRect] = []
        rects.reserveCapacity(max(0, (c1 - c0) * (r1 - r0) / 2 + 1))
        for r in r0..<max(r0, r1) {
            for c in c0..<max(c0, c1) where (r + c) & 1 != 0 {
                rects.append(CGRect(x: CGFloat(c) * side, y: CGFloat(r) * side, width: side, height: side))
            }
        }
        ctx.setFillColor(gray: 0xE8 / 255, alpha: 1)
        ctx.fill(rects)
    }
}

/// A CGImage shown as layer contents (GPU-scaled; no redraw while painting).
private final class ImageLayerView: NSView {
    var image: CGImage? {
        didSet { if image !== oldValue { needsDisplay = true } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.minificationFilter = .trilinear
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Strokes

final class BrushStrokeView: NSView {
    var strokes: [BrushEditorView.Stroke] = [] {
        didSet { if strokes != oldValue { needsDisplay = true } }
    }
    var mode: BrushEditorView.Mode = .remove
    var radius: CGFloat = 10 {
        didSet { if radius != oldValue { invalidateHover(at: hover, radius: max(radius, oldValue)) } }
    }
    var enabled = true
    var onStroke: ((BrushEditorView.Stroke) -> Void)?
    var onBrushSizeStep: ((Int) -> Void)?

    private var live: BrushEditorView.Stroke?
    private var hover: CGPoint?
    private var spaceDown = false
    private var panLast: CGPoint?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var magnification: CGFloat { enclosingScrollView?.magnification ?? 1 }
    private var scroll: BrushScrollView? { enclosingScrollView as? BrushScrollView }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor() }

    private func updateCursor() {
        if panLast != nil { NSCursor.closedHand.set() }
        else if spaceDown { NSCursor.openHand.set() }
        else { NSCursor.crosshair.set() }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if spaceDown {
            panLast = event.locationInWindow
            updateCursor()
            return
        }
        guard enabled else { return }
        let p = convert(event.locationInWindow, from: nil)
        live = BrushEditorView.Stroke(mode: mode, radius: radius, points: [p])
        invalidate(from: p, to: p, radius: radius)
    }

    override func mouseDragged(with event: NSEvent) {
        if let last = panLast {
            let now = event.locationInWindow
            // Window y is up, the document is flipped (y down).
            scroll?.pan(by: CGSize(width: now.x - last.x, height: -(now.y - last.y)))
            panLast = now
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        moveHover(to: p)
        guard var stroke = live, let last = stroke.points.last else { return }
        stroke.points.append(p)
        live = stroke
        invalidate(from: last, to: p, radius: stroke.radius)
    }

    override func mouseUp(with event: NSEvent) {
        if panLast != nil {
            panLast = nil
            updateCursor()
            return
        }
        guard let stroke = live else { return }
        live = nil
        strokes.append(stroke)
        onStroke?(stroke)
    }

    override func mouseMoved(with event: NSEvent) {
        moveHover(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        moveHover(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        moveHover(to: nil)
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.subtracting([.capsLock, .numericPad, .function]).isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch event.charactersIgnoringModifiers {
        case " ":
            if !spaceDown {
                spaceDown = true
                updateCursor()
            }
        case "[": onBrushSizeStep?(-1)
        case "]": onBrushSizeStep?(1)
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            spaceDown = false
            updateCursor()
        } else {
            super.keyUp(with: event)
        }
    }

    // MARK: Drawing

    private func moveHover(to p: CGPoint?) {
        invalidateHover(at: hover, radius: radius)
        hover = p
        invalidateHover(at: hover, radius: radius)
    }

    private func invalidateHover(at p: CGPoint?, radius: CGFloat) {
        guard let p else { return }
        let pad = radius + 3 / magnification
        setNeedsDisplay(CGRect(x: p.x - pad, y: p.y - pad, width: pad * 2, height: pad * 2))
    }

    private func invalidate(from a: CGPoint, to b: CGPoint, radius: CGFloat) {
        let pad = radius + 2
        setNeedsDisplay(CGRect(x: min(a.x, b.x) - pad, y: min(a.y, b.y) - pad,
                               width: abs(a.x - b.x) + pad * 2, height: abs(a.y - b.y) + pad * 2))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in strokes + (live.map { [$0] } ?? []) {
            guard let first = stroke.points.first else { continue }
            let color: NSColor = stroke.mode == .keep ? .systemGreen : .systemRed
            ctx.setStrokeColor(color.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(stroke.radius * 2)
            ctx.beginPath()
            ctx.move(to: first)
            for p in stroke.points.dropFirst() { ctx.addLine(to: p) }
            if stroke.points.count == 1 { ctx.addLine(to: first) }
            ctx.strokePath()
        }
        // Brush outline under the pointer: dark ring inside a light ring, 1 pt each.
        if let hover, enabled, !spaceDown {
            let px = 1 / magnification
            let ring = CGRect(x: hover.x - radius, y: hover.y - radius, width: radius * 2, height: radius * 2)
            ctx.setLineWidth(px)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            ctx.strokeEllipse(in: ring.insetBy(dx: -px / 2, dy: -px / 2))
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.8).cgColor)
            ctx.strokeEllipse(in: ring.insetBy(dx: px / 2, dy: px / 2))
        }
    }
}

import AppKit

/// Shows batch progress on the Dock icon — a count badge plus a progress bar
/// drawn over the app icon, the way many native Mac apps surface long work.
@MainActor
final class DockProgress {
    static let shared = DockProgress()

    private var tileView: DockTileView?

    /// `progress` in 0...1, `badge` is the number of images still in flight.
    func update(progress: Double, badge: Int) {
        let tile = NSApp.dockTile
        if tileView == nil {
            let view = DockTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
            tileView = view
            tile.contentView = view
        }
        tileView?.progress = max(0, min(1, progress))
        tile.badgeLabel = badge > 0 ? "\(badge)" : nil
        tile.display()
    }

    func clear() {
        let tile = NSApp.dockTile
        tile.contentView = nil
        tileView = nil
        tile.badgeLabel = nil
        tile.display()
    }
}

/// Custom Dock tile content: the app icon with a rounded progress bar overlaid
/// near the bottom edge.
private final class DockTileView: NSView {
    var progress: Double = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(in: bounds)

        guard progress > 0, progress < 1 else { return }

        let barHeight = bounds.height * 0.13
        let inset = bounds.width * 0.12
        let track = NSRect(
            x: inset,
            y: bounds.height * 0.14,
            width: bounds.width - inset * 2,
            height: barHeight
        )
        let radius = barHeight / 2

        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        let fill = NSRect(
            x: track.minX,
            y: track.minY,
            width: max(barHeight, track.width * CGFloat(progress)),
            height: barHeight
        )
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}

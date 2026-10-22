import Foundation
import CoreGraphics

/// Which screen edge the shelf docks to.
public enum ShelfEdge: String, Codable, CaseIterable, Sendable {
    case right, left

    public var label: String { self == .right ? "Right" : "Left" }
}

/// Pure geometry for the shelf window and the "is a drag near the edge" check, kept out of
/// AppKit so it can be tested. All rects are in Cocoa global coordinates (origin bottom-left).
public enum ShelfGeometry {
    public static let width: CGFloat = 132
    public static let margin: CGFloat = 6
    public static let header: CGFloat = 30
    public static let tile: CGFloat = 96       // one item row, thumbnail + label
    public static let emptyHeight: CGFloat = 200
    /// With items, the shelf is always tall enough for this many rows, so it reads as a shelf
    /// rather than a single-item popup, then grows with content up to the cap and scrolls.
    public static let minVisibleRows = 5
    public static let maxHeightFraction: CGFloat = 0.8

    /// Height that fits `count` items, clamped to the screen.
    public static func height(itemCount count: Int, visible: CGRect) -> CGFloat {
        let rows = count == 0 ? 0 : max(count, minVisibleRows)
        let wanted = count == 0 ? emptyHeight : header + CGFloat(rows) * tile + 10
        return min(max(wanted, emptyHeight), visible.height * maxHeightFraction)
    }

    /// Window frame hugging `edge` of `visible`, vertically centered.
    public static func frame(edge: ShelfEdge, itemCount: Int, visible: CGRect) -> CGRect {
        let h = height(itemCount: itemCount, visible: visible)
        let x = edge == .right ? visible.maxX - width - margin : visible.minX + margin
        let y = visible.midY - h / 2
        return CGRect(x: x, y: y, width: width, height: h).integral
    }

    /// Same frame slid fully off-screen, used as the start/end of the show/hide animation.
    public static func hiddenFrame(edge: ShelfEdge, itemCount: Int, visible: CGRect) -> CGRect {
        var f = frame(edge: edge, itemCount: itemCount, visible: visible)
        f.origin.x = edge == .right ? visible.maxX + 2 : visible.minX - f.width - 2
        return f
    }

    /// True when the pointer is within `distance` points of the docking edge of `screen`.
    /// Uses the full screen frame, so it also fires over the Dock.
    public static func pointerNearEdge(_ p: CGPoint, edge: ShelfEdge, screen: CGRect, distance: CGFloat) -> Bool {
        guard p.y >= screen.minY, p.y <= screen.maxY else { return false }
        switch edge {
        case .right: return p.x >= screen.maxX - distance && p.x <= screen.maxX + 1
        case .left:  return p.x <= screen.minX + distance && p.x >= screen.minX - 1
        }
    }

    /// Classifies a stream of drag samples as "the user is actually dragging", filtering out
    /// clicks and tiny jitters: true once the pointer has moved `threshold` points from where
    /// the drag started.
    public static func isRealDrag(start: CGPoint, current: CGPoint, threshold: CGFloat = 6) -> Bool {
        hypot(current.x - start.x, current.y - start.y) >= threshold
    }
}

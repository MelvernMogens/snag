import Foundation

/// Finder-style multi-selection over the shelf's ordered item ids.
///
/// - plain click: select only that item, unless it is already part of a multi-selection, in
///   which case the selection is kept so the whole group can be dragged; it collapses to the
///   single item on mouse-up if no drag happened (`commitPlainClick`).
/// - ⌘-click: toggle one item.
/// - ⇧-click: select the range from the anchor to the clicked item.
public struct Selection: Equatable, Sendable {
    public enum Modifier: Sendable { case none, toggle, extend }

    public private(set) var ids: Set<UUID> = []
    public private(set) var anchor: UUID?
    /// Set when a plain click landed on an already-multi-selected item.
    public private(set) var pendingCollapse: UUID?

    public init() {}

    public func contains(_ id: UUID) -> Bool { ids.contains(id) }
    public var isEmpty: Bool { ids.isEmpty }
    public var count: Int { ids.count }

    /// Selected ids in shelf order.
    public func ordered(in order: [UUID]) -> [UUID] { order.filter { ids.contains($0) } }

    public mutating func click(_ id: UUID, modifier: Modifier, order: [UUID]) {
        pendingCollapse = nil
        switch modifier {
        case .toggle:
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
            anchor = id
        case .extend:
            guard let a = anchor, let i = order.firstIndex(of: a), let j = order.firstIndex(of: id) else {
                ids = [id]; anchor = id; return
            }
            ids.formUnion(order[min(i, j)...max(i, j)])
        case .none:
            if ids.contains(id) && ids.count > 1 {
                pendingCollapse = id
            } else {
                ids = [id]
            }
            anchor = id
        }
    }

    /// Mouse-up after a plain click without a drag.
    public mutating func commitPlainClick() {
        if let id = pendingCollapse { ids = [id] }
        pendingCollapse = nil
    }

    /// A drag started: keep the group as it is.
    public mutating func cancelPendingCollapse() { pendingCollapse = nil }

    public mutating func set(_ id: UUID?) {
        ids = id.map { [$0] } ?? []
        anchor = id
        pendingCollapse = nil
    }

    public mutating func selectAll(_ order: [UUID]) {
        ids = Set(order)
        anchor = order.first
        pendingCollapse = nil
    }

    /// Drops ids that are no longer on the shelf.
    public mutating func prune(to order: [UUID]) {
        let live = Set(order)
        ids.formIntersection(live)
        if let a = anchor, !live.contains(a) { anchor = nil }
        if let p = pendingCollapse, !live.contains(p) { pendingCollapse = nil }
    }
}

import Foundation

/// When the shelf appears.
public enum ShowMode: String, Codable, CaseIterable, Sendable {
    case onAnyDrag       // fade in as soon as any drag starts (Yoink default)
    case nearEdge        // only when the drag reaches the docking edge
    case manual          // only via hotkey / menu bar

    public var label: String {
        switch self {
        case .onAnyDrag: return "As soon as I start dragging"
        case .nearEdge: return "When a drag reaches the screen edge"
        case .manual: return "Only from the menu bar or hotkey"
        }
    }
}

/// User preferences, persisted in UserDefaults under one JSON blob so tests can use a
/// throwaway suite.
public struct Settings: Codable, Equatable, Sendable {
    public var edge: ShelfEdge = .left
    public var showMode: ShowMode = .onAnyDrag
    /// Drag an item out of the shelf -> it is removed (Yoink's default).
    public var removeAfterDragOut: Bool = true
    /// Hide the shelf again when it becomes empty.
    public var hideWhenEmpty: Bool = true
    /// Keep the shelf visible while it holds items, instead of hiding when idle.
    public var stayVisibleWithItems: Bool = true
    /// Pushing the pointer against the docking edge reveals a shelf that holds items.
    public var revealOnEdgeHover: Bool = true
    public var launchAtLogin: Bool = false
    public var edgeDistance: Double = 60

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        edge = (try? c.decode(ShelfEdge.self, forKey: .edge)) ?? d.edge
        showMode = (try? c.decode(ShowMode.self, forKey: .showMode)) ?? d.showMode
        removeAfterDragOut = (try? c.decode(Bool.self, forKey: .removeAfterDragOut)) ?? d.removeAfterDragOut
        hideWhenEmpty = (try? c.decode(Bool.self, forKey: .hideWhenEmpty)) ?? d.hideWhenEmpty
        stayVisibleWithItems = (try? c.decode(Bool.self, forKey: .stayVisibleWithItems)) ?? d.stayVisibleWithItems
        revealOnEdgeHover = (try? c.decode(Bool.self, forKey: .revealOnEdgeHover)) ?? d.revealOnEdgeHover
        launchAtLogin = (try? c.decode(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin
        edgeDistance = (try? c.decode(Double.self, forKey: .edgeDistance)) ?? d.edgeDistance
    }

    private static let key = "snag.settings.v3"
    /// v2 defaulted to "near edge"; carried over on upgrade except for the show mode.
    private static let legacyKey = "snag.settings.v2"

    public static func load(from defaults: UserDefaults = .standard) -> Settings {
        var s: Settings
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            s = decoded
        } else if let data = defaults.data(forKey: legacyKey),
                  let old = try? JSONDecoder().decode(Settings.self, from: data) {
            s = old
            s.showMode = Settings().showMode
        } else {
            return Settings()
        }
        s.edgeDistance = min(max(s.edgeDistance.isFinite ? s.edgeDistance : 60, 4), 200)
        return s
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

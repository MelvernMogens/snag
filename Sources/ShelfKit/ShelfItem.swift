import Foundation

/// What a shelf item originally was. Every item is backed by real files on disk so it can
/// always be dragged out as a file; `kind` only changes how it is shown and what extra
/// representations (plain text, a web URL) are offered on drag-out.
public enum ItemKind: String, Codable, Sendable {
    case file   // the user's own file(s), held by reference — never copied
    case text   // a text snippet, saved as an owned .txt
    case link   // a web link, saved as an owned .webloc
    case image  // raw image data (browser / screenshot), saved as an owned image file
}

/// One file inside an item. A stack has several.
public struct ShelfEntry: Codable, Equatable, Sendable {
    public var path: String
    /// Bookmark so a referenced file that gets moved or renamed is still found.
    public var bookmark: Data?
    /// True when Snag created the file (text/link/image/promise) and must clean it up.
    public var owned: Bool

    public init(path: String, bookmark: Data? = nil, owned: Bool) {
        self.path = path
        self.bookmark = bookmark
        self.owned = owned
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var name: String { url.lastPathComponent }
}

public struct ShelfItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var kind: ItemKind
    public var entries: [ShelfEntry]
    /// Raw text for `.text`, absolute URL string for `.link`.
    public var text: String?
    public var title: String
    public var addedAt: Date

    public init(id: UUID = UUID(), kind: ItemKind, entries: [ShelfEntry], text: String? = nil,
                title: String, addedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.entries = entries
        self.text = text
        self.title = title
        self.addedAt = addedAt
    }

    public var isStack: Bool { entries.count > 1 }
    public var urls: [URL] { entries.map(\.url) }
    public var ownsFiles: Bool { entries.contains { $0.owned } }

    /// Label shown under the thumbnail.
    public var displayTitle: String {
        if isStack { return "\(entries.count) items" }
        return title
    }
}

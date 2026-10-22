import Foundation

/// Turns whatever was dropped or pasted into a `ShelfItem`, writing owned backing files where
/// needed. Pure Foundation so it is fully unit-testable.
public struct ItemFactory {
    public let itemsDirectory: URL
    private let fm = FileManager.default

    public init(itemsDirectory: URL) {
        self.itemsDirectory = itemsDirectory
    }

    /// References to the user's own files. One URL = single item, several = a stack.
    public func files(_ urls: [URL]) -> ShelfItem? {
        var seen = Set<String>()
        let entries: [ShelfEntry] = urls.compactMap { url in
            let u = url.standardizedFileURL
            guard u.isFileURL, fm.fileExists(atPath: u.path), seen.insert(u.path).inserted else { return nil }
            return ShelfEntry(path: u.path, bookmark: ShelfStore.bookmark(for: u), owned: false)
        }
        guard !entries.isEmpty else { return nil }
        return ShelfItem(kind: .file, entries: entries, title: entries.count == 1 ? entries[0].name : "")
    }

    /// A text snippet saved as a .txt named after its first line.
    public func text(_ raw: String) -> ShelfItem? {
        let text = raw.count > 5_000_000 ? String(raw.prefix(5_000_000)) : raw
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let name = Self.snippetName(for: text) + ".txt"
        guard let url = writeOwned(name: name, data: Data(text.utf8)) else { return nil }
        return ShelfItem(kind: .text, entries: [ShelfEntry(path: url.path, owned: true)],
                         text: text, title: Self.snippetName(for: text))
    }

    /// A web link saved as a .webloc so it can be dropped into Finder and opened later.
    public func link(_ url: URL, title: String? = nil) -> ShelfItem? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "ftp", "mailto"].contains(scheme) else { return nil }
        let label = Self.clean(title?.isEmpty == false ? title! : (url.host ?? url.absoluteString), max: 60)
        let plist: [String: Any] = ["URL": url.absoluteString]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
              let file = writeOwned(name: label + ".webloc", data: data) else { return nil }
        return ShelfItem(kind: .link, entries: [ShelfEntry(path: file.path, owned: true)],
                         text: url.absoluteString, title: label)
    }

    /// Raw image bytes (dragged from a browser, pasted screenshot). `ext` like "png".
    public func image(_ data: Data, ext: String, suggestedName: String? = nil) -> ShelfItem? {
        guard !data.isEmpty else { return nil }
        let base = Self.clean(suggestedName ?? "Image \(Self.stamp())", max: 60)
        let name = base.lowercased().hasSuffix("." + ext.lowercased()) ? base : base + "." + ext
        guard let url = writeOwned(name: name, data: data) else { return nil }
        return ShelfItem(kind: .image, entries: [ShelfEntry(path: url.path, owned: true)],
                         title: (name as NSString).deletingPathExtension)
    }

    /// Files Snag already wrote into its own Items directory (received file promises).
    public func ownedFiles(_ urls: [URL]) -> ShelfItem? {
        let entries = urls.filter { fm.fileExists(atPath: $0.path) }.map { ShelfEntry(path: $0.path, owned: true) }
        guard !entries.isEmpty else { return nil }
        return ShelfItem(kind: .file, entries: entries, title: entries.count == 1 ? entries[0].name : "")
    }

    /// A fresh empty directory inside Items for an app to deliver promised files into.
    public func makeDropDirectory() -> URL? {
        let dir = itemsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch { return nil }
    }

    // MARK: Naming

    /// First non-empty line, cleaned for use as a filename, max 40 chars.
    public static func snippetName(for text: String) -> String {
        let first = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "Snippet"
        let cleaned = clean(first, max: 40)
        return cleaned.isEmpty ? "Snippet" : cleaned
    }

    /// Strips characters that are illegal or awkward in macOS filenames.
    public static func clean(_ s: String, max: Int) -> String {
        let bad = CharacterSet(charactersIn: "/:\\\0").union(.controlCharacters).union(.newlines)
        var out = String(String.UnicodeScalarView(s.unicodeScalars.filter { !bad.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
        while out.hasPrefix(".") { out.removeFirst() }
        if out.count > max { out = String(out.prefix(max)).trimmingCharacters(in: .whitespaces) }
        return out.isEmpty ? "Item" : out
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: Date())
    }

    private func writeOwned(name: String, data: Data) -> URL? {
        guard let dir = makeDropDirectory() else { return nil }
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            try? fm.removeItem(at: dir)
            return nil
        }
    }
}

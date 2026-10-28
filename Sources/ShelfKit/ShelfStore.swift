import Foundation

/// The shelf's contents, newest first, persisted as JSON under `root`.
///
/// Owned files (snippets, images, received file promises) live in `root/Items/<uuid>/`.
/// Referenced files (the user's own) are never touched — removing them from the shelf only
/// forgets the reference.
public final class ShelfStore {
    public private(set) var items: [ShelfItem] = []
    public let root: URL
    public var itemsDirectory: URL { root.appendingPathComponent("Items", isDirectory: true) }
    public var indexURL: URL { root.appendingPathComponent("shelf.json") }

    /// Called on the caller's thread after every mutation.
    public var onChange: (() -> Void)?
    /// Owned files of an item removed by a drag-out are deleted after this delay, because the
    /// drop target (Mail, Slack, a browser upload) may still be reading the file.
    public var deferredDeletionDelay: TimeInterval = 300

    private let fm = FileManager.default

    public init(root: URL) {
        self.root = root
        try? fm.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)
    }

    // MARK: Persistence

    public func load() {
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
        revalidate(notify: false)
        sweepOrphans()
        save()
    }

    public func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: Queries

    public func item(id: UUID) -> ShelfItem? { items.first { $0.id == id } }
    public var isEmpty: Bool { items.isEmpty }

    // MARK: Mutations

    /// Inserts at the top. Re-adding a single file that is already on the shelf moves the
    /// existing item to the top instead of duplicating it.
    public func add(_ new: ShelfItem) {
        guard !new.entries.isEmpty else { return }
        if !new.ownsFiles, new.entries.count == 1,
           let i = items.firstIndex(where: { $0.entries.count == 1 && $0.entries[0].path == new.entries[0].path }) {
            let existing = items.remove(at: i)
            items.insert(existing, at: 0)
        } else {
            items.insert(new, at: 0)
        }
        commit()
    }

    public func remove(id: UUID, deferDeletion: Bool = false) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: i)
        discardOwnedFiles(of: removed, deferred: deferDeletion)
        commit()
    }

    public enum RenameError: Error, Equatable {
        case notFound, isStack, invalidName, alreadyExists, failed(String)
    }

    /// A name macOS will accept for a file, without surprises: no path separators, not hidden,
    /// not empty, at most 255 bytes.
    public static func isValidFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != "..", !name.hasPrefix("."),
              name.utf8.count <= 255 else { return false }
        return !name.unicodeScalars.contains { $0 == "/" || $0 == ":" || $0 == "\0" || CharacterSet.newlines.contains($0) }
    }

    /// Renames the item's file on disk (in place, same folder) and updates the shelf.
    /// Works for the user's own files and for Snag-owned snippets/links/images alike.
    @discardableResult
    public func rename(id: UUID, to rawName: String) throws -> ShelfItem {
        guard let i = items.firstIndex(where: { $0.id == id }) else { throw RenameError.notFound }
        var item = items[i]
        guard item.entries.count == 1 else { throw RenameError.isStack }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidFileName(name) else { throw RenameError.invalidName }
        let old = item.entries[0].url
        guard name != old.lastPathComponent else { return item }
        let new = old.deletingLastPathComponent().appendingPathComponent(name)
        let caseOnly = name.lowercased() == old.lastPathComponent.lowercased()
        if !caseOnly && fm.fileExists(atPath: new.path) { throw RenameError.alreadyExists }
        do {
            if caseOnly {
                // Case-insensitive volumes see "a.txt" and "A.txt" as the same file: hop via a temp name.
                let tmp = old.deletingLastPathComponent().appendingPathComponent(".snag-rename-\(UUID().uuidString)")
                try fm.moveItem(at: old, to: tmp)
                try fm.moveItem(at: tmp, to: new)
            } else {
                try fm.moveItem(at: old, to: new)
            }
        } catch {
            throw RenameError.failed(error.localizedDescription)
        }
        item.entries[0].path = new.path
        if !item.entries[0].owned { item.entries[0].bookmark = Self.bookmark(for: new) ?? item.entries[0].bookmark }
        let base = (name as NSString).deletingPathExtension
        item.title = item.kind == .file || base.isEmpty ? name : base
        items[i] = item
        commit()
        return item
    }

    /// Removes several items with a single save/notify.
    public func remove(ids: [UUID], deferDeletion: Bool = false) {
        let set = Set(ids)
        let removed = items.filter { set.contains($0.id) }
        guard !removed.isEmpty else { return }
        items.removeAll { set.contains($0.id) }
        removed.forEach { discardOwnedFiles(of: $0, deferred: deferDeletion) }
        commit()
    }

    public func clear() {
        let all = items
        items.removeAll()
        all.forEach { discardOwnedFiles(of: $0, deferred: false) }
        commit()
    }

    /// Breaks a stack into one item per file, in place.
    public func split(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].isStack else { return }
        let stack = items[i]
        let singles = stack.entries.map { entry in
            ShelfItem(kind: stack.kind, entries: [entry], text: nil, title: entry.name, addedAt: stack.addedAt)
        }
        items.replaceSubrange(i...i, with: singles)
        commit()
    }

    /// Removes one file from a stack (used when only part of a stack is dragged out).
    public func removeEntry(path: String, from id: UUID, deferDeletion: Bool = false) {
        guard let i = items.firstIndex(where: { $0.id == id }),
              let j = items[i].entries.firstIndex(where: { $0.path == path }) else { return }
        let entry = items[i].entries.remove(at: j)
        if entry.owned { deleteOwned(paths: [entry.path], deferred: deferDeletion) }
        if items[i].entries.isEmpty {
            items.remove(at: i)
        } else if items[i].entries.count == 1 {
            items[i].title = items[i].entries[0].name
        }
        commit()
    }

    /// Re-finds referenced files that were moved/renamed (via bookmark) and drops files that
    /// are gone for good. Returns true if anything changed.
    @discardableResult
    public func revalidate(notify: Bool = true) -> Bool {
        var changed = false
        var kept: [ShelfItem] = []
        for var item in items {
            var entries: [ShelfEntry] = []
            for var entry in item.entries {
                if fm.fileExists(atPath: entry.path) {
                    entries.append(entry)
                    continue
                }
                if let bm = entry.bookmark, let resolved = Self.resolve(bookmark: bm),
                   fm.fileExists(atPath: resolved.path) {
                    entry.path = resolved.path
                    entry.bookmark = Self.bookmark(for: resolved) ?? bm
                    entries.append(entry)
                }
                changed = true
            }
            if entries.isEmpty { changed = true; continue }
            if entries.count == 1, item.entries.count != 1 || item.entries[0].path != entries[0].path,
               item.kind == .file {
                item.title = entries[0].name
            }
            item.entries = entries
            kept.append(item)
        }
        items = kept
        if changed && notify { commit() }
        return changed
    }

    /// Deletes owned files that no item references (left over from deferred deletions or a crash).
    public func sweepOrphans() {
        let referenced = Set(items.flatMap { $0.entries.filter(\.owned).map { Self.normalize($0.path) } })
        guard let dirs = try? fm.contentsOfDirectory(at: itemsDirectory, includingPropertiesForKeys: nil) else { return }
        for dir in dirs {
            let children = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for child in children where !referenced.contains(Self.normalize(child.path)) {
                try? fm.removeItem(at: child)
            }
            if ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).isEmpty {
                try? fm.removeItem(at: dir)
            }
        }
    }

    // MARK: Helpers

    public static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public static func resolve(bookmark: Data) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                        relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    private static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func commit() {
        save()
        onChange?()
    }

    private func discardOwnedFiles(of item: ShelfItem, deferred: Bool) {
        deleteOwned(paths: item.entries.filter(\.owned).map(\.path), deferred: deferred)
    }

    private func deleteOwned(paths: [String], deferred: Bool) {
        guard !paths.isEmpty else { return }
        // Only ever delete inside our own Items directory, whatever the JSON says.
        let base = Self.normalize(itemsDirectory.path) + "/"
        let safe = paths.filter { Self.normalize($0).hasPrefix(base) }
        let work = { [fm] in
            for p in safe {
                try? fm.removeItem(atPath: p)
                let dir = (p as NSString).deletingLastPathComponent
                if ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).isEmpty {
                    try? fm.removeItem(atPath: dir)
                }
            }
        }
        if deferred && deferredDeletionDelay > 0 {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + deferredDeletionDelay, execute: work)
        } else {
            work()
        }
    }
}

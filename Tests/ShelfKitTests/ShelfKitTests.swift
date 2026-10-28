import XCTest
@testable import ShelfKit

final class ShelfKitTests: XCTestCase {
    var root: URL!
    var store: ShelfStore!
    var factory: ItemFactory!
    var scratch: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("snag-test-\(UUID().uuidString)")
        scratch = root.appendingPathComponent("user-files")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        store = ShelfStore(root: root.appendingPathComponent("data"))
        store.deferredDeletionDelay = 0
        factory = ItemFactory(itemsDirectory: store.itemsDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func userFile(_ name: String, _ body: String = "x") throws -> URL {
        let u = scratch.appendingPathComponent(name)
        try body.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    // MARK: Factory

    func testSingleFileIsReferencedNotCopied() throws {
        let f = try userFile("report.pdf")
        let item = try XCTUnwrap(factory.files([f]))
        XCTAssertEqual(item.kind, .file)
        XCTAssertFalse(item.isStack)
        XCTAssertEqual(item.entries[0].path, f.standardizedFileURL.path)
        XCTAssertFalse(item.entries[0].owned)
        XCTAssertEqual(item.displayTitle, "report.pdf")
    }

    func testMultipleFilesBecomeOneStackAndDedupe() throws {
        let a = try userFile("a.txt"), b = try userFile("b.txt")
        let item = try XCTUnwrap(factory.files([a, b, a]))
        XCTAssertTrue(item.isStack)
        XCTAssertEqual(item.entries.count, 2)
        XCTAssertEqual(item.displayTitle, "2 items")
    }

    func testMissingFilesAreRejected() {
        XCTAssertNil(factory.files([URL(fileURLWithPath: "/definitely/not/here.txt")]))
        XCTAssertNil(factory.files([]))
    }

    func testTextSnippetWritesOwnedFileNamedAfterFirstLine() throws {
        let item = try XCTUnwrap(factory.text("\n  Meeting notes: Q3/plan  \nsecond line"))
        XCTAssertEqual(item.kind, .text)
        XCTAssertTrue(item.entries[0].owned)
        XCTAssertEqual(item.title, "Meeting notes Q3plan")
        XCTAssertEqual(item.entries[0].url.lastPathComponent, "Meeting notes Q3plan.txt")
        XCTAssertEqual(try String(contentsOf: item.entries[0].url, encoding: .utf8), "\n  Meeting notes: Q3/plan  \nsecond line")
    }

    func testWhitespaceTextIsRejected() {
        XCTAssertNil(factory.text("   \n\t "))
    }

    func testLinkWritesWebloc() throws {
        let url = URL(string: "https://example.com/page?q=1")!
        let item = try XCTUnwrap(factory.link(url, title: "Example Page"))
        XCTAssertEqual(item.kind, .link)
        XCTAssertEqual(item.text, url.absoluteString)
        XCTAssertEqual(item.entries[0].url.pathExtension, "webloc")
        let data = try Data(contentsOf: item.entries[0].url)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["URL"] as? String, url.absoluteString)
    }

    func testLinkRejectsNonWebSchemes() {
        XCTAssertNil(factory.link(URL(string: "javascript:alert(1)")!))
        XCTAssertNil(factory.link(URL(fileURLWithPath: "/etc/hosts")))
    }

    func testImageKeepsExtension() throws {
        let item = try XCTUnwrap(factory.image(Data([0x89, 0x50, 0x4E, 0x47]), ext: "png", suggestedName: "shot.png"))
        XCTAssertEqual(item.entries[0].url.lastPathComponent, "shot.png")
        XCTAssertNil(factory.image(Data(), ext: "png"))
    }

    func testCleanStripsIllegalCharacters() {
        XCTAssertEqual(ItemFactory.clean("../../etc/passwd", max: 60), "etcpasswd")
        XCTAssertEqual(ItemFactory.clean("a:b\\c", max: 60), "abc")
        XCTAssertEqual(ItemFactory.clean("", max: 60), "Item")
        XCTAssertEqual(ItemFactory.clean(String(repeating: "x", count: 100), max: 10).count, 10)
    }

    // MARK: Store

    func testAddPutsNewestFirstAndPersists() throws {
        let a = try XCTUnwrap(factory.files([try userFile("a.txt")]))
        let b = try XCTUnwrap(factory.text("hello"))
        store.add(a)
        store.add(b)
        XCTAssertEqual(store.items.map(\.id), [b.id, a.id])

        let reopened = ShelfStore(root: store.root)
        reopened.load()
        XCTAssertEqual(reopened.items.map(\.id), [b.id, a.id])
        XCTAssertEqual(reopened.items[0].text, "hello")
    }

    func testReaddingSameFileMovesItToTopInsteadOfDuplicating() throws {
        let fa = try userFile("a.txt")
        store.add(try XCTUnwrap(factory.files([fa])))
        store.add(try XCTUnwrap(factory.text("snippet")))
        store.add(try XCTUnwrap(factory.files([fa])))
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items[0].entries[0].name, "a.txt")
    }

    func testRemovingOwnedItemDeletesItsFileButNeverUserFiles() throws {
        let userURL = try userFile("keep-me.txt")
        let user = try XCTUnwrap(factory.files([userURL]))
        let snippet = try XCTUnwrap(factory.text("temp"))
        store.add(user); store.add(snippet)
        let snippetPath = snippet.entries[0].path
        XCTAssertTrue(FileManager.default.fileExists(atPath: snippetPath))

        store.remove(id: snippet.id)
        store.remove(id: user.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snippetPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: userURL.path), "user's own file must never be deleted")
        XCTAssertTrue(store.isEmpty)
    }

    func testTamperedIndexCannotMakeStoreDeleteOutsideItsDirectory() throws {
        let victim = try userFile("victim.txt")
        // Hand-craft an item claiming to own a user file.
        let evil = ShelfItem(kind: .text, entries: [ShelfEntry(path: victim.path, owned: true)], text: "x", title: "x")
        store.add(evil)
        store.remove(id: evil.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: victim.path))
        store.add(ShelfItem(kind: .text, entries: [ShelfEntry(path: victim.path, owned: true)], text: "x", title: "x"))
        store.clear()
        XCTAssertTrue(FileManager.default.fileExists(atPath: victim.path))
    }

    func testClearRemovesEverything() throws {
        store.add(try XCTUnwrap(factory.text("one")))
        store.add(try XCTUnwrap(factory.link(URL(string: "https://a.b")!)))
        store.clear()
        XCTAssertTrue(store.isEmpty)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: store.itemsDirectory.path)) ?? []
        XCTAssertEqual(leftovers, [])
    }

    func testSplitStack() throws {
        let stack = try XCTUnwrap(factory.files([try userFile("1.txt"), try userFile("2.txt"), try userFile("3.txt")]))
        store.add(try XCTUnwrap(factory.text("above")))
        store.add(stack)
        store.split(id: stack.id)
        XCTAssertEqual(store.items.count, 4)
        XCTAssertEqual(store.items.prefix(3).map(\.title), ["1.txt", "2.txt", "3.txt"])
        XCTAssertEqual(store.items[3].kind, .text)
    }

    func testRemoveEntryShrinksStackThenDropsIt() throws {
        let a = try userFile("a.txt"), b = try userFile("b.txt")
        let stack = try XCTUnwrap(factory.files([a, b]))
        store.add(stack)
        store.removeEntry(path: a.standardizedFileURL.path, from: stack.id)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertFalse(store.items[0].isStack)
        XCTAssertEqual(store.items[0].title, "b.txt")
        store.removeEntry(path: b.standardizedFileURL.path, from: stack.id)
        XCTAssertTrue(store.isEmpty)
    }

    func testRevalidateFollowsMovedFileAndDropsDeletedOne() throws {
        let moved = try userFile("old-name.txt")
        let deleted = try userFile("gone.txt")
        let m = try XCTUnwrap(factory.files([moved]))
        let d = try XCTUnwrap(factory.files([deleted]))
        store.add(m); store.add(d)

        let newURL = scratch.appendingPathComponent("new-name.txt")
        try FileManager.default.moveItem(at: moved, to: newURL)
        try FileManager.default.removeItem(at: deleted)

        XCTAssertTrue(store.revalidate())
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].entries[0].name, "new-name.txt")
        XCTAssertEqual(store.items[0].title, "new-name.txt")
    }

    func testLoadSweepsOrphanedOwnedFiles() throws {
        let kept = try XCTUnwrap(factory.text("kept"))
        store.add(kept)
        let orphanDir = store.itemsDirectory.appendingPathComponent("orphan")
        try FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)
        try "junk".write(to: orphanDir.appendingPathComponent("junk.txt"), atomically: true, encoding: .utf8)

        let reopened = ShelfStore(root: store.root)
        reopened.load()
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.entries[0].path))
    }

    func testCorruptIndexLoadsEmpty() throws {
        try "{not json".write(to: store.indexURL, atomically: true, encoding: .utf8)
        store.load()
        XCTAssertTrue(store.isEmpty)
    }

    func testDeferredDeletionKeepsFileUntilDelay() throws {
        store.deferredDeletionDelay = 0.3
        let s = try XCTUnwrap(factory.text("dragged out"))
        store.add(s)
        store.remove(id: s.id, deferDeletion: true)
        XCTAssertTrue(store.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.entries[0].path), "destination may still be reading")
        let gone = expectation(description: "deleted later")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
            if !FileManager.default.fileExists(atPath: s.entries[0].path) { gone.fulfill() }
        }
        wait(for: [gone], timeout: 2)
    }

    // MARK: Geometry

    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testFrameHugsChosenEdge() {
        let r = ShelfGeometry.frame(edge: .right, itemCount: 2, visible: screen)
        XCTAssertEqual(r.maxX, screen.maxX - ShelfGeometry.margin)
        let l = ShelfGeometry.frame(edge: .left, itemCount: 2, visible: screen)
        XCTAssertEqual(l.minX, ShelfGeometry.margin)
        XCTAssertEqual(r.midY, screen.midY, accuracy: 1)
    }

    func testHeightGrowsWithItemsButIsClamped() {
        let empty = ShelfGeometry.height(itemCount: 0, visible: screen)
        let one = ShelfGeometry.height(itemCount: 1, visible: screen)
        let three = ShelfGeometry.height(itemCount: 3, visible: screen)
        let eight = ShelfGeometry.height(itemCount: 8, visible: screen)
        // A single item still gets a tall shelf with room for several rows.
        XCTAssertGreaterThanOrEqual(one, ShelfGeometry.header + CGFloat(ShelfGeometry.minVisibleRows) * ShelfGeometry.tile)
        XCTAssertEqual(one, three)
        XCTAssertGreaterThan(eight, three)
        let many = ShelfGeometry.height(itemCount: 500, visible: screen)
        XCTAssertEqual(empty, ShelfGeometry.emptyHeight)
        XCTAssertGreaterThan(three, empty)
        XCTAssertEqual(many, screen.height * ShelfGeometry.maxHeightFraction)
    }

    func testHiddenFrameIsOffScreen() {
        for edge in ShelfEdge.allCases {
            let h = ShelfGeometry.hiddenFrame(edge: edge, itemCount: 1, visible: screen)
            XCTAssertFalse(h.intersects(screen), "\(edge)")
        }
    }

    func testPointerNearEdge() {
        XCTAssertTrue(ShelfGeometry.pointerNearEdge(CGPoint(x: 1500, y: 400), edge: .right, screen: screen, distance: 40))
        XCTAssertFalse(ShelfGeometry.pointerNearEdge(CGPoint(x: 1400, y: 400), edge: .right, screen: screen, distance: 40))
        XCTAssertTrue(ShelfGeometry.pointerNearEdge(CGPoint(x: 5, y: 400), edge: .left, screen: screen, distance: 40))
        XCTAssertFalse(ShelfGeometry.pointerNearEdge(CGPoint(x: 1500, y: 2000), edge: .right, screen: screen, distance: 40))
    }

    func testIsRealDrag() {
        XCTAssertFalse(ShelfGeometry.isRealDrag(start: .zero, current: CGPoint(x: 2, y: 2)))
        XCTAssertTrue(ShelfGeometry.isRealDrag(start: .zero, current: CGPoint(x: 6, y: 0)))
    }

    // MARK: Settings

    func testDefaultsDockLeftAndShowOnAnyDrag() {
        let s = Settings()
        XCTAssertEqual(s.edge, .left)
        XCTAssertEqual(s.showMode, .onAnyDrag)
        XCTAssertTrue(s.stayVisibleWithItems)
        XCTAssertTrue(s.revealOnEdgeHover)
    }

    func testSettingsDecodeFillsMissingKeysWithDefaults() throws {
        let partial = Data(#"{"edge":"right","removeAfterDragOut":false}"#.utf8)
        let s = try JSONDecoder().decode(Settings.self, from: partial)
        XCTAssertEqual(s.edge, .right)
        XCTAssertFalse(s.removeAfterDragOut)
        XCTAssertEqual(s.showMode, .onAnyDrag)
        XCTAssertTrue(s.revealOnEdgeHover)
    }

    func testV2SettingsMigrateToShowOnAnyDrag() throws {
        let suite = "snag-test-\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        d.set(Data(#"{"edge":"right","showMode":"nearEdge","launchAtLogin":true}"#.utf8), forKey: "snag.settings.v2")
        let s = Settings.load(from: d)
        XCTAssertEqual(s.showMode, .onAnyDrag)
        XCTAssertEqual(s.edge, .right)
        XCTAssertTrue(s.launchAtLogin)
    }

    func testSettingsRoundTripAndClamp() throws {
        let suite = "snag-test-\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertEqual(Settings.load(from: d), Settings())
        var s = Settings()
        s.edge = .left
        s.showMode = .nearEdge
        s.edgeDistance = 10_000
        s.save(to: d)
        let back = Settings.load(from: d)
        XCTAssertEqual(back.edge, .left)
        XCTAssertEqual(back.showMode, .nearEdge)
        XCTAssertEqual(back.edgeDistance, 200)
    }

    // MARK: Multi-select

    private let o = (0..<5).map { _ in UUID() }

    func testPlainClickSelectsOne() {
        var sel = Selection()
        sel.click(o[1], modifier: .none, order: o)
        sel.click(o[3], modifier: .none, order: o)
        XCTAssertEqual(sel.ids, [o[3]])
    }

    func testCommandClickToggles() {
        var sel = Selection()
        sel.click(o[0], modifier: .none, order: o)
        sel.click(o[2], modifier: .toggle, order: o)
        sel.click(o[4], modifier: .toggle, order: o)
        XCTAssertEqual(sel.ordered(in: o), [o[0], o[2], o[4]])
        sel.click(o[2], modifier: .toggle, order: o)
        XCTAssertEqual(sel.ordered(in: o), [o[0], o[4]])
    }

    func testShiftClickSelectsRangeFromAnchor() {
        var sel = Selection()
        sel.click(o[3], modifier: .none, order: o)
        sel.click(o[1], modifier: .extend, order: o)
        XCTAssertEqual(sel.ordered(in: o), [o[1], o[2], o[3]])
    }

    func testPlainClickOnGroupKeepsItForDragThenCollapsesOnMouseUp() {
        var sel = Selection()
        sel.selectAll(o)
        sel.click(o[2], modifier: .none, order: o)
        XCTAssertEqual(sel.count, 5, "group must survive mouse-down so it can be dragged together")
        var dragged = sel
        dragged.cancelPendingCollapse()
        dragged.commitPlainClick()
        XCTAssertEqual(dragged.count, 5)
        sel.commitPlainClick()
        XCTAssertEqual(sel.ids, [o[2]])
    }

    func testPruneDropsRemovedIds() {
        var sel = Selection()
        sel.selectAll(o)
        sel.prune(to: Array(o.prefix(2)))
        XCTAssertEqual(sel.ordered(in: o), [o[0], o[1]])
    }

    func testRemoveManyAtOnce() throws {
        let a = try XCTUnwrap(factory.text("a")), b = try XCTUnwrap(factory.text("b")), c = try XCTUnwrap(factory.text("c"))
        store.add(a); store.add(b); store.add(c)
        var changes = 0
        store.onChange = { changes += 1 }
        store.remove(ids: [a.id, c.id])
        XCTAssertEqual(store.items.map(\.id), [b.id])
        XCTAssertEqual(changes, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.entries[0].path))
    }

    // MARK: Rename

    func testRenameMovesUserFileOnDiskAndUpdatesShelf() throws {
        let f = try userFile("draft.pdf", "content")
        let item = try XCTUnwrap(factory.files([f]))
        store.add(item)
        try store.rename(id: item.id, to: "Final Report.pdf")
        let renamed = scratch.appendingPathComponent("Final Report.pdf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.path))
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "content")
        XCTAssertEqual(store.items[0].entries[0].path, renamed.standardizedFileURL.path)
        XCTAssertEqual(store.items[0].title, "Final Report.pdf")
        let reopened = ShelfStore(root: store.root); reopened.load()
        XCTAssertEqual(reopened.items[0].title, "Final Report.pdf")
    }

    func testRenameRefusesToOverwriteExistingFile() throws {
        let a = try userFile("a.txt", "A"); _ = try userFile("b.txt", "B")
        let item = try XCTUnwrap(factory.files([a]))
        store.add(item)
        XCTAssertThrowsError(try store.rename(id: item.id, to: "b.txt")) {
            XCTAssertEqual($0 as? ShelfStore.RenameError, .alreadyExists)
        }
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "A")
        XCTAssertEqual(try String(contentsOf: scratch.appendingPathComponent("b.txt"), encoding: .utf8), "B")
    }

    func testRenameRejectsBadNames() throws {
        let item = try XCTUnwrap(factory.files([try userFile("a.txt")]))
        store.add(item)
        for bad in ["", "   ", "../x.txt", "a/b.txt", "a:b", ".hidden", String(repeating: "x", count: 300)] {
            XCTAssertThrowsError(try store.rename(id: item.id, to: bad), bad)
        }
        XCTAssertEqual(store.items[0].title, "a.txt")
    }

    func testRenameCaseOnly() throws {
        let item = try XCTUnwrap(factory.files([try userFile("photo.jpg")]))
        store.add(item)
        try store.rename(id: item.id, to: "Photo.JPG")
        XCTAssertEqual(store.items[0].entries[0].name, "Photo.JPG")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: scratch.path).contains("Photo.JPG"))
    }

    func testRenameStackIsRefused() throws {
        let stack = try XCTUnwrap(factory.files([try userFile("1.txt"), try userFile("2.txt")]))
        store.add(stack)
        XCTAssertThrowsError(try store.rename(id: stack.id, to: "x")) {
            XCTAssertEqual($0 as? ShelfStore.RenameError, .isStack)
        }
    }

    func testRenamedSnippetIsStillOwnedAndCleanedUp() throws {
        let snip = try XCTUnwrap(factory.text("hello world"))
        store.add(snip)
        let renamed = try store.rename(id: snip.id, to: "greeting.txt")
        XCTAssertEqual(renamed.title, "greeting")
        let path = renamed.entries[0].path
        XCTAssertTrue(path.hasSuffix("/greeting.txt"))
        store.remove(id: snip.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }
}

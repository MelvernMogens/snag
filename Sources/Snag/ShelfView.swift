import AppKit
import Quartz
import ShelfKit

/// The floating shelf: a borderless, non-activating HUD panel docked to a screen edge that
/// follows the user across Spaces and full-screen apps.
final class ShelfPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: ShelfGeometry.width, height: ShelfGeometry.emptyHeight),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .statusBar
        // canJoinAllSpaces + fullScreenAuxiliary = visible on every desktop, including full-screen apps
        // (which are their own Space). AppDelegate re-orders it front on every Space switch, because
        // macOS does not always carry an already-visible panel into a full-screen Space by itself.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        animationBehavior = .none
        setAccessibilityLabel("Snag shelf")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

protocol ShelfViewDelegate: AnyObject {
    func shelfReceived(_ items: [ShelfItem])
    func shelfClearAll()
    func shelfDropTargetChanged(_ hovering: Bool)
}

/// Content of the shelf panel: header (count + clear), scrolling column of tiles, drop target.
final class ShelfView: NSView, ItemTileDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    weak var delegate: ShelfViewDelegate?
    let store: ShelfStore
    let factory: ItemFactory
    var settingsProvider: () -> Settings = { Settings() }

    private let effect = NSVisualEffectView()
    private let header = NSTextField(labelWithString: "")
    private let clearButton = NSButton()
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "Drop here")
    private var tiles: [UUID: ItemTileView] = [:]
    private var selection = Selection()
    /// Items travelling in the current drag-out, removed from the shelf when it lands.
    private var draggedIDs: [UUID] = []
    private var orderIDs: [UUID] { store.items.map(\.id) }
    private var dropHover = false { didSet { updateBorder(); delegate?.shelfDropTargetChanged(dropHover) } }
    private(set) var dragOutInProgress = false

    init(store: ShelfStore, factory: ItemFactory) {
        self.store = store
        self.factory = factory
        super.init(frame: NSRect(x: 0, y: 0, width: ShelfGeometry.width, height: ShelfGeometry.emptyHeight))
        wantsLayer = true
        build()
        registerForDraggedTypes(Ingest.acceptedTypes)
        updateBorder()
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.appearance = NSAppearance(named: .vibrantDark)
        effect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effect)

        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = NSColor.white.withAlphaComponent(0.55)
        header.translatesAutoresizingMaskIntoConstraints = false

        clearButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear shelf")
        clearButton.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        clearButton.isBordered = false
        clearButton.contentTintColor = NSColor.white.withAlphaComponent(0.55)
        clearButton.target = self
        clearButton.action = #selector(clearAll)
        clearButton.toolTip = "Clear shelf"
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .centerX
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 6, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        // Drops must land on ShelfView, not on the scroll/clip views.
        scroll.unregisterDraggedTypes()

        emptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        emptyLabel.textColor = NSColor.white.withAlphaComponent(0.45)
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        for v in [header, clearButton, scroll, emptyLabel] as [NSView] { effect.addSubview(v) }

        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor),

            header.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
            header.topAnchor.constraint(equalTo: effect.topAnchor, constant: 9),
            clearButton.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16),

            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: effect.topAnchor, constant: ShelfGeometry.header),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -4),

            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: effect.centerYAnchor, constant: 8),
        ])
    }

    // MARK: Model -> views

    func reload() {
        let items = store.items
        let ids = Set(items.map(\.id))
        for (id, tile) in tiles where !ids.contains(id) {
            tile.removeFromSuperview()
            tiles[id] = nil
        }
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v) }
        for item in items {
            let tile: ItemTileView
            if let t = tiles[item.id] {
                t.update(item)
                tile = t
            } else {
                tile = ItemTileView(item: item)
                tile.delegate = self
                tile.translatesAutoresizingMaskIntoConstraints = false
                tile.heightAnchor.constraint(equalToConstant: ShelfGeometry.tile).isActive = true
                tiles[item.id] = tile
            }
            stack.addArrangedSubview(tile)
            tile.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        selection.prune(to: items.map(\.id))
        refreshSelectionViews()
        let files = items.reduce(0) { $0 + $1.entries.count }
        header.stringValue = items.isEmpty ? "SNAG" : "\(files) FILE\(files == 1 ? "" : "S")"
        clearButton.isHidden = items.isEmpty
        emptyLabel.isHidden = !items.isEmpty
        scroll.isHidden = items.isEmpty
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
        }
    }

    private func updateBorder() {
        effect.layer?.borderWidth = dropHover ? 2 : 0.5
        effect.layer?.borderColor = dropHover
            ? NSColor.controlAccentColor.cgColor
            : NSColor.white.withAlphaComponent(0.12).cgColor
    }

    @objc private func clearAll() { NSLog("Snag: clear button"); delegate?.shelfClearAll() }

    // MARK: Drop in

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if (sender.draggingSource as? ItemTileView) != nil { return [] }
        dropHover = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        (sender.draggingSource as? ItemTileView) != nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { dropHover = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { dropHover = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHover = false
        guard (sender.draggingSource as? ItemTileView) == nil else { return false }
        let pb = sender.draggingPasteboard
        Ingest.read(pb, factory: factory) { [weak self] items in
            guard !items.isEmpty else { NSSound.beep(); return }
            self?.delegate?.shelfReceived(items)
        }
        return true
    }

    // MARK: Keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        switch (event.keyCode, cmd) {
        case (49, false): toggleQuickLook()                         // space
        case (51, _), (117, _): removeSelected()                    // delete / fwd delete
        case (36, false), (76, false): beginRenameSelected()        // return / enter = rename (Finder)
        case (125, true), (31, true): openSelected()                // ⌘↓ / ⌘O = open
        case (125, false): moveSelection(+1)                        // down
        case (126, false): moveSelection(-1)                        // up
        case (0, true): selection.selectAll(orderIDs); refreshSelectionViews()   // ⌘A
        case (53, false): window?.resignKey(); selection.set(nil); refreshSelectionViews()  // esc
        default: super.keyDown(with: event)
        }
    }

    @objc func paste(_ sender: Any?) {
        Ingest.read(.general, factory: factory, allowPromises: false) { [weak self] items in
            if items.isEmpty { NSSound.beep() } else { self?.delegate?.shelfReceived(items) }
        }
    }

    @objc func copy(_ sender: Any?) {
        let writers = selection.ordered(in: orderIDs).compactMap { tiles[$0] }.flatMap { $0.pasteboardWriters() }
        guard !writers.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(writers)
    }

    @objc func delete(_ sender: Any?) { removeSelected() }

    @objc override func selectAll(_ sender: Any?) {
        selection.selectAll(orderIDs)
        refreshSelectionViews()
    }

    private func moveSelection(_ delta: Int) {
        let items = store.items
        guard !items.isEmpty else { return }
        let cur = items.firstIndex { $0.id == selection.anchor } ?? (delta > 0 ? -1 : items.count)
        let next = min(max(cur + delta, 0), items.count - 1)
        select(items[next].id)
        if let t = tiles[items[next].id] { t.scrollToVisible(t.bounds) }
    }

    private func select(_ id: UUID?) {
        selection.set(id)
        refreshSelectionViews()
    }

    private func refreshSelectionViews() {
        for (tid, tile) in tiles { tile.isSelected = selection.contains(tid) }
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
        }
    }

    private func removeSelected() {
        let ids = selection.ordered(in: orderIDs)
        guard let first = ids.first else { return }
        let idx = orderIDs.firstIndex(of: first)
        store.remove(ids: ids)
        if let idx, !store.items.isEmpty { select(store.items[min(idx, store.items.count - 1)].id) }
    }

    private func openSelected() {
        selection.ordered(in: orderIDs).compactMap { store.item(id: $0) }.forEach(open)
    }

    private func open(_ item: ShelfItem) {
        if item.kind == .link, let s = item.text, let u = URL(string: s) {
            NSWorkspace.shared.open(u)
        } else {
            item.urls.forEach { NSWorkspace.shared.open($0) }
        }
    }

    // MARK: ItemTileDelegate

    func tileSelected(_ tile: ItemTileView) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        select(tile.item.id)
    }

    func tileClicked(_ tile: ItemTileView, modifier: Selection.Modifier) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        selection.click(tile.item.id, modifier: modifier, order: orderIDs)
        refreshSelectionViews()
    }

    func tileClickEnded(_ tile: ItemTileView) {
        selection.commitPlainClick()
        refreshSelectionViews()
    }

    func tileDraggingItems(_ tile: ItemTileView) -> [NSDraggingItem] {
        selection.cancelPendingCollapse()
        // Dragging an unselected tile drags just that tile (Finder behaviour).
        let ids = selection.contains(tile.item.id) ? selection.ordered(in: orderIDs) : [tile.item.id]
        draggedIDs = ids
        return ids.compactMap { tiles[$0] }.flatMap { $0.draggingItems(relativeTo: tile) }
    }

    func tileOpen(_ tile: ItemTileView) { open(tile.item) }

    func beginRenameSelected() {
        let ids = selection.ordered(in: orderIDs)
        guard ids.count == 1, let tile = tiles[ids[0]], !tile.item.isStack else { NSSound.beep(); return }
        tile.scrollToVisible(tile.bounds)
        tile.beginRename()
    }

    func tileRename(_ tile: ItemTileView, to name: String) -> Bool {
        do {
            try store.rename(id: tile.item.id, to: name)
            Thumbnails.shared.invalidate()
            return true
        } catch {
            NSLog("Snag: rename to %@ refused: %@", name, String(describing: error))
            return false
        }
    }

    /// Self-test: rename the top item by typing `base` over the pre-selected base name.
    func selfTestRename(base: String, done: @escaping (String) -> Void) {
        guard let first = store.items.first, let tile = tiles[first.id] else { done("FAIL no item"); return }
        select(first.id)
        beginRenameSelected()
        let opened = tile.isEditing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            let r = tile.selfTestType(base)
            let now = self?.store.item(id: first.id)?.entries.first?.name ?? "?"
            done("opened=\(opened) preselected=\(r.selected.location),\(r.selected.length) closed=\(r.ok) name=\(now)")
        }
    }

    func tileRenameFinished(_ tile: ItemTileView) {
        window?.makeFirstResponder(self)
    }

    func tileRemove(_ tile: ItemTileView) { NSLog("Snag: x remove %@", tile.item.title); store.remove(id: tile.item.id) }

    func tileQuickLook(_ tile: ItemTileView) {
        select(tile.item.id)
        toggleQuickLook()
    }

    func tileMenu(_ tile: ItemTileView) -> NSMenu {
        let item = tile.item
        let m = NSMenu()
        func add(_ title: String, _ action: @escaping () -> Void) {
            let mi = ClosureMenuItem(title: title, action: action)
            m.addItem(mi)
        }
        let group = selection.contains(item.id) && selection.count > 1 ? selection.ordered(in: orderIDs) : [item.id]
        if group.count > 1 {
            add("Open \(group.count) Items") { [weak self] in self?.openSelected() }
            add("Copy \(group.count) Items") { [weak self] in self?.copy(nil) }
            add("Show in Finder") { [weak self] in
                guard let self else { return }
                let urls = group.compactMap { self.store.item(id: $0) }.filter { $0.kind == .file }.flatMap(\.urls)
                if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            }
            m.addItem(.separator())
            add("Remove \(group.count) Items from Shelf") { [weak self] in self?.store.remove(ids: group) }
            return m
        }
        add("Open") { [weak self] in self?.open(item) }
        add("Quick Look") { [weak self] in self?.tileQuickLook(tile) }
        if item.kind == .file {
            add("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(item.urls) }
        }
        add("Copy") { [weak self] in self?.select(item.id); self?.copy(nil) }
        if item.kind == .text || item.kind == .link, let t = item.text {
            add(item.kind == .link ? "Copy Link" : "Copy Text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(t, forType: .string)
            }
        }
        if !item.isStack {
            add("Rename…") { [weak self] in self?.select(item.id); tile.beginRename() }
        }
        if item.isStack {
            add("Split Stack") { [weak self] in self?.store.split(id: item.id) }
        }
        m.addItem(.separator())
        add("Remove from Shelf") { [weak self] in self?.store.remove(id: item.id) }
        return m
    }

    func tileDragBegan(_ tile: ItemTileView) { dragOutInProgress = true }

    func tileDragEnded(_ tile: ItemTileView, operation: NSDragOperation, insideShelf: Bool) {
        dragOutInProgress = false
        NSLog("Snag: drag-out ended op=%lu inside=%d", operation.rawValue, insideShelf ? 1 : 0)
        guard !insideShelf, !operation.isEmpty, settingsProvider().removeAfterDragOut else { draggedIDs = []; return }
        // Keep owned files around for a while: the destination may still be reading them.
        let ids = draggedIDs.isEmpty ? [tile.item.id] : draggedIDs
        draggedIDs = []
        store.remove(ids: ids, deferDeletion: true)
    }

    // MARK: Quick Look

    private var previewURLs: [URL] {
        selection.ordered(in: orderIDs).compactMap { store.item(id: $0) }.flatMap(\.urls)
    }

    private func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible { panel.orderOut(nil); return }
        guard !previewURLs.isEmpty else { return }
        window?.makeKey()
        window?.makeFirstResponder(self)
        panel.makeKeyAndOrderFront(nil)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
        panel.level = .statusBar + 1
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let urls = previewURLs
        return index < urls.count ? urls[index] as NSURL : nil
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown, event.keyCode == 49 { panel.orderOut(nil); return true }
        return false
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, keyEquivalent: String = "", action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

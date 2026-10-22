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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
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
    private var selectedID: UUID?
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
            tile.isSelected = item.id == selectedID
        }
        if let s = selectedID, !ids.contains(s) { selectedID = nil }
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
        case (36, false): openSelected()                            // return
        case (125, false): moveSelection(+1)                        // down
        case (126, false): moveSelection(-1)                        // up
        case (53, false): window?.resignKey(); selectedID = nil; reload()  // esc
        default: super.keyDown(with: event)
        }
    }

    @objc func paste(_ sender: Any?) {
        Ingest.read(.general, factory: factory, allowPromises: false) { [weak self] items in
            if items.isEmpty { NSSound.beep() } else { self?.delegate?.shelfReceived(items) }
        }
    }

    @objc func copy(_ sender: Any?) {
        guard let id = selectedID, let tile = tiles[id] else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(tile.pasteboardWriters())
    }

    @objc func delete(_ sender: Any?) { removeSelected() }

    private func moveSelection(_ delta: Int) {
        let items = store.items
        guard !items.isEmpty else { return }
        let cur = items.firstIndex { $0.id == selectedID } ?? (delta > 0 ? -1 : items.count)
        let next = min(max(cur + delta, 0), items.count - 1)
        select(items[next].id)
        if let t = tiles[items[next].id] { t.scrollToVisible(t.bounds) }
    }

    private func select(_ id: UUID?) {
        selectedID = id
        for (tid, tile) in tiles { tile.isSelected = tid == id }
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
        }
    }

    private func removeSelected() {
        guard let id = selectedID else { return }
        let items = store.items
        let idx = items.firstIndex { $0.id == id }
        store.remove(id: id)
        if let idx, !store.items.isEmpty { select(store.items[min(idx, store.items.count - 1)].id) }
    }

    private func openSelected() {
        guard let id = selectedID, let item = store.item(id: id) else { return }
        open(item)
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

    func tileOpen(_ tile: ItemTileView) { open(tile.item) }

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
        guard !insideShelf, !operation.isEmpty, settingsProvider().removeAfterDragOut else { return }
        // Keep owned files around for a while: the destination may still be reading them.
        store.remove(id: tile.item.id, deferDeletion: true)
    }

    // MARK: Quick Look

    private var previewURLs: [URL] {
        guard let id = selectedID, let item = store.item(id: id) else { return [] }
        return item.urls
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

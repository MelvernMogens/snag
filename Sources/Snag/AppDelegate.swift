import AppKit
import ServiceManagement
import ShelfKit

final class AppDelegate: NSObject, NSApplicationDelegate, ShelfViewDelegate {
    private var store: ShelfStore!
    private var factory: ItemFactory!
    private var settings = Settings.load()

    private var panel: ShelfPanel!
    private var shelfView: ShelfView!
    private var statusItem: NSStatusItem!
    private let dragMonitor = DragMonitor()
    private var hotKeys: [HotKey] = []
    private var settingsWindow: SettingsWindowController?

    private var shown = false
    private var pinned = false          // opened manually: stays until toggled/Esc
    private var dropHover = false
    private var hideWork: DispatchWorkItem?
    private var currentScreen: NSScreen?
    private var moveMonitors: [Any] = []
    private var edgeDwell: DispatchWorkItem?

    // MARK: Launch

    func applicationDidFinishLaunching(_ note: Notification) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = ProcessInfo.processInfo.environment["SNAG_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? support.appendingPathComponent("Snag", isDirectory: true)
        store = ShelfStore(root: root)
        store.load()
        factory = ItemFactory(itemsDirectory: store.itemsDirectory)

        panel = ShelfPanel()
        shelfView = ShelfView(store: store, factory: factory)
        shelfView.delegate = self
        shelfView.settingsProvider = { [weak self] in self?.settings ?? Settings() }
        panel.contentView = shelfView
        store.onChange = { [weak self] in self?.storeChanged() }

        buildStatusItem()
        registerHotKeys()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        dragMonitor.onChange = { [weak self] s in self?.dragChanged(s) }
        dragMonitor.start()
        startEdgeHoverMonitor()

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(revalidate),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)

        if !store.isEmpty && settings.stayVisibleWithItems { show(animated: false) }
        if ProcessInfo.processInfo.environment["SNAG_SHOW_ON_LAUNCH"] == "1" { pinned = true; show(animated: false) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        pinned = true
        show()
        return false
    }

    /// `open -a Snag file…`, Dock-icon drops, "Open With → Snag".
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        if let item = factory.files(files) { shelfReceived([item]) }
        for web in urls where !web.isFileURL {
            if let item = factory.link(web) { shelfReceived([item]) }
        }
    }

    // MARK: Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Snag")
            b.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func rebuildMenu(_ m: NSMenu) {
        m.removeAllItems()
        let count = store.items.count
        let header = NSMenuItem(title: count == 0 ? "Shelf is empty" : "\(count) item\(count == 1 ? "" : "s") on shelf",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        m.addItem(header)
        m.addItem(.separator())
        let toggle = ClosureMenuItem(title: shown ? "Hide Shelf" : "Show Shelf") { [weak self] in self?.toggleShelf() }
        toggle.keyEquivalent = "y"
        toggle.keyEquivalentModifierMask = [.option, .command]
        m.addItem(toggle)
        let clip = ClosureMenuItem(title: "Add Clipboard to Shelf") { [weak self] in self?.addClipboard() }
        clip.keyEquivalent = "v"
        clip.keyEquivalentModifierMask = [.control, .option, .command]
        m.addItem(clip)
        let clear = ClosureMenuItem(title: "Clear Shelf") { [weak self] in self?.shelfClearAll() }
        clear.isEnabled = count > 0
        m.addItem(clear)
        m.addItem(.separator())

        let edgeMenu = NSMenu()
        for e in ShelfEdge.allCases {
            let mi = ClosureMenuItem(title: e.label) { [weak self] in self?.update { $0.edge = e } }
            mi.state = settings.edge == e ? .on : .off
            edgeMenu.addItem(mi)
        }
        let edge = NSMenuItem(title: "Screen Edge", action: nil, keyEquivalent: "")
        edge.submenu = edgeMenu
        m.addItem(edge)
        m.addItem(ClosureMenuItem(title: "Settings…", keyEquivalent: ",") { [weak self] in self?.openSettings() })
        m.addItem(.separator())
        m.addItem(ClosureMenuItem(title: "Quit Snag", keyEquivalent: "q") { NSApp.terminate(nil) })
    }

    private func registerHotKeys() {
        // ⌥⌘Y toggle shelf, ⌃⌥⌘V add clipboard. Carbon modifier bits: cmd 256, opt 2048, ctrl 4096.
        if let h = HotKey(id: 1, keyCode: 16, modifiers: 256 | 2048, handler: { [weak self] in self?.toggleShelf() }) {
            hotKeys.append(h)
        }
        if let h = HotKey(id: 2, keyCode: 9, modifiers: 256 | 2048 | 4096, handler: { [weak self] in self?.addClipboard() }) {
            hotKeys.append(h)
        }
    }

    // MARK: Actions

    func toggleShelf() {
        if shown { pinned = false; hide() } else { pinned = true; show() }
    }

    func addClipboard() {
        Ingest.read(.general, factory: factory, allowPromises: false) { [weak self] items in
            if items.isEmpty { NSSound.beep() } else { self?.shelfReceived(items) }
        }
    }

    private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings) { [weak self] new in
                self?.update { $0 = new }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    private func update(_ change: (inout Settings) -> Void) {
        let old = settings
        change(&settings)
        settings.save()
        if old.launchAtLogin != settings.launchAtLogin { applyLaunchAtLogin() }
        if old.edge != settings.edge, shown { reposition(animated: true) }
        settingsWindow?.refresh(settings)
    }

    private func applyLaunchAtLogin() {
        do {
            if settings.launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Snag: launch at login failed: \(error.localizedDescription)")
        }
    }

    // MARK: ShelfViewDelegate

    func shelfReceived(_ items: [ShelfItem]) {
        for item in items.reversed() { store.add(item) }
        if !shown { show() }
        if !pinned { scheduleHide(after: 1.2) }
    }

    func shelfClearAll() { NSLog("Snag: clear all"); store.clear() }

    func shelfDropTargetChanged(_ hovering: Bool) {
        dropHover = hovering
        if hovering { cancelHide() }
    }

    // MARK: Store

    private func storeChanged() {
        shelfView.reload()
        if shown {
            if store.isEmpty && settings.hideWhenEmpty && !pinned && !dragMonitor.state.active {
                scheduleHide(after: 0.4)
            } else {
                reposition(animated: true)
            }
        }
    }

    @objc private func revalidate() {
        if store.revalidate() { NSLog("Snag: revalidate changed items -> %ld", store.items.count) }
    }

    @objc private func screensChanged() {
        if let s = currentScreen, !NSScreen.screens.contains(s) { currentScreen = nil }
        if shown { reposition(animated: false) }
    }

    // MARK: Drag tracking -> show / hide

    private func dragChanged(_ s: DragMonitor.State) {
        if s.active {
            guard !shelfView.dragOutInProgress else { return }
            switch settings.showMode {
            case .onAnyDrag:
                if !shown { show(on: screen(containing: s.location)) }
                cancelHide()
            case .nearEdge:
                let scr = screen(containing: s.location) ?? NSScreen.main
                if let scr, ShelfGeometry.pointerNearEdge(s.location, edge: settings.edge, screen: scr.frame,
                                                          distance: settings.edgeDistance) {
                    if !shown { show(on: scr) }
                    cancelHide()
                }
            case .manual:
                break
            }
        } else {
            // Drag finished. Give a drop that just landed a moment to register before deciding.
            if shown && !pinned { scheduleHide(after: 0.5) }
        }
    }

    private func shouldStayVisible() -> Bool {
        if pinned || dropHover || dragMonitor.state.active || shelfView.dragOutInProgress { return true }
        if store.isEmpty { return false }
        if settings.stayVisibleWithItems { return true }
        return panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation)
    }

    private func scheduleHide(after delay: TimeInterval) {
        cancelHide()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.shouldStayVisible() {
                // Held open by something transient (pointer over it, a drag): check again later.
                let permanent = self.pinned || (self.settings.stayVisibleWithItems && !self.store.isEmpty)
                if !permanent { self.scheduleHide(after: 0.8) }
                return
            }
            self.hide()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelHide() {
        hideWork?.cancel()
        hideWork = nil
    }

    private func screen(containing p: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }
    }

    // MARK: Edge hover (reveal a shelf that holds items)

    private func startEdgeHoverMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] _ in self?.pointerMoved() }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler) { moveMonitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] e in
            self?.pointerMoved(); return e
        }) { moveMonitors.append(m) }
    }

    private func pointerMoved() {
        guard !shown, settings.revealOnEdgeHover, !store.isEmpty, !dragMonitor.state.active else {
            edgeDwell?.cancel(); edgeDwell = nil
            return
        }
        let p = NSEvent.mouseLocation
        guard let scr = screen(containing: p),
              ShelfGeometry.pointerNearEdge(p, edge: settings.edge, screen: scr.frame, distance: 2) else {
            edgeDwell?.cancel(); edgeDwell = nil
            return
        }
        guard edgeDwell == nil else { return }
        // Short dwell so flicking past the edge doesn't pop the shelf.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.edgeDwell = nil
            let now = NSEvent.mouseLocation
            guard !self.shown, let s2 = self.screen(containing: now),
                  ShelfGeometry.pointerNearEdge(now, edge: self.settings.edge, screen: s2.frame, distance: 3) else { return }
            self.show(on: s2)
            self.scheduleHide(after: 1.2)
        }
        edgeDwell = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    // MARK: Window motion

    private func show(on screen: NSScreen? = nil, animated: Bool = true) {
        cancelHide()
        let scr = screen ?? self.screen(containing: NSEvent.mouseLocation) ?? NSScreen.main
        guard let scr else { return }
        currentScreen = scr
        let vis = scr.visibleFrame
        let target = ShelfGeometry.frame(edge: settings.edge, itemCount: store.items.count, visible: vis)
        if !shown {
            shown = true
            let start = ShelfGeometry.hiddenFrame(edge: settings.edge, itemCount: store.items.count, visible: vis)
            panel.setFrame(animated ? start : target, display: false)
            panel.alphaValue = animated ? 0 : 1
            panel.orderFrontRegardless()
        }
        guard animated else { panel.setFrame(target, display: true); panel.alphaValue = 1; return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    private func reposition(animated: Bool) {
        guard shown, let scr = currentScreen ?? NSScreen.main else { return }
        let target = ShelfGeometry.frame(edge: settings.edge, itemCount: store.items.count, visible: scr.visibleFrame)
        guard target != panel.frame else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    private func hide() {
        cancelHide()
        guard shown else { return }
        shown = false
        pinned = false
        let scr = currentScreen ?? NSScreen.main
        let end = scr.map { ShelfGeometry.hiddenFrame(edge: settings.edge, itemCount: store.items.count, visible: $0.visibleFrame) }
            ?? panel.frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.shown else { return }
            self.panel.orderOut(nil)
        })
    }

    // MARK: Services ("Send to Snag")

    @objc func addToShelf(_ pb: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        Ingest.read(pb, factory: factory, allowPromises: false) { [weak self] items in
            if !items.isEmpty { self?.shelfReceived(items) }
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }
}

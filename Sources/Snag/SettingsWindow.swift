import AppKit
import ShelfKit

/// Small native preferences window. Every control writes straight through `onChange`.
final class SettingsWindowController: NSWindowController {
    private var settings: Settings
    private let onChange: (Settings) -> Void

    private let edgePopup = NSPopUpButton()
    private let modePopup = NSPopUpButton()
    private let removeAfterDrag = NSButton(checkboxWithTitle: "Remove items after dragging them out", target: nil, action: nil)
    private let hideWhenEmpty = NSButton(checkboxWithTitle: "Hide the shelf when it becomes empty", target: nil, action: nil)
    private let stayVisible = NSButton(checkboxWithTitle: "Keep the shelf visible while it holds items", target: nil, action: nil)
    private let launchAtLogin = NSButton(checkboxWithTitle: "Launch Snag at login", target: nil, action: nil)
    private let edgeHover = NSButton(checkboxWithTitle: "Show items when the pointer touches the screen edge", target: nil, action: nil)

    init(settings: Settings, onChange: @escaping (Settings) -> Void) {
        self.settings = settings
        self.onChange = onChange
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 290),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Snag Settings"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        build()
        refresh(settings)
        w.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        for e in ShelfEdge.allCases { edgePopup.addItem(withTitle: e.label) }
        for m in ShowMode.allCases { modePopup.addItem(withTitle: m.label) }
        for c in [edgePopup, modePopup, removeAfterDrag, hideWhenEmpty, stayVisible, edgeHover, launchAtLogin] as [NSControl] {
            c.target = self
            c.action = #selector(changed)
        }
        let hint = NSTextField(wrappingLabelWithString:
            "Shortcuts: ⌥⌘Y show/hide the shelf · ⌃⌥⌘V add clipboard. In the shelf: Return = rename, Space = Quick Look, ⌫ = remove, ⌘V = paste.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Dock to:"), edgePopup],
            [NSTextField(labelWithString: "Show shelf:"), modePopup],
            [NSGridCell.emptyContentView, removeAfterDrag],
            [NSGridCell.emptyContentView, hideWhenEmpty],
            [NSGridCell.emptyContentView, stayVisible],
            [NSGridCell.emptyContentView, edgeHover],
            [NSGridCell.emptyContentView, launchAtLogin],
            [NSGridCell.emptyContentView, hint],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false
        hint.preferredMaxLayoutWidth = 300
        let content = window!.contentView!
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])
    }

    func refresh(_ s: Settings) {
        settings = s
        edgePopup.selectItem(at: ShelfEdge.allCases.firstIndex(of: s.edge) ?? 0)
        modePopup.selectItem(at: ShowMode.allCases.firstIndex(of: s.showMode) ?? 0)
        removeAfterDrag.state = s.removeAfterDragOut ? .on : .off
        hideWhenEmpty.state = s.hideWhenEmpty ? .on : .off
        stayVisible.state = s.stayVisibleWithItems ? .on : .off
        edgeHover.state = s.revealOnEdgeHover ? .on : .off
        launchAtLogin.state = s.launchAtLogin ? .on : .off
    }

    @objc private func changed() {
        var s = settings
        s.edge = ShelfEdge.allCases[max(0, edgePopup.indexOfSelectedItem)]
        s.showMode = ShowMode.allCases[max(0, modePopup.indexOfSelectedItem)]
        s.removeAfterDragOut = removeAfterDrag.state == .on
        s.hideWhenEmpty = hideWhenEmpty.state == .on
        s.stayVisibleWithItems = stayVisible.state == .on
        s.revealOnEdgeHover = edgeHover.state == .on
        s.launchAtLogin = launchAtLogin.state == .on
        settings = s
        onChange(s)
    }
}

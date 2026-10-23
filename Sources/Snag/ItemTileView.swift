import AppKit
import ShelfKit

protocol ItemTileDelegate: AnyObject {
    func tileSelected(_ tile: ItemTileView)
    func tileOpen(_ tile: ItemTileView)
    func tileRemove(_ tile: ItemTileView)
    func tileQuickLook(_ tile: ItemTileView)
    func tileMenu(_ tile: ItemTileView) -> NSMenu
    func tileDragBegan(_ tile: ItemTileView)
    /// `operation` is what the destination did; `insideShelf` = dropped back onto the shelf.
    func tileDragEnded(_ tile: ItemTileView, operation: NSDragOperation, insideShelf: Bool)
}

/// One shelf item: thumbnail (fanned for stacks), two-line label, hover × to remove.
/// Dragging it out hands real file URLs (plus text / URL flavours) to the destination.
final class ItemTileView: NSView, NSDraggingSource {
    static let thumbSide: CGFloat = 60

    private(set) var item: ShelfItem
    weak var delegate: ItemTileDelegate?
    var isSelected = false { didSet { needsDisplay = true } }

    private var thumbs: [NSImage] = []
    private var hovering = false { didSet { needsDisplay = true } }
    private var mouseDownPoint: NSPoint?
    private var tracking: NSTrackingArea?

    init(item: ShelfItem) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: ShelfGeometry.width - 12, height: ShelfGeometry.tile))
        loadThumbs()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.displayTitle)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: ShelfGeometry.tile) }

    func update(_ newItem: ShelfItem) {
        let changed = newItem.entries.map(\.path) != item.entries.map(\.path)
        item = newItem
        setAccessibilityLabel(item.displayTitle)
        if changed { loadThumbs() }
        needsDisplay = true
    }

    private func loadThumbs() {
        let side = Self.thumbSide
        let urls = Array(item.urls.prefix(3))
        thumbs = urls.enumerated().map { idx, url in
            Thumbnails.shared.image(for: url, size: NSSize(width: side * 2, height: side * 2)) { [weak self] img in
                guard let self, idx < self.thumbs.count, self.item.urls.prefix(3).contains(url) else { return }
                self.thumbs[idx] = img
                self.needsDisplay = true
            }
        }
    }

    // MARK: Drawing

    private var closeRect: NSRect { NSRect(x: bounds.maxX - 17, y: 3, width: 14, height: 14) }

    override func draw(_ dirty: NSRect) {
        let bg = bounds.insetBy(dx: 2, dy: 2)
        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: bg, xRadius: 9, yRadius: 9).fill()
        } else if hovering {
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bg, xRadius: 9, yRadius: 9).fill()
        }

        let side = Self.thumbSide
        let base = NSRect(x: (bounds.width - side) / 2, y: 5, width: side, height: side)
        if item.isStack {
            // Pile: back cards peek out up-right behind the front one (flipped coords: -y is up).
            let front = base.insetBy(dx: 5, dy: 5).offsetBy(dx: -4, dy: 4)
            for (i, img) in thumbs.enumerated().reversed() {
                let r = front.offsetBy(dx: CGFloat(i) * 6, dy: CGFloat(-i) * 6)
                drawThumb(img, in: r, shadow: true)
            }
            drawBadge("\(item.entries.count)", near: base.offsetBy(dx: 0, dy: 4))
        } else if let img = thumbs.first {
            drawThumb(img, in: base, shadow: item.kind != .file)
        }
        if item.kind == .link { drawBadge("↗", near: base) }

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingMiddle
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            .paragraphStyle: para,
        ]
        let label = NSAttributedString(string: item.displayTitle, attributes: attrs)
        label.draw(with: NSRect(x: 6, y: base.maxY + 3, width: bounds.width - 12, height: 28),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        if hovering {
            let c = closeRect
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(ovalIn: c).fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let x = NSBezierPath()
            x.lineWidth = 1.3
            x.move(to: NSPoint(x: c.minX + 4.5, y: c.minY + 4.5)); x.line(to: NSPoint(x: c.maxX - 4.5, y: c.maxY - 4.5))
            x.move(to: NSPoint(x: c.maxX - 4.5, y: c.minY + 4.5)); x.line(to: NSPoint(x: c.minX + 4.5, y: c.maxY - 4.5))
            x.stroke()
        }
    }

    private func drawThumb(_ img: NSImage, in rect: NSRect, shadow: Bool) {
        let fit = aspectFit(img.size, in: rect)
        NSGraphicsContext.saveGraphicsState()
        if shadow {
            let s = NSShadow()
            s.shadowBlurRadius = 3
            s.shadowOffset = NSSize(width: 0, height: -1)
            s.shadowColor = NSColor.black.withAlphaComponent(0.45)
            s.set()
        }
        img.draw(in: fit, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawBadge(_ text: String, near r: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: NSColor.white,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        let w = max(sz.width + 8, 15)
        let badge = NSRect(x: r.maxX - w + 4, y: r.maxY - 13, width: w, height: 15)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: badge, xRadius: 7.5, yRadius: 7.5).fill()
        s.draw(at: NSPoint(x: badge.midX - sz.width / 2, y: badge.midY - sz.height / 2))
    }

    private func aspectFit(_ size: NSSize, in r: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return r }
        let s = min(r.width / size.width, r.height / size.height)
        let w = size.width * s, h = size.height * s
        return NSRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if hovering, closeRect.insetBy(dx: -3, dy: -3).contains(p) {
            delegate?.tileRemove(self); return
        }
        mouseDownPoint = p
        delegate?.tileSelected(self)
        if event.clickCount == 2 { delegate?.tileOpen(self) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - start.x, p.y - start.y) > 3 else { return }
        mouseDownPoint = nil
        beginDragOut(event)
    }

    override func mouseUp(with event: NSEvent) { mouseDownPoint = nil }

    override func menu(for event: NSEvent) -> NSMenu? {
        delegate?.tileSelected(self)
        return delegate?.tileMenu(self)
    }

    // MARK: Drag out

    /// Pasteboard writers for this item: one per file, each backed by a real `NSURL` so AppKit
    /// attaches the sandbox extension that sandboxed destinations (WhatsApp, Mail, Messages,
    /// Slack from the App Store) need to read the file. A raw `public.file-url` string has no
    /// extension and those apps silently reject the drop. Text and links add their content.
    func pasteboardWriters() -> [NSPasteboardWriting] {
        item.entries.map { entry in
            var extras: [NSPasteboard.PasteboardType: String] = [:]
            switch item.kind {
            case .text:
                if let t = item.text { extras[.string] = t }
            case .link:
                if let t = item.text { extras[.string] = t; extras[Ingest.urlName] = item.title }
            case .file, .image:
                break
            }
            return FileDragWriter(url: entry.url, extras: extras)
        }
    }

    private func beginDragOut(_ event: NSEvent) {
        let side = Self.thumbSide
        let start = NSRect(x: (bounds.width - side) / 2, y: 6, width: side, height: side)
        let dragItems: [NSDraggingItem] = pasteboardWriters().enumerated().map { i, writer in
            let di = NSDraggingItem(pasteboardWriter: writer)
            let img = i < thumbs.count ? thumbs[i] : (thumbs.first ?? NSImage())
            di.setDraggingFrame(start.offsetBy(dx: CGFloat(i) * 4, dy: CGFloat(i) * 4), contents: img)
            return di
        }
        guard !dragItems.isEmpty else { return }
        delegate?.tileDragBegan(self)
        let session = beginDraggingSession(with: dragItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Outside: behave like Finder (move on the same volume, copy across volumes).
        context == .outsideApplication ? [.copy, .move, .link, .generic, .delete] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let inside = window?.frame.contains(screenPoint) ?? false
        delegate?.tileDragEnded(self, operation: operation, insideShelf: inside)
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { false }
}

/// Writes a file URL exactly the way `NSURL` does (including its sandbox extension and the
/// file's content type), plus optional extra flavours such as plain text.
final class FileDragWriter: NSObject, NSPasteboardWriting {
    private let url: NSURL
    private let extras: [NSPasteboard.PasteboardType: String]

    init(url: URL, extras: [NSPasteboard.PasteboardType: String]) {
        self.url = url as NSURL
        self.extras = extras
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        let own = url.writableTypes(for: pasteboard)
        return own + extras.keys.filter { !own.contains($0) }
    }

    func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        extras[type] != nil ? [] : url.writingOptions(forType: type, pasteboard: pasteboard)
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if let s = extras[type] { return s }
        return url.pasteboardPropertyList(forType: type)
    }
}

import AppKit

/// Detects drags happening anywhere on screen, in any app, without Accessibility permission.
///
/// A drag session always writes to the system drag pasteboard. So: snapshot its changeCount
/// when the mouse goes down; while the button stays down, a changed count plus real movement
/// means a drag is in progress. Global mouse monitors don't need permission, and the polling
/// only runs while a button is held.
final class DragMonitor {
    struct State: Equatable {
        var active = false
        var location = CGPoint.zero
    }

    var onChange: ((State) -> Void)?
    private(set) var state = State()

    private let dragPB = NSPasteboard(name: .drag)
    private var baseline = 0
    private var startPoint = CGPoint.zero
    private var monitors: [Any] = []
    private var timer: Timer?

    func start() {
        baseline = dragPB.changeCount
        let down: (NSEvent) -> Void = { [weak self] _ in self?.mouseDown() }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: down) { monitors.append(m) }
        // Drags that start inside Snag's own windows come through the local monitor.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] e in
            self?.mouseDown(); return e
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged], handler: { [weak self] _ in
            self?.ensurePolling()
        }) { monitors.append(m) }
    }

    private func mouseDown() {
        baseline = dragPB.changeCount
        startPoint = NSEvent.mouseLocation
        ensurePolling()
    }

    private func ensurePolling() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let down = NSEvent.pressedMouseButtons & 1 == 1
        let loc = NSEvent.mouseLocation
        var next = state
        next.location = loc
        if down {
            if !state.active, dragPB.changeCount != baseline,
               hypot(loc.x - startPoint.x, loc.y - startPoint.y) >= 4 {
                next.active = true
            }
        } else {
            next.active = false
            timer?.invalidate()
            timer = nil
            baseline = dragPB.changeCount
        }
        if next != state {
            state = next
            onChange?(state)
        }
    }
}

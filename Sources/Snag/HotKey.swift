import Carbon.HIToolbox

/// System-wide hotkeys via Carbon's RegisterEventHotKey — works without Accessibility permission.
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false
    private var ref: EventHotKeyRef?
    private let id: UInt32

    init?(id: UInt32, keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        self.id = id
        HotKey.installHandler()
        let hkID = EventHotKeyID(signature: OSType(0x534E4147) /* 'SNAG' */, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        HotKey.handlers[id] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.handlers[id] = nil
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { HotKey.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

import AppKit
import Carbon

final class KeyMonitor {
    var changed: (Set<String>) -> Void = { _ in }
    var interrupted: () -> Void = {}
    var foregroundAllowed: () -> Bool = { false }
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var guardTimer: Timer?
    private var keys = PhysicalKeys()
    var running: Bool { port != nil }
    #if SAGE_QA
    var simulateDenied=false
    #endif
    private var hasAccess:Bool {
        #if SAGE_QA
        if simulateDenied {return false}
        #endif
        return Self.authorized
    }

    static func safeSession() -> Bool {
        guard !IsSecureEventInputEnabled(),
              let s = CGSessionCopyCurrentDictionary() as? [String:Any],
              s[kCGSessionOnConsoleKey as String] as? Bool == true,
              s[kCGSessionLoginDoneKey as String] as? Bool == true else { return false }
        return s["CGSSessionScreenIsLocked"] as? Bool != true
    }
    static var authorized: Bool { CGPreflightListenEventAccess() }

    func start() -> Bool {
        guard !running else { return true }
        guard hasAccess, Self.safeSession(), foregroundAllowed() else { return false }
        let mask = [CGEventType.keyDown,.keyUp,.flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap:.cgSessionEventTap, place:.tailAppendEventTap, options:.listenOnly,
            eventsOfInterest:mask, callback:{ _, type, event, ref in
                if let ref = ref { Unmanaged<KeyMonitor>.fromOpaque(ref).takeUnretainedValue().receive(type,event) }
                return Unmanaged.passUnretained(event)
            }, userInfo:Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let signal = CFMachPortCreateRunLoopSource(nil,tap,0) else {
            CFMachPortInvalidate(tap); return false
        }
        port=tap; source=signal
        CFRunLoopAddSource(CFRunLoopGetMain(),signal,.commonModes)
        CGEvent.tapEnable(tap:tap,enable:true)
        let timer=Timer(timeInterval:0.75,repeats:true) { [weak self] _ in
            guard let self=self else { return }
            if !self.hasAccess || !Self.safeSession() || !self.foregroundAllowed() { self.interrupted() }
        }
        timer.tolerance=0.15
        RunLoop.main.add(timer,forMode:.common)
        guardTimer=timer
        return true
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) {
        // Fail closed before inspecting even the physical key field.
        guard running, type != .tapDisabledByTimeout, type != .tapDisabledByUserInput,
              hasAccess, Self.safeSession(), foregroundAllowed() else { interrupted(); return }
        let num=event.getIntegerValueField(.keyboardEventKeycode)
        if keys.apply(type,num,event.flags,repeated:type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0) {
            changed(keys.held)
        }
    }
    func stop() {
        guardTimer?.invalidate(); guardTimer=nil
        if let tap=port {
            CGEvent.tapEnable(tap:tap,enable:false)
            if let s=source { CFRunLoopRemoveSource(CFRunLoopGetMain(),s,.commonModes) }
            CFMachPortInvalidate(tap)
        }
        source=nil; port=nil; keys.clear()
    }
    deinit { stop() }
}

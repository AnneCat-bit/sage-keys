import AppKit
import Carbon

protocol PhysicalMonitoring: AnyObject {
    var changed: (Set<String>) -> Void { get set }
    var interrupted: () -> Void { get set }
    var foregroundChanged: () -> Void { get set }
    var foregroundAllowed: () -> Bool { get set }
    var running: Bool { get }
    var hasAccess: Bool { get }
    func requestListenAccess()
    func start() -> Bool
    func stop()
}

final class KeyMonitor: PhysicalMonitoring {
    var changed: (Set<String>) -> Void = { _ in }
    var interrupted: () -> Void = {}
    var foregroundAllowed: () -> Bool = { false }
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    var foregroundChanged: () -> Void = {}
    private var keys = PhysicalKeys()
    var running: Bool { port != nil }
    #if SAGE_QA
    var simulateDenied=false
    #endif
    var hasAccess:Bool {
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
    // Only called directly from the user's consent/start action, never on launch or recheck.
    func requestListenAccess() { _ = CGRequestListenEventAccess() }
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
        return true
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) {
        // Fail closed before inspecting even the physical key field.
        guard running else {return}
        guard type != .tapDisabledByTimeout, type != .tapDisabledByUserInput,
              hasAccess, Self.safeSession() else { interrupted(); return }
        guard foregroundAllowed() else { foregroundChanged(); return }
        let num=event.getIntegerValueField(.keyboardEventKeycode)
        if keys.apply(type,num,event.flags,repeated:type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0) {
            changed(keys.held)
        }
    }
    func stop() {
        if let tap=port {
            CGEvent.tapEnable(tap:tap,enable:false)
            if let s=source { CFRunLoopRemoveSource(CFRunLoopGetMain(),s,.commonModes) }
            CFMachPortInvalidate(tap)
        }
        source=nil; port=nil; keys.clear()
    }
    deinit { stop() }
}

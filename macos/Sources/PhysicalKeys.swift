import CoreGraphics

// Only the 82 positions engraved on the Sage 75 are representable.
struct PhysicalKeys {
    static let names: [Int64: String] = [
        0:"KeyA",1:"KeyS",2:"KeyD",3:"KeyF",4:"KeyH",5:"KeyG",6:"KeyZ",7:"KeyX",8:"KeyC",9:"KeyV",
        11:"KeyB",12:"KeyQ",13:"KeyW",14:"KeyE",15:"KeyR",16:"KeyY",17:"KeyT",18:"Digit1",19:"Digit2",
        20:"Digit3",21:"Digit4",22:"Digit6",23:"Digit5",24:"Equal",25:"Digit9",26:"Digit7",27:"Minus",
        28:"Digit8",29:"Digit0",30:"BracketRight",31:"KeyO",32:"KeyU",33:"BracketLeft",34:"KeyI",35:"KeyP",
        36:"Enter",37:"KeyL",38:"KeyJ",39:"Quote",40:"KeyK",41:"Semicolon",42:"Backslash",43:"Comma",
        44:"Slash",45:"KeyN",46:"KeyM",47:"Period",48:"Tab",49:"Space",50:"Backquote",51:"Backspace",
        53:"Escape",54:"MetaRight",55:"MetaLeft",56:"ShiftLeft",57:"CapsLock",58:"AltLeft",59:"ControlLeft",
        60:"ShiftRight",61:"AltRight",62:"ControlRight",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",
        101:"F9",103:"F11",109:"F10",111:"F12",115:"Home",116:"PageUp",117:"Delete",118:"F4",119:"End",
        120:"F2",121:"PageDown",122:"F1",123:"ArrowLeft",124:"ArrowRight",125:"ArrowDown",126:"ArrowUp"
    ]
    // Side-specific device flag masks from Apple's IOLLEvent.h.
    private static let modifier: [Int64:(UInt64, CGEventFlags)] = [
        54:(0x10,.maskCommand),55:(0x8,.maskCommand),56:(0x2,.maskShift),60:(0x4,.maskShift),
        58:(0x20,.maskAlternate),61:(0x40,.maskAlternate),59:(0x1,.maskControl),62:(0x2000,.maskControl)
    ]
    private(set) var held = Set<String>()

    mutating func clear() { held.removeAll() }

    mutating func apply(_ type: CGEventType, _ number: Int64, _ flags: CGEventFlags, repeated: Bool) -> Bool {
        guard !repeated, let name = Self.names[number] else { return false }
        let down: Bool
        switch type {
        case .keyDown: down = true
        case .keyUp: down = false
        case .flagsChanged:
            if number == 57 { down = flags.contains(.maskAlphaShift) }
            else if let (mask, aggregate) = Self.modifier[number] {
                let family = Self.modifier.values.filter { $0.1 == aggregate }.reduce(UInt64(0)) { $0 | $1.0 }
                down = flags.rawValue & family != 0 ? flags.rawValue & mask != 0 : (flags.contains(aggregate) && !held.contains(name))
            } else { return false }
        default: return false
        }
        return down ? held.insert(name).inserted : held.remove(name) != nil
    }
}

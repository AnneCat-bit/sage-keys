// Runs only on an empty CI desktop. Read System Settings labels, never click a control.
import AppKit
import ApplicationServices

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
}

func visiblePane(_ requested: String) -> (Bool, String) {
    guard let settings = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else { return (false, "not running") }
    let app = AXUIElementCreateApplication(settings.processIdentifier)
    let wins = attr(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    let titles = wins.compactMap {attr($0, kAXTitleAttribute) as? String}
    if titles.contains(requested) {return (true, "AX window title: " + requested)}
    // A list row labelled Input Monitoring also exists on its parent page.
    // Require distinctive detail text if the window title doesn't identify the pane.
    if requested == "Input Monitoring" {
        var nodes = wins
        var seen = 0
        while let el = nodes.popLast(), seen < 1400 {
            seen += 1
            for key in [kAXDescriptionAttribute, kAXValueAttribute, kAXTitleAttribute] {
                guard let line = attr(el,key) as? String else {continue}
                let lower = line.lowercased()
                if lower.contains("monitor") && lower.contains("keyboard") && (lower.contains("app") || lower.contains("input")) {
                    return (true, "AX detail text: " + line)
                }
            }
            nodes += attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
    }
    return (false, "AX titles: " + titles.joined(separator: ", "))
}
let trusted = AXIsProcessTrusted()
print("OS", ProcessInfo.processInfo.operatingSystemVersionString, "existing read-only QA AX access:", trusted)
var failed = false
for (detail, title) in [(false,"Privacy & Security"),(true,"Input Monitoring")] {
    let delivery = SettingsLinks.open(inputPane: detail)
    let end = Date().addingTimeInterval(12)
    var observed = (false,"no existing QA accessibility access")
    repeat {
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        if trusted {observed = visiblePane(title)}
    } while trusted && !observed.0 && Date() < end
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
    if trusted && !observed.0 {failed = true}
    print("expected=\(title) dispatch=\(delivery.rawValue) foreground=\(front) exactPaneVerified=\(observed.0) evidence=\(observed.1)")
}
if failed {exit(1)}

// Separate CI helper reads only the explicitly identified QA window's accessibility tree.
import AppKit
import ApplicationServices
guard let pid=Int32(CommandLine.arguments[1]), NSRunningApplication(processIdentifier:pid)?.bundleIdentifier == "io.github.annecat-bit.sagekeys.qa" else {exit(2)}
func get(_ e:AXUIElement,_ key:String)->CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(e,key as CFString,&value) == .success ? value:nil
}
let trusted=AXIsProcessTrusted()
let application=AXUIElementCreateApplication(pid)
let wins=get(application,kAXWindowsAttribute) as? [AXUIElement] ?? []
var todo=wins.filter {get($0,kAXTitleAttribute) as? String == "Sage Keys · 輸入監察導覽"}
var checked=false, image=false, heading=false
while let el=todo.popLast() {
    let role=get(el,kAXRoleAttribute) as? String ?? ""
    let strings=[kAXTitleAttribute,kAXDescriptionAttribute,kAXValueAttribute].compactMap {get(el,$0) as? String}
    if role == "AXButton" && strings.contains("重新檢查權限"){checked=true}
    if role == "AXImage" && strings.contains(where:{$0.contains("放大鏡")}){image=true}
    if strings.contains("已開啟，但尚未生效"){heading=true}
    todo += get(el,kAXChildrenAttribute) as? [AXUIElement] ?? []
}
let result=["existingQAAccess":trusted,"recheckButton":checked,"illustrationDescription":image,"mismatchHeading":heading]
print(String(decoding:try JSONEncoder().encode(result),as:UTF8.self))

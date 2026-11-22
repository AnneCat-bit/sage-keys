// Dedicated GitHub runner only. AX and mouse operations target Finder and this test build.
import AppKit
import ApplicationServices

struct CheckError: Error, CustomStringConvertible {
    let description: String
    init(_ message:String){description=message}
}
func require(_ condition:Bool,_ why:String) throws {if !condition {throw CheckError(why)}}
func wait(_ label:String,_ predicate:()->Bool) throws {
    let end=Date().addingTimeInterval(14)
    repeat {
        RunLoop.current.run(until:Date().addingTimeInterval(0.12))
        if predicate() {return}
    } while Date() < end
    throw CheckError(label)
}
func attr(_ element:AXUIElement,_ key:String)->CFTypeRef? {
    var value:CFTypeRef?
    return AXUIElementCopyAttributeValue(element,key as CFString,&value) == .success ? value:nil
}
func window(_ app:NSRunningApplication,_ title:String)->AXUIElement? {
    let root=AXUIElementCreateApplication(app.processIdentifier)
    let all=attr(root,kAXWindowsAttribute) as? [AXUIElement] ?? []
    return all.first {attr($0,kAXTitleAttribute) as? String == title}
}
func elements(_ root:AXUIElement)->[AXUIElement] {
    var pending=[root], result=[AXUIElement]()
    while let el=pending.popLast(), result.count<800 {
        result.append(el);pending += attr(el,kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    return result
}
func strings(_ el:AXUIElement)->[String] {
    [kAXTitleAttribute,kAXDescriptionAttribute,kAXValueAttribute].compactMap {attr(el,$0) as? String}
}
func click(_ app:NSRunningApplication,_ title:String,_ button:String) throws {
    var found:AXUIElement?
    try wait("missing actionable "+button){
        if let w=window(app,title) {
            found=elements(w).first {attr($0,kAXRoleAttribute) as? String == "AXButton" && strings($0).contains(button)}
        }
        return found != nil
    }
    // NSMenu tracking can block synchronous AXPress until it times out. Click the
    // real button at its AX-reported coordinates, as a user would, then inspect it.
    guard let pos=attr(found!,kAXPositionAttribute),let size=attr(found!,kAXSizeAttribute),
          CFGetTypeID(pos)==AXValueGetTypeID(),CFGetTypeID(size)==AXValueGetTypeID() else {throw CheckError("button geometry "+button)}
    var p=CGPoint.zero,s=CGSize.zero
    AXValueGetValue(pos as! AXValue,.cgPoint,&p);AXValueGetValue(size as! AXValue,.cgSize,&s)
    let center=CGPoint(x:p.x+s.width/2,y:p.y+s.height/2)
    CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:center,mouseButton:.left)?.post(tap:.cghidEventTap)
    RunLoop.current.run(until:Date().addingTimeInterval(0.08))
    CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:center,mouseButton:.left)?.post(tap:.cghidEventTap)
}
func open(_ url:URL, separateInstance:Bool = false) throws -> NSRunningApplication {
    let config=NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance=separateInstance
    var proc:NSRunningApplication?, failure:Error?
    NSWorkspace.shared.openApplication(at:url,configuration:config){proc=$0;failure=$1}
    try wait("Launch Services completion"){proc != nil || failure != nil}
    if let proc=proc {return proc}
    throw failure ?? CheckError("no running application")
}
func quit(_ proc:NSRunningApplication) throws {
    try require(proc.terminate(),"quit rejected");try wait("process did not quit"){proc.isTerminated}
}
func log(_ fields:[String:Any]) throws {
    print("DMG_TEST "+String(decoding:try JSONSerialization.data(withJSONObject:fields,options:.sortedKeys),as:UTF8.self))
}
func command(_ executable:String,_ args:[String]) throws -> String {
    let process=Process(), pipe=Pipe()
    process.executableURL=URL(fileURLWithPath:executable);process.arguments=args;process.standardOutput=pipe
    try process.run()
    let data=pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try require(process.terminationStatus==0,"command failed "+executable)
    return String(decoding:data,as:UTF8.self)
}
func capture(_ app:NSRunningApplication,_ name:String,_ destination:String) throws {
    let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
    guard let id=windows.first(where:{($0[kCGWindowOwnerPID as String] as? Int32)==app.processIdentifier &&
        ($0[kCGWindowName as String] as? String)==name})?[kCGWindowNumber as String] as? Int else {throw CheckError("window capture "+name)}
    _ = try command("/usr/sbin/screencapture",["-x","-o","-l",String(id),destination])
}
func description(_ app:NSRunningApplication,_ title:String)->String {
    guard let view=window(app,title) else {return ""}
    return elements(view).flatMap(strings).joined(separator:"\n")
}
func drag(_ from:CGPoint,_ to:CGPoint) {
    CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:from,mouseButton:.left)?.post(tap:.cghidEventTap)
    RunLoop.current.run(until:Date().addingTimeInterval(0.25))
    for i in 1...28 {
        let fraction=Double(i)/28
        let point=CGPoint(x:from.x+(to.x-from.x)*fraction,y:from.y+(to.y-from.y)*fraction)
        CGEvent(mouseEventSource:nil,mouseType:.leftMouseDragged,mouseCursorPosition:point,mouseButton:.left)?.post(tap:.cghidEventTap)
        RunLoop.current.run(until:Date().addingTimeInterval(0.035))
    }
    CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:to,mouseButton:.left)?.post(tap:.cghidEventTap)
}
func run() throws {
    guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",AXIsProcessTrusted() else {throw CheckError("isolated GUI runner required")}
    let mount=URL(fileURLWithPath:CommandLine.arguments[1]), evidence=CommandLine.arguments[2]
    let fm=FileManager.default
    let installed=URL(fileURLWithPath:"/Applications/Sage Keys.app")
    let source=mount.appendingPathComponent("Sage Keys.app")
    let installTitle="Sage Keys · 安裝", guide="Sage Keys · 輸入監察導覽", pet="Sage 75"
    try require(!fm.fileExists(atPath:installed.path),"installation destination occupied")
    let downloads=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Downloads")
    try fm.createDirectory(at:downloads,withIntermediateDirectories:true)
    defer {try? fm.removeItem(at:downloads.deletingLastPathComponent())}
    let loose=downloads.appendingPathComponent("Sage Keys.app")
    try fm.copyItem(at:source,to:loose)
    let looseApp=try open(loose)
    try wait("download location gate"){window(looseApp,installTitle) != nil}
    try require(window(looseApp,guide)==nil,"download requested permission")
    try log(["step":"download-folder","installationGate":true,"path":looseApp.executableURL?.path ?? ""])
    try quit(looseApp)
    let fromDMG=try open(source)
    try wait("installation gate for DMG"){window(fromDMG,installTitle) != nil}
    try require(window(fromDMG,guide)==nil,"DMG entered permission flow")
    try capture(fromDMG,installTitle,evidence+"/install-location.png")
    try log(["step":"launch-from-dmg","path":fromDMG.executableURL?.path ?? "", "installationGate":true,"permissionGuide":false])
    try quit(fromDMG)
    _ = try command("/usr/bin/osascript",["-e","tell application \"Finder\" to open POSIX file \""+mount.path+"\"","-e","tell application \"Finder\" to activate"])
    guard let finder=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.finder").first else {throw CheckError("Finder")}
    try wait("mounted Finder window"){window(finder,"Sage Keys") != nil}
    RunLoop.current.run(until:Date().addingTimeInterval(1))
    try capture(finder,"Sage Keys",evidence+"/dmg-finder.png")
    // Read actual AX geometry of the two icons after opening the final compressed image.
    let view=window(finder,"Sage Keys")!
    var points=[String:CGPoint]()
    var tree=[String]()
    for el in elements(view) {
        let names=strings(el)
        let role=attr(el,kAXRoleAttribute) as? String ?? ""
        tree.append(role+" "+names.joined(separator:" | "))
        guard role=="AXImage",let name=["Sage Keys.app","Applications"].first(where:{target in names.contains(where:{$0==target || $0==target.replacingOccurrences(of:".app",with:"")})}),
              let pos=attr(el,kAXPositionAttribute),let size=attr(el,kAXSizeAttribute),
              CFGetTypeID(pos)==AXValueGetTypeID(),CFGetTypeID(size)==AXValueGetTypeID() else {continue}
        var p=CGPoint.zero,s=CGSize.zero
        AXValueGetValue(pos as! AXValue,.cgPoint,&p);AXValueGetValue(size as! AXValue,.cgSize,&s)
        points[name]=CGPoint(x:p.x+s.width/2,y:p.y+min(s.height/2,48))
    }
    try tree.joined(separator:"\n").write(toFile:evidence+"/finder-ax.txt",atomically:true,encoding:.utf8)
    guard let from=points["Sage Keys.app"],let to=points["Applications"] else {throw CheckError("Finder icon geometry missing")}
    try require(from.x<to.x && abs(from.y-to.y)<10,"Finder arrangement")
    drag(from,to)
    try wait("Finder drag copied the application"){fm.fileExists(atPath:installed.appendingPathComponent("Contents/_CodeSignature/CodeResources").path)}
    try log(["step":"finder-drag","from":[from.x,from.y],"to":[to.x,to.y],"target":installed.path])
    // An old instance can survive a copy. Reproduce and require an explicit quit.
    let old=try open(source)
    try wait("disk instance gate"){window(old,installTitle) != nil}
    let newer=try open(installed,separateInstance:true)
    try wait("two processes gate"){description(newer,installTitle).contains("另一份 Sage Keys")}
    try require(window(newer,guide)==nil,"duplicate entered permission flow")
    try log(["step":"duplicate","oldPID":old.processIdentifier,"newPID":newer.processIdentifier,"blocked":true])
    try quit(newer);try quit(old)
    _ = try command("/usr/bin/hdiutil",["detach",mount.path])
    let app=try open(installed)
    try wait("installed pet"){window(app,pet) != nil}
    RunLoop.current.run(until:Date().addingTimeInterval(2))
    try require(window(app,installTitle)==nil && window(app,guide)==nil,"correct install looped")
    // Open the normal toolbar menu via AX, without choosing any synchronization or granting a permission.
    try click(app,pet,"桌寵選單")
    let root=AXUIElementCreateApplication(app.processIdentifier)
    var item:AXUIElement?
    try wait("diagnostic menu"){
        item=elements(root).first{strings($0).contains("檢查安裝與授權…")}
        return item != nil
    }
    try require(AXUIElementPerformAction(item!,kAXPressAction as CFString) == .success,"diagnostic menu action")
    try wait("installed self diagnosis"){description(app,guide).contains("proc_pidpath")}
    let text=description(app,guide)
    try require(text.contains("本次同步已關閉") || description(app,pet).contains("同步已關閉"),"automatic synchronization")
    try require(text.contains(installed.path+"/Contents/MacOS/SageKeys"),"actual installed path")
    try capture(app,guide,evidence+"/installed-diagnostic.png")
    try log(["step":"installed-relaunch","path":app.executableURL?.path ?? "",
             "installationPrompt":false,"diagnostic":text])
    try quit(app)
    // User Applications is a supported independent location.
    let user=try fm.url(for:.applicationDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("Sage Keys.app")
    try require(!fm.fileExists(atPath:user.path),"user Applications occupied")
    try fm.copyItem(at:installed,to:user)
    defer {try? fm.removeItem(at:user)}
    let userApp=try open(user)
    try wait("user Applications launch"){window(userApp,pet) != nil}
    RunLoop.current.run(until:Date().addingTimeInterval(1))
    try require(window(userApp,installTitle)==nil,"user Applications rejected")
    try log(["step":"user-applications","path":userApp.executableURL?.path ?? "", "installationPrompt":false])
    try quit(userApp)
}
do {try run()} catch {fputs("DMG check failed: \(error)\n",stderr);exit(1)}

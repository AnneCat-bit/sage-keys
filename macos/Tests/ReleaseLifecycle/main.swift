// Dedicated GitHub runner only. All AX operations target the two downloaded Sage Keys releases.
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
    try require(AXUIElementPerformAction(found!,kAXPressAction as CFString) == .success,"could not press "+button)
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
func readVersion(_ bundle:URL) throws -> String {
    let data=try Data(contentsOf:bundle.appendingPathComponent("Contents/Info.plist"))
    let info=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any]
    guard info?["CFBundleIdentifier"] as? String == "io.github.annecat-bit.sagekeys",
          let v=info?["CFBundleShortVersionString"] as? String else {throw CheckError("unexpected release")}
    return v
}
func log(_ fields:[String:Any]) throws {
    print("LIFECYCLE "+String(decoding:try JSONSerialization.data(withJSONObject:fields,options:.sortedKeys),as:UTF8.self))
}
func run() throws {
    let fm=FileManager.default
    guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true", CommandLine.arguments.count == 5,
          AXIsProcessTrusted() else {throw CheckError("requires isolated runner with existing QA AX access")}
    let installed=URL(fileURLWithPath:CommandLine.arguments[1])
    let extracted=URL(fileURLWithPath:CommandLine.arguments[2])
    let previous=URL(fileURLWithPath:CommandLine.arguments[3])
    let oldHash=CommandLine.arguments[4]
    let id="io.github.annecat-bit.sagekeys", guide="Sage Keys · 輸入監察導覽", pet="Sage 75"
    try require(installed.path == "/Applications/Sage Keys.app" && !fm.fileExists(atPath:previous.path),"unexpected installation path")
    let oldVersion=try readVersion(installed), newVersion=try readVersion(extracted)
    try require(oldVersion=="0.2.2","legacy preference reproduction requires the published 0.2.2 artifact")
    let prefs=UserDefaults(suiteName:id)!
    let keys=["inputGuide.pending.v1","inputGuide.resume","inputGuide.switchReportedOn","inputGuide.lastGrantedBuild","inputGuide.lastGrantedHash"]
    // Simulate a legacy draft and an earlier successful permission check. No change to system authorization.
    let prior=keys.map {prefs.object(forKey:$0)}
    defer {for (k,v) in zip(keys,prior) {prefs.set(v,forKey:k)};prefs.synchronize()}
    let data=try PropertyListSerialization.data(fromPropertyList:["help":[String:String]()],format:.binary,options:0)
    for (k,v) in zip(keys,[data,true,true,"4",oldHash] as [Any]) {prefs.set(v,forKey:k)}
    prefs.synchronize()
    let first=try open(installed)
    try wait("old guide auto-open"){window(first,guide) != nil}
    try quit(first)
    let old=try open(installed)
    try wait("repeated old guide"){window(old,guide) != nil}
    try click(old,guide,"檢查安裝與授權")
    let applications=try fm.url(for:.applicationDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
    let extra=applications.appendingPathComponent(installed.lastPathComponent)
    try require(!fm.fileExists(atPath:extra.path),"user Applications already occupied")
    try fm.copyItem(at:installed,to:extra)
    defer {try? fm.removeItem(at:extra)}
    func oldText() -> String {
        guard let view=window(old,guide) else {return ""}
        return elements(view).flatMap(strings).joined(separator:"\n")
    }
    let finder=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.finder").first
    finder?.activate(options:[.activateIgnoringOtherApps])
    try wait("focus Finder"){NSWorkspace.shared.frontmostApplication == finder}
    old.activate(options:[.activateIgnoringOtherApps])
    try wait("return to old diagnostic"){NSWorkspace.shared.frontmostApplication == old}
    RunLoop.current.run(until:Date().addingTimeInterval(0.45))
    try require(!oldText().contains(extra.path),"0.2.2 did not reproduce stale copy list")
    try click(old,guide,"重新檢查權限")
    try wait("explicit check discovers actual second copy"){oldText().contains(extra.path)}
    try fm.removeItem(at:extra)
    try log(["step":"old-diagnostic","focusReturnKeptOldSnapshot":true,"manualCheckFoundActualCopy":true])
    let reopened=try open(installed)
    try require(reopened.processIdentifier==old.processIdentifier,"Finder-style reopen did not reuse its process")
    // Both releases stay intact. Move the old bundle aside while its process still exists.
    try fm.moveItem(at:installed,to:previous)
    try fm.moveItem(at:extracted,to:installed)
    let diskVersion=try readVersion(installed)
    try require(diskVersion == newVersion && !old.isTerminated,"old process not alive after replacement")
    try log(["step":"replace","oldVersion":oldVersion,"firstPID":first.processIdentifier,"oldPID":old.processIdentifier,
             "finderReusedPID":reopened.processIdentifier,"oldAutoGuideLaunches":2,"oldAliveAfterReplacement":true,
             "installedPath":installed.path,"diskVersion":diskVersion])
    // Launch a separate copy only on the test machine to observe two live processes.
    let parallel=try open(installed,separateInstance:true)
    try require(parallel.processIdentifier != old.processIdentifier,"second instance not created")
    try click(parallel,pet,"授權導覽")
    try click(parallel,guide,"檢查安裝與授權")
    try wait("old PID listed separately from installed copies"){
        guard let view=window(parallel,guide) else {return false}
        return elements(view).flatMap(strings).joined(separator:"\n").contains("其他執行程序   PID "+String(old.processIdentifier))
    }
    try log(["step":"concurrent-processes","diagnosingPID":parallel.processIdentifier,"otherPID":old.processIdentifier])
    try quit(parallel)
    try quit(old)
    let current=try open(installed)
    try require(current.processIdentifier != old.processIdentifier && old.isTerminated,"old PID not terminated")
    try wait("updated pet visible"){window(current,pet) != nil}
    // The toolbar title is populated by the product after initialising the pet and reading its pending draft.
    try wait("draft toolbar after launch"){
        guard let w=window(current,pet) else {return false}
        return elements(w).contains {strings($0).contains("授權導覽")}
    }
    RunLoop.current.run(until:Date().addingTimeInterval(2))
    try require(window(current,guide) == nil,"legacy draft trapped updated launch")
    try click(current,pet,"授權導覽")
    try click(current,guide,"檢查安裝與授權")
    var detail=""
    try wait("read the running release's own installation diagnosis"){
        guard let w=window(current,guide) else {return false}
        detail=elements(w).flatMap(strings).joined(separator:"\n")
        return detail.contains("proc_pidpath") && detail.contains(installed.path+"/Contents/MacOS/SageKeys") &&
            detail.contains("PID "+String(current.processIdentifier)) && detail.contains("0.2.3 (5)")
    }
    try require(detail.contains("目前執行位置已在「應用程式」") && detail.contains("未發現") &&
                detail.contains("目前 CDHash 與上次有效時不同") && !detail.contains("將 App"),"misdiagnosed installed release")
    try log(["step":"diagnostics","pid":current.processIdentifier,"executable":current.executableURL?.path ?? "",
             "AppKitDiagnostic":Array(detail.components(separatedBy:"\n").filter {$0.contains("執行檔（") || $0.contains("暫時掛載路徑特徵") || $0.contains("CGPreflightListenEventAccess") || $0.contains("IOHIDCheckAccess")}.suffix(4)),
             "signingChangeDetectedFromSeededGrant":true,"guideOnLaunch":false])
    try click(current,guide,"繼續使用桌寵")
    try wait("guide dismissed"){window(current,guide)==nil && window(current,pet) != nil}
    try quit(current)
    let final=try open(installed)
    try wait("pet after cancellation"){window(final,pet) != nil}
    RunLoop.current.run(until:Date().addingTimeInterval(2))
    try require(window(final,guide)==nil && final.processIdentifier != current.processIdentifier,"cancel lost on restart")
    try log(["step":"cancel-relaunch","pid":final.processIdentifier,"onlyPet":true])
    try quit(final)
}
do {try run()} catch {fputs("Lifecycle failed: \(error)\n",stderr);exit(1)}

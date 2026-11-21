// Same-machine release-to-release comparison. Prime only Sage Keys' ordinary guide
// draft on the disposable runner. Never request keyboard access or inspect TCC.
import AppKit
import ApplicationServices

guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" else {exit(2)}
let path=URL(fileURLWithPath:CommandLine.arguments[1])
let id="io.github.annecat-bit.sagekeys"
guard let bundle=Bundle(url:path), bundle.bundleIdentifier == id,
      let defaults=UserDefaults(suiteName:id) else {exit(2)}
let draftKey="inputGuide.pending.v1", resumeKey="inputGuide.resume"
let priorDraft=defaults.object(forKey:draftKey), priorResume=defaults.object(forKey:resumeKey)
let data=try PropertyListSerialization.data(fromPropertyList:["help":[String:String]()],format:.binary,options:0)
defaults.set(data,forKey:draftKey);defaults.set(true,forKey:resumeKey);defaults.synchronize()
func restore(){
    defaults.set(priorDraft,forKey:draftKey);defaults.set(priorResume,forKey:resumeKey);defaults.synchronize()
}
func pump(_ seconds:Double){RunLoop.current.run(until:Date().addingTimeInterval(seconds))}
func attr(_ el:AXUIElement,_ key:String)->CFTypeRef? {
    var value:CFTypeRef?
    return AXUIElementCopyAttributeValue(el,key as CFString,&value) == .success ? value:nil
}
func guideVisible(_ pid:pid_t)->Bool {
    let el=AXUIElementCreateApplication(pid)
    let wins=attr(el,kAXWindowsAttribute) as? [AXUIElement] ?? []
    return wins.contains {attr($0,kAXTitleAttribute) as? String == "Sage Keys · 輸入監察導覽"}
}
func reading(_ pid:pid_t)throws->(rss:Double,cpu:Double) {
    let ps=Process(), pipe=Pipe()
    ps.executableURL=URL(fileURLWithPath:"/bin/ps");ps.arguments=["-p",String(pid),"-o","rss=,time="];ps.standardOutput=pipe
    try ps.run();ps.waitUntilExit()
    let fields=String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self).split(whereSeparator:{$0.isWhitespace})
    guard fields.count==2,let rss=Double(fields[0]) else {throw NSError(domain:"GuideCost",code:1)}
    let cpu=fields[1].split(separator:":").compactMap {Double($0)}.reduce(0,{$0*60+$1})
    return (rss/1024,cpu)
}
var target:NSRunningApplication?
let config=NSWorkspace.OpenConfiguration();config.createsNewApplicationInstance=true
NSWorkspace.shared.openApplication(at:path,configuration:config){app,_ in target=app}
let deadline=Date().addingTimeInterval(20)
while Date()<deadline && (target == nil || !guideVisible(target!.processIdentifier)) {pump(0.2)}
guard let app=target, guideVisible(app.processIdentifier) else {restore();target?.terminate();print("Guide visibility could not be verified");exit(1)}
pump(2)
let pid=app.processIdentifier
let start=ProcessInfo.processInfo.systemUptime
let first=try reading(pid)
var rss=[Double]()
for _ in 0..<12 {pump(0.5);rss.append(try reading(pid).rss)}
let last=try reading(pid), duration=ProcessInfo.processInfo.systemUptime-start
let version=bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "?"
let result:[String:Any]=["version":version,"seconds":duration,"hostCPUOneCorePct":100*(last.cpu-first.cpu)/duration,
    "hostMedianRSSMiB":rss.sorted()[rss.count/2],"guideWindowVerified":true]
print("GUIDE_COST "+String(decoding:try JSONSerialization.data(withJSONObject:result,options:.sortedKeys),as:UTF8.self))
app.terminate()
let end=Date().addingTimeInterval(6)
while !app.isTerminated && Date()<end {pump(0.1)}
restore()
if !app.isTerminated {exit(1)}

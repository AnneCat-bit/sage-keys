import AppKit
import WebKit

struct Failure: Error, CustomStringConvertible { let description:String;init(_ s:String){description=s} }
func require(_ yes:Bool,_ info:String)throws {if !yes {throw Failure(info)}}
let app=NSApplication.shared
let endpoint: DenialFixture = {
    if KeyMonitor.authorized {return KeyMonitor()}
    return SilentEndpoint()
}()
let delegate = PetApp(monitor: endpoint)
let evidence=URL(fileURLWithPath:CommandLine.arguments[1])
let probeURL=URL(fileURLWithPath:CommandLine.arguments[2])
delegate.testProbe=WKUserScript(source:try String(contentsOf:probeURL),injectionTime:.atDocumentStart,forMainFrameOnly:true)
app.setActivationPolicy(.accessory)
app.delegate=delegate

@MainActor func runChecks() async {
    var results:[String:Any]=[:],failed=[String]()
    func record(_ name:String,_ body:() async throws -> Any) async {
        do {let value=try await body();results[name]=value;print("PASS",name)}
        catch {failed.append(name);results[name]=["error":String(describing:error)];print("FAIL",name,error)}
    }
    func sleepMS(_ ms:Int)async{try? await Task.sleep(nanoseconds:UInt64(ms)*1_000_000)}
    func js(_ script:String)async throws -> Any {
        guard let display=delegate.display else {throw Failure("no WebView")}
        return try await display.web.evaluateJavaScript(script) ?? NSNull()
    }
    func wait(_ expression:String,_ ms:Int=6000)async throws {
        let end=Date().addingTimeInterval(Double(ms)/1000)
        while Date()<end {
            if (try? await js(expression)) as? Bool == true {return}
            await sleepMS(35)
        }
        throw Failure("condition timed out: "+expression)
    }
    func menu(_ prefix:String)throws {
        let menu=NSMenu();delegate.menuNeedsUpdate(menu)
        guard let n=menu.items.firstIndex(where:{$0.title.hasPrefix(prefix)}) else {throw Failure(prefix)}
        menu.performActionForItem(at:n)
    }
    await record("physicalState") {
        var keys=PhysicalKeys()
        try require(Set(PhysicalKeys.names.values).count==82,"layout")
        _=keys.apply(.flagsChanged,56,[.maskShift,CGEventFlags(rawValue:2)],repeated:false)
        _=keys.apply(.flagsChanged,60,[.maskShift,CGEventFlags(rawValue:6)],repeated:false)
        _=keys.apply(.flagsChanged,56,[.maskShift,CGEventFlags(rawValue:4)],repeated:false)
        _=keys.apply(.keyDown,0,[],repeated:false);_=keys.apply(.keyDown,1,[],repeated:false)
        try require(keys.held==["ShiftRight","KeyA","KeyS"],"independent modifiers/chord")
        try require(!keys.apply(.keyDown,0,[],repeated:true),"repeat")
        for n:Int64 in [49,36,51,55,58,59] {try require(keys.apply(.keyDown,n,[],repeated:false),"recognized key")}
        _=keys.apply(.keyUp,0,[],repeated:false)
        try require(!keys.held.contains("KeyA"),"release")
        keys.clear();try require(keys.held.isEmpty,"clear")
        return "82 unique positions; chord, release, repeat and reset using synthetic inputs"
    }
    await record("permission") {
        let granted=KeyMonitor.authorized, monitor=KeyMonitor()
        // Real preflight and start guard, with no approval prompt or event injection in CI.
        try require(!monitor.start() && !monitor.running,"unarmed start")
        monitor.foregroundAllowed={true}
        monitor.simulateDenied=true
        try require(!monitor.start() && !monitor.running,"simulated denial failed")
        monitor.simulateDenied=false
        let safe=KeyMonitor.safeSession()
        // Open and remove before yielding the main run loop. No actual system
        // input is dispatched, observed or manufactured by this check.
        let opened=monitor.start()
        monitor.stop()
        if granted && safe {try require(opened,"OS tap creation")}
        return ["preflight":granted,"simulatedDenialBlocked":true,"realTapOpened":opened,
                "removed":!monitor.running,"safeSession":safe]
    }
    await record("offlineLaunch") {
        try await wait("Boolean(window.sagePet && window.qa)",12000)
        try require(delegate.display.web.url?.isFileURL==true && delegate.panel.isVisible,"local panel")
        return ["fileURL":true,"contentSize":NSStringFromSize(delegate.panel.contentView!.bounds.size),
                "nonactivating":delegate.panel.styleMask.contains(.nonactivatingPanel),"canBecomeKey":delegate.panel.canBecomeKey]
    }
    await record("webglAndKeys") {
        try await wait("qa.draws>0 && !!document.querySelector('canvas')",12000)
        await sleepMS(240);_=try await js("qa.rest=null;qa.pixels()")
        delegate.display.setKeys(["KeyA","Space"])
        try await wait("qa.pixels()>30")
        let changed=try await js("qa.pixels()")
        if let uri=try await js("qa.gl.canvas.toDataURL()") as? String,
           let payload=uri.split(separator:",").last,let png=Data(base64Encoded:String(payload)) {
            try png.write(to:evidence.appendingPathComponent("runner-keyboard.png"))
        }
        delegate.display.setKeys(["KeyA"]);await sleepMS(350)
        let single=try await js("qa.pixels()") as? Int ?? 0
        try require(single>0 && single < (changed as? Int ?? 0),"independent return")
        delegate.display.setKeys([]);try await wait("qa.pixels()===0")
        return ["twoKeyPixels":changed,"oneKeyPixels":single,"restPixels":0,"contextCount":try await js("qa.contexts")]
    }
    await record("recordings") {
        var tones:[String:Any]=[:]
        for tone in ["rainy","topre","brown"] {
            delegate.display.configure(muted:false,eco:true,top:false,tone:tone)
            let before=try await js("qa.starts") as? Int ?? 0
            _=try await js("qa.mark=qa.audio?.currentTime || 0")
            delegate.display.setKeys(["Enter"]);try await wait("qa.starts>\(before) && qa.last.rms>0 && qa.last.state==='running'")
            try await wait("qa.mixPeak()>0.0001")
            tones[tone]=try await js("({...qa.last,mixedPeak:qa.mixPeak()})");delegate.display.setKeys([]);await sleepMS(160)
        }
        return tones
    }
    await record("panelAndPause") {
        try menu("保持置頂");try require(delegate.panel.level == .normal,"normal window")
        try menu("保持置頂");try require(delegate.panel.level == .floating,"floating window")
        try menu("俯視");try menu("省電");try menu("標準")
        try menu("隱藏");try require(!delegate.panel.isVisible && delegate.display.paused,"hidden")
        await sleepMS(200);let before=try await js("[qa.draws,qa.starts]") as! [Int]
        delegate.display.setKeys(["KeyS"]);await sleepMS(200)
        let after=try await js("[qa.draws,qa.starts]") as! [Int]
        try require(before==after,"hidden work")
        try menu("顯示");try require(delegate.panel.isVisible && !delegate.display.paused,"show")
        try menu("試敲");try await wait("qa.starts>\(after[1])")
        NSWorkspace.shared.notificationCenter.post(name:NSWorkspace.willSleepNotification,object:nil)
        try require(delegate.display.paused,"sleep notification did not pause")
        try menu("試敲")
        return ["simulatedSleepPaused":true,"normalAndFloating":true,"hiddenDrawDelta":0,"hiddenSoundDelta":0,"resumed":true]
    }
    await record("foregroundWindow") {
        guard let editor=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.TextEdit") else {throw Failure("TextEdit unavailable")}
        let config=NSWorkspace.OpenConfiguration()
        config.activates=true
        let target:NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at:editor,configuration:config) {other,error in
                if let other=other {continuation.resume(returning:other)}
                else {continuation.resume(throwing:error ?? Failure("TextEdit launch failed"))}
            }
        }
        _=target.activate(options:[.activateIgnoringOtherApps])
        let end=Date().addingTimeInterval(4)
        while NSWorkspace.shared.frontmostApplication != target && Date()<end {await sleepMS(90)}
        try require(NSWorkspace.shared.frontmostApplication==target,"test did not acquire foreground")
        delegate.panel.orderFrontRegardless();await sleepMS(250)
        try require(delegate.panel.isVisible && NSWorkspace.shared.frontmostApplication==target,"panel took focus")
        return ["foreground":"com.apple.TextEdit","visible":true,"foregroundPreserved":true,"sentSystemKeys":0]
    }
    let daily = DailyChecks(pet: delegate, endpoint: endpoint)
    await record("reopen") {
        await sleepMS(500)
        _ = try await js("qa.rest=null;qa.pixels()")
        delegate.display.setKeys(["KeyA"])
        try await wait("qa.pixels()>20")
        let heldPixels = try await js("qa.pixels()")
        var result = try await daily.reopen()
        try await wait("qa.pixels()===0 && qa.contexts===1")
        result["pixelsBeforeClose"] = heldPixels
        result["pixelsAfterRestore"] = 0
        result["contexts"] = 1
        return result
    }
    await record("trustAndForeground") {try await daily.follow()}
    await record("protectionTransitions") {try await daily.protection()}
    await record("trustedIdleAndStandby") {
        var deltas: [String: [Int]] = [:]
        _ = try await daily.focus("com.apple.TextEdit")
        try daily.menu("開啟本次")
        for (phase, id) in [("trustedIdle","com.apple.TextEdit"), ("untrustedStandby","com.apple.finder")] {
            _ = try await daily.focus(id)
            try await daily.wait(phase) {delegate.qaArmed && delegate.qaMonitoring == (phase == "trustedIdle")}
            await sleepMS(600)
            let before = try await js("[qa.draws,qa.requests,qa.starts]") as! [Int]
            try Data(phase.utf8).write(to:evidence.appendingPathComponent("phase"),options:.atomic)
            await sleepMS(4200)
            let after = try await js("[qa.draws,qa.requests,qa.starts]") as! [Int]
            try Data("finished".utf8).write(to:evidence.appendingPathComponent("phase"),options:.atomic)
            try require(after == before, phase + " scheduled work while idle")
            deltas[phase] = zip(after,before).map { $0.0 - $0.1 }
        }
        try daily.menu("立即暫停")
        try daily.menu("試敲")
        return deltas
    }
    await record("idle") {
        delegate.display.setKeys([]);await sleepMS(2000)
        let a=try await js("[qa.draws,qa.requests]") as! [Int]
        await sleepMS(2300);let b=try await js("[qa.draws,qa.requests]") as! [Int]
        try require(a==b,"unexpected idle frames")
        return ["seconds":2.3,"draws":b[0]-a[0],"rafRequests":b[1]-a[1],"audioState":try await js("qa.audio?.state ?? 'unopened'")]
    }
    await record("frameAndProcessMeasurements") {
        var out:[String:Any]=[:]
        for eco in [true,false] {
            delegate.display.configure(muted:false,eco:eco,top:false,tone:"rainy")
            await sleepMS(200)
            let before=try await js("qa.draws") as! Int
            let start=ProcessInfo.processInfo.systemUptime
            let label=eco ? "typing15":"typing30"
            try Data(label.utf8).write(to:evidence.appendingPathComponent("phase"),options:.atomic)
            for i in 0..<24 {
                delegate.display.setKeys([i%2==0 ? "KeyA":"KeyS"]);await sleepMS(40)
                delegate.display.setKeys([]);await sleepMS(90)
            }
            await sleepMS(250)
            let draws=(try await js("qa.draws") as! Int)-before
            try require(draws > 0, label+" did not draw")
            out[label]=["seconds":ProcessInfo.processInfo.systemUptime-start,"strokes":24,"drawCalls":draws,"renderedFrames":draws/5]
        }
        try Data("idle".utf8).write(to:evidence.appendingPathComponent("phase"),options:.atomic)
        await sleepMS(3500)
        try Data("finished".utf8).write(to:evidence.appendingPathComponent("phase"),options:.atomic)
        return out
    }
    await record("offlinePolicy") {
        let blocked:Any = try await withCheckedThrowingContinuation { continuation in
            delegate.display.web.callAsyncJavaScript(
                "try { await fetch('https://example.invalid/sage-qa'); return false } catch { return true }",
                arguments:[:],in:nil,in:.page) { result in continuation.resume(with:result) }
        }
        try require(blocked as? Bool==true,"external fetch not rejected")
        try await wait("qa.policyBlocks>0")
        try require((try await js("qa.requestsOut")) as? Int==1,"unexpected app fetch")
        return ["appFetchCount":0,"externalProbeBlockedByCSP":true,"origin":"bundle file"]
    }
    await record("shutdown") {
        weak var host=delegate.display
        weak var web=delegate.display?.web
        var retained:WKWebView?=delegate.display.web
        await withCheckedContinuation { continuation in delegate.shutdown {continuation.resume()} }
        let state=try await retained!.evaluateJavaScript("({audio:qa.audio?.state, lost:qa.gl.isContextLost(), canvases:document.querySelectorAll('canvas').length})") as? [String:Any]
        retained=nil
        // Allow the bounded native close watchdog to release its closure.
        await sleepMS(1800)
        try require(state?["audio"] as? String=="closed" && state?["lost"] as? Bool==true && state?["canvases"] as? Int==0,"JS resources not released")
        try require(host==nil && web==nil,"native display retained")
        return ["hostReleased":true,"webViewReleased":true,"audioClosed":true,"webglLost":true,"canvases":0]
    }
    let report:[String:Any]=["transitionEndpoint":endpoint is SilentEndpoint ? "silent test double; no OS events" : "CGEvent listenOnly","system":ProcessInfo.processInfo.operatingSystemVersionString,"tests":results,"failed":failed]
    do {try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:evidence.appendingPathComponent("mac-results.json"))}
    catch {print(error);exit(2)}
    exit(failed.isEmpty ? 0:1)
}
@MainActor func coldLaunch(_ phase: String) async {
    do {
        let checks = DailyChecks(pet: delegate, endpoint: endpoint)
        try await checks.wait("cold launch display") {delegate.display?.ready == true}
        let saved = TrustedApps().entries.map { $0.bundleID }
        try require(saved == ["com.apple.TextEdit"], "trusted app missing after process restart")
        let initial = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let editor = try await checks.focus("com.apple.TextEdit")
        try require(!delegate.qaArmed && !delegate.qaWatching && !delegate.qaMonitoring && delegate.panel.isVisible, "new launch armed or invisible")
        if phase == "quit-active" {
            try checks.menu("開啟本次")
            try await checks.wait("manual enable before quit") {delegate.qaActiveID == editor.bundleIdentifier}
        }
        let data: [String: Any] = ["pid":getpid(), "savedIDs":saved, "startedVisible":true, "startedOff":true,
                                   "foregroundAtLaunch":initial, "activeAtQuit":delegate.qaMonitoring]
        try JSONSerialization.data(withJSONObject:data).write(to:evidence.appendingPathComponent(phase+".json"))
        try checks.menu("退出 Sage Keys")
    } catch {print(error);exit(1)}
}
DispatchQueue.main.async {Task {@MainActor in
    if let phase = CommandLine.arguments.dropFirst(3).first {await coldLaunch(phase)}
    else {
        try String(getpid()).write(to:evidence.appendingPathComponent("qa-pid"),atomically:true,encoding:.utf8)
        await runChecks()
    }
}}
app.run()

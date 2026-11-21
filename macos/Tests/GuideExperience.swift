import AppKit
import Darwin

extension GuideChecks {
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    func capture(_ name:String) throws {
        guard let content=window?.contentView,
              let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds) else {throw Failure("guide image")}
        content.layoutSubtreeIfNeeded();content.displayIfNeeded()
        content.cacheDisplay(in:content.bounds,to:bitmap)
        guard let png=bitmap.representation(using:.png,properties:[:]) else {throw Failure("PNG")}
        try png.write(to:evidence.appendingPathComponent("guide-"+name+".png"))
    }
    func checkLayout() throws {
        guard let scroll=window?.contentView as? NSScrollView,let doc=scroll.documentView else {throw Failure("scrollable guide")}
        for view in doc.subviews {
            try require(doc.bounds.insetBy(dx:-1,dy:-1).contains(view.frame), "outside guide document")
            if let b=view as? NSButton {
                try require(b.frame.width+1 >= b.intrinsicContentSize.width,"clipped button "+b.title)
                doc.scrollToVisible(b.frame)
                try require(scroll.documentVisibleRect.insetBy(dx:-2,dy:-2).contains(b.frame),"cannot reach "+b.title)
            }
            if let f=view as? NSTextField, let cell=f.cell {
                let needed=cell.cellSize(forBounds:NSRect(x:0,y:0,width:f.frame.width,height:10000)).height
                try require(f.frame.height+1 >= needed,"cut off field")
            }
        }
        scroll.contentView.scroll(to:.zero);scroll.reflectScrolledClipView(scroll.contentView)
    }
    func usability() async throws -> [String:Any] {
        guard let w=window else {throw Failure("no guide")}
        let normal=w.contentView!.bounds.size
        try press("調整字級");try press("調整字級")
        let large=descendants(w.contentView!).compactMap {($0 as? NSTextField)?.font?.pointSize}.max() ?? 0
        try require(large>=34,"150% heading")
        for size in [NSSize(width:356,height:295),NSSize(width:640,height:600)] {
            w.setContentSize(size)
            try await Task.sleep(nanoseconds:180_000_000)
            try checkLayout()
        }
        w.setContentSize(normal);try press("調整字級");try checkLayout()
        let first=try button("在 Finder 顯示目前版本")
        guard let next=first.nextKeyView as? NSButton else {throw Failure("key view loop")}
        try require(w.makeFirstResponder(first),"focus initial button")
        func tab(_ flags:NSEvent.ModifierFlags) throws {
            guard let e=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:w.windowNumber,context:nil,characters:"\t",charactersIgnoringModifiers:"\t",isARepeat:false,keyCode:48) else {throw Failure("local tab")}
            w.sendEvent(e)
        }
        try tab([])
        try require(w.firstResponder === next, "Tab did not focus next action")
        try tab([.shift]);try require(w.firstResponder === first, "Shift-Tab did not return")
        let ws=NSWorkspace.shared
        let already=ws.isVoiceOverEnabled
        var voiceLaunch="already enabled"
        if !already {
            if let url=ws.urlForApplication(withBundleIdentifier:"com.apple.VoiceOver") {
                voiceLaunch="launch requested"
                let config=NSWorkspace.OpenConfiguration();config.activates=false
                ws.openApplication(at:url,configuration:config){_,_ in}
                for _ in 0..<20 {
                    try await Task.sleep(nanoseconds:200_000_000)
                    if ws.isVoiceOverEnabled {break}
                }
            } else {voiceLaunch="system VoiceOver application unavailable"}
        }
        let voiceEnabled=ws.isVoiceOverEnabled
        w.makeKeyAndOrderFront(nil)
        try press("重新檢查權限")
        try String(getpid()).write(to:evidence.appendingPathComponent("ax-ready"),atomically:true,encoding:.utf8)
        let axURL=evidence.appendingPathComponent("guide-ax.json")
        try await daily.wait("external AX audit",seconds:20){FileManager.default.fileExists(atPath:axURL.path)}
        let ax=try JSONDecoder().decode([String:Bool].self,from:Data(contentsOf:axURL))
        if ax["existingQAAccess"] == true {try require(ax.values.allSatisfy {$0},"incomplete OS accessibility tree: "+String(describing:ax))}
        try await Task.sleep(nanoseconds:500_000_000)
        func usage()->Double {
            var u=rusage();getrusage(RUSAGE_SELF,&u)
            return Double(u.ru_utime.tv_sec+u.ru_stime.tv_sec)+Double(u.ru_utime.tv_usec+u.ru_stime.tv_usec)/1e6
        }
        let paints=GuideDrawing.qaPaints, cpu=usage(), start=ProcessInfo.processInfo.systemUptime
        try await Task.sleep(nanoseconds:4_000_000_000)
        let delta=GuideDrawing.qaPaints-paints
        return ["textScale":1.5,"largestFontPt":large,"sizes":["356×295","640×600"],"tabAndShiftTab":true,"AX":ax,
                "voiceOverLaunch":voiceLaunch,"voiceOverEnabled":voiceEnabled,"spokenOutputEvaluated":false,
                "idleDraws":delta,"idleHostCPUOneCorePct":100*(usage()-cpu)/(ProcessInfo.processInfo.systemUptime-start)]
    }
}

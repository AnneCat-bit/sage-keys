import AppKit

@MainActor
struct GuideChecks {
    let daily: DailyChecks
    let endpoint: SilentEndpoint
    let evidence: URL

    var window: NSWindow? {NSApp.windows.first { $0.title == "Sage Keys · 輸入監察導覽" && $0.isVisible }}
    func controls(_ view: NSView) -> [NSButton] {
        if let button = view as? NSButton {return [button]}
        return view.subviews.flatMap(controls)
    }
    func button(_ title: String) throws -> NSButton {
        guard let content = window?.contentView, let b = controls(content).first(where: {$0.title == title}) else {throw Failure("missing guide control "+title)}
        return b
    }
    func press(_ title: String) throws {
        let b = try button(title); try require(b.isEnabled,"unexpected disabled button "+title);b.performClick(nil)
    }
    func off() throws {
        try require(!daily.pet.qaArmed && !daily.pet.qaMonitoring && !daily.pet.qaWatching, "guide unexpectedly enabled monitoring")
    }
    func consent(_ bundle: String, remember: Bool) async throws {
        _ = try await daily.focus(bundle)
        try daily.dialog(button:"允許並開始同步",remember:remember) {try daily.menu("管理已信任 App","允許目前 App")}
        try await daily.wait("guide visible") {window != nil}
        try off()
    }

    func diagnostics() throws {
        let suite = "io.github.annecat-bit.sagekeys.qa.status"
        let prefs = UserDefaults(suiteName:suite)!
        defer {prefs.removePersistentDomain(forName:suite)}
        let old = PermissionProgress(prefs,build:"2")
        try require(old.statusText(.undetermined).contains("未回報"),"unknown guessed")
        try require(old.statusText(.denied).contains("未獲得"),"denied message")
        old.observedGrant()
        try require(old.statusText(.denied).contains("失效"),"previously granted")
        let update = PermissionProgress(prefs,build:"3")
        try require(update.statusText(.denied).contains("更新後") && update.statusText(.inconsistent).contains("不一致"),"update / inconsistent")
        try require(update.statusText(.granted).contains("已取得"),"re-authorized")
        for success in [1,2,3,4] {
            var calls = [URL]()
            let root = URL(fileURLWithPath:"/System/Applications/System Settings.app")
            let result = SettingsLinks.open(inputPane:true,launch:{u in calls.append(u);return calls.count == success},settingsApp:root)
            let expected:[SettingsLinks.Destination] = [.input,.privacy,.settings,.unavailable]
            try require(result == expected[success-1] && calls == Array([SettingsLinks.input,SettingsLinks.privacy,root].prefix(min(success,3))),"fallback order")
        }
    }

    func run(_ phase: String) async throws {
        let editor="com.apple.TextEdit", calc="com.apple.calculator"
        let pet=daily.pet
        var result: [String:Any] = ["pid":getpid(),"realTCCPreflight":KeyMonitor.authorized,
                                  "endpoint":"test double, no system event source","phase":phase]
        try await daily.wait("guide test startup") {pet.display?.ready == true}
        try off()
        switch phase {
        case "guide-draft":
            try diagnostics()
            endpoint.simulateDenied=true;endpoint.grantOnRequest=true
            try await consent(editor,remember:false)
            try require(endpoint.requests == 1 && endpoint.hasAccess,"first simulated grant")
            try press("重新檢查權限");try off()
            try press("確認並開始本次同步")
            _ = try await daily.focus(editor);try await daily.wait("manual start") {pet.qaActiveID == editor}
            try daily.menu("立即暫停")
            try daily.menu("開啟本次")
            try await daily.wait("already granted, no guide or request") {pet.qaActiveID == editor}
            try require(endpoint.requests == 1 && window == nil, "already granted asked again")
            try daily.menu("立即暫停")
            let initial = TrustedApps().entries
            endpoint.simulateDenied=true;endpoint.grantOnRequest=false
            try await consent(calc,remember:true)
            guard case .remembered(let saved) = PermissionProgress().pending else {throw Failure("missing pending consent")}
            try require(saved.bundleID == calc && TrustedApps().entries == initial, "draft changed trust")
            try press("重新檢查權限")
            try require(!(try button("確認並開始本次同步")).isEnabled && endpoint.requests == 2,"recheck requested or armed")
            try press("稍後再說")
            try require(window == nil && !PermissionProgress().resumeOnLaunch, "defer")
            try off()
            try daily.menu("輸入監察授權導覽")
            try press("打開輸入監察設定")
            try await daily.wait("Settings foreground from guide button") {
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences"
            }
            try off()
            try daily.menu("輸入監察授權導覽")
            guard let content=window?.contentView, let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds) else {throw Failure("guide layout")}
            content.layoutSubtreeIfNeeded()
            for b in controls(content) {try require(content.bounds.insetBy(dx:-1,dy:-1).contains(b.convert(b.bounds,to:content)), "clipped "+b.title)}
            content.cacheDisplay(in:content.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])?.write(to:evidence.appendingPathComponent("permission-guide.png"))
            result["checks"]=["first grant needs manual start","decline keeps target out of trust","later retains draft","recheck issues no request","status and fallback branches","Settings foreground from actual guide button","already granted skipped OS request","buttons inside window"]
            result["size"]=NSStringFromSize(content.bounds.size)
        case "guide-restored":
            try await daily.wait("guide restored") {window != nil}
            try require(endpoint.requests == 0 && PermissionProgress().resumeOnLaunch,"restart asked OS")
            guard case .remembered(let saved) = PermissionProgress().pending else {throw Failure("missing draft after restart")}
            try require(saved.bundleID==calc && !TrustedApps().entries.contains(saved),"premature grant")
            try press("重新檢查權限");try off()
            try press("確認並開始本次同步")
            _ = try await daily.focus("com.apple.finder")
            try await daily.wait("unknown stays off") {pet.qaArmed && !pet.qaMonitoring}
            _ = try await daily.focus(calc);try await daily.wait("chosen target follows") {pet.qaActiveID == calc}
            try require(TrustedApps().entries.contains(saved) && PermissionProgress().pending == nil, "confirmed grant missing")
            try daily.menu("立即暫停")
            // The next process must reject a saved identity with a mismatched signing requirement.
            PermissionProgress().stage(.remembered(TrustedApp(name:saved.name,bundleID:calc,signer:saved.signer,requirement:"never")))
            result["checks"]=["distinct launch, saved signed intent","recheck stays disarmed","manual confirmation saves only calculator","Finder remains unapproved"]
        case "guide-mismatch":
            try await daily.wait("mismatch guide") {window != nil}
            let before=TrustedApps().entries
            try press("確認並開始本次同步")
            try off()
            try require(TrustedApps().entries==before && window != nil,"identity mismatch granted")
            result["checks"]=["mismatched signed requirement blocked despite granted permission","previous trust intact"]
        default: throw Failure("unexpected guide phase")
        }
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:evidence.appendingPathComponent(phase+".json"))
        if phase == "guide-draft" {try press("退出並保留進度")} else {try daily.menu("退出 Sage Keys")}
    }
}

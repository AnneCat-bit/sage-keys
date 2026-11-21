import AppKit

enum ListenStatus: String {
    case granted, denied, undetermined, inconsistent
}

// A pending choice has no monitoring authority. A one-time grant never saves
// an app identity; its original NSRunningApplication stays only in memory.
enum PendingConsent: Codable, Equatable {
    case remembered(TrustedApp), once, trustedList, help
}

final class PermissionProgress {
    private let defaults: UserDefaults
    private let build: String
    private let key = "inputGuide.pending.v1"
    private(set) var pending: PendingConsent?

    init(_ defaults: UserDefaults = .standard, build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown") {
        self.defaults = defaults
        self.build = build
        pending = defaults.data(forKey: key).flatMap {try? PropertyListDecoder().decode(PendingConsent.self, from: $0)}
    }

    var switchReportedOn: Bool {
        get {defaults.bool(forKey:"inputGuide.switchReportedOn")}
        set {defaults.set(newValue, forKey:"inputGuide.switchReportedOn")}
    }
    var lastAuthorizedHash: String? {defaults.string(forKey:"inputGuide.lastGrantedHash")}
    func rememberHash(_ hash: String?) {
        if let hash = hash, hash != lastAuthorizedHash {defaults.set(hash,forKey:"inputGuide.lastGrantedHash")}
    }
    var resumeOnLaunch: Bool {pending != nil && defaults.bool(forKey: "inputGuide.resume")}
    func stage(_ choice: PendingConsent) {
        if let data = try? PropertyListEncoder().encode(choice) {
            defaults.set(data, forKey: key)
            pending = choice
            resumeNextLaunch(true)
        }
    }
    func resumeNextLaunch(_ value: Bool) {defaults.set(value, forKey: "inputGuide.resume")}
    func clear() {pending = nil; defaults.removeObject(forKey: key);resumeNextLaunch(false)}
    func observedGrant() {
        if defaults.string(forKey: "inputGuide.lastGrantedBuild") != build {
            defaults.set(build, forKey: "inputGuide.lastGrantedBuild")
        }
    }

    func statusText(_ status: ListenStatus) -> String {
        if status == .granted {observedGrant();return "已取得輸入監察權限"}
        if status == .inconsistent {return "系統權限回報不一致，目前無法同步。請重新檢查，必要時退出再開。"}
        if let past = defaults.string(forKey: "inputGuide.lastGrantedBuild") {
            return past == build ? "之前取得的權限目前未生效。" : "更新後，新版本目前沒有輸入監察權限。"
        }
        switch status {
        case .denied: return "Sage Keys 還未獲得有效的鍵盤監察權限。"
        case .undetermined: return "尚未取得權限。macOS 未回報是否已作選擇。"
        default: return "系統權限狀態未能確定。請檢查設定後再試。"
        }
    }
}

private final class GuideSheet: NSView {
    override var isFlipped: Bool {true}
    var rows = [[NSView]]()
    override func draw(_ dirtyRect:NSRect) {GuideDrawing.paper.setFill();dirtyRect.fill()}
    func arrange(width: CGFloat) {
        let margin:CGFloat = 22, available = max(200,width-margin*2)
        var y:CGFloat = 17
        for row in rows {
            var x = margin, line:CGFloat = 0
            for view in row {
                var size = view.intrinsicContentSize
                if let field = view as? NSTextField {
                    field.preferredMaxLayoutWidth = available
                    let fit = field.cell?.cellSize(forBounds:NSRect(x:0,y:0,width:available,height:10000)).height ?? 18
                    size = NSSize(width:available,height:ceil(max(fit,field.intrinsicContentSize.height))+2)
                } else if view is GuideDrawing {size = NSSize(width:available,height:108)}
                else {size.width = min(available,ceil(size.width)+4);size.height = max(26,ceil(size.height))}
                if x > margin && x+size.width > width-margin {y += line+4;x=margin;line=0}
                view.frame=NSRect(origin:NSPoint(x:x,y:y),size:size)
                line=max(line,size.height);x += size.width+5
            }
            y += line+8
        }
        setFrameSize(NSSize(width:width,height:y+14))
    }
}

private final class GuidePanel: NSPanel {
    var moveKeyboardFocus: ((Bool) -> Void)?
    override func sendEvent(_ event: NSEvent) {
        // Navigation is local to this guide, including when system-wide full keyboard access is off.
        if event.type == .keyDown && event.keyCode == 48 &&
           event.modifierFlags.intersection([.command,.option,.control]).isEmpty, let move = moveKeyboardFocus {
            move(event.modifierFlags.contains(.shift))
            return
        }
        super.sendEvent(event)
    }
}
private final class GuideButton: NSButton {
    override var acceptsFirstResponder: Bool {true}
    override func becomeFirstResponder() -> Bool {
        let accepted=super.becomeFirstResponder()
        if accepted {scrollToVisible(bounds)}
        return accepted
    }
}

final class PermissionGuide: NSWindowController, NSWindowDelegate {
    private let scroll = NSScrollView()
    private let sheet = GuideSheet()
    private var page = GuidePage.status
    private var reading = AccessReading(preflight:false,hid:.unknown,request:nil)
    private var install: InstallationCheck?
    private var statusText="", targetText="", hint=""
    private var reported=false, authorized=false, canStart=false, reopened=false
    private var zoom = 1.0
    private var buttons = [NSButton]()
    var recheck: () -> Void = {}
    var finish: () -> Void = {}
    var chooseTarget: () -> Void = {}
    var later: () -> Void = {}
    var quitToApply: () -> Void = {}
    var reportSwitch: (Bool) -> Void = {_ in}
    var inspect: () -> InstallationCheck = {InstallationCheck(previousHash:nil)}

    init() {
        let panel=GuidePanel(contentRect:NSRect(x:0,y:0,width:510,height:460),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        super.init(window:panel)
        panel.title="Sage Keys · 輸入監察導覽";panel.isReleasedWhenClosed=false;panel.hidesOnDeactivate=false
        panel.contentMinSize=NSSize(width:356,height:295)
        panel.appearance=NSAppearance(named:.aqua);panel.backgroundColor=GuideDrawing.paper
        scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.scrollerStyle = .overlay
        scroll.drawsBackground=true;scroll.backgroundColor=GuideDrawing.paper;scroll.borderType = .noBorder
        panel.contentView=scroll;scroll.documentView=sheet;panel.delegate=self;panel.center()
        panel.moveKeyboardFocus = { [weak self] backward in
            guard let self=self, let window=self.window else {return}
            let choices=self.buttons.filter(\.isEnabled)
            guard !choices.isEmpty else {return}
            let index=choices.firstIndex { $0 === window.firstResponder } ?? (backward ? 0 : -1)
            let next=(index + (backward ? -1:1) + choices.count) % choices.count
            window.makeFirstResponder(choices[next])
        }
    }
    required init?(coder:NSCoder){fatalError()}
    func windowDidResize(_ note:Notification){sheet.arrange(width:scroll.contentSize.width)}
    func windowDidBecomeKey(_ note:Notification){recheck()}
    func present() {NSApp.activate(ignoringOtherApps:true);window?.makeKeyAndOrderFront(nil)}
    func dismiss(){window?.orderOut(nil);install=nil}
    func windowShouldClose(_ sender:NSWindow)->Bool {later();return false}

    func update(status:String,target:String,reading new:AccessReading,reported on:Bool,reopened:Bool,canStart:Bool,hint:String) {
        let before=page
        if new.preflight != authorized || (new.preflight && page == .status) {
            if page != .installation {page = new.preflight ? .success : (on ? .repair:.status)}
        } else if !new.preflight && on && page == .status {page = .repair}
        authorized=new.preflight;reading=new;reported=on;self.reopened=reopened
        self.canStart=canStart;statusText=status;targetText=target;self.hint=hint
        if (page == .repair || page == .installation) && install == nil {install=inspect()}
        render(reset:page != before)
    }

    private func label(_ text:String,_ size:CGFloat=13,_ weight:NSFont.Weight = .regular,technical:Bool=false) {
        let f=NSTextField(wrappingLabelWithString:text)
        f.font = technical ? .monospacedSystemFont(ofSize:size*zoom,weight:weight) : .systemFont(ofSize:size*zoom,weight:weight)
        f.textColor=GuideDrawing.ink;f.lineBreakMode = technical ? .byCharWrapping : .byWordWrapping
        if technical {f.isSelectable=true}
        sheet.rows.append([f]);sheet.addSubview(f)
    }
    private func actions(_ entries:[(String,Selector)], primary:Bool=false) {
        var row=[NSView]()
        for (i,entry) in entries.enumerated() {
            let b=GuideButton(title:entry.0,target:self,action:entry.1)
            b.bezelStyle = .rounded;b.font = .systemFont(ofSize:13*zoom,weight:.medium)
            if primary && i == 0 {b.bezelColor=NSColor(srgbRed:0.68,green:0.77,blue:0.63,alpha:1)}
            if entry.1 == #selector(start) {b.isEnabled=canStart}
            b.setAccessibilityLabel(entry.0)
            buttons.append(b);sheet.addSubview(b);row.append(b)
        }
        sheet.rows.append(row)
    }
    private func render(reset:Bool) {
        let previous=(window?.firstResponder as? NSButton)?.title
        let offset=scroll.contentView.bounds.origin
        for v in sheet.subviews {v.removeFromSuperview()}
        sheet.rows.removeAll();buttons.removeAll()
        let art=GuideDrawing(page);sheet.addSubview(art);sheet.rows.append([art])
        switch page {
        case .status:
            label("核對鍵盤監察權限",23,.semibold)
            label(statusText)
            label("你在「輸入監察」看到哪種情況？",15,.medium)
            actions([("開關已開，仍無法同步",#selector(switchOn)),("尚未開啟或找不到",#selector(settingsPage))],primary:true)
            actions([("打開輸入監察設定",#selector(openInput)),("檢查安裝與授權",#selector(diagnostics))])
        case .settings:
            label("找到 Sage Keys 的開關",23,.semibold)
            label("系統設定  →  私隱與保安  →  輸入監察",16,.medium)
            label("在列表找到 Sage Keys，親自開啟旁邊的開關。若系統要求退出，請保存進度再重開。")
            actions([("直接打開設定",#selector(openInput)),("打開私隱與保安",#selector(openPrivacy))],primary:true)
            actions([("開關已開，仍無法同步",#selector(switchOn)),("找不到目前版本",#selector(replacement))])
        case .repair:
            label("已開啟，但尚未生效",23,.semibold)
            label("你回報開關已開。這份 Sage Keys 的權限檢查仍未通過，本次同步維持關閉。")
            label(reopened ? "重開後仍未生效？核對授權的副本" : "先核對正在執行的副本",15,.semibold)
            label(install?.advice ?? "")
            if !reopened {label("已確認是同一份？先退出再重開。若仍未生效，可重新加入新版。")}
            actions([("在 Finder 顯示目前版本",#selector(reveal)),("檢查安裝與授權",#selector(diagnostics))],primary:true)
            actions([("退出並保留進度",#selector(quit)),("如何重新加入新版",#selector(replacement))])
            actions([("打開輸入監察設定",#selector(openInput)),("修正開關回報",#selector(settingsPage))])
        case .replace:
            label("重新選取正在使用的版本",22,.semibold)
            label("① 在 Finder 顯示這份 App，確認它在「應用程式」內。")
            label("② 到輸入監察。若舊 Sage Keys 項目已失效，選取該項，按列表下方「−」。")
            label("③ 按「＋」並選擇剛才核對的 Sage Keys。依系統提示退出，再從 Finder 打開同一份。")
            actions([("在 Finder 顯示目前版本",#selector(reveal)),("打開輸入監察設定",#selector(openInput))],primary:true)
            actions([("退出並保留進度",#selector(quit)),("檢查安裝與授權",#selector(diagnostics))])
        case .success:
            label("鍵盤監察權限已生效",23,.semibold)
            label(canStart ? "macOS 已授權。現在可以確認並開始本次同步。" : "macOS 已授權。請選擇要同步的目標 App。")
            label(targetText)
            actions([("確認並開始本次同步",#selector(start)),("重新選取 App",#selector(selectTarget))],primary:true)
        case .installation:
            label("檢查安裝與授權",23,.semibold)
            label(authorized ? "系統授權有效 · 本次同步已關閉" : (reported ? "開關已開，這份 App 尚未取得有效權限" : statusText),15,.medium)
            if let install=install {
                if !authorized {label(install.advice)}
                label(install.details(reading),12,.regular,technical:true)
            }
            actions([("在 Finder 顯示目前版本",#selector(reveal)),("返回導覽",#selector(home))])
        }
        if !hint.isEmpty {label(hint,13,.medium)}
        if page != .success {
            actions([("重新檢查權限",#selector(check))])
        } else {
            actions([("重新檢查權限",#selector(check)),("檢查安裝與授權",#selector(diagnostics))])
        }
        var tools:[(String,Selector)]=[("稍後再說",#selector(deferGuide)),("調整字級",#selector(scaleText))]
        if page != .repair && page != .replace {tools.append(("退出並保留進度",#selector(quit)))}
        actions(tools)
        sheet.arrange(width:scroll.contentSize.width)
        let enabled=buttons.filter(\.isEnabled)
        for (i,b) in enabled.enumerated() {b.nextKeyView=enabled[(i+1)%enabled.count]}
        window?.initialFirstResponder=enabled.first
        if let previous=previous {
            window?.makeFirstResponder(enabled.first(where:{$0.title==previous}) ?? enabled.first)
        }
        let top=reset ? 0:min(offset.y,max(0,sheet.frame.height-scroll.contentSize.height))
        scroll.contentView.scroll(to:NSPoint(x:0,y:top));scroll.reflectScrolledClipView(scroll.contentView)
        NSAccessibility.post(element:sheet,notification:.layoutChanged)
    }

    private func move(_ next:GuidePage){page=next;hint="";if next == .repair || next == .installation {install=inspect()};render(reset:true)}
    @objc func diagnostics(){move(.installation)}
    @objc private func home(){move(authorized ? .success : (reported ? .repair:.status))}
    @objc private func switchOn(){reportSwitch(true);move(authorized ? .success:.repair)}
    @objc private func settingsPage(){reportSwitch(false);move(authorized ? .success:.settings)}
    @objc private func replacement(){move(.replace)}
    @objc private func openInput(){openSettings(true)}
    @objc private func openPrivacy(){openSettings(false)}
    private func openSettings(_ input:Bool) {
        switch SettingsLinks.open(inputPane:input) {
        case .input: hint="回來時會重新檢查。若只見設定首頁，請選「私隱與保安」→「輸入監察」。"
        case .privacy,.settings: hint="請在「私隱與保安」內選「輸入監察」。"
        case .unavailable: hint="請從左上角  → 系統設定 → 私隱與保安 → 輸入監察。"
        }
        render(reset:false)
    }
    @objc private func check(){
        install=nil
        recheck()
        if !authorized && !reported && page == .status {hint="這份 App 暫未通過檢查。若開關已開，請選上方對應選項核對版本。";render(reset:false)}
        let announcement = authorized ? "系統權限有效，本次同步仍然關閉" : "這份 App 的權限尚未生效"
        NSAccessibility.post(element:sheet,notification:.announcementRequested,userInfo:[.announcement:announcement,.priority:NSAccessibilityPriorityLevel.medium.rawValue])
    }
    @objc private func scaleText(){zoom=zoom >= 1.5 ? 1 : zoom+0.25;render(reset:false)}
    @objc private func reveal(){NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])}
    @objc private func selectTarget(){chooseTarget()}
    @objc private func start(){finish()}
    @objc private func deferGuide(){later()}
    @objc private func quit(){quitToApply()}
}

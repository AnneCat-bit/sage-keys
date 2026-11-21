import AppKit
import ServiceManagement
import WebKit

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private(set) var panel: FloatingPanel!
    private(set) var display: PetWeb!
    #if SAGE_QA
    var testProbe: WKUserScript?
    private(set) var reopenCount = 0
    var qaArmed: Bool {armed}
    var qaMonitoring: Bool {monitor.running}
    var qaActiveID: String? {monitor.running ? verifiedFront?.bundleIdentifier : nil}
    var qaWatching: Bool {foregroundObserver != nil || protectionTimer != nil}
    var qaStatus: String {label.stringValue}
    #endif
    private let monitor: PhysicalMonitoring

    init(monitor: PhysicalMonitoring = KeyMonitor()) {
        self.monitor = monitor
        super.init()
    }

    private var item: NSStatusItem!
    private let label=NSTextField(labelWithString:"載入中")
    private let syncButton=NSButton()
    private let muteButton=NSButton()
    private let prefs=UserDefaults.standard
    private let trust = TrustedApps()
    private var allowed = [NSRunningApplication]() // Explicit, ephemeral grants to particular instances.
    private var verifiedFront: NSRunningApplication?
    private var foregroundObserver: NSObjectProtocol?
    private var protectionTimer: Timer?
    private var consentGeneration = 0
    private var syncStatus = "等待已信任 App"
    private var armed=false, paused=false, closing=false
    private var mode="載入中", notice:String?
    private var observed: [(NotificationCenter,NSObjectProtocol)]=[]
    private var demoWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification:Notification) {
        prefs.register(defaults:["eco":true,"pinned":true,"muted":false,"top":false,"tone":"rainy"])
        let resources=Bundle.main.resourceURL!.appendingPathComponent("Pet")
        #if SAGE_QA
        display=PetWeb(resources:resources,probe:testProbe)
        #else
        display=PetWeb(resources:resources)
        #endif
        buildPanel()
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        let menu=NSMenu(); menu.delegate=self; item.menu=menu
        monitor.changed={ [weak self] in self?.display.setKeys($0) }
        monitor.interrupted={ [weak self] in
            guard let self = self else {return}
            self.pauseAll(self.protectionIssue ?? "事件監測已中斷")
        }
        monitor.foregroundChanged={ [weak self] in
            // A tap can notice the switch before NSWorkspace delivers its notification.
            self?.detachFront()
            DispatchQueue.main.async {self?.frontChanged()}
        }
        monitor.foregroundAllowed={ [weak self] in self?.isAllowedFront() ?? false }
        display.onReady={ [weak self] value in self?.mode=value; self?.refresh() }
        display.onFailure={ [weak self] message in self?.pauseAll(message) }
        observeSystem()
        applySettings()
        panel.orderFrontRegardless()
        display.load()
        refresh()
    }

    private func button(_ b:NSButton,_ title:String,_ action:Selector) {
        b.title=title; b.bezelStyle = .rounded; b.controlSize = .small
        b.font = .systemFont(ofSize:11,weight:.medium); b.target=self; b.action=action
        b.setContentHuggingPriority(.required,for:.horizontal)
    }
    private func buildPanel() {
        panel=FloatingPanel(contentRect:NSRect(x:0,y:0,width:400,height:250),styleMask:[.titled,.closable,.miniaturizable,.resizable,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title="Sage 75"; panel.isReleasedWhenClosed=false; panel.hidesOnDeactivate=false
        panel.isFloatingPanel=true; panel.becomesKeyOnlyIfNeeded=true
        panel.contentMinSize=NSSize(width:300,height:190)
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.backgroundColor=NSColor(srgbRed:0.91,green:0.93,blue:0.88,alpha:1)
        panel.delegate=self
        let bar=NSStackView(); bar.orientation = .horizontal; bar.spacing=6
        bar.edgeInsets=NSEdgeInsets(top:2,left:9,bottom:2,right:7)
        label.font = .systemFont(ofSize:11,weight:.medium);label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        button(syncButton,"同步",#selector(toggleSync));button(muteButton,"靜音",#selector(toggleMute))
        let more=NSButton();button(more,"•••",#selector(openOptions(_:)));more.setAccessibilityLabel("桌寵選單")
        [label,NSView(),syncButton,muteButton,more].forEach{bar.addArrangedSubview($0)}
        let content=NSView();panel.contentView=content
        let web=display.web
        for v in [web,bar] {v.translatesAutoresizingMaskIntoConstraints=false;content.addSubview(v)}
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo:content.topAnchor),web.leadingAnchor.constraint(equalTo:content.leadingAnchor),
            web.trailingAnchor.constraint(equalTo:content.trailingAnchor),web.bottomAnchor.constraint(equalTo:bar.topAnchor),
            bar.bottomAnchor.constraint(equalTo:content.bottomAnchor),bar.leadingAnchor.constraint(equalTo:content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo:content.trailingAnchor),bar.heightAnchor.constraint(equalToConstant:32)
        ])
        if !panel.setFrameUsingName("SagePetFrame") { panel.center() }
        panel.setFrameAutosaveName("SagePetFrame")
    }
    private func observe(_ center:NotificationCenter,_ name:Notification.Name,_ action:@escaping()->Void) {
        observed.append((center,center.addObserver(forName:name,object:nil,queue:.main){ _ in action() }))
    }
    private func observeSystem() {
        let ws=NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observe(ws,name){[weak self] in self?.pauseAll("系統已暫停同步")}
        }
        observe(DistributedNotificationCenter.default(),Notification.Name("com.apple.screenIsLocked")){[weak self] in self?.pauseAll("螢幕已鎖定")}
        observe(NotificationCenter.default,NSApplication.didHideNotification){[weak self] in self?.pauseAll("已隱藏")}
    }
    private var protectionIssue: String? {
        if !monitor.hasAccess {return "未獲輸入監察授權"}
        if !KeyMonitor.safeSession() {return "系統安全輸入保護中或工作階段已鎖定"}
        return nil
    }

    private func eligible(_ front: NSRunningApplication) -> Bool {
        !front.isTerminated && front.activationPolicy == .regular &&
            front.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
            front.bundleIdentifier != nil && front.bundleIdentifier != "com.apple.Passwords"
    }

    private func isAllowedFront() -> Bool {
        guard armed, !paused, panelShown, let verified = verifiedFront, !verified.isTerminated else {return false}
        return NSWorkspace.shared.frontmostApplication == verified
    }

    private func detachFront() {
        let hadTarget = verifiedFront != nil || monitor.running
        verifiedFront = nil
        monitor.stop()
        if hadTarget {display.clear()}
    }

    private func frontChanged() {
        guard armed else {return}
        if let issue = protectionIssue {pauseAll(issue);return}
        guard panelShown else {pauseAll("已隱藏");return}
        // Ignore duplicate notifications for an already checked, still-live instance.
        if monitor.running && isAllowedFront() {return}
        detachFront()
        allowed.removeAll { $0.isTerminated }
        syncStatus = "等待已信任 App"
        if let front = NSWorkspace.shared.frontmostApplication, eligible(front) {
            let saved = trust.allows(front)
            if saved || allowed.contains(front) {
                verifiedFront = front
                if monitor.start() {
                    syncStatus = (saved ? "同步中 · 已信任 " : "同步中 · 本次允許 ") + (front.localizedName ?? "App")
                } else if NSWorkspace.shared.frontmostApplication == front {
                    pauseAll(protectionIssue ?? "無法啟動輸入監察")
                    return
                } else {
                    verifiedFront = nil // A later activation notification reconciles the new target.
                }
            } else {
                syncStatus = "未允許的 App · " + (front.localizedName ?? "待命")
            }
        }
        refresh()
    }

    private func beginSession() {
        guard display.ready, !closing else {return}
        if let issue = protectionIssue {pauseAll(issue);return}
        show()
        armed = true
        paused = false
        notice = nil
        if foregroundObserver == nil {
            foregroundObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.frontChanged() }
            // macOS has no public TCC revocation notification. Check protection only while armed,
            // including standby. Foreground identity resolution is driven by Workspace notifications.
            let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
                if let self = self, let issue = self.protectionIssue {self.pauseAll(issue)}
            }
            timer.tolerance = 0.25
            RunLoop.main.add(timer, forMode: .common)
            protectionTimer = timer
        }
        frontChanged()
    }

    private func endSession() {
        consentGeneration += 1
        armed = false
        verifiedFront = nil
        allowed.removeAll()
        monitor.stop()
        protectionTimer?.invalidate()
        protectionTimer = nil
        if let token = foregroundObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            foregroundObserver = nil
        }
    }

    private func pauseAll(_ reason:String) {
        endSession()
        paused=true
        demoWork?.cancel();demoWork=nil
        notice=reason;display?.setPaused(true);refresh()
    }
    private func refresh() {
        guard item != nil else{return}
        label.stringValue = armed ? syncStatus : ("同步已關閉" + (notice.map { " · " + $0 } ?? ""))
        label.toolTip=label.stringValue + " · " + mode
        syncButton.title=armed ? "暫停":"同步"
        muteButton.title=prefs.bool(forKey:"muted") ? "開聲":"靜音"
        item.button?.image=NSImage(systemSymbolName:monitor.running ? "keyboard.fill":"keyboard",accessibilityDescription:"Sage Keys")
        item.button?.title=armed ? (monitor.running ? " 同步":" 待命") : ""
        item.button?.toolTip="Sage Keys · "+label.stringValue
    }
    private func applySettings() {
        panel.level=prefs.bool(forKey:"pinned") ? .floating:.normal
        display.configure(muted:prefs.bool(forKey:"muted"),eco:prefs.bool(forKey:"eco"),top:prefs.bool(forKey:"top"),tone:prefs.string(forKey:"tone") ?? "rainy")
        refresh()
    }
    private func requestAccess(for generation: Int) -> Bool {
        let granted = monitor.hasAccess || CGRequestListenEventAccess()
        guard generation == consentGeneration, !closing else {return false}
        if !granted {pauseAll("未獲輸入監察授權")}
        return granted
    }
    @objc private func toggleSync() {
        if armed {pauseAll("已暫停");return}
        guard display.ready else {notice="等待鍵盤載入";refresh();return}
        if trust.entries.isEmpty {addFront();return}
        if requestAccess(for: consentGeneration) {beginSession()}
    }

    private static let scope = "範圍涵蓋整個 App，用目前按住的物理鍵位驅動本機鍵帽及錄音。瀏覽器的所有網站都在同一範圍內。無法辨識每個網站或密碼欄，輸入敏感資料前請暫停。"
    @objc private func addFront() {
        guard display.ready else {notice="等待鍵盤載入";refresh();return}
        guard let front = NSWorkspace.shared.frontmostApplication, eligible(front) else {
            if !armed {notice="先選取要同步的文字 App";refresh()}
            return
        }
        guard KeyMonitor.safeSession() else {pauseAll("系統安全輸入保護中或工作階段已鎖定");return}
        let prior = allowed.filter { !$0.isTerminated }
        pauseAll("等待確認")
        let generation = consentGeneration
        let candidate = SignedProcess(front)?.identity
        let alert = NSAlert()
        alert.messageText = "允許「" + (front.localizedName ?? "目前 App") + "」同步？"
        alert.informativeText = [front.bundleIdentifier ?? "", candidate?.signer ?? "無法驗證簽署者，只可允許本次程序", Self.scope].joined(separator: "\n\n")
        alert.addButton(withTitle: "允許並開始同步")
        alert.addButton(withTitle: "取消")
        alert.showsSuppressionButton = candidate != nil
        alert.suppressionButton?.title = "記住此 App，下次手動開啟同步時自動跟隨"
        alert.suppressionButton?.state = .off
        let response = alert.runModal()
        guard generation == consentGeneration else {return}
        guard response == .alertFirstButtonReturn else {pauseAll("已取消允許");return}
        guard requestAccess(for: generation) else {return}
        guard KeyMonitor.safeSession() else {pauseAll("系統安全輸入保護中或工作階段已鎖定");return}
        let remember = alert.showsSuppressionButton && alert.suppressionButton?.state == .on
        guard approve(front, saving: remember, candidate: candidate, prior: prior) else {
            pauseAll("App 身分有變，請重新選取");return
        }
        beginSession()
    }

    private func approve(_ process: NSRunningApplication, saving: Bool, candidate: TrustedApp?,
                         prior: [NSRunningApplication]) -> Bool {
        guard eligible(process) else {return false}
        if saving {
            guard let approval = candidate, let live = SignedProcess(process), live.matches(approval) else {return false}
            trust.save(approval)
        }
        allowed = prior.filter { !$0.isTerminated && $0 != process }
        if !saving {allowed.append(process)}
        return true
    }

    private func forget(_ bundleID: String?) {
        // Detach before changing scope, even when a menu is tracking.
        if armed {detachFront()}
        if let id = bundleID {
            trust.remove(id)
            allowed.removeAll { $0.bundleIdentifier == id }
        } else {
            trust.clear()
            allowed.removeAll()
        }
        frontChanged()
    }

    @objc private func removeApp(_ item: NSMenuItem) {
        if let id = item.representedObject as? String {forget(id)}
    }
    @objc private func clearTrust() {
        let alert = NSAlert()
        alert.messageText = "清空已信任 App？"
        alert.informativeText = "會移除所有已保存及本次允許的 App，並暫停同步。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "清空並暫停")
        if alert.runModal() == .alertSecondButtonReturn {pauseAll("已清空信任清單");forget(nil)}
    }

    private func trustMenu() -> NSMenu {
        let list = NSMenu()
        list.addItem(withTitle: "授權涵蓋整個 App 及其所有網站，敏感輸入前請暫停", action: nil, keyEquivalent: "")
        _ = entry(list, "允許目前 App…", #selector(addFront))
        list.addItem(.separator())
        if trust.entries.isEmpty {
            list.addItem(withTitle: "尚未保存任何 App", action: nil, keyEquivalent: "")
        } else {
            for app in trust.entries.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
                let row = NSMenuItem(title: app.name, action: nil, keyEquivalent: "")
                let detail = NSMenu()
                detail.addItem(withTitle: app.bundleID, action: nil, keyEquivalent: "")
                detail.addItem(withTitle: app.signer, action: nil, keyEquivalent: "")
                entry(detail, "移除此 App", #selector(removeApp(_:))).representedObject = app.bundleID
                list.addItem(row); row.submenu = detail
            }
            list.addItem(.separator())
            _ = entry(list, "清空信任清單…", #selector(clearTrust))
        }
        return list
    }
    @objc private func toggleMute(){prefs.set(!prefs.bool(forKey:"muted"),forKey:"muted");applySettings()}
    @objc private func quality(){prefs.set(!prefs.bool(forKey:"eco"),forKey:"eco");applySettings()}
    @objc private func pose(){prefs.set(!prefs.bool(forKey:"top"),forKey:"top");applySettings()}
    @objc private func pin(){prefs.set(!prefs.bool(forKey:"pinned"),forKey:"pinned");applySettings()}
    @objc private func tone(_ sender:NSMenuItem) {
        guard let value=sender.representedObject as? String else{return}
        prefs.set(value,forKey:"tone");applySettings(); if !armed {demo()}
    }
    @objc private func demo() {
        guard !armed,display.ready else{return}
        show();demoWork?.cancel();display.clear()
        display.setKeys(["Space"])
        let release=DispatchWorkItem{[weak self] in self?.display.setKeys([])}
        demoWork=release;DispatchQueue.main.asyncAfter(deadline:.now()+0.09,execute:release)
    }
    private var panelShown: Bool {
        panel != nil && panel.isVisible && !panel.isMiniaturized && !NSApp.isHidden
    }
    @objc private func show() {
        guard !closing, panel != nil else {return}
        if NSApp.isHidden {NSApp.unhideWithoutActivation()}
        if panel.isMiniaturized {panel.deminiaturize(nil)}
        panel.orderFrontRegardless()
        if !armed {paused=false;notice=nil;display.setPaused(false)}
        refresh()
    }
    @objc private func hide() {pauseAll("已隱藏");panel.orderOut(nil)}
    func windowShouldClose(_ sender:NSWindow)->Bool {hide();return false}
    func windowDidMiniaturize(_ notification:Notification){pauseAll("已縮小")}
    func windowDidDeminiaturize(_ notification:Notification) {show()}
    func applicationShouldHandleReopen(_ sender:NSApplication, hasVisibleWindows flag:Bool) -> Bool {
        // AppKit may count other windows. The existing pet is the reopen target.
        #if SAGE_QA
        reopenCount += 1
        #endif
        if panelShown {panel.orderFrontRegardless()} else {show()}
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool {false}
    @objc private func quit(){NSApp.terminate(nil)}
    @objc private func login(){
        do {
            if SMAppService.mainApp.status == .requiresApproval {SMAppService.openSystemSettingsLoginItems()}
            else if SMAppService.mainApp.status == .enabled {try SMAppService.mainApp.unregister()}
            else {try SMAppService.mainApp.register()}
        } catch {notice="請在系統設定檢查登入項目";refresh()}
    }
    private func entry(_ menu:NSMenu,_ name:String,_ action:Selector,checked:Bool?=nil)->NSMenuItem {
        let m=NSMenuItem(title:name,action:action,keyEquivalent:"");m.target=self
        if let checked=checked {m.state=checked ? .on:.off}
        menu.addItem(m);return m
    }
    func menuNeedsUpdate(_ menu:NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: label.stringValue, action: nil, keyEquivalent: "")
        _=entry(menu,armed ? "立即暫停同步":"開啟本次跨 App 同步",#selector(toggleSync))
        let manage = NSMenuItem(title: "管理已信任 App", action: nil, keyEquivalent: "")
        menu.addItem(manage); manage.submenu = trustMenu()
        if armed {_=entry(menu,"允許另一個目前 App…",#selector(addFront))}
        _=entry(menu,panelShown ? "隱藏並暫停":"顯示桌寵",panelShown ? #selector(hide):#selector(show))
        _=entry(menu,"試敲空白鍵",#selector(demo))
        menu.addItem(.separator())
        _=entry(menu,"靜音",#selector(toggleMute),checked:prefs.bool(forKey:"muted"))
        for (name,id) in [("Rainy 75","rainy"),("HHKB Topre","topre"),("Cherry MX Brown","brown")] {
            entry(menu,name,#selector(tone(_:)),checked:prefs.string(forKey:"tone")==id).representedObject=id
        }
        menu.addItem(.separator())
        _=entry(menu,prefs.bool(forKey:"eco") ? "省電 · 15 FPS（切換至 30）":"標準 · 30 FPS（切換至 15）",#selector(quality))
        _=entry(menu,"俯視",#selector(pose),checked:prefs.bool(forKey:"top"))
        _=entry(menu,"保持置頂",#selector(pin),checked:prefs.bool(forKey:"pinned"))
        _=entry(menu,SMAppService.mainApp.status == .requiresApproval ? "登入項目等待系統核准…":"登入時啟動",#selector(login),checked:SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator());_=entry(menu,"退出 Sage Keys",#selector(quit))
    }
    @objc private func openOptions(_ sender:NSButton) {
        let menu=NSMenu();menuNeedsUpdate(menu);menu.popUp(positioning:nil,at:NSPoint(x:0,y:sender.bounds.maxY),in:sender)
    }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if closing {return .terminateLater}
        shutdown { DispatchQueue.main.async {sender.reply(toApplicationShouldTerminate:true)} }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification:Notification) {if !closing {shutdown()}}
    func shutdown(completion:@escaping()->Void = {}) {
        guard !closing else{return};closing=true
        endSession();demoWork?.cancel()
        for (center,token) in observed {center.removeObserver(token)};observed.removeAll()
        panel?.delegate=nil;panel?.orderOut(nil)
        if let item=item {NSStatusBar.system.removeStatusItem(item)}
        item=nil
        display.close { [weak self] in
            self?.display=nil;self?.panel=nil
            completion()
        }
    }
}

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
    #endif
    private let monitor=KeyMonitor()
    private var item: NSStatusItem!
    private let label=NSTextField(labelWithString:"載入中")
    private let syncButton=NSButton()
    private let muteButton=NSButton()
    private let prefs=UserDefaults.standard
    private var allowed=[NSRunningApplication]()
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
        monitor.interrupted={ [weak self] in self?.pauseAll("同步已暫停") }
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
        panel=FloatingPanel(contentRect:NSRect(x:0,y:0,width:400,height:250),styleMask:[.titled,.closable,.resizable,.nonactivatingPanel],backing:.buffered,defer:false)
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
        observe(ws,NSWorkspace.didActivateApplicationNotification){[weak self] in self?.frontChanged()}
        observe(NotificationCenter.default,NSApplication.didHideNotification){[weak self] in self?.pauseAll("已隱藏")}
    }
    private func isAllowedFront()->Bool {
        guard armed,!paused,panel.isVisible,let front=NSWorkspace.shared.frontmostApplication else{return false}
        return allowed.contains { !$0.isTerminated && $0==front }
    }
    private func frontChanged() {
        guard armed else{return}
        monitor.stop();display.clear()
        allowed.removeAll{$0.isTerminated}
        if isAllowedFront(),!monitor.start() {pauseAll("保護狀態或授權有變，已暫停")}
        refresh()
    }
    private func pauseAll(_ reason:String) {
        armed=false;paused=true;allowed.removeAll();monitor.stop()
        demoWork?.cancel();demoWork=nil
        notice=reason;display?.setPaused(true);refresh()
    }
    private func refresh() {
        guard item != nil else{return}
        label.stringValue=notice ?? (armed ? (monitor.running ? "● 跨 App 同步中":"等待允許的 App") : "Sage 75 · "+(paused ? "已暫停":mode))
        label.toolTip=label.stringValue
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
    @objc private func toggleSync() {
        if armed {pauseAll("已暫停同步");return}
        addFront()
    }
    @objc private func addFront() {
        guard display.ready else {notice="等待鍵盤載入";refresh();return}
        guard let front=NSWorkspace.shared.frontmostApplication,front.activationPolicy == .regular,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              front.bundleIdentifier != "com.apple.Passwords" else {
            notice="先選取要同步的文字 App";refresh();return
        }
        guard KeyMonitor.safeSession() else {pauseAll("安全輸入或工作階段不明");return}
        // A modal consent dialog can run a nested event loop.
        // Disarm before opening it, including when extending the current scope.
        let prior=allowed.filter{!$0.isTerminated}
        pauseAll("等待確認")
        let alert=NSAlert()
        alert.messageText="允許「"+(front.localizedName ?? "前景 App")+"」在本次同步？"
        alert.informativeText="只以物理鍵位驅動鍵帽和錄音。系統安全輸入時暫停。部分網站及 App 的密碼欄未啟用安全輸入，輸入敏感資料前請先按暫停。暫停後清除本次允許清單。"
        alert.addButton(withTitle:"允許本次同步");alert.addButton(withTitle:"取消")
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        guard KeyMonitor.authorized || CGRequestListenEventAccess() else {
            pauseAll("未獲授權 · 請見「輸入監控」");return
        }
        guard KeyMonitor.safeSession() else {pauseAll("系統保護中");return}
        allowed=prior
        if !allowed.contains(front) {allowed.append(front)}
        armed=true;paused=false;notice=nil
        panel.orderFrontRegardless();display.setPaused(false);frontChanged()
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
    @objc private func show() {
        panel.orderFrontRegardless()
        if !armed {paused=false;notice=nil;display.setPaused(false)}
        refresh()
    }
    @objc private func hide() {pauseAll("已隱藏");panel.orderOut(nil)}
    func windowShouldClose(_ sender:NSWindow)->Bool {hide();return false}
    func windowDidMiniaturize(_ notification:Notification){pauseAll("已縮小")}
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
        _=entry(menu,armed ? "立即暫停同步":"允許目前 App 並開始同步…",#selector(toggleSync))
        if armed {_=entry(menu,"允許另一個目前 App…",#selector(addFront))}
        _=entry(menu,panel.isVisible ? "隱藏並暫停":"顯示桌寵",panel.isVisible ? #selector(hide):#selector(show))
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
        monitor.stop();armed=false;allowed.removeAll();demoWork?.cancel()
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

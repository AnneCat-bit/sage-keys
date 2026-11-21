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
    private var foregroundObserver: NSKeyValueObservation?
    private var protectionTimer: Timer?
    private let progress = PermissionProgress()
    private var guide: PermissionGuide?
    private var reportedAtLaunch = false
    private var recordedSigningHash = false
    private var channelFailed = false
    private var oneTimeTarget: NSRunningApplication?
    private var oneTimeSignature: TrustedApp?
    private var needsPermissionHelp = false
    private var restoringGuide = true
    private var selectingTarget = false
    private var consentGeneration = 0
    private var terminationReplyPending = false
    private var syncStatus = "等待已信任 App"
    private var armed=false, paused=false, closing=false
    private var mode="載入中", notice:String?
    private var observed: [(NotificationCenter,NSObjectProtocol)]=[]
    private var demoWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification:Notification) {
        reportedAtLaunch = progress.switchReportedOn
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
        display.onReady={ [weak self] value in
            guard let self = self else {return}
            self.mode=value; self.refresh()
            if self.restoringGuide {
                self.restoringGuide=false
                if self.progress.resumeOnLaunch {self.openGuide()}
            }
        }
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
                    channelFailed=false
                    syncStatus = (saved ? "同步中 · 已信任 " : "同步中 · 本次允許 ") + (front.localizedName ?? "App")
                } else if NSWorkspace.shared.frontmostApplication == front {
                    let issue=protectionIssue
                    channelFailed = issue == nil
                    if channelFailed {needsPermissionHelp=true}
                    pauseAll(issue ?? "權限檢查已通過，事件監測未能啟動。請檢查安裝與授權。")
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
        if !recordedSigningHash {
            progress.rememberHash(InstallationCheck.runningHash())
            recordedSigningHash=true
        }
        show()
        armed = true
        paused = false
        notice = nil
        if foregroundObserver == nil {
            // Observe the actual key-event destination. A didActivate notification can
            // arrive before frontmostApplication reflects the new process.
            foregroundObserver = NSWorkspace.shared.observe(\.frontmostApplication, options: [.new]) { [weak self] _, _ in
                if Thread.isMainThread {self?.frontChanged()}
                else {DispatchQueue.main.async {self?.frontChanged()}}
            }
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
        foregroundObserver?.invalidate()
        foregroundObserver = nil
    }

    private func pauseAll(_ reason:String) {
        endSession()
        if reason == "未獲輸入監察授權" {needsPermissionHelp = true}
        paused=true
        demoWork?.cancel();demoWork=nil
        notice=reason;display?.setPaused(true);refresh()
    }
    private func refresh() {
        guard item != nil else{return}
        label.stringValue = armed ? syncStatus : ("同步已關閉" + (notice.map { " · " + $0 } ?? ""))
        label.toolTip=label.stringValue + " · " + mode
        if armed {syncButton.title = "暫停"}
        else if selectingTarget {syncButton.title = "選取 App"}
        else {syncButton.title = needsPermissionHelp || progress.pending != nil ? "授權導覽" : "同步"}
        muteButton.title=prefs.bool(forKey:"muted") ? "開聲":"靜音"
        item.button?.image=NSImage(systemSymbolName:monitor.running ? "keyboard.fill":"keyboard",accessibilityDescription:"Sage Keys")
        item.button?.title=armed ? (monitor.running ? " 同步":" 待命") : ""
        item.button?.toolTip="Sage Keys · "+label.stringValue
    }
    private func applySettings() {
        panel.level = prefs.bool(forKey:"pinned") && guide?.window?.isVisible != true ? .floating : .normal
        display.configure(muted:prefs.bool(forKey:"muted"),eco:prefs.bool(forKey:"eco"),top:prefs.bool(forKey:"top"),tone:prefs.string(forKey:"tone") ?? "rainy")
        refresh()
    }
    private func hasPermissionOrGuide(_ intent: PendingConsent, generation: Int,
                                      process: NSRunningApplication? = nil, signature: TrustedApp? = nil) -> Bool {
        if monitor.hasAccess {progress.observedGrant();return true}
        // The system may quit the app from its own prompt. Save the user's choice first.
        progress.stage(intent)
        oneTimeTarget = process
        oneTimeSignature = signature
        if monitor.accessReading.request != false {monitor.requestListenAccess()}
        guard generation == consentGeneration, !closing else {return false}
        pauseAll("請完成輸入監察設定")
        openGuide()
        return false
    }

    private func clearDraft() {
        progress.clear()
        selectingTarget = false
        oneTimeTarget = nil
        oneTimeSignature = nil
        needsPermissionHelp = false
        dismissGuide()
    }

    private func dismissGuide() {
        guide?.dismiss()
        panel.level = prefs.bool(forKey:"pinned") ? .floating : .normal
    }

    @objc private func toggleSync() {
        if armed {pauseAll("已暫停");return}
        guard display.ready else {notice="等待鍵盤載入";refresh();return}
        if selectingTarget {addFront();return}
        if channelFailed {openInstallationCheck();return}
        if progress.pending != nil {openGuide();return}
        if trust.entries.isEmpty {
            if needsPermissionHelp && !monitor.hasAccess {openGuide()} else {addFront()}
            return
        }
        if hasPermissionOrGuide(.trustedList, generation: consentGeneration) {
            clearDraft()
            beginSession()
        }
    }

    @objc private func openGuide() {
        guard !closing else {return}
        if armed {pauseAll("已暫停同步")}
        if progress.pending != nil {progress.resumeNextLaunch(true)}
        else if !monitor.hasAccess {progress.stage(.help)}
        if guide == nil {
            let view = PermissionGuide()
            view.inspect = { [weak self] in InstallationCheck(previousHash:self?.progress.lastAuthorizedHash,previousBuild:self?.progress.lastAuthorizedBuild) }
            view.reportSwitch = { [weak self] on in
                self?.progress.switchReportedOn = on
                self?.updateGuide()
            }
            view.recheck = { [weak self] in self?.updateGuide() }
            view.finish = { [weak self] in self?.finishGuide() }
            view.chooseTarget = { [weak self] in
                guard let self = self else {return}
                self.clearDraft()
                self.selectingTarget = true
                self.show()
                self.notice = "先點選要同步的 App，再按「選取 App」"
                self.refresh()
            }
            view.later = { [weak self] in
                guard let self = self else {return}
                self.progress.resumeNextLaunch(false)
                if self.progress.pending == .help || (self.progress.pending == .once && self.oneTimeTarget?.isTerminated != false) {
                    self.clearDraft()
                } else {
                    self.dismissGuide()
                }
                self.refresh()
            }
            view.quitToApply = { [weak self] in
                guard let self = self else {return}
                if self.progress.pending == nil {self.progress.stage(.help)}
                self.progress.resumeNextLaunch(true)
                self.quit()
            }
            guide = view
        }
        updateGuide()
        // Give System Settings and the guide an unobstructed window while the user acts.
        panel.level = .normal
        guide?.present()
    }

    @objc private func openInstallationCheck() {
        openGuide()
        guide?.diagnostics()
    }

    private func updateGuide(_ hint: String = "") {
        let reading = monitor.accessReading
        let status = reading.status
        if reading.preflight {progress.switchReportedOn=false;reportedAtLaunch=false}
        needsPermissionHelp = status != .granted || channelFailed
        let permission = progress.statusText(status)
        var target: String
        var canConfirm = true
        switch progress.pending {
        case .remembered(let identity):
            target = "已選擇記住「" + identity.name + "」\n" + identity.bundleID + " · " + identity.signer
        case .once where oneTimeTarget?.isTerminated == false:
            target = "只允許這次的「" + (oneTimeTarget?.localizedName ?? "App") + "」。"
        case .once:
            target = "原本的單次選擇已結束。切回目標 App，再從「管理已信任 App」選「允許目前 App」。"
            canConfirm = false
        default:
            canConfirm = !trust.entries.isEmpty
            target = canConfirm ? "已保存的信任清單仍在。確認後才會開始本次同步。" : "完成後切回目標 App，再從選單允許該 App。"
        }
        let message = hint.isEmpty && channelFailed ? "上次權限檢查通過，但事件監測未能建立。請核對安裝副本，退出再開。" : hint
        guide?.update(status:permission, target:target, reading:reading, reported:progress.switchReportedOn,
                      reopened:reportedAtLaunch, canStart:reading.preflight && canConfirm && display.ready, hint:message)
        refresh()
    }

    private func finishGuide() {
        guard display.ready, !closing, monitor.hasAccess else {updateGuide();return}
        guard KeyMonitor.safeSession() else {updateGuide("系統正在保護鍵盤輸入。請離開安全輸入欄，再手動確認。");return}
        switch progress.pending {
        case .remembered(let identity):
            let matching = NSRunningApplication.runningApplications(withBundleIdentifier: identity.bundleID)
                .filter { eligible($0) && SignedProcess($0)?.matches(identity) == true }
            guard matching.count == 1,
                  approve(matching[0],saving:true,candidate:identity,prior:[]) else {
                updateGuide("請先打開原本的「" + identity.name + "」再確認。若已更換簽署身分，請重新選取並允許。");return
            }
        case .once:
            guard let process = oneTimeTarget, eligible(process),
                  oneTimeSignature.map({ SignedProcess(process)?.matches($0) == true }) ?? true,
                  approve(process,saving:false,candidate:nil,prior:[]) else {
                updateGuide("請從選單重新選取要允許的 App。");return
            }
        default:
            guard !trust.entries.isEmpty else {updateGuide();return}
        }
        clearDraft()
        beginSession()
    }

    private static let scope = "範圍涵蓋整個 App，用目前按住的物理鍵位驅動本機鍵帽及錄音。瀏覽器的所有網站都在同一範圍內。無法辨識每個網站或密碼欄，輸入敏感資料前請暫停。"
    @objc private func addFront() {
        guard display.ready else {notice="等待鍵盤載入";refresh();return}
        guard let front = NSWorkspace.shared.frontmostApplication, eligible(front) else {
            if !armed {notice="先選取要同步的文字 App";refresh()}
            return
        }
        guard KeyMonitor.safeSession() else {pauseAll("系統安全輸入保護中或工作階段已鎖定");return}
        selectingTarget = false
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
        let remember = alert.showsSuppressionButton && alert.suppressionButton?.state == .on
        let intent: PendingConsent = remember ? candidate.map(PendingConsent.remembered) ?? .once : .once
        guard hasPermissionOrGuide(intent, generation:generation, process:front, signature:candidate) else {return}
        guard KeyMonitor.safeSession() else {pauseAll("系統安全輸入保護中或工作階段已鎖定");return}
        guard approve(front, saving: remember, candidate: candidate, prior: prior) else {
            pauseAll("App 身分有變，請重新選取");return
        }
        clearDraft()
        beginSession()
    }

    private func approve(_ process: NSRunningApplication, saving: Bool, candidate: TrustedApp?,
                         prior: [NSRunningApplication]) -> Bool {
        guard eligible(process) else {return false}
        if let identity = candidate {
            guard SignedProcess(process)?.matches(identity) == true else {return false}
            if saving {trust.save(identity)}
        } else if saving {return false}
        allowed = prior.filter { !$0.isTerminated && $0 != process }
        if !saving {allowed.append(process)}
        return true
    }

    private func forget(_ bundleID: String?) {
        // Detach before changing scope, even when a menu is tracking.
        if armed {detachFront()}
        if case .remembered(let saved) = progress.pending, saved.bundleID == bundleID {clearDraft()}
        if let id = bundleID {
            trust.remove(id)
            allowed.removeAll { $0.bundleIdentifier == id }
        } else {
            clearDraft()
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
    @objc private func hide() {pauseAll("已隱藏");dismissGuide();panel.orderOut(nil)}
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
    @objc private func quit() {
        guard !closing else {return}
        // Finish WebKit work in the ordinary run loop before AppKit enters its quit loop.
        shutdown { [weak self] in
            if self?.terminationReplyPending == false {NSApp.terminate(nil)}
        }
    }
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
        _=entry(menu,"輸入監察授權導覽…",#selector(openGuide))
        _=entry(menu,"檢查安裝與授權…",#selector(openInstallationCheck))
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
        if closing && display == nil {return .terminateNow}
        terminationReplyPending = true
        if !closing {shutdown()}
        return .terminateLater
    }
    func applicationWillTerminate(_ notification:Notification) {if !closing {shutdown()}}
    func shutdown(completion:@escaping()->Void = {}) {
        guard !closing else{return};closing=true
        endSession();demoWork?.cancel();guide?.dismiss();guide=nil
        for (center,token) in observed {center.removeObserver(token)};observed.removeAll()
        panel?.delegate=nil;panel?.orderOut(nil)
        if let item=item {NSStatusBar.system.removeStatusItem(item)}
        item=nil
        display.close { [weak self] in
            self?.display=nil;self?.panel=nil
            completion()
            if self?.terminationReplyPending == true {
                RunLoop.main.perform(inModes: [.default, .modalPanel, .eventTracking]) {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
            }
        }
    }
}

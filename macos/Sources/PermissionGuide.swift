import AppKit
import IOKit.hid

enum ListenStatus: String {
    case granted, denied, undetermined, inconsistent

    static func current(preflight: Bool) -> Self {
        if preflight {return .granted}
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeDenied: return .denied
        case kIOHIDAccessTypeUnknown: return .undetermined
        default: return .inconsistent
        }
    }
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
            return past == build ? "之前有權限，目前已失效。請重新授權。" : "更新後，新版本目前沒有輸入監察權限。"
        }
        switch status {
        case .denied: return "macOS 目前拒絕輸入監察存取。可在系統設定更改。"
        case .undetermined: return "尚未取得權限。macOS 未回報是否已作選擇。"
        default: return "系統權限狀態未能確定。請檢查設定後再試。"
        }
    }
}

final class PermissionGuide: NSWindowController, NSWindowDelegate {
    private let status = NSTextField(wrappingLabelWithString: "")
    private let target = NSTextField(wrappingLabelWithString: "")
    private let feedback = NSTextField(wrappingLabelWithString: "")
    let confirm = NSButton()
    var recheck: () -> Void = {}
    var finish: () -> Void = {}
    var chooseTarget: () -> Void = {}
    var later: () -> Void = {}
    var quitToApply: () -> Void = {}

    init() {
        let window = NSPanel(contentRect: NSRect(x:0,y:0,width:460,height:460),
                             styleMask:[.titled,.closable], backing:.buffered, defer:false)
        super.init(window: window)
        window.title = "Sage Keys · 輸入監察導覽"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top:18,left:20,bottom:16,right:20)
        let header = NSView()
        let badge = NSImageView(image:NSImage(systemSymbolName:"keyboard", accessibilityDescription:nil)!)
        badge.contentTintColor = NSColor(srgbRed:0.33, green:0.51, blue:0.40, alpha:1)
        let heading = NSTextField(labelWithString:"讓桌寵跟隨你的鍵盤")
        heading.font = .systemFont(ofSize:19,weight:.semibold)
        for v in [badge,heading] {v.translatesAutoresizingMaskIntoConstraints=false;header.addSubview(v)}
        NSLayoutConstraint.activate([badge.leadingAnchor.constraint(equalTo:header.leadingAnchor),badge.centerYAnchor.constraint(equalTo:header.centerYAnchor),
            heading.leadingAnchor.constraint(equalTo:badge.trailingAnchor,constant:8),heading.topAnchor.constraint(equalTo:header.topAnchor),
            heading.bottomAnchor.constraint(equalTo:header.bottomAnchor),heading.trailingAnchor.constraint(equalTo:header.trailingAnchor)])
        stack.addArrangedSubview(header)
        status.font = .systemFont(ofSize:14,weight:.semibold)
        for field in [status, target, feedback] {field.preferredMaxLayoutWidth=420;field.setContentCompressionResistancePriority(.required,for:.vertical)}
        stack.addArrangedSubview(status)
        stack.addArrangedSubview(target)
        func step(_ symbol: String, _ copy: String) {
            let icon = NSImageView(image:NSImage(systemSymbolName:symbol,accessibilityDescription:nil)!)
            icon.contentTintColor = .secondaryLabelColor
            let field = NSTextField(wrappingLabelWithString:copy)
            field.preferredMaxLayoutWidth = 388
            let row = NSStackView(views:[icon,field]);row.alignment = .top;row.spacing=9
            icon.widthAnchor.constraint(equalToConstant:20).isActive=true
            stack.addArrangedSubview(row)
        }
        step("1.circle","打開「私隱與保安」→「輸入監察」（也稱「輸入監控」），開啟 Sage Keys 旁的開關。")
        step("2.circle","找不到 Sage Keys？按「＋」加入目前這份 App。更新後舊開關仍然無效？可先選舊 Sage Keys 按「−」，再加入新版。")
        step("3.circle","回來按「重新檢查權限」。若系統要求重開，請退出，再從 Finder 開啟同一份 Sage Keys。")
        func button(_ text:String, _ selector:Selector) -> NSButton {
            let b=NSButton(title:text,target:self,action:selector);b.bezelStyle = .rounded;return b
        }
        func row(_ buttons:[NSButton]) {let line=NSStackView(views:buttons);line.spacing=6;stack.addArrangedSubview(line)}
        row([button("打開輸入監察設定",#selector(openInput)),button("打開私隱與保安",#selector(openPrivacy))])
        feedback.font = .systemFont(ofSize:12)
        feedback.textColor = .secondaryLabelColor
        stack.addArrangedSubview(feedback)
        row([button("重新檢查權限",#selector(check)),button("在 Finder 顯示此版本",#selector(reveal)),button("重新選取 App",#selector(selectTarget))])
        confirm.title="確認並開始本次同步";confirm.target=self;confirm.action = #selector(start);confirm.bezelStyle = .rounded
        row([confirm,button("稍後再說",#selector(deferGuide)),button("退出並保留進度",#selector(quit))])
        let content = NSView()
        window.contentView = content
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo:content.trailingAnchor),stack.topAnchor.constraint(equalTo:content.topAnchor)])
        stack.widthAnchor.constraint(equalToConstant:460).isActive=true
        window.center()
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) unsupported")}
    func update(status text:String, target copy:String, canStart:Bool, hint:String) {
        status.stringValue=text;target.stringValue=copy;confirm.isEnabled=canStart
        feedback.stringValue=hint.isEmpty ? "若只打開了系統設定首頁，可按「打開私隱與保安」再選「輸入監察」。" : hint
        fit()
    }
    private func fit() {
        guard let window=window,let stack=window.contentView?.subviews.first as? NSStackView else {return}
        window.setContentSize(NSSize(width:460,height:ceil(stack.fittingSize.height)+3))
    }
    func present() {
        NSApp.activate(ignoringOtherApps:true)
        window?.makeKeyAndOrderFront(nil)
    }
    func dismiss() {window?.orderOut(nil)}
    func windowShouldClose(_ sender:NSWindow)->Bool {later();return false}
    @objc private func openInput(){openSettings(true)}
    @objc private func openPrivacy(){openSettings(false)}
    private func openSettings(_ input:Bool) {
        switch SettingsLinks.open(inputPane:input) {
        case .input: feedback.stringValue="若未看到「輸入監察」，按「打開私隱與保安」，再選「輸入監察」。"
        case .privacy,.settings: feedback.stringValue="請在「私隱與保安」選「輸入監察」，開啟 Sage Keys 後回來重新檢查。"
        case .unavailable: feedback.stringValue="未能打開設定。請從左上角  → 系統設定 → 私隱與保安 → 輸入監察。"
        }
        fit()
    }
    @objc private func reveal(){NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])}
    @objc private func selectTarget(){chooseTarget()}
    @objc private func check(){recheck()}
    @objc private func start(){finish()}
    @objc private func deferGuide(){later()}
    @objc private func quit(){quitToApply()}
}

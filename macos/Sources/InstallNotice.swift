import AppKit

// Installation has no authority to request Input Monitoring or start a session.
final class InstallNotice: NSWindowController, NSWindowDelegate {
    private let message = NSTextField(wrappingLabelWithString:"")
    var closePreview: () -> Void = {}
    var quitApp: () -> Void = {}
    var refresh: () -> Void = {}
    init() {
        let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:500,height:370),
                          styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init(window:panel)
        panel.title="Sage Keys · 安裝";panel.isReleasedWhenClosed=false
        panel.backgroundColor=GuideDrawing.paper;panel.appearance=NSAppearance(named:.aqua)
        panel.hidesOnDeactivate=false;panel.delegate=self
        let art=GuideDrawing(.installation)
        message.font = .systemFont(ofSize:14)
        message.textColor=GuideDrawing.ink
        let actions=NSStackView()
        for (title,selector) in [("打開應用程式",#selector(applications)),("退出這份 Sage Keys",#selector(quit)),("先試用鍵盤",#selector(preview))] {
            let button=NSButton(title:title,target:self,action:selector)
            button.bezelStyle = .rounded
            actions.addArrangedSubview(button)
        }
        let stack=NSStackView(views:[art,message,actions])
        stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=16
        stack.translatesAutoresizingMaskIntoConstraints=false
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:panel.contentView!.leadingAnchor,constant:22),
            stack.trailingAnchor.constraint(equalTo:panel.contentView!.trailingAnchor,constant:-22),
            stack.topAnchor.constraint(equalTo:panel.contentView!.topAnchor,constant:16),
            art.widthAnchor.constraint(equalTo:stack.widthAnchor),art.heightAnchor.constraint(equalToConstant:95),
            message.widthAnchor.constraint(equalTo:stack.widthAnchor)
        ])
        panel.center()
    }
    required init?(coder:NSCoder){fatalError()}
    func update(_ check:InstallationCheck) {
        let text:String
        if !check.otherProcesses.isEmpty {
            text="另一份 Sage Keys 仍在運行。\n請先從各份 App 的選單列選「退出 Sage Keys」，再開啟已安裝版本。\n\n" + check.otherProcesses.joined(separator:"\n")
        } else if check.diskMatchesRunning == false {
            text="這個程序與磁碟上的 App 已不同。\n請退出這份 Sage Keys，再從「應用程式」開啟。"
        } else {
            text="先完成 Finder 安裝\n將 DMG 裏的 Sage Keys 拖到 Applications。安裝完成後退出這份程序、退出磁碟映像，再從「應用程式」開啟。\n\n目前位置\n" + check.path.path
        }
        message.stringValue=text
        message.preferredMaxLayoutWidth=456
        let height=message.cell?.cellSize(forBounds:NSRect(x:0,y:0,width:456,height:2000)).height ?? 160
        window?.setContentSize(NSSize(width:500,height:max(320,height+185)))
    }
    func present(){NSApp.activate(ignoringOtherApps:true);window?.makeKeyAndOrderFront(nil)}
    func windowDidBecomeKey(_ notification:Notification){refresh()}
    func windowShouldClose(_ sender:NSWindow)->Bool {closePreview();return false}
    @objc private func applications(){NSWorkspace.shared.open(URL(fileURLWithPath:"/Applications"))}
    @objc private func quit(){quitApp()}
    @objc private func preview(){closePreview()}
}

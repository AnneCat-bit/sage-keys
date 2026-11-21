import AppKit
import WebKit

private final class PetMessages: NSObject, WKScriptMessageHandler {
    weak var owner: PetWeb?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let m=message.body as? [String:String] else { return }
        owner?.message(m)
    }
}

final class PetWeb: NSObject, WKNavigationDelegate {
    let web: WKWebView
    private let page: URL
    private let messages = PetMessages()
    var onReady: (String)->Void = { _ in }
    var onFailure: (String)->Void = { _ in }
    private(set) var ready=false
    private(set) var paused=false
    private var latest=Set<String>(), delivered=Set<String>()
    private var busy=false, closed=false, generation=0
    private var preferences: [String:Any] = [:]

    init(resources: URL, probe: WKUserScript? = nil) {
        page=resources.appendingPathComponent("index.html")
        let config=WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback=[]
        config.preferences.javaScriptCanOpenWindowsAutomatically=false
        config.userContentController.add(messages,name:"pet")
        if let probe=probe { config.userContentController.addUserScript(probe) }
        web=WKWebView(frame:NSRect(x:0,y:0,width:400,height:216),configuration:config)
        super.init()
        messages.owner=self
        web.navigationDelegate=self
        web.allowsBackForwardNavigationGestures=false
    }

    func load() { web.loadFileURL(page,allowingReadAccessTo:page.deletingLastPathComponent()) }

    fileprivate func message(_ m:[String:String]) {
        guard !closed else { return }
        if m["kind"]=="ready", let mode=m["value"], ["2D","3D"].contains(mode) {
            ready=true
            sendSettings()
            setPaused(paused)
            onReady(mode)
        } else if m["kind"]=="audio" { onFailure("錄音暫不可用") }
    }

    func configure(muted:Bool,eco:Bool,top:Bool,tone:String) {
        preferences=["muted":muted,"quality":eco ? "eco":"standard","pose":top ? "top":"angle","tone":tone]
        sendSettings()
    }
    private func sendSettings() {
        guard ready, !preferences.isEmpty else { return }
        call("window.sagePet.settings(value)",preferences)
    }
    private func call(_ script:String,_ value:Any) {
        web.callAsyncJavaScript(script,arguments:["value":value],in:nil,in:.page,completionHandler:nil)
    }
    func setPaused(_ value:Bool) {
        paused=value
        clear()
        if ready { call("window.sagePet.pause(value)",value) }
    }
    func clear() {
        generation += 1
        latest.removeAll(); delivered.removeAll()
        if ready { call("window.sagePet.reset()",false) }
    }

    func setKeys(_ keys:Set<String>) {
        guard ready, !paused, !closed else { return }
        latest=keys
        flush()
    }
    // One WebKit request in flight; retain only the most recent physical state.
    private func flush() {
        guard !busy,ready,!paused,!closed,latest != delivered else { return }
        busy=true; delivered=latest
        let epoch=generation
        web.callAsyncJavaScript("window.sagePet.keys(value)",arguments:["value":Array(latest)],in:nil,in:.page) { [weak self] result in
            guard let self=self else { return }
            self.busy=false
            if case .failure = result, epoch==self.generation, !self.closed {
                self.failed(); return
            }
            self.flush()
        }
    }
    func close() {
        guard !closed else { return }
        closed=true; ready=false; latest.removeAll(); delivered.removeAll(); generation+=1
        web.evaluateJavaScript("window.sagePet?.close()")
        web.stopLoading(); web.navigationDelegate=nil
        web.configuration.userContentController.removeScriptMessageHandler(forName:"pet")
        web.configuration.userContentController.removeAllUserScripts()
        messages.owner=nil
        web.removeFromSuperview()
    }
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        let ok=action.targetFrame?.isMainFrame == true && action.request.url?.standardizedFileURL==page.standardizedFileURL
        decisionHandler(ok ? .allow:.cancel)
    }
    private func failed() {
        guard !closed else { return }
        ready=false; paused=true; latest.removeAll(); delivered.removeAll(); generation+=1
        onFailure("顯示層中斷，請重新開啟 Sage Keys")
    }
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView) { failed() }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) { failed() }
}

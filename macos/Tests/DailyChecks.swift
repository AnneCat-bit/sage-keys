import AppKit
import Carbon

protocol DenialFixture: PhysicalMonitoring {
    var simulateDenied: Bool { get set }
}
extension KeyMonitor: DenialFixture {}

// A state-only endpoint for machines on which macOS denies Input Monitoring.
// It has no event source, callback invocation, system event API or key data.
final class SilentEndpoint: DenialFixture {
    var simulateDenied = false
    var hasAccess: Bool { !simulateDenied }
    var missingStatus = ListenStatus.denied
    var listenStatus: ListenStatus {hasAccess ? .granted : missingStatus}
    var grantOnRequest = false
    private(set) var requests = 0
    func requestListenAccess() {requests += 1;if grantOnRequest {simulateDenied = false}}
    private(set) var running = false
    var changed: (Set<String>) -> Void = { _ in }
    var interrupted: () -> Void = {}
    var foregroundChanged: () -> Void = {}
    var foregroundAllowed: () -> Bool = { false }
    func start() -> Bool {
        running = hasAccess && KeyMonitor.safeSession() && foregroundAllowed()
        return running
    }
    func stop() { running = false }
}

@MainActor
struct DailyChecks {
    let pet: PetApp
    let endpoint: DenialFixture
    func wait(_ name: String, seconds: Double = 6, until condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < end else {throw Failure("timed out: " + name + " · " + pet.qaStatus + " · front=" + (NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"))}
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func focus(_ bundle: String) async throws -> NSRunningApplication {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {throw Failure(bundle)}
        func running() -> NSRunningApplication? {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first { !$0.isTerminated }
        }
        let target: NSRunningApplication
        if let existing = running() {
            target = existing
        } else {
            do {target = try await open(url)}
            catch {
                // LS can time out sending a reopen event after the app has already launched.
                // The check below still requires this precise instance to become frontmost.
                guard let launched = running() else {throw error}
                target = launched
            }
        }
        _ = target.activate(options: [.activateIgnoringOtherApps])
        var frontSince: Date?
        try await wait("foreground " + bundle) {
            guard NSWorkspace.shared.frontmostApplication == target else {frontSince = nil;return false}
            if frontSince == nil {frontSince = Date()}
            return Date().timeIntervalSince(frontSince!) >= 0.20
        }
        return target
    }

    func open(_ url: URL) async throws -> NSRunningApplication {
        try await withCheckedThrowingContinuation { continuation in
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                if let app = app {continuation.resume(returning: app)}
                else {continuation.resume(throwing: error ?? Failure("Launch Services could not open application"))}
            }
        }
    }

    func menu(_ titles: String...) throws {
        var menu = NSMenu()
        pet.menuNeedsUpdate(menu)
        for (i, title) in titles.enumerated() {
            guard let n = menu.items.firstIndex(where: { $0.title.hasPrefix(title) }) else {throw Failure("missing " + title)}
            if i == titles.count - 1 { menu.performActionForItem(at: n) }
            else if let submenu = menu.items[n].submenu { menu = submenu }
            else {throw Failure("missing submenu " + title)}
        }
    }

    // Click the real AppKit dialog in the isolated QA process. No Accessibility
    // permission, system-wide UI automation, synthetic keystrokes or TCC edits.
    func dialog(button title: String, remember: Bool? = nil, perform: () throws -> Void) throws {
        var clicked = false
        var unchecked = false
        let end = Date().addingTimeInterval(5)
        func buttons(_ view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        // This timer is installed exclusively on RunLoop.main in AppKit's modal mode.
        let tick: @MainActor (Timer) -> Void = { timer in
            guard let content = NSApp.modalWindow?.contentView else {return}
            let all = buttons(content)
            if let action = all.first(where: {$0.title == title}) {
                if let remember = remember {
                    guard let check = all.first(where: {$0.title.hasPrefix("記住此 App")}) else {
                        timer.invalidate(); NSApp.abortModal(); return
                    }
                    unchecked = check.state == .off
                    if remember {check.state = .on}
                }
                clicked = true
                timer.invalidate()
                action.performClick(nil)
            } else if Date() > end {timer.invalidate(); NSApp.abortModal()}
        }
        let timer = Timer(timeInterval: 0.12, repeats: true) { timer in
            MainActor.assumeIsolated {tick(timer)}
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        defer {timer.invalidate()}
        try perform()
        try require(clicked && (remember == nil || unchecked), "actual consent/confirmation button or opt-in checkbox")
    }

    func approve(_ bundle: String, remember: Bool) async throws -> NSRunningApplication {
        let front = try await focus(bundle)
        try dialog(button: "允許並開始同步", remember: remember) {try menu("管理已信任 App", "允許目前 App")}
        _ = front.activate(options: [.activateIgnoringOtherApps])
        try await wait("attach " + bundle) {pet.qaActiveID == bundle}
        return front
    }

    func reopen() async throws -> [String: Any] {
        let original = pet.panel!
        let before = pet.reopenCount
        guard let close = original.standardWindowButton(.closeButton) else {throw Failure("red button missing")}
        close.performClick(nil)
        try require(!original.isVisible && pet.display.paused && !pet.qaWatching && !pet.qaMonitoring, "red close")
        try menu("顯示桌寵")
        try require(original.isVisible && !pet.qaArmed, "menu restore")
        close.performClick(nil)
        let running = try await open(Bundle.main.bundleURL)
        try await wait("Launch Services reopen callback") { self.pet.reopenCount > before && original.isVisible }
        try require(running.processIdentifier == getpid() && pet.panel === original && !pet.qaArmed, "reused process/panel and stayed off")
        original.miniaturize(nil)
        try await wait("minimize") {original.isMiniaturized}
        try menu("顯示桌寵")
        try await wait("deminiaturize") {!original.isMiniaturized && original.isVisible}
        return ["samePID": true, "samePanel": true, "reopenCallbacks": pet.reopenCount-before,
                "redCloseThenMenu": true, "minimizeThenShow": true, "armedAfterShow": pet.qaArmed]
    }

    func follow() async throws -> [String: Any] {
        let first = "com.apple.TextEdit", second = "com.apple.calculator", unknown = "com.apple.finder"
        let editor = try await approve(first, remember: false)
        try require(TrustedApps().entries.isEmpty, "unchecked consent persisted")
        try menu("立即暫停")
        _ = try await focus(first)
        try dialog(button: "取消", remember: false) {try menu("管理已信任 App", "允許目前 App")}
        try require(!pet.qaArmed && TrustedApps().entries.isEmpty, "cancel granted trust")
        _ = try await approve(first, remember: true)
        _ = try await approve(second, remember: true)
        let saved = TrustedApps().entries
        try require(Set(saved.map(\.bundleID)) == Set([first, second]), "reload saved trust")
        guard let real = SignedProcess(editor) else {throw Failure("TextEdit signing")}
        let otherDR = saved.first { $0.bundleID == second }!.requirement
        let wrongDR = TrustedApp(name: real.identity.name, bundleID: first, signer: real.identity.signer, requirement: otherDR)
        try require(!real.matches(wrongDR) && SignedProcess(.current) == nil, "forged requirement or ad-hoc trusted")
        var trace = [String]()
        for id in [first, second, unknown, first] {
            _ = try await focus(id)
            if id == unknown {
                try await wait("untrusted detaches") {pet.qaArmed && !pet.qaMonitoring && pet.qaStatus.contains("未允許")}
                try require(TrustedApps().entries == saved, "unknown was saved")
            } else {
                try await wait("trusted follows " + id) {pet.qaActiveID == id}
            }
            trace.append(id + " · " + pet.qaStatus)
        }
        let name = real.identity.name
        try menu("管理已信任 App", name, "移除")
        try await wait("removal detaches foreground") {pet.qaArmed && !pet.qaMonitoring}
        try require(TrustedApps().entries.map(\.bundleID) == [second], "removal durability")
        _ = try await focus(second); try await wait("remaining approval works") {pet.qaActiveID == second}
        try menu("立即暫停")
        _ = try await focus(first); _ = try await focus(second)
        try require(!pet.qaArmed && !pet.qaMonitoring && !pet.qaWatching, "pause resumed")
        try dialog(button: "清空並暫停") {try menu("管理已信任 App", "清空")}
        try require(TrustedApps().entries.isEmpty, "clear durability")
        return ["workspaceTransitions": trace, "checkboxDefaultsOff": true, "cancelGrantsNothing": true,
                "savedIdentities": saved.map {[$0.bundleID, $0.signer]}, "differentDesignatedRequirementRejected": true,
                "adHocProcessRejected": true, "removedActive": true, "cleared": true, "pauseStoppedObserversAndTimer": true]
    }

    func browserIdentity() async throws -> [String: Any] {
        let id = "com.google.Chrome"
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {throw Failure("Chrome unavailable")}
        // Use a fresh, empty profile to avoid first-run and profile chooser dialogs.
        guard let executable = Bundle(url: url)?.executableURL else {throw Failure("Chrome executable")}
        let profile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let launcher = Process()
        launcher.executableURL = executable
        launcher.arguments = ["--user-data-dir=" + profile.path, "--no-first-run", "--no-default-browser-check",
                              "--disable-background-networking", "--disable-sync", "about:blank"]
        launcher.standardOutput = FileHandle.nullDevice
        launcher.standardError = FileHandle.nullDevice
        try launcher.run()
        defer {if launcher.isRunning {launcher.terminate()}}
        var chrome: NSRunningApplication?
        try await wait("running signed browser", seconds: 12) {
            chrome = NSRunningApplication(processIdentifier: launcher.processIdentifier)
            return chrome?.bundleIdentifier == id
        }
        let start = ProcessInfo.processInfo.systemUptime
        guard let browser = chrome, let signed = SignedProcess(browser) else {throw Failure("Chrome signing identity")}
        let suite = "io.github.annecat-bit.sagekeys.qa.browser"
        let prefs = UserDefaults(suiteName: suite)!
        defer {prefs.removePersistentDomain(forName: suite)}
        let list = TrustedApps(defaults: prefs)
        list.save(signed.identity)
        let saved = TrustedApps(defaults: prefs)
        try require(signed.identity.signer.hasPrefix("Team ") && saved.allows(browser), "third-party signed identity")
        let seconds = ProcessInfo.processInfo.systemUptime - start
        saved.remove(id)
        try require(!saved.allows(browser), "removal did not revoke browser approval")
        return ["bundleID":id, "signer":signed.identity.signer, "verifiedAndReloaded":true,
                "identityAndReloadCheckSeconds":seconds, "removed":true]
    }

    func protection() async throws -> [String: Any] {
        let id = "com.apple.TextEdit"
        _ = try await approve(id, remember: true)
        endpoint.simulateDenied = true
        defer { endpoint.simulateDenied = false }
        try await wait("revoked while attached") {!pet.qaArmed && !pet.qaMonitoring && !pet.qaWatching}
        endpoint.simulateDenied = false
        _ = try await focus(id)
        try require(!pet.qaArmed, "access restoration rearmed")
        try menu("開啟本次")
        try await wait("manual enable") {pet.qaActiveID == id}
        _ = try await focus("com.apple.finder")
        try await wait("standby") {pet.qaArmed && !pet.qaMonitoring}
        endpoint.simulateDenied = true
        try await wait("revoked in standby") {!pet.qaArmed && !pet.qaWatching}
        endpoint.simulateDenied = false
        _ = try await focus(id); try menu("開啟本次")
        try await wait("reattached after manual enable") {pet.qaActiveID == id}
        guard EnableSecureEventInput() == noErr else {throw Failure("EnableSecureEventInput")}
        do {
            defer {DisableSecureEventInput()}
            try await wait("secure input") {!pet.qaArmed && pet.qaStatus.contains("安全輸入")}
        }
        try require(!pet.qaMonitoring && !pet.qaWatching, "secure input resumed")
        try menu("開啟本次")
        try await wait("manually resumed for close") {pet.qaActiveID == id}
        pet.panel.performClose(nil)
        try require(!pet.qaMonitoring && !pet.qaWatching && !pet.qaArmed, "active close left tap")
        try menu("顯示桌寵")
        try require(!pet.qaArmed && !pet.qaMonitoring, "show resumed")
        return ["simulatedRevocationAttached":true,"simulatedRevocationStandby":true,"actualSecureEventInputDisarmed":true,
                "hideRemovedTap":true,"restoreKeptOff":true,"trustRetained":TrustedApps().entries.count]
    }
}

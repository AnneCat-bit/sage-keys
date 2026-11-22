import AppKit
import Security
import Darwin
import IOKit.hid

struct AccessReading {
    enum HID: String { case granted, denied, unknown, unexpected }
    let preflight: Bool
    let hid: HID
    let request: Bool?
    var status: ListenStatus {
        if preflight {return .granted} // Core Graphics supplies the event tap we actually use.
        switch hid {
        case .denied: return .denied
        case .unknown: return .undetermined
        default: return .inconsistent
        }
    }
    static func sample(preflight: Bool, request: Bool?) -> Self {
        let hid: HID
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: hid = .granted
        case kIOHIDAccessTypeDenied: hid = .denied
        case kIOHIDAccessTypeUnknown: hid = .unknown
        default: hid = .unexpected
        }
        return Self(preflight:preflight,hid:hid,request:request)
    }
    var details: String {
        let answer = request.map {String($0)} ?? "本次程序未請求"
        return "CGPreflightListenEventAccess   \(preflight)\nCGRequestListenEventAccess   \(answer)\nIOHIDCheckAccess (ListenEvent)   \(hid.rawValue)"
    }
}

struct InstallationCheck {
    let executable: URL?
    let pathSource: String
    let reopened: Bool
    let otherProcesses: [String]
    let launchHash: String?
    let onDiskHash: String?
    let translocationEvidence: Bool
    let path: URL
    let version: String
    let bundleID: String
    let inApplications: Bool
    let copies: [URL]
    let differentInstalledCopy: URL?
    let signer: String
    let cdHash: String?
    let requirement: String?
    let validity: OSStatus?
    let diskMatchesRunning: Bool?
    let previousHashChanged: Bool
    let previousBuild: String?
    let buildChanged: Bool

    // CS_ADHOC bit in the CodeDirectory flags returned by Security.framework.
    private static let adHocFlag: UInt32 = 0x0002
    private static func canonical(_ url: URL) -> URL {url.resolvingSymlinksInPath().standardizedFileURL}
    private static func hash(_ code: SecStaticCode) -> String? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
              let d = (info as? [String:Any])?[kSecCodeInfoUnique as String] as? Data else {return nil}
        return d.map {String(format:"%02x",$0)}.joined()
    }
    static func runningHash() -> String? {
        var live: SecCode?
        var representation: SecStaticCode?
        guard SecCodeCopySelf([], &live) == errSecSuccess, let live = live,
              SecCodeCopyStaticCode(live, [], &representation) == errSecSuccess, let code = representation else {return nil}
        return hash(code)
    }
    static func hasTranslocationLayout(_ url: URL) -> Bool {
        // Use the OS temporary directory layout, UUID and read-only mount's d/ prefix.
        // A folder merely named AppTranslocation elsewhere is not evidence.
        let parts = canonical(url).pathComponents
        guard let i=parts.firstIndex(of:"AppTranslocation"), i >= 5, i+3 < parts.count,
              parts[i-1] == "T", UUID(uuidString:parts[i+1]) != nil, parts[i+2] == "d" else {return false}
        return parts.starts(with:["/","private","var","folders"]) || parts.starts(with:["/","var","folders"])
    }

    private static func processExecutable() -> (URL?, String) {
        var buffer = [CChar](repeating:0,count:4 * Int(MAXPATHLEN))
        let size = buffer.count
        let length = buffer.withUnsafeMutableBytes {proc_pidpath(getpid(),$0.baseAddress,UInt32(size))}
        if length > 0 {return (canonical(URL(fileURLWithPath:String(cString:buffer))),"proc_pidpath")}
        if let url = NSRunningApplication.current.executableURL {return (canonical(url),"NSRunningApplication")}
        return (nil,"無法讀取執行檔路徑")
    }

    // Only inspect our own bundle and known registrations for this bundle ID, on demand.
    init(previousHash: String?, previousBuild: String? = nil, launchHash: String? = nil, reopened: Bool = false) {
        let b = Bundle.main
        self.previousBuild = previousBuild
        buildChanged = previousBuild != nil && previousBuild != b.object(forInfoDictionaryKey:"CFBundleVersion") as? String
        self.reopened = reopened
        self.launchHash = launchHash
        let (binary, source) = Self.processExecutable()
        executable = binary
        pathSource = source
        let macOS = binary?.deletingLastPathComponent()
        let contents = macOS?.deletingLastPathComponent()
        let bundle = contents?.deletingLastPathComponent()
        let current: URL
        if macOS?.lastPathComponent == "MacOS", contents?.lastPathComponent == "Contents", let bundle=bundle, bundle.pathExtension == "app" {
            current = bundle
        } else {current = Self.canonical(b.bundleURL)}
        path = current
        version = (b.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "?") +
            " (" + (b.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "?") + ")"
        let id = b.bundleIdentifier ?? ""
        bundleID = id
        let appDirs = FileManager.default.urls(for:.applicationDirectory,in:[.localDomainMask,.userDomainMask])
        inApplications = appDirs.contains {current.path.hasPrefix(Self.canonical($0).path + "/")}
        translocationEvidence = !inApplications && binary.map(Self.hasTranslocationLayout) == true
        let running = NSRunningApplication.runningApplications(withBundleIdentifier:id)
        otherProcesses = running.filter {$0.processIdentifier != getpid() && !$0.isTerminated}.map {
            "PID \($0.processIdentifier) · \($0.bundleURL?.path ?? "路徑未能讀取")"
        }
        let known = NSWorkspace.shared.urlsForApplications(withBundleIdentifier:id) +
            running.compactMap(\.bundleURL) +
            appDirs.map {$0.appendingPathComponent(b.bundleURL.lastPathComponent)}
        let otherPaths = Set(known.map {Self.canonical($0).path}).subtracting([current.path])
        copies = otherPaths.sorted().map {URL(fileURLWithPath:$0,isDirectory:true)}.filter {FileManager.default.fileExists(atPath:$0.path) && Bundle(url:$0)?.bundleIdentifier == id}
        var live: SecCode?
        var disk: SecStaticCode?
        var representation: SecStaticCode?
        var info: CFDictionary?
        var dr: SecRequirement?
        var string: CFString?
        var identity = "未能讀取"
        var valid: OSStatus?
        var diskDigest: String?
        var digest: String?
        if SecCodeCopySelf([], &live) == errSecSuccess, let live = live {
            valid = SecCodeCheckValidity(live, [], nil)
            if SecCodeCopyStaticCode(live, [], &representation) == errSecSuccess, let code = representation {
                digest = Self.hash(code)
                if SecCodeCopySigningInformation(code,SecCSFlags(rawValue:kSecCSSigningInformation),&info) == errSecSuccess,
                   let props = info as? [String:Any] {
                    let flags = (props[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
                    if flags & Self.adHocFlag != 0 {identity = "ad-hoc · 無開發者團隊簽署"}
                    else {identity = props[kSecCodeInfoTeamIdentifier as String] as? String ?? "沒有 Team ID"}
                }
                if SecCodeCopyDesignatedRequirement(code,[],&dr) == errSecSuccess, let dr = dr {
                    _ = SecRequirementCopyString(dr,[],&string)
                }
            }
        }
        if SecStaticCodeCreateWithPath(current as CFURL,[],&disk) == errSecSuccess, let disk=disk {
            diskDigest = Self.hash(disk)
        }
        signer = identity; cdHash = digest; validity = valid
        onDiskHash = diskDigest
        requirement = string as String?; diskMatchesRunning = (launchHash ?? digest).flatMap {running in diskDigest.map {$0 == running}}
        let loadedHash = launchHash ?? digest
        previousHashChanged = previousHash != nil && loadedHash != nil && previousHash != loadedHash
        differentInstalledCopy = copies.first {url in
            guard let loadedHash=loadedHash,
                  appDirs.contains(where:{url.path.hasPrefix(Self.canonical($0).path + "/")}) else {return false}
            var other: SecStaticCode?
            guard SecStaticCodeCreateWithPath(url as CFURL,[],&other) == errSecSuccess, let code=other,
                  let hash=Self.hash(code) else {return false}
            return hash != loadedHash
        }
    }
    var summary: String {
        if translocationEvidence {
            return "目前程序的執行路徑符合 macOS AppTranslocation 暫時掛載格式。\n" + (executable?.path ?? path.path)
        }
        if diskMatchesRunning == false {
            return "這個程序與磁碟上這份 App 的簽署雜湊不同。舊程序可能仍在運行。\n" + path.path
        }
        if !inApplications, let installed=differentInstalledCopy {
            return "此程序仍從另一個位置執行。已安裝的副本簽署雜湊不同。\n執行中：\(path.path)\n已安裝：\(installed.path)"
        }
        if inApplications {return "目前執行位置已在「應用程式」。\n" + path.path}
        return "目前執行位置：\n" + path.path
    }
    func details(_ reading: AccessReading) -> String {
        let other = copies.isEmpty ? "未找到其他已登記副本" : copies.map(\.path).joined(separator:"\n")
        let match = diskMatchesRunning.map {$0 ? "一致" : "不同"} ?? "未能確定"
        return """
        程序   PID \(getpid()) · \(reopened ? "本程序已收到重新開啟事件" : "本程序未收到重新開啟事件")
        其他執行程序   \(otherProcesses.isEmpty ? "未發現" : otherProcesses.joined(separator:"\n"))
        版本   \(version)
        位置   \(inApplications ? "應用程式" : "其他位置")
        \(path.path)
        執行檔（\(pathSource)）   \(executable?.path ?? "未能讀取，以上顯示 bundle 路徑")
        暫時掛載路徑特徵   \(translocationEvidence ? "符合 /var/folders/…/T/AppTranslocation/<UUID>/d/ 及執行檔路徑" : "未發現")
        Bundle ID   \(bundleID)
        簽署   \(signer)
        CDHash   \(cdHash ?? "未能讀取")
        啟動時 CDHash   \(launchHash ?? "未能讀取")
        磁碟 CDHash   \(onDiskHash ?? "未能讀取")
        簽署要求   \(requirement ?? "未能讀取")
        簽署檢查 OSStatus   \(validity.map { String($0) } ?? "未能確定")
        執行中與磁碟身分   \(match)
        上次權限有效的 build   \(previousBuild ?? "沒有紀錄")
        \(previousHashChanged ? "目前 CDHash 與上次有效時不同。" : "")
        \(buildChanged ? "上次通過系統授權檢查的是另一個 build。" : "")
        其他已登記副本   \(other)

        目前系統權限   \(reading.preflight ? "有效" : previousBuild != nil ? "過去曾有效，本程序目前未通過；原因無法由 API 判定" : "本程序目前未通過；原因無法由 API 判定")
        \(reading.details)
        """
    }
}

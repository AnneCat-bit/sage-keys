import AppKit
import Security
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
    let path: URL
    let version: String
    let bundleID: String
    let inApplications: Bool
    let copies: [URL]
    let signer: String
    let cdHash: String?
    let requirement: String?
    let validity: OSStatus?
    let diskMatchesRunning: Bool?
    let previousHashChanged: Bool

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
    // Only inspect our own bundle and known registrations for this bundle ID, on demand.
    init(previousHash: String?) {
        let b = Bundle.main
        let current = Self.canonical(b.bundleURL)
        path = current
        version = (b.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "?") +
            " (" + (b.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "?") + ")"
        let id = b.bundleIdentifier ?? ""
        bundleID = id
        let appDirs = FileManager.default.urls(for:.applicationDirectory,in:[.localDomainMask,.userDomainMask])
        inApplications = appDirs.contains {current.path.hasPrefix(Self.canonical($0).path + "/")}
        let known = NSWorkspace.shared.urlsForApplications(withBundleIdentifier:id) +
            NSRunningApplication.runningApplications(withBundleIdentifier:id).compactMap(\.bundleURL) +
            appDirs.map {$0.appendingPathComponent(b.bundleURL.lastPathComponent)}
        copies = Set(known.map(Self.canonical).filter {$0.path != current.path && Bundle(url:$0)?.bundleIdentifier == id})
            .sorted {$0.path < $1.path}
        var live: SecCode?
        var disk: SecStaticCode?
        var representation: SecStaticCode?
        var info: CFDictionary?
        var dr: SecRequirement?
        var string: CFString?
        var identity = "未能讀取"
        var valid: OSStatus?
        var matches: Bool?
        var digest: String?
        if SecCodeCopySelf([], &live) == errSecSuccess, let live = live {
            valid = SecCodeCheckValidity(live, [], nil)
            if SecCodeCopyStaticCode(live, [], &representation) == errSecSuccess, let code = representation {
                digest = Self.hash(code)
                if SecCodeCopySigningInformation(code,SecCSFlags(rawValue:kSecCSSigningInformation),&info) == errSecSuccess,
                   let props = info as? [String:Any] {
                    let flags = (props[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
                    if flags & UInt32(kSecCodeSignatureAdhoc) != 0 {identity = "ad-hoc · 無開發者團隊簽署"}
                    else {identity = props[kSecCodeInfoTeamIdentifier as String] as? String ?? "沒有 Team ID"}
                }
                if SecCodeCopyDesignatedRequirement(code,[],&dr) == errSecSuccess, let dr = dr {
                    _ = SecRequirementCopyString(dr,[],&string)
                }
            }
            if SecStaticCodeCreateWithPath(current as CFURL,[],&disk) == errSecSuccess, let disk = disk,
               let diskHash = Self.hash(disk), let digest = digest {
                matches = diskHash == digest && valid == errSecSuccess
            }
        }
        signer = identity; cdHash = digest; validity = valid
        requirement = string as String?; diskMatchesRunning = matches
        previousHashChanged = previousHash != nil && digest != nil && previousHash != digest
    }
    var advice: String {
        if diskMatchesRunning == false {return "執行中與磁碟上的簽署未能核對。先退出，再從「應用程式」打開已安裝的版本。"}
        if path.pathComponents.contains("AppTranslocation") {return "macOS 從隔離的暫時位置啟動了這份 App。請退出，將 App 放進「應用程式」，再從 Finder 開啟。"}
        if !inApplications {return "目前從「應用程式」以外的位置啟動。請退出，將要使用的副本放到「應用程式」，再從那裏開啟。"}
        if !copies.isEmpty {return "找到其他同 Bundle ID 的副本。先在 Finder 核對正在執行的這份，再到設定選它。"}
        if previousHashChanged {return "與先前取得權限時的簽署雜湊不同。若重開後仍無效，可在輸入監察重新選取這份 App。"}
        return "開關可能仍對應舊簽署，或 macOS 需要重開程序。先核對這份 App，再退出、重開。"
    }
    func details(_ reading: AccessReading) -> String {
        let other = copies.isEmpty ? "未找到其他已登記副本" : copies.map(\.path).joined(separator:"\n")
        let match = diskMatchesRunning.map {$0 ? "一致" : "未能核對"} ?? "未能確定"
        return """
        版本   \(version)
        位置   \(inApplications ? "應用程式" : "其他位置")
        \(path.path)
        Bundle ID   \(bundleID)
        簽署   \(signer)
        CDHash   \(cdHash ?? "未能讀取")
        簽署要求   \(requirement ?? "未能讀取")
        簽署檢查 OSStatus   \(validity.map { String($0) } ?? "未能確定")
        執行中與磁碟身分   \(match)
        其他副本   \(other)

        \(reading.details)
        """
    }
}

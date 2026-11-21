import AppKit
import Security

/// The label is for the menu. It never participates in an authorization decision.
struct TrustedApp: Codable, Equatable {
    let name: String
    let bundleID: String
    let signer: String
    let requirement: String
}

struct SignedProcess {
    let identity: TrustedApp
    private let code: SecCode

    private static func satisfies(_ code: SecCode, _ source: String) -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(source as CFString, [], &requirement) == errSecSuccess,
              let requirement = requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    init?(_ process: NSRunningApplication) {
        guard !process.isTerminated, let bundleID = process.bundleIdentifier else { return nil }
        var guest: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: process.processIdentifier)]
        guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &guest) == errSecSuccess,
              let guest = guest else { return nil }
        var disk: SecStaticCode?
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopyStaticCode(guest, [], &disk) == errSecSuccess, let disk = disk,
              SecCodeCopySigningInformation(disk, flags, &info) == errSecSuccess,
              let properties = info as? [String: Any],
              properties[kSecCodeInfoIdentifier as String] as? String == bundleID else { return nil }
        let signer: String
        if Self.satisfies(guest, "anchor apple") {
            signer = "Apple"
        } else {
            guard let team = properties[kSecCodeInfoTeamIdentifier as String] as? String,
                  team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil,
                  Self.satisfies(guest, "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"") else { return nil }
            signer = "Team " + team
        }
        var dr: SecRequirement?
        var source: CFString?
        guard SecCodeCopyDesignatedRequirement(disk, [], &dr) == errSecSuccess, let dr = dr,
              SecRequirementCopyString(dr, [], &source) == errSecSuccess, let source = source,
              !process.isTerminated else { return nil }
        code = guest
        identity = TrustedApp(name: process.localizedName ?? bundleID, bundleID: bundleID,
                              signer: signer, requirement: source as String)
    }

    func matches(_ approval: TrustedApp) -> Bool {
        identity.bundleID == approval.bundleID && identity.signer == approval.signer &&
            Self.satisfies(code, approval.requirement)
    }
}

final class TrustedApps {
    private let defaults: UserDefaults
    private let key = "trustedApplications.v1"
    private(set) var entries: [TrustedApp]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: key).flatMap {
            try? PropertyListDecoder().decode([TrustedApp].self, from: $0)
        } ?? []
    }

    func allows(_ process: NSRunningApplication) -> Bool {
        let candidates = entries.filter { $0.bundleID == process.bundleIdentifier }
        guard !candidates.isEmpty, let signed = SignedProcess(process) else { return false }
        return candidates.contains(where: signed.matches)
    }

    func save(_ entry: TrustedApp) {
        entries.removeAll { $0.bundleID == entry.bundleID }
        entries.append(entry)
        persist()
    }

    func remove(_ bundleID: String) {
        entries.removeAll { $0.bundleID == bundleID }
        persist()
    }

    func clear() {
        entries.removeAll()
        defaults.removeObject(forKey: key)
    }

    private func persist() {
        if let data = try? PropertyListEncoder().encode(entries) { defaults.set(data, forKey: key) }
    }
}

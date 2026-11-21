import AppKit

enum SettingsLinks {
    static let input = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    static let privacy = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")!
    enum Destination: String { case input, privacy, settings, unavailable }

    // Launch Services reports URL delivery, not the selected pane. Keep the manual path visible.
    static func open(inputPane: Bool, launch: (URL) -> Bool = NSWorkspace.shared.open,
                     settingsApp: URL? = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences")) -> Destination {
        if inputPane && launch(input) {return .input}
        if launch(privacy) {return .privacy}
        if let app = settingsApp, launch(app) {return .settings}
        return .unavailable
    }
}

import AppKit
let app=NSApplication.shared
let delegate=PetApp()
app.setActivationPolicy(.accessory)
app.delegate=delegate
app.run()

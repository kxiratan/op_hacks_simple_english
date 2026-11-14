import AppKit

// The process starts on the main thread, so it is safe to set up the UI here.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Accessory: no Dock icon and no main menu; the widget and a menu bar item are the whole UI.
    app.setActivationPolicy(.accessory)
    app.run()
}

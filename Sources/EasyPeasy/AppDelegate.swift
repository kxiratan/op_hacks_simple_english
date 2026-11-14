import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = WidgetModel()
    var panel: WidgetPanel!
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = WidgetPanel(content: WidgetView(model: model))
        panel.restoreOrPlaceAtBottomCenter()
        panel.orderFrontRegardless()
        installStatusItem()

        // Developer check: `EasyPeasy --self-test` runs Peasify once, prints
        // only the outcome (never the page text) and exits.
        if CommandLine.arguments.contains("--self-test") {
            Task {
                await model.run()
                print("self-test: \(model.status.message)")
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Easy Peasy")
            image?.isTemplate = true
            button.image = image
            if image == nil { button.title = "EP" }
        }

        let menu = NSMenu()
        let keyItem = NSMenuItem(
            title: "Set API Key…",
            action: #selector(setAPIKey(_:)),
            keyEquivalent: ""
        )
        keyItem.target = self
        menu.addItem(keyItem)
        let moveItem = NSMenuItem(
            title: "Move Widget to Bottom of Screen",
            action: #selector(moveWidgetToBottom(_:)),
            keyEquivalent: ""
        )
        moveItem.target = self
        menu.addItem(moveItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Easy Peasy",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu
    }

    @objc private func setAPIKey(_ sender: Any?) {
        APIKeyPrompt.run()
    }

    @objc private func moveWidgetToBottom(_ sender: Any?) {
        panel.placeAtBottomCenter()
        panel.orderFrontRegardless()
    }
}

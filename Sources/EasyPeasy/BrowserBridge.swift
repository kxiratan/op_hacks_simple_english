import AppKit
import Foundation

/// Errors surfaced by `BrowserBridge`. Descriptions are short enough for the widget status line.
enum BrowserBridgeError: LocalizedError {
    /// The frontmost app is not a supported browser.
    case noBrowser
    /// macOS Automation permission was refused (error -1743). Carries the browser name.
    case automationDenied(String)
    /// "Allow JavaScript from Apple Events" is off. Carries the browser name.
    case javaScriptDisabled(String)
    /// The browser has no window or tab open. Carries the browser name.
    case noPage(String)
    /// Anything else, with a short message.
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .noBrowser:
            return "Click on a webpage in your browser first, then click Peasify."
        case .automationDenied(let name):
            return "Allow Easy Peasy to control \(name) in System Settings > Privacy & Security > Automation."
        case .javaScriptDisabled(let name):
            if name == "Safari" {
                return "In Safari, turn on Develop > Developer Settings > Allow JavaScript from Apple Events."
            }
            return "In \(name), turn on View > Developer > Allow JavaScript from Apple Events."
        case .noPage(let name):
            return "Open a webpage in \(name) first."
        case .scriptFailed(let message):
            return message
        }
    }
}

/// Runs JavaScript in the front tab of the frontmost browser via AppleScript.
@MainActor
enum BrowserBridge {
    /// A supported browser and the AppleScript dialect it speaks.
    struct Browser: Equatable {
        let bundleID: String
        let name: String
        let isSafari: Bool
    }

    /// Supported browsers by bundle identifier.
    private static let supported: [String: Browser] = {
        let list = [
            Browser(bundleID: "com.apple.Safari", name: "Safari", isSafari: true),
            Browser(bundleID: "com.google.Chrome", name: "Google Chrome", isSafari: false),
            Browser(bundleID: "company.thebrowser.Browser", name: "Arc", isSafari: false),
            Browser(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge", isSafari: false),
            Browser(bundleID: "com.brave.Browser", name: "Brave", isSafari: false),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.bundleID, $0) })
    }()

    /// The frontmost application if it is a supported browser, else nil.
    static func frontBrowser() -> Browser? {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
        return supported[bundleID]
    }

    /// Runs JavaScript in the browser's front tab and returns its result as a string.
    static func run(_ javaScript: String, in browser: Browser) throws -> String {
        let literal = appleScriptLiteral(javaScript)
        let source: String
        if browser.isSafari {
            source = "tell application id \"\(browser.bundleID)\" to do JavaScript \(literal) in front document"
        } else {
            source = "tell application id \"\(browser.bundleID)\" to execute active tab of front window javascript \(literal)"
        }

        guard let script = NSAppleScript(source: source) else {
            throw BrowserBridgeError.scriptFailed("Couldn't talk to \(browser.name).")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo = errorInfo {
            throw mapError(errorInfo, browser: browser)
        }
        return result.stringValue ?? ""
    }

    // MARK: - Helpers

    /// Quotes text as an AppleScript string literal (backslashes first, then double quotes).
    private static func appleScriptLiteral(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }

    /// Turns an `NSAppleScript` error dictionary into a `BrowserBridgeError`.
    private static func mapError(_ info: NSDictionary, browser: Browser) -> BrowserBridgeError {
        let number = (info[NSAppleScript.errorNumber] as? NSNumber)?.intValue
        let message = (info[NSAppleScript.errorMessage] as? String) ?? ""
        let lowered = message
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()

        if number == -1743 {
            return .automationDenied(browser.name)
        }
        if lowered.contains("allow javascript from apple events")
            || lowered.contains("javascript through applescript is turned off") {
            return .javaScriptDisabled(browser.name)
        }
        if number == -1728 || number == -1719
            || lowered.contains("can't get front document")
            || lowered.contains("can't get document")
            || lowered.contains("can't get window")
            || lowered.contains("can't get front window")
            || lowered.contains("can't get active tab") {
            return .noPage(browser.name)
        }

        // Error messages come from the browser or AppleScript, not from the page; keep them short.
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .scriptFailed("\(browser.name) couldn't run the page script.")
        }
        return .scriptFailed(String(trimmed.prefix(140)))
    }
}

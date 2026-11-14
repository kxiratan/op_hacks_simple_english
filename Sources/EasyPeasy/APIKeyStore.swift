import AppKit
import Foundation
import Security

/// Stores the user's OpenRouter API key in the macOS Keychain.
/// The key is never written to UserDefaults, to disk in the repository, or to logs.
enum APIKeyStore {
    private static let service = "com.easypeasy.widget"
    private static let account = "openrouter-api-key"
    private static let environmentVariable = "OPENROUTER_API_KEY"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Keychain first, then the OPENROUTER_API_KEY environment variable, then a
    /// `.env` file in the project folder (development). Trimmed; nil if none.
    static func load() -> String? {
        if let key = loadFromKeychain() { return key }
        if let value = ProcessInfo.processInfo.environment[environmentVariable] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return loadFromEnvFile(environmentVariable)
    }

    /// The model to use: OPENROUTER_MODEL from the environment or `.env`, else nil.
    static func modelOverride() -> String? {
        let name = "OPENROUTER_MODEL"
        if let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty { return value }
        return loadFromEnvFile(name)
    }

    /// Looks for `.env` in the working directory and in the folders above the app
    /// (so `build/EasyPeasy.app` finds the one in the project root).
    private static func loadFromEnvFile(_ wanted: String) -> String? {
        var folders = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
        var folder = Bundle.main.bundleURL
        for _ in 0..<5 {
            folder = folder.deletingLastPathComponent()
            folders.append(folder)
        }

        for folder in folders {
            let file = folder.appendingPathComponent(".env")
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in contents.split(whereSeparator: \.isNewline) {
                var entry = line.trimmingCharacters(in: .whitespaces)
                if entry.hasPrefix("#") { continue }
                if entry.hasPrefix("export ") { entry = String(entry.dropFirst(7)) }
                guard let equals = entry.firstIndex(of: "=") else { continue }
                let name = entry[..<equals].trimmingCharacters(in: .whitespaces)
                guard name == wanted else { continue }
                let value = entry[entry.index(after: equals)...]
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// Adds or updates the generic password item.
    static func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(trimmed.utf8)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw APIKeyStoreError.keychain(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIKeyStoreError.keychain(addStatus)
        }
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// True if a key is available from the Keychain or the environment.
    static var hasKey: Bool { load() != nil }

    /// True only if a key is stored in the Keychain (the environment is ignored).
    fileprivate static var hasStoredKey: Bool { loadFromKeychain() != nil }

    private static func loadFromKeychain() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum APIKeyStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            return "The Keychain could not save the key: \(detail) (\(status))."
        }
    }
}

@MainActor
enum APIKeyPrompt {
    /// Shows a dialog with a secure text field. Saves on OK. Returns true if a key is now stored.
    @discardableResult
    static func run() -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let hadStoredKey = APIKeyStore.hasStoredKey

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "OpenRouter API Key"
        alert.informativeText = "Easy Peasy uses your own OpenRouter API key to translate and simplify pages. "
            + "The key is stored in your Mac's Keychain. You can create a key at openrouter.ai/keys."

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "sk-or-…"
        alert.accessoryView = field

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if hadStoredKey {
            alert.addButton(withTitle: "Remove Key")
        }
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            let entry = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.isEmpty else { return APIKeyStore.hasStoredKey }
            do {
                try APIKeyStore.save(entry)
            } catch {
                let failure = NSAlert()
                failure.alertStyle = .warning
                failure.messageText = "The key was not saved"
                failure.informativeText = error.localizedDescription
                failure.addButton(withTitle: "OK")
                failure.runModal()
            }
            return APIKeyStore.hasStoredKey
        case .alertThirdButtonReturn:
            APIKeyStore.delete()
            return false
        default:
            return APIKeyStore.hasStoredKey
        }
    }
}

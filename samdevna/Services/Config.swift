import CoreGraphics
import Foundation
import Security

/// Where the Meta Model API key comes from, in priority order:
/// 1. the key typed in Settings (stored in the Keychain, this device only),
/// 2. `META_MODEL_API_KEY` from the optional, git-ignored `Config/Secrets.xcconfig` (local dev builds only),
/// 3. the `MODEL_API_KEY` environment variable (Xcode scheme / UI tests).
/// The key is never logged. Don't ship a build with a bundled key: anything in Info.plist can be extracted.
enum SecretStore {
    private static let account = "meta-model-api-key"
    private static let legacyDefaultsKey = "metaAPIKey"

    static let metaBaseURL = URL(string: "https://api.meta.ai/v1")!

    static var metaAPIKey: String {
        migrateLegacyKeyIfNeeded()
        if let stored = Keychain.read(account), !stored.isEmpty { return stored }
        if let bundled = Bundle.main.object(forInfoDictionaryKey: "META_MODEL_API_KEY") as? String {
            let trimmed = bundled.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.contains("YOUR_META"), !trimmed.hasPrefix("$(") { return trimmed }
        }
        return ProcessInfo.processInfo.environment["MODEL_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var hasCloudKey: Bool { !metaAPIKey.isEmpty }

    /// True when the key the app is using was typed in Settings (as opposed to a dev build setting).
    static var hasUserKey: Bool { !(Keychain.read(account) ?? "").isEmpty }

    static func saveUserKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(account)
        } else {
            Keychain.write(trimmed, account: account)
        }
    }

    /// Earlier builds kept the key in UserDefaults. Move it into the Keychain once.
    private static func migrateLegacyKeyIfNeeded() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: legacyDefaultsKey) else { return }
        if !legacy.isEmpty, Keychain.read(account) == nil { Keychain.write(legacy, account: account) }
        defaults.removeObject(forKey: legacyDefaultsKey)
    }
}

/// Minimal generic-password Keychain wrapper.
enum Keychain {
    private static let service = "com.codewithik.samdevna.fixitlens"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let update = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        var add = query(account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

import Foundation
import Security

/// Canonical store for the JWT access token and opaque refresh token.
///
/// Tokens are kept in the iOS Keychain (kSecAttrAccessibleAfterFirstUnlock) and
/// **mirrored** to UserDefaults under the same legacy keys ("authToken",
/// "refreshToken") so existing consumers (widgets, background services, the
/// watch bridge, per-service helpers) keep working unchanged. New code should
/// read/write via `TokenStore` directly so the Keychain copy is authoritative.
///
/// On first read after upgrade we promote any UserDefaults-only value into the
/// Keychain (one-time migration). On `clear()` we wipe both.
enum TokenStore {
    private static let service = "tech.mindgoblin.mileaday.auth"
    private static let accessAccount = "accessToken"
    private static let refreshAccount = "refreshToken"

    // Legacy UserDefaults keys — kept as a mirror for non-migrated readers.
    private static let legacyAccessKey = "authToken"
    private static let legacyRefreshKey = "refreshToken"

    // MARK: - Public API

    static var accessToken: String? {
        readWithMigration(account: accessAccount, legacyKey: legacyAccessKey)
    }

    static var refreshToken: String? {
        readWithMigration(account: refreshAccount, legacyKey: legacyRefreshKey)
    }

    static func setTokens(accessToken: String, refreshToken: String) {
        write(account: accessAccount, value: accessToken)
        write(account: refreshAccount, value: refreshToken)
        // Mirror for legacy consumers (background tasks, widgets, watch bridge).
        UserDefaults.standard.set(accessToken, forKey: legacyAccessKey)
        UserDefaults.standard.set(refreshToken, forKey: legacyRefreshKey)
    }

    static func clear() {
        delete(account: accessAccount)
        delete(account: refreshAccount)
        UserDefaults.standard.removeObject(forKey: legacyAccessKey)
        UserDefaults.standard.removeObject(forKey: legacyRefreshKey)
    }

    /// Convenience — true if both tokens exist (regardless of expiry).
    static var hasTokens: Bool {
        accessToken != nil && refreshToken != nil
    }

    // MARK: - Keychain primitives

    private static func readWithMigration(account: String, legacyKey: String) -> String? {
        if let fromKeychain = read(account: account) {
            return fromKeychain
        }
        // Migration: promote a UserDefaults-only value into the Keychain.
        if let legacy = UserDefaults.standard.string(forKey: legacyKey), !legacy.isEmpty {
            write(account: account, value: legacy)
            return legacy
        }
        return nil
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private static func write(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertQuery = baseQuery
            insertQuery.merge(attributes) { _, new in new }
            SecItemAdd(insertQuery as CFDictionary, nil)
        }
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

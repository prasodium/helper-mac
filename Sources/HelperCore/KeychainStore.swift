import Foundation
import Security

/// Thin wrapper over the macOS Keychain for secrets (API keys, license key).
public enum KeychainStore {
    public static let service = "com.helper.mac"

    public static func get(_ account: String) -> String {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    public static func set(_ value: String, for account: String) -> Bool {
        guard !value.isEmpty else { return remove(account) }
        let data = Data(value.utf8)
        let status = SecItemUpdate(base(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        var add = base(account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    public static func remove(_ account: String) -> Bool {
        let status = SecItemDelete(base(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// Last four characters, e.g. "••••a1b2", so a key can be recognised without being shown.
    public static func mask(_ secret: String) -> String {
        secret.count < 4 ? "" : "••••" + secret.suffix(4)
    }
}

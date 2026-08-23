import Foundation
import Security

/// Stores and retrieves the Hugging Face token used by the Parakeet engine.
///
/// Service identifier matches the README and ARCHITECTURE.md:
///   `com.smartmur.murrflow.hf-token`
///
/// Token is stored as a GenericPassword item. Nothing is logged or persisted
/// in plaintext — the raw token never leaves Keychain outside of a direct
/// caller read.
enum KeychainHelper {

    private static let service = "com.smartmur.murrflow.hf-token"
    private static let account = "hugging-face-token"

    // MARK: - Save

    /// Writes the token to Keychain, replacing any existing entry.
    /// Throws `KeychainError` on failure.
    static func saveToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        // Remove stale entry first so we can always use SecItemAdd.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - Load

    /// Returns the stored token, or `nil` if none is saved.
    /// Throws `KeychainError` on unexpected Keychain failures.
    static func loadToken() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: kCFBooleanTrue as Any,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    /// Removes the stored token. Silent no-op if none exists.
    static func deleteToken() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Errors

    enum KeychainError: LocalizedError {
        case encodingFailed
        case saveFailed(OSStatus)
        case loadFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode token as UTF-8."
            case .saveFailed(let status):
                return "Keychain save failed (OSStatus \(status))."
            case .loadFailed(let status):
                return "Keychain load failed (OSStatus \(status))."
            }
        }
    }
}

import Foundation
import Security

/// Errors from Keychain operations.
public enum KeychainError: Error, Sendable {
    /// An unexpected Security framework status code.
    case unexpectedStatus(OSStatus)
    /// Could not convert Keychain data to/from UTF-8.
    case dataConversionFailed
}

/// Wraps the macOS Keychain for storing and retrieving secrets.
///
/// Each secret is stored as a generic password keyed by service + account.
/// The service name scopes all items to this app (or a test namespace).
public struct KeychainStore: Sendable {
    /// Keychain service name used to scope stored items.
    private let service: String

    /// Creates a KeychainStore scoped to the given service name.
    /// - Parameter service: Keychain service identifier (default: `"com.trnscrb"`).
    public init(service: String = "com.trnscrb") {
        self.service = service
    }

    /// Retrieves a secret from the Keychain.
    /// - Parameter key: Which secret to retrieve.
    /// - Returns: The secret string, or `nil` if not found.
    public func get(for key: SecretKey) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataConversionFailed
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Stores or updates a secret in the Keychain.
    /// - Parameters:
    ///   - value: The secret string to store.
    ///   - key: Which secret to store.
    public func set(_ value: String, for key: SecretKey) throws {
        guard let data: Data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        // Try to update an existing item first.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let update: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus: OSStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            // Item doesn't exist yet — add it.
            var addQuery: [String: Any] = query
            addQuery[kSecValueData as String] = data
            let addStatus: OSStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    /// Removes a secret from the Keychain. Does nothing if the item doesn't exist.
    /// - Parameter key: Which secret to remove.
    public func remove(for key: SecretKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let status: OSStatus = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

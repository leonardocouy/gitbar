import Foundation
import Security

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            "Keychain operation failed with status \(status)."
        case .invalidData:
            "Keychain returned invalid data."
        }
    }
}

struct GitBarKeychain {
    enum Key: String {
        case githubToken = "gitbar.github-token"
    }

    private let service = "com.softaworks.GitBar"

    func string(for key: Key) throws -> String {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard
                let data = result as? Data,
                let string = String(data: data, encoding: .utf8)
            else {
                throw KeychainError.invalidData
            }
            return string
        case errSecItemNotFound:
            return ""
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func set(_ value: String, for key: Key) throws {
        let data = Data(value.utf8)
        let query = baseQuery(for: key)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var newItem = query
            newItem[kSecValueData as String] = data
            let createStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard createStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(createStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    func removeValue(for key: Key) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}


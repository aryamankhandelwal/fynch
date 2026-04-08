import Foundation
import Security

struct KeychainService {
    private static let account = "fynch.auth.session"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func save(_ session: AuthSession) {
        guard let data = try? encoder.encode(session) else { return }

        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrAccount:     account,
            kSecAttrAccessible:  kSecAttrAccessibleAfterFirstUnlock
        ]

        if SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary) == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func load() -> AuthSession? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let session = try? decoder.decode(AuthSession.self, from: data)
        else { return nil }
        return session
    }

    static func delete() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

import Foundation
import Security

struct AppCredentialStore {
    private static let defaultService = "com.bitstraum.usage.credentials"

    private let service: String

    init(service: String = defaultService) {
        self.service = service
    }

    func readClaudeCredentials() -> KeychainHelper.ClaudeCredentials? {
        read(KeychainHelper.ClaudeCredentials.self, account: "claude")
    }

    func writeClaudeCredentials(_ credentials: KeychainHelper.ClaudeCredentials) throws {
        try write(credentials, account: "claude")
    }

    func deleteClaudeCredentials() {
        delete(account: "claude")
    }

    func readOpenAICredentials() -> OpenAIAuthHelper.Credentials? {
        read(OpenAIAuthHelper.Credentials.self, account: "openai")
    }

    func writeOpenAICredentials(_ credentials: OpenAIAuthHelper.Credentials) throws {
        try write(credentials, account: "openai")
    }

    func deleteOpenAICredentials() {
        delete(account: "openai")
    }

    private func read<T: Decodable>(_ type: T.Type, account: String) -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(baseQuery as CFDictionary)

        var item = baseQuery
        item[kSecValueData as String] = data

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppCredentialStoreError.writeFailed(status)
        }
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum AppCredentialStoreError: LocalizedError {
    case writeFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let status):
            return "Failed to save app credentials (\(status))"
        }
    }
}

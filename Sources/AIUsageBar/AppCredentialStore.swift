import Foundation
import LocalAuthentication
import Security

struct AppCredentialStore {
    private static let defaultService = "com.bitstraum.usage.credentials"
    private static let operationPrompt = "Unlock Bitstraum Usage credentials"

    private let service: String

    init(service: String = defaultService) {
        self.service = service
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
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

    func makeProtectedItem(_ account: String, data: Data) throws -> [String: Any] {
        var accessError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &accessError
        ) else {
            let reason = (accessError?.takeRetainedValue() as Error?)?.localizedDescription ?? "unknown"
            throw AppCredentialStoreError.accessControlCreationFailed(reason)
        }

        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl,
        ]
    }

    func makeProtectedReadQuery(_ account: String, context: LAContext) -> [String: Any] {
        context.localizedReason = Self.operationPrompt

        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        return query
    }

    private func makeProtectedWriteQuery(_ account: String, context: LAContext) -> [String: Any] {
        context.localizedReason = Self.operationPrompt

        var query = baseQuery(for: account)
        query[kSecUseAuthenticationContext as String] = context
        return query
    }

    private func read<T: Decodable>(_ type: T.Type, account: String) -> T? {
        if let data = readProtectedData(account: account),
           let decoded = try? JSONDecoder().decode(type, from: data) {
            return decoded
        }

        guard let legacyData = readLegacyData(account: account),
              let decoded = try? JSONDecoder().decode(type, from: legacyData) else {
            return nil
        }

        if let encodable = decoded as? any Encodable {
            try? writeAny(encodable, account: account)
        }

        return decoded
    }

    private func readProtectedData(account: String) -> Data? {
        let context = LAContext()
        let query = makeProtectedReadQuery(account, context: context)

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private func readLegacyData(account: String) -> Data? {
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
        return data
    }

    private func write<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        try writeProtectedData(data, account: account)
    }

    private func writeAny(_ value: any Encodable, account: String) throws {
        let data = try JSONEncoder().encode(AnyEncodable(value))
        try writeProtectedData(data, account: account)
    }

    private func writeProtectedData(_ data: Data, account: String) throws {
        let item = try makeProtectedItem(account, data: data)
        let addStatus = SecItemAdd(item as CFDictionary, nil)

        if addStatus == errSecDuplicateItem {
            let context = LAContext()
            let query = makeProtectedWriteQuery(account, context: context)
            let attrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw AppCredentialStoreError.writeFailed(updateStatus)
            }
            return
        }

        guard addStatus == errSecSuccess else {
            throw AppCredentialStoreError.writeFailed(addStatus)
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

private struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        self.encodeImpl = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeImpl(encoder)
    }
}

enum AppCredentialStoreError: LocalizedError {
    case writeFailed(OSStatus)
    case accessControlCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let status):
            return "Failed to save app credentials (\(status))"
        case .accessControlCreationFailed(let reason):
            return "Failed to configure protected credentials (\(reason))"
        }
    }
}

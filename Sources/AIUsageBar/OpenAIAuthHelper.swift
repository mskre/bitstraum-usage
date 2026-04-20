import Foundation

enum OpenAIAuthHelper {
    private static let appStore = AppCredentialStore()

    /// Resolves the OAuth client ID from the Codex auth.json or the JWT audience claim.
    private static func resolveClientID() -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // 1. Explicit client_id field in auth.json
        if let cid = json["client_id"] as? String, !cid.isEmpty {
            return cid
        }
        // 2. Extract from the id_token JWT audience ("aud") claim
        if let tokens = json["tokens"] as? [String: Any],
           let idToken = tokens["id_token"] as? String,
           let payload = decodeJWTPayload(idToken) {
            if let aud = payload["aud"] as? String, !aud.isEmpty {
                return aud
            }
            if let audArray = payload["aud"] as? [String], let first = audArray.first {
                return first
            }
        }
        return nil
    }

    struct Credentials: Codable, Equatable {
        let idToken: String
        let accessToken: String
        let refreshToken: String
        let clientID: String
        let accountID: String
        let planType: String
        let email: String?
        let expiresAt: Date?
    }

    static func readCodexCredentials() -> Credentials? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["auth_mode"] as? String) == "chatgpt",
              let tokens = json["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              let refreshToken = tokens["refresh_token"] as? String,
              let accountID = tokens["account_id"] as? String,
              let idToken = tokens["id_token"] as? String else {
            return nil
        }

        let payload = decodeJWTPayload(idToken) ?? [:]
        let auth = payload["https://api.openai.com/auth"] as? [String: Any]
        let planType = auth?["chatgpt_plan_type"] as? String ?? "chatgpt"
        let email = payload["email"] as? String
        let clientID = resolveClientID() ?? ""
        let expiresAt: Date?
        if let exp = payload["exp"] as? Double {
            expiresAt = Date(timeIntervalSince1970: exp)
        } else if let exp = payload["exp"] as? Int {
            expiresAt = Date(timeIntervalSince1970: Double(exp))
        } else {
            expiresAt = nil
        }

        return Credentials(
            idToken: idToken,
            accessToken: accessToken,
            refreshToken: refreshToken,
            clientID: clientID,
            accountID: accountID,
            planType: planType,
            email: email,
            expiresAt: expiresAt
        )
    }

    static func readImportedCodexCredentials() -> Credentials? {
        appStore.readOpenAICredentials()
    }

    @discardableResult
    static func importCodexCredentials() throws -> Credentials? {
        guard let credentials = readCodexCredentials() else { return nil }
        try appStore.writeOpenAICredentials(credentials)
        return credentials
    }

    static func clearImportedCodexCredentials() {
        appStore.deleteOpenAICredentials()
    }

    static func isTokenValid(_ credentials: Credentials) -> Bool {
        guard let expiresAt = credentials.expiresAt else { return true }
        return expiresAt > Date().addingTimeInterval(60)
    }

    static func isUsableForImport(_ credentials: Credentials) -> Bool {
        if isTokenValid(credentials) {
            return true
        }

        return !credentials.refreshToken.isEmpty && !credentials.clientID.isEmpty
    }

    static func refreshCodexCredentialsIfNeeded() async throws -> Credentials {
        guard let existing = readImportedCodexCredentials() else {
            throw OpenAIAuthError.credentialsUnavailable
        }
        if isTokenValid(existing) {
            return existing
        }

        let refreshed = try await refreshCodexCredentials(using: existing.refreshToken, clientID: existing.clientID)
        try persistRefreshedCredentials(refreshed)
        return refreshed
    }

    static func planDisplayName(fromPlanType planType: String) -> String {
        switch planType.lowercased() {
        case "pro":
            return "Pro"
        case "plus":
            return "Plus"
        case "free":
            return "Free"
        case "team":
            return "Team"
        case "enterprise":
            return "Enterprise"
        default:
            let raw = planType
            return raw.isEmpty ? "OpenAI" : raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    private static func decodeJWTPayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func refreshCodexCredentials(using refreshToken: String, clientID: String) async throws -> Credentials {
        guard !clientID.isEmpty else {
            throw OpenAIAuthError.credentialsUnavailable
        }
        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        request.httpBody = body
            .map { key, value in
                "\(key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OpenAIAuthError.refreshFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let newRefreshToken = json["refresh_token"] as? String,
              let idToken = json["id_token"] as? String else {
            throw OpenAIAuthError.invalidRefreshResponse
        }

        let payload = decodeJWTPayload(idToken) ?? [:]
        let auth = payload["https://api.openai.com/auth"] as? [String: Any]
        let planType = auth?["chatgpt_plan_type"] as? String ?? "chatgpt"
        let email = payload["email"] as? String
        let accountID = auth?["chatgpt_account_id"] as? String ?? ""
        let expiresAt: Date?
        if let exp = payload["exp"] as? Double {
            expiresAt = Date(timeIntervalSince1970: exp)
        } else if let exp = payload["exp"] as? Int {
            expiresAt = Date(timeIntervalSince1970: Double(exp))
        } else {
            expiresAt = nil
        }

        return Credentials(
            idToken: idToken,
            accessToken: accessToken,
            refreshToken: newRefreshToken,
            clientID: clientID,
            accountID: accountID,
            planType: planType,
            email: email,
            expiresAt: expiresAt
        )
    }

    private static func persistRefreshedCredentials(_ credentials: Credentials) throws {
        try appStore.writeOpenAICredentials(credentials)
    }

    enum OpenAIAuthError: LocalizedError {
        case credentialsUnavailable
        case refreshFailed(Int)
        case invalidRefreshResponse

        var errorDescription: String? {
            switch self {
            case .credentialsUnavailable:
                return "Codex credentials unavailable"
            case .refreshFailed(let status):
                return "OpenAI token refresh failed (\(status))"
            case .invalidRefreshResponse:
                return "Invalid OpenAI token refresh response"
            }
        }
    }
}

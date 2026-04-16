import Foundation
import Security

/// Reads Claude Code OAuth credentials from the macOS Keychain.
enum KeychainHelper {

    struct ClaudeCredentials {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Double          // ms since epoch
        let subscriptionType: String   // e.g. "max", "pro"
        let rateLimitTier: String      // e.g. "default_claude_max_20x"
        let scopes: [String]
    }

    /// Reads the Claude Code OAuth token from the login keychain.
    /// Returns nil if Claude Code is not installed or unauthenticated.
    static func readClaudeCodeCredentials() -> ClaudeCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              let refreshToken = oauth["refreshToken"] as? String,
              let expiresAt = oauth["expiresAt"] as? Double else { return nil }

        return ClaudeCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String ?? "",
            rateLimitTier: oauth["rateLimitTier"] as? String ?? "",
            scopes: oauth["scopes"] as? [String] ?? []
        )
    }

    /// Whether the stored token is still valid (not expired).
    static func isTokenValid(_ creds: ClaudeCredentials) -> Bool {
        let expiryDate = Date(timeIntervalSince1970: creds.expiresAt / 1000)
        return expiryDate > Date()
    }

    /// Formats the subscription type into a display-friendly plan name.
    /// e.g. "max" -> "Max (20x)", "pro" -> "Pro"
    static func planName(from creds: ClaudeCredentials) -> String {
        let sub = creds.subscriptionType.lowercased()
        let base = sub.isEmpty ? "Anthropic" : sub.prefix(1).uppercased() + sub.dropFirst()

        // Extract multiplier from tier like "default_claude_max_20x"
        if let range = creds.rateLimitTier.range(of: #"\d+x"#, options: .regularExpression) {
            return "\(base) (\(creds.rateLimitTier[range]))"
        }
        return base
    }
}

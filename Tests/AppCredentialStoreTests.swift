import Foundation

@main
struct AppCredentialStoreTests {
    static func main() throws {
        let store = AppCredentialStore(service: "com.bitstraum.usage.tests.\(UUID().uuidString)")

        defer {
            store.deleteClaudeCredentials()
            store.deleteOpenAICredentials()
        }

        let claude = KeychainHelper.ClaudeCredentials(
            accessToken: "claude-access",
            refreshToken: "claude-refresh",
            expiresAt: 1_800_000_000_000,
            subscriptionType: "max",
            rateLimitTier: "default_claude_max_20x",
            scopes: ["org:read"]
        )

        try store.writeClaudeCredentials(claude)
        guard store.readClaudeCredentials() == claude else {
            fatalError("Expected Claude credentials to round-trip through the app store")
        }

        let openAI = OpenAIAuthHelper.Credentials(
            idToken: "id-token",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            clientID: "client-id",
            accountID: "account-id",
            planType: "pro",
            email: "user@example.com",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try store.writeOpenAICredentials(openAI)
        guard store.readOpenAICredentials() == openAI else {
            fatalError("Expected OpenAI credentials to round-trip through the app store")
        }

        store.deleteClaudeCredentials()
        guard store.readClaudeCredentials() == nil else {
            fatalError("Expected Claude credentials to be deleted from the app store")
        }
    }
}

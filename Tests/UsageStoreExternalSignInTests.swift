import AppKit
import Foundation
import SwiftUI

@main
struct UsageStoreExternalSignInTests {
    static func main() async throws {
        try await chatGPTSuccessfulImportRefreshesAllProviders()
        try await claudeImportsCredentialsAfterExternalLoginAppears()
        try await claudeIgnoresStaleCredentialsUntilFreshLoginAppears()
        try await claudeStaysUnauthenticatedAfterExternalLoginTimeout()
        try await repeatedClaudeSignInCancelsEarlierResyncTask()
        try await signOutCancelsClaudeResyncTask()
        try await chatGPTImportsRefreshableCredentialsImmediately()
        try await chatGPTImportsCredentialsAfterExternalLoginAppears()
        try await chatGPTStaysUnauthenticatedAfterExternalLoginTimeout()
    }

    private actor DelayedAttemptSource {
        private var nextAttemptID = 0
        private var readyAttempts = Set<Int>()

        func beginAttempt() -> Int {
            nextAttemptID += 1
            return nextAttemptID
        }

        func markReady(_ attemptID: Int) {
            readyAttempts.insert(attemptID)
        }

        func hasReadyAttempt() -> Bool {
            !readyAttempts.isEmpty
        }
    }

    @MainActor
    private static func chatGPTSuccessfulImportRefreshesAllProviders() async throws {
        let defaults = makeDefaults("chatgpt-refresh-all")
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName("chatgpt-refresh-all")) }

        let store = UsageStore(defaults: defaults)
        var refreshAllCount = 0

        store.openAICredentialImport = {
            OpenAIAuthHelper.Credentials(
                idToken: "id",
                accessToken: "access",
                refreshToken: "refresh",
                clientID: "client",
                accountID: "account",
                planType: "pro",
                email: "test@example.com",
                expiresAt: Date().addingTimeInterval(3600)
            )
        }
        store.refreshAllAction = {
            refreshAllCount += 1
        }

        store.signIn(to: .chatgpt)

        try await waitUntil("Successful ChatGPT import triggers refreshAll") {
            refreshAllCount == 1
        }
    }

    @MainActor
    private static func claudeIgnoresStaleCredentialsUntilFreshLoginAppears() async throws {
        let defaults = makeDefaults("claude-stale-then-fresh")
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName("claude-stale-then-fresh")) }

        let store = UsageStore(defaults: defaults)
        var refreshedProviders: [ProviderID] = []
        var currentCredentials = KeychainHelper.ClaudeCredentials(
            accessToken: "stale-access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000,
            subscriptionType: "max",
            rateLimitTier: "default_claude_max_20x",
            scopes: []
        )

        store.externalCredentialWaitTimeout = 0.2
        store.externalCredentialPollInterval = 0
        store.refreshSingleAction = { provider in
            refreshedProviders.append(provider)
        }
        store.claudeCredentialImport = {
            currentCredentials
        }
        store.waitForClaudeExternalCredentials = { _, _ in
            try? await Task.sleep(nanoseconds: 20_000_000)
            currentCredentials = KeychainHelper.ClaudeCredentials(
                accessToken: "fresh-access",
                refreshToken: "refresh",
                expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
                subscriptionType: "max",
                rateLimitTier: "default_claude_max_20x",
                scopes: []
            )
            return currentCredentials
        }

        store.signIn(to: .claude)

        try await waitUntil("Claude waits through stale credentials and refreshes after fresh login") {
            refreshedProviders == [.claude]
        }
    }

    @MainActor
    private static func claudeImportsCredentialsAfterExternalLoginAppears() async throws {
        let defaults = makeDefaults("claude-delayed-success")
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName("claude-delayed-success")) }

        let store = UsageStore(defaults: defaults)
        var browserProviders: [ProviderID] = []
        var refreshedProviders: [ProviderID] = []
        var events: [String] = []

        store.externalCredentialWaitTimeout = 0.2
        store.externalCredentialPollInterval = 0
        store.embeddedBrowserSignIn = { provider, _ in
            browserProviders.append(provider)
        }
        store.refreshSingleAction = { provider in
            refreshedProviders.append(provider)
        }
        store.claudeCredentialImport = {
            events.append("import")
            return events.contains("credentials-ready")
                ? KeychainHelper.ClaudeCredentials(
                    accessToken: "access",
                    refreshToken: "refresh",
                    expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
                    subscriptionType: "max",
                    rateLimitTier: "default_claude_max_20x",
                    scopes: []
                )
                : nil
        }
        store.waitForClaudeExternalCredentials = { _, _ in
            events.append("wait")
            try? await Task.sleep(nanoseconds: 20_000_000)
            events.append("credentials-ready")
            return KeychainHelper.ClaudeCredentials(
                accessToken: "access",
                refreshToken: "refresh",
                expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
                subscriptionType: "max",
                rateLimitTier: "default_claude_max_20x",
                scopes: []
            )
        }

        store.signIn(to: .claude)

        try await waitUntil("Claude prompt appears") {
            card(for: .claude, in: store).statusMessage == "Sign into Claude Code, then wait..."
        }
        try await waitUntil("Claude refresh runs after external credentials import") {
            refreshedProviders == [.claude]
        }

        guard browserProviders.isEmpty else {
            fatalError("Expected Claude sign-in to avoid embedded browser fallback")
        }

        guard events == ["import", "wait", "credentials-ready", "import"] else {
            fatalError("Expected Claude resync order import -> wait -> import, got: \(events)")
        }
    }

    @MainActor
    private static func claudeStaysUnauthenticatedAfterExternalLoginTimeout() async throws {
        let defaults = makeDefaults("claude-timeout")
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName("claude-timeout")) }

        let store = UsageStore(defaults: defaults)
        var browserProviders: [ProviderID] = []
        var importAttempts = 0

        store.externalCredentialWaitTimeout = 0.05
        store.externalCredentialPollInterval = 0
        store.embeddedBrowserSignIn = { provider, _ in
            browserProviders.append(provider)
        }
        store.claudeCredentialImport = {
            importAttempts += 1
            return nil
        }
        store.waitForClaudeExternalCredentials = { _, _ in
            try? await Task.sleep(nanoseconds: 20_000_000)
            return nil
        }

        store.signIn(to: .claude)

        try await waitUntil("Claude timeout message appears") {
            let providerCard = card(for: .claude, in: store)
            return providerCard.state == .unauthenticated && providerCard.statusMessage == "Claude Code login not detected"
        }

        let finalCard = card(for: .claude, in: store)
        guard browserProviders.isEmpty else {
            fatalError("Expected Claude timeout flow to avoid embedded browser fallback")
        }
        guard importAttempts == 1 else {
            fatalError("Expected Claude timeout flow to try immediate import once, got \(importAttempts) attempts")
        }
        guard finalCard.limits.isEmpty, !finalCard.authenticated else {
            fatalError("Expected Claude timeout flow to keep the provider unauthenticated")
        }
    }

    @MainActor
    private static func repeatedClaudeSignInCancelsEarlierResyncTask() async throws {
        let defaults = makeDefaults("claude-repeated-sign-in")
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName("claude-repeated-sign-in")) }

        let store = UsageStore(defaults: defaults)
        let source = DelayedAttemptSource()
        var refreshCount = 0
        var readyAttempts = 0

        store.externalCredentialWaitTimeout = 0.2
        store.externalCredentialPollInterval = 0
        store.claudeCredentialImport = {
            readyAttempts > 0
                ? KeychainHelper.ClaudeCredentials(
                    accessToken: "access",
                    refreshToken: "refresh",
                    expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
                    subscriptionType: "max",
                    rateLimitTier: "default_claude_max_20x",
                    scopes: []
                )
                : nil
        }
        store.waitForClaudeExternalCredentials = { _, _ in
            let attemptID = await source.beginAttempt()
            if attemptID == 1 {
                try? await Task.sleep(nanoseconds: 80_000_000)
            } else {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            await source.markReady(attemptID)
            await MainActor.run {
                readyAttempts += 1
            }
            return KeychainHelper.ClaudeCredentials(
                accessToken: "access",
                refreshToken: "refresh",
                expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
                subscriptionType: "max",
                rateLimitTier: "default_claude_max_20x",
                scopes: []
            )
        }
        store.refreshSingleAction = { provider in
            guard provider == .claude else { return }
            refreshCount += 1
        }

        store.signIn(to: .claude)
        try? await Task.sleep(nanoseconds: 10_000_000)
        store.signIn(to: .claude)

        try await waitUntil("Only latest Claude sign-in refreshes") {
            refreshCount == 1
        }
        try? await Task.sleep(nanoseconds: 100_000_000)

        guard refreshCount == 1 else {
            fatalError("Expected earlier Claude sign-in task to be cancelled before importing credentials")
        }
    }

    @MainActor
    private static func signOutCancelsClaudeResyncTask() async throws {
        let defaults = makeDefaults("claude-sign-out-cancel")
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName("claude-sign-out-cancel")) }

        let store = UsageStore(defaults: defaults)
        var refreshCount = 0
        var importAttempts = 0
        var credentialsReady = false

        store.externalCredentialWaitTimeout = 0.2
        store.externalCredentialPollInterval = 0
        store.automationSignOutAction = { _ in }
        store.claudeCredentialImport = {
            importAttempts += 1
            return credentialsReady
                ? KeychainHelper.ClaudeCredentials(
                    accessToken: "access",
                    refreshToken: "refresh",
                    expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
                    subscriptionType: "max",
                    rateLimitTier: "default_claude_max_20x",
                    scopes: []
                )
                : nil
        }
        store.waitForClaudeExternalCredentials = { _, _ in
            try? await Task.sleep(nanoseconds: 80_000_000)
            await MainActor.run {
                credentialsReady = true
            }
            return KeychainHelper.ClaudeCredentials(
                accessToken: "access",
                refreshToken: "refresh",
                expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
                subscriptionType: "max",
                rateLimitTier: "default_claude_max_20x",
                scopes: []
            )
        }
        store.refreshSingleAction = { provider in
            guard provider == .claude else { return }
            refreshCount += 1
        }

        store.signIn(to: .claude)
        try await waitUntil("Claude waiting prompt appears before sign-out") {
            card(for: .claude, in: store).statusMessage == "Sign into Claude Code, then wait..."
        }
        await store.signOut(from: .claude)
        try? await Task.sleep(nanoseconds: 120_000_000)

        let finalCard = card(for: .claude, in: store)
        guard refreshCount == 0 else {
            fatalError("Expected sign-out to cancel the Claude resync task before refresh")
        }
        guard importAttempts == 1 else {
            fatalError("Expected sign-out to prevent any post-cancellation Claude credential import")
        }
        guard finalCard.statusMessage == "Sign in to start", !finalCard.authenticated else {
            fatalError("Expected sign-out to leave Claude disconnected after cancelling resync")
        }
    }

    @MainActor
    private static func chatGPTImportsRefreshableCredentialsImmediately() async throws {
        let defaults = makeDefaults("chatgpt-refreshable-immediate")
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName("chatgpt-refreshable-immediate")) }

        let store = UsageStore(defaults: defaults)
        var browserProviders: [ProviderID] = []
        var refreshedProviders: [ProviderID] = []
        var waitCalls = 0

        store.embeddedBrowserSignIn = { provider, _ in
            browserProviders.append(provider)
        }
        store.refreshSingleAction = { provider in
            refreshedProviders.append(provider)
        }
        store.openAICredentialImport = {
            OpenAIAuthHelper.Credentials(
                idToken: "expired-id-token",
                accessToken: "valid-access-token",
                refreshToken: "refresh-token",
                clientID: "client-id",
                accountID: "account-id",
                planType: "pro",
                email: "test@example.com",
                expiresAt: Date().addingTimeInterval(-3600)
            )
        }
        store.waitForOpenAIExternalCredentials = { _, _ in
            waitCalls += 1
            return nil
        }

        store.signIn(to: .chatgpt)

        try await waitUntil("ChatGPT refresh runs immediately for refreshable credentials") {
            refreshedProviders == [.chatgpt]
        }

        guard waitCalls == 0 else {
            fatalError("Expected refreshable Codex credentials to skip the wait flow")
        }
        guard browserProviders.isEmpty else {
            fatalError("Expected refreshable Codex credentials to avoid embedded browser fallback")
        }
    }

    @MainActor
    private static func chatGPTImportsCredentialsAfterExternalLoginAppears() async throws {
        let defaults = makeDefaults("chatgpt-delayed-success")
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName("chatgpt-delayed-success")) }

        let store = UsageStore(defaults: defaults)
        var browserProviders: [ProviderID] = []
        var refreshedProviders: [ProviderID] = []
        var events: [String] = []

        store.externalCredentialWaitTimeout = 0.2
        store.externalCredentialPollInterval = 0
        store.embeddedBrowserSignIn = { provider, _ in
            browserProviders.append(provider)
        }
        store.refreshSingleAction = { provider in
            refreshedProviders.append(provider)
        }
        store.openAICredentialImport = {
            events.append("import")
            return events.contains("credentials-ready")
                ? OpenAIAuthHelper.Credentials(
                    idToken: "id",
                    accessToken: "access",
                    refreshToken: "refresh",
                    clientID: "client",
                    accountID: "account",
                    planType: "pro",
                    email: "test@example.com",
                    expiresAt: Date().addingTimeInterval(3600)
                )
                : nil
        }
        store.waitForOpenAIExternalCredentials = { _, _ in
            events.append("wait")
            try? await Task.sleep(nanoseconds: 20_000_000)
            events.append("credentials-ready")
            return OpenAIAuthHelper.Credentials(
                idToken: "id",
                accessToken: "access",
                refreshToken: "refresh",
                clientID: "client",
                accountID: "account",
                planType: "pro",
                email: "test@example.com",
                expiresAt: Date().addingTimeInterval(3600)
            )
        }

        store.signIn(to: .chatgpt)

        try await waitUntil("ChatGPT prompt appears") {
            card(for: .chatgpt, in: store).statusMessage == "Sign into Codex, then wait..."
        }
        try await waitUntil("ChatGPT refresh runs after external credentials import") {
            refreshedProviders == [.chatgpt]
        }

        guard browserProviders.isEmpty else {
            fatalError("Expected ChatGPT sign-in to avoid embedded browser fallback")
        }

        guard events == ["import", "wait", "credentials-ready", "import"] else {
            fatalError("Expected ChatGPT resync order import -> wait -> import, got: \(events)")
        }
    }

    @MainActor
    private static func chatGPTStaysUnauthenticatedAfterExternalLoginTimeout() async throws {
        let defaults = makeDefaults("chatgpt-timeout")
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName("chatgpt-timeout")) }

        let store = UsageStore(defaults: defaults)
        var browserProviders: [ProviderID] = []
        var importAttempts = 0

        store.externalCredentialWaitTimeout = 0.05
        store.externalCredentialPollInterval = 0
        store.embeddedBrowserSignIn = { provider, _ in
            browserProviders.append(provider)
        }
        store.openAICredentialImport = {
            importAttempts += 1
            return nil
        }
        store.waitForOpenAIExternalCredentials = { _, _ in
            try? await Task.sleep(nanoseconds: 20_000_000)
            return nil
        }

        store.signIn(to: .chatgpt)

        try await waitUntil("ChatGPT timeout message appears") {
            let providerCard = card(for: .chatgpt, in: store)
            return providerCard.state == .unauthenticated && providerCard.statusMessage == "Codex login not detected"
        }

        let finalCard = card(for: .chatgpt, in: store)
        guard browserProviders.isEmpty else {
            fatalError("Expected ChatGPT timeout flow to avoid embedded browser fallback")
        }
        guard importAttempts == 1 else {
            fatalError("Expected ChatGPT timeout flow to try immediate import once, got \(importAttempts) attempts")
        }
        guard finalCard.limits.isEmpty, !finalCard.authenticated else {
            fatalError("Expected ChatGPT timeout flow to keep the provider unauthenticated")
        }
    }

    @MainActor
    private static func card(for provider: ProviderID, in store: UsageStore) -> ProviderUsageCard {
        guard let card = store.cards.first(where: { $0.id == provider }) else {
            fatalError("Missing card for \(provider.rawValue)")
        }
        return card
    }

    private static func waitUntil(
        _ message: String,
        timeoutNanoseconds: UInt64 = 300_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        fatalError("Timed out waiting for condition: \(message)")
    }

    private static func defaultsSuiteName(_ suffix: String) -> String {
        "UsageStoreExternalSignInTests.\(suffix)"
    }

    private static func makeDefaults(_ suffix: String) -> UserDefaults {
        let suiteName = defaultsSuiteName(suffix)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create UserDefaults suite \(suiteName)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

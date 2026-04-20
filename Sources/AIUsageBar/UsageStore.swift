import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published var cards: [ProviderUsageCard]
    @Published var isRefreshing = false
    @Published var lastRefresh: Date?
    @Published var lastDowndetectorRefresh: Date?
    @Published var downdetectorData: [ProviderID: DowndetectorReport] = [:]
    @Published var downdetectorTabState: DowndetectorTabState = .unavailable
    @Published var isRefreshingDowndetector = false

    private let automation = WebAutomationService()
    private let colorSettings = ColorSettings.shared
    private let defaults: UserDefaults
    private var refreshTask: Task<Void, Never>?
    private var signInTasks: [ProviderID: Task<Void, Never>] = [:]
    private var signInTaskIDs: [ProviderID: UUID] = [:]
    private let locallySignedOutKey = "locallySignedOutProviders"
    private var locallySignedOutProviders: Set<ProviderID> = []

    var externalCredentialWaitTimeout: TimeInterval = 30
    var externalCredentialPollInterval: TimeInterval = 1
    var claudeCredentialImport: () throws -> KeychainHelper.ClaudeCredentials? = {
        try KeychainHelper.importClaudeCodeCredentials()
    }
    var waitForClaudeExternalCredentials: (TimeInterval, TimeInterval) async -> KeychainHelper.ClaudeCredentials? = { timeout, interval in
        await KeychainHelper.waitForExternalCredentials(timeout: timeout, interval: interval) {
            guard let credentials = KeychainHelper.readClaudeCodeCredentials(),
                  KeychainHelper.isTokenValid(credentials) else {
                return nil
            }
            return credentials
        }
    }
    var openAICredentialImport: () throws -> OpenAIAuthHelper.Credentials? = {
        try OpenAIAuthHelper.importCodexCredentials()
    }
    var waitForOpenAIExternalCredentials: (TimeInterval, TimeInterval) async -> OpenAIAuthHelper.Credentials? = { timeout, interval in
        await KeychainHelper.waitForExternalCredentials(timeout: timeout, interval: interval) {
            guard let credentials = OpenAIAuthHelper.readCodexCredentials(),
                  OpenAIAuthHelper.isUsableForImport(credentials) else {
                return nil
            }
            return credentials
        }
    }
    var embeddedBrowserSignIn: ((ProviderID, @escaping () -> Void) -> Void)?
    var automationSignOutAction: ((ProviderID) async -> Void)?
    var refreshSingleAction: ((ProviderID) async -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let saved = UsagePersistence.load(), saved.count == ProviderID.allCases.count {
            let order = Dictionary(uniqueKeysWithValues: ProviderID.allCases.enumerated().map { ($0.element, $0.offset) })
            self.cards = saved.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        } else {
            self.cards = ProviderID.allCases.map(ProviderUsageCard.placeholder)
        }

        if let raw = defaults.array(forKey: locallySignedOutKey) as? [String] {
            self.locallySignedOutProviders = Set(raw.compactMap(ProviderID.init(rawValue:)))
        }
    }

    var hasImportedClaudeCredentials: Bool {
        !locallySignedOutProviders.contains(.claude) && KeychainHelper.readImportedClaudeCredentials() != nil
    }

    var hasImportedOpenAICredentials: Bool {
        !locallySignedOutProviders.contains(.chatgpt) && OpenAIAuthHelper.readImportedCodexCredentials() != nil
    }

    func shouldShowReconnect(for card: ProviderUsageCard) -> Bool {
        guard card.state == .unauthenticated else { return false }

        switch card.id {
        case .claude:
            return hasImportedClaudeCredentials
        case .chatgpt:
            return hasImportedOpenAICredentials
        }
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.refreshAuthenticated()
            while !Task.isCancelled {
                let interval = max(1, Int((self?.colorSettings.refreshIntervalMinutes ?? 5).rounded()))
                try? await Task.sleep(for: .seconds(interval * 60))
                await self?.refreshAuthenticated()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Sign in uses external credential resync for Claude/ChatGPT and browser auth for others.
    func signIn(to provider: ProviderID) {
        locallySignedOutProviders.remove(provider)
        persistLocallySignedOutProviders()

        if provider == .chatgpt {
            startSignInTask(for: provider) { [weak self] taskID in
                await self?.resyncFromCodex(taskID: taskID)
            }
            return
        }

        if provider == .claude {
            startSignInTask(for: provider) { [weak self] taskID in
                await self?.resyncFromClaudeCode(taskID: taskID)
            }
            return
        }

        // Fall back to embedded browser sign-in
        let signIn = embeddedBrowserSignIn ?? { [automation] provider, onAuth in
            automation.signIn(for: provider, onAuth: onAuth)
        }
        signIn(provider) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                NotificationCenter.default.post(name: .signInCompleted, object: nil)
                await self.refreshSingle(provider)
            }
        }
    }

    func signOut(from provider: ProviderID) async {
        cancelSignInTask(for: provider)
        if provider == .claude {
            KeychainHelper.clearImportedClaudeCredentials()
        }
        if provider == .chatgpt {
            OpenAIAuthHelper.clearImportedCodexCredentials()
        }
        if let automationSignOutAction {
            await automationSignOutAction(provider)
        } else {
            await automation.signOut(for: provider)
        }
        locallySignedOutProviders.insert(provider)
        persistLocallySignedOutProviders()
        if let i = cards.firstIndex(where: { $0.id == provider }) {
            cards[i] = ProviderUsageCard.placeholder(for: provider)
        }
        UsagePersistence.save(cards)
    }

    func refreshSingle(_ provider: ProviderID) async {
        await refresh(provider: provider)
        lastRefresh = Date()
        UsagePersistence.save(cards)
    }

    func refreshAll() async {
        if isRefreshing { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefresh = Date()
            UsagePersistence.save(cards)
        }
        if colorSettings.showDowndetector {
            await refreshDowndetector()
        }
        for p in ProviderID.allCases {
            await refresh(provider: p)
        }
    }

    func refreshAuthenticated() async {
        if isRefreshing { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefresh = Date()
            UsagePersistence.save(cards)
        }

        if colorSettings.showDowndetector {
            await refreshDowndetector()
        }

        // Collect providers to refresh: already authenticated + Claude if Keychain exists
        var toRefresh = Set(cards.filter { $0.authenticated }.map { $0.id })
        if hasImportedClaudeCredentials {
            toRefresh.insert(.claude)
        }
        if hasImportedOpenAICredentials {
            toRefresh.insert(.chatgpt)
        }

        for p in toRefresh {
            await refresh(provider: p)
        }
    }

    // MARK: - Downdetector

    func retryDowndetectorNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await refreshDowndetector()
    }

    func openDowndetectorUnlockWindow() {
        guard case .blocked(let slug) = downdetectorTabState else { return }
        DowndetectorService.onUnlockWindowClosed = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.retryDowndetectorNow()
            }
        }
        DowndetectorService.presentUnlockWindow(for: slug)
    }

    private func refreshDowndetector() async {
        guard !isRefreshingDowndetector else { return }
        isRefreshingDowndetector = true
        defer { isRefreshingDowndetector = false }

        var blockedSlug: String?
        var sawReport = false

        for provider in ProviderID.allCases {
            guard let slug = provider.downdetectorSlug else { continue }
            switch await DowndetectorService.fetchResult(slug: slug) {
            case .report(let report):
                sawReport = true
                downdetectorData[provider] = report
            case .blocked:
                blockedSlug = blockedSlug ?? slug
                if let existing = downdetectorData[provider],
                   !existing.isFresh(staleAfter: colorSettings.downdetectorFreshnessInterval) {
                    downdetectorData.removeValue(forKey: provider)
                }
            case .unavailable:
                if let existing = downdetectorData[provider],
                   !existing.isFresh(staleAfter: colorSettings.downdetectorFreshnessInterval) {
                    downdetectorData.removeValue(forKey: provider)
                }
            }
        }

        downdetectorTabState = DowndetectorService.tabState(
            hasReportData: !downdetectorData.isEmpty,
            blockedSlug: blockedSlug
        )
        if sawReport {
            lastDowndetectorRefresh = Date()
        }
    }

    private func refresh(provider: ProviderID) async {
        guard !isExternalResyncInProgress(for: provider) else { return }
        update(provider) { $0.state = .loading; $0.statusMessage = "Refreshing..." }

        let clients = ProviderFactory.makeAll()
        guard let client = clients[provider] else {
            update(provider) { $0.state = .error; $0.statusMessage = "No client" }
            return
        }

        do {
            let card = try await client.refresh(using: automation)
            replace(card)
        } catch let e as ProviderError {
            handleError(provider: provider, error: e)
        } catch {
            update(provider) {
                $0.state = .error
                $0.statusMessage = error.localizedDescription
                $0.limits = []
                $0.authenticated = false
            }
        }
    }

    private func handleError(provider: ProviderID, error: ProviderError) {
        switch error {
        case .authRequired(let msg):
            update(provider) {
                $0.state = .unauthenticated
                $0.statusMessage = msg
                $0.planName = "Not connected"
                $0.limits = []
                $0.authenticated = false
                $0.email = nil
            }
        case .invalidPayload(let msg), .unavailable(let msg):
            update(provider) {
                $0.state = .error
                $0.statusMessage = msg
                $0.authenticated = true
            }
        }
    }

    private func replace(_ card: ProviderUsageCard) {
        if let i = cards.firstIndex(where: { $0.id == card.id }) { cards[i] = card }
    }

    private func persistLocallySignedOutProviders() {
        defaults.set(locallySignedOutProviders.map(\.rawValue), forKey: locallySignedOutKey)
    }

    private func update(_ provider: ProviderID, transform: (inout ProviderUsageCard) -> Void) {
        guard let i = cards.firstIndex(where: { $0.id == provider }) else { return }
        var c = cards[i]
        transform(&c)
        cards[i] = c
    }

    private func startSignInTask(
        for provider: ProviderID,
        operation: @escaping (UUID) async -> Void
    ) {
        cancelSignInTask(for: provider)

        let taskID = UUID()
        signInTaskIDs[provider] = taskID
        signInTasks[provider] = Task { [weak self] in
            await operation(taskID)
            if let self {
                self.finishSignInTask(for: provider, taskID: taskID)
            }
        }
    }

    private func cancelSignInTask(for provider: ProviderID) {
        signInTasks[provider]?.cancel()
        signInTasks[provider] = nil
        signInTaskIDs[provider] = nil
    }

    private func finishSignInTask(for provider: ProviderID, taskID: UUID) {
        guard signInTaskIDs[provider] == taskID else { return }
        signInTasks[provider] = nil
        signInTaskIDs[provider] = nil
    }

    private func isActiveSignInTask(_ taskID: UUID, for provider: ProviderID) -> Bool {
        !Task.isCancelled && signInTaskIDs[provider] == taskID
    }

    private func isExternalResyncInProgress(for provider: ProviderID) -> Bool {
        signInTaskIDs[provider] != nil
    }

    private func resyncFromClaudeCode(taskID: UUID) async {
        guard isActiveSignInTask(taskID, for: .claude) else { return }

        if let imported = try? claudeCredentialImport(),
           KeychainHelper.isTokenValid(imported) {
            await refreshAfterExternalImport(.claude, taskID: taskID)
            return
        }

        guard isActiveSignInTask(taskID, for: .claude) else { return }

        update(.claude) {
            $0.state = .loading
            $0.statusMessage = "Sign into Claude Code, then wait..."
            $0.planName = "Not connected"
            $0.limits = []
            $0.authenticated = false
            $0.email = nil
        }

        guard isActiveSignInTask(taskID, for: .claude) else { return }

        if await waitForClaudeExternalCredentials(externalCredentialWaitTimeout, externalCredentialPollInterval) != nil,
           isActiveSignInTask(taskID, for: .claude),
           let imported = try? claudeCredentialImport(),
           KeychainHelper.isTokenValid(imported) {
            await refreshAfterExternalImport(.claude, taskID: taskID)
            return
        }

        guard isActiveSignInTask(taskID, for: .claude) else { return }

        update(.claude) {
            $0.state = .unauthenticated
            $0.statusMessage = "Claude Code login not detected"
            $0.planName = "Not connected"
            $0.limits = []
            $0.authenticated = false
            $0.email = nil
        }
    }

    private func resyncFromCodex(taskID: UUID) async {
        guard isActiveSignInTask(taskID, for: .chatgpt) else { return }

        if let imported = try? openAICredentialImport(),
           OpenAIAuthHelper.isUsableForImport(imported) {
            await refreshAfterExternalImport(.chatgpt, taskID: taskID)
            return
        }

        guard isActiveSignInTask(taskID, for: .chatgpt) else { return }

        update(.chatgpt) {
            $0.state = .loading
            $0.statusMessage = "Sign into Codex, then wait..."
            $0.planName = "Not connected"
            $0.limits = []
            $0.authenticated = false
            $0.email = nil
        }

        guard isActiveSignInTask(taskID, for: .chatgpt) else { return }

        if await waitForOpenAIExternalCredentials(externalCredentialWaitTimeout, externalCredentialPollInterval) != nil,
           isActiveSignInTask(taskID, for: .chatgpt),
           let imported = try? openAICredentialImport(),
           OpenAIAuthHelper.isUsableForImport(imported) {
            await refreshAfterExternalImport(.chatgpt, taskID: taskID)
            return
        }

        guard isActiveSignInTask(taskID, for: .chatgpt) else { return }

        update(.chatgpt) {
            $0.state = .unauthenticated
            $0.statusMessage = "Codex login not detected"
            $0.planName = "Not connected"
            $0.limits = []
            $0.authenticated = false
            $0.email = nil
        }
    }

    private func refreshAfterExternalImport(_ provider: ProviderID, taskID: UUID) async {
        guard isActiveSignInTask(taskID, for: provider) else { return }
        if let refreshSingleAction {
            await refreshSingleAction(provider)
        } else {
            await refreshSingle(provider)
        }
    }

}

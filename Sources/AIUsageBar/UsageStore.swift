import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published var cards: [ProviderUsageCard]
    @Published var isRefreshing = false
    @Published var lastRefresh: Date?
    @Published var downdetectorData: [ProviderID: DowndetectorReport] = [:]

    private let automation = WebAutomationService()
    private let clients = ProviderFactory.makeAll()
    private let colorSettings = ColorSettings.shared
    private var refreshTask: Task<Void, Never>?
    private let locallySignedOutKey = "locallySignedOutProviders"
    private var locallySignedOutProviders: Set<ProviderID> = []

    init() {
        if let saved = UsagePersistence.load(), saved.count == ProviderID.allCases.count {
            let order = Dictionary(uniqueKeysWithValues: ProviderID.allCases.enumerated().map { ($0.element, $0.offset) })
            self.cards = saved.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        } else {
            self.cards = ProviderID.allCases.map(ProviderUsageCard.placeholder)
        }

        if let raw = UserDefaults.standard.array(forKey: locallySignedOutKey) as? [String] {
            self.locallySignedOutProviders = Set(raw.compactMap(ProviderID.init(rawValue:)))
        }
    }

    /// Whether Claude Code credentials exist in the Keychain.
    var hasClaudeCodeCredentials: Bool {
        !locallySignedOutProviders.contains(.claude) && KeychainHelper.readClaudeCodeCredentials() != nil
    }

    var hasOpenAICodexCredentials: Bool {
        !locallySignedOutProviders.contains(.chatgpt) && OpenAIAuthHelper.readCodexCredentials() != nil
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

    /// Sign in: for Claude, try API first (no browser needed if Claude Code exists).
    /// Falls back to embedded browser if no Keychain credentials.
    func signIn(to provider: ProviderID) {
        locallySignedOutProviders.remove(provider)
        persistLocallySignedOutProviders()

        if provider == .chatgpt, hasOpenAICodexCredentials {
            Task {
                await refreshSingle(provider)
            }
            return
        }

        if provider == .claude, hasClaudeCodeCredentials {
            // Use the API directly -- no browser needed
            Task {
                await refreshSingle(provider)
            }
            return
        }

        // Fall back to embedded browser sign-in
        automation.signIn(for: provider) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                NotificationCenter.default.post(name: .signInCompleted, object: nil)
                await self.refreshSingle(provider)
            }
        }
    }

    func signOut(from provider: ProviderID) async {
        await automation.signOut(for: provider)
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
        if hasClaudeCodeCredentials {
            toRefresh.insert(.claude)
        }
        if hasOpenAICodexCredentials {
            toRefresh.insert(.chatgpt)
        }

        for p in toRefresh {
            await refresh(provider: p)
        }
    }

    // MARK: - Downdetector

    private func refreshDowndetector() async {
        for provider in ProviderID.allCases {
            guard let slug = provider.downdetectorSlug else { continue }
            if let report = await DowndetectorService.fetch(slug: slug) {
                downdetectorData[provider] = report
            }
        }
    }

    private func refresh(provider: ProviderID) async {
        update(provider) { $0.state = .loading; $0.statusMessage = "Refreshing..." }

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
                $0.limits = []
                $0.authenticated = false
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
        UserDefaults.standard.set(locallySignedOutProviders.map(\.rawValue), forKey: locallySignedOutKey)
    }

    private func update(_ provider: ProviderID, transform: (inout ProviderUsageCard) -> Void) {
        guard let i = cards.firstIndex(where: { $0.id == provider }) else { return }
        var c = cards[i]
        transform(&c)
        cards[i] = c
    }

}

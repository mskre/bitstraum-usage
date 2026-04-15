import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published var cards: [ProviderUsageCard]
    @Published var isRefreshing = false
    @Published var lastRefresh: Date?

    private let automation = WebAutomationService()
    private let clients = ProviderFactory.makeAll()
    private var refreshTask: Task<Void, Never>?

    init() {
        if let saved = UsagePersistence.load(), saved.count == ProviderID.allCases.count {
            let order = Dictionary(uniqueKeysWithValues: ProviderID.allCases.enumerated().map { ($0.element, $0.offset) })
            self.cards = saved.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        } else {
            self.cards = ProviderID.allCases.map(ProviderUsageCard.placeholder)
        }
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            // Refresh all authenticated providers on launch
            await self?.refreshAuthenticated()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await self?.refreshAuthenticated()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Opens in-app browser window for provider login.
    /// Auto-refreshes that provider when the window is closed.
    func signIn(to provider: ProviderID) {
        automation.signIn(for: provider) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshSingle(provider)
            }
        }
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
        for p in ProviderID.allCases {
            await refresh(provider: p)
        }
    }

    func refreshAuthenticated() async {
        if isRefreshing { return }
        let authed = cards.filter { $0.authenticated }.map { $0.id }
        guard !authed.isEmpty else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefresh = Date()
            UsagePersistence.save(cards)
        }
        for p in authed {
            await refresh(provider: p)
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
        // Debug: write status to file for providers with no limits
        if card.limits.isEmpty && card.authenticated {
            let debugPath = "/tmp/ai_usage_debug_\(card.id.rawValue).json"
            try? card.statusMessage.write(toFile: debugPath, atomically: true, encoding: .utf8)
        }
    }

    private func update(_ provider: ProviderID, transform: (inout ProviderUsageCard) -> Void) {
        guard let i = cards.firstIndex(where: { $0.id == provider }) else { return }
        var c = cards[i]
        transform(&c)
        cards[i] = c
    }
}

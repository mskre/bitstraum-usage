import AppKit
import Foundation

enum ProviderID: String, CaseIterable, Codable, Identifiable {
    case chatgpt
    case claude
    case gemini
    case openrouter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatgpt: return "ChatGPT"
        case .claude: return "Claude"
        case .gemini: return "Google Gemini"
        case .openrouter: return "OpenRouter"
        }
    }

    var shortTitle: String {
        switch self {
        case .chatgpt: return "GPT"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .openrouter: return "OR"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .chatgpt: return NSColor(white: 0.95, alpha: 1.0)
        case .claude: return NSColor(calibratedRed: 0.95, green: 0.50, blue: 0.19, alpha: 1.0)
        case .gemini: return NSColor(calibratedRed: 0.30, green: 0.58, blue: 0.98, alpha: 1.0)
        case .openrouter: return NSColor(calibratedRed: 0.54, green: 0.42, blue: 0.96, alpha: 1.0)
        }
    }

    /// URL opened in the system browser for initial sign-in
    var loginURL: URL {
        switch self {
        case .chatgpt: return URL(string: "https://chatgpt.com/")!
        case .claude: return URL(string: "https://claude.ai/")!
        case .gemini: return URL(string: "https://gemini.google.com/app")!
        case .openrouter: return URL(string: "https://openrouter.ai/credits")!
        }
    }

    /// URL opened in the in-app verify window and used for scraping
    var usageURL: URL {
        switch self {
        case .chatgpt: return URL(string: "https://chatgpt.com/codex/cloud/settings/usage")!
        case .claude: return URL(string: "https://claude.ai/settings/usage")!
        case .gemini: return URL(string: "https://gemini.google.com/app")!
        case .openrouter: return URL(string: "https://openrouter.ai/")!
        }
    }
}

// MARK: - Usage limit row

struct UsageLimit: Codable, Identifiable {
    var id: String
    var label: String
    var remaining: Double?
    var total: Double?
    var fraction: Double?
    var resetLabel: String?
}

// MARK: - Provider card

enum ProviderState: String, Codable {
    case idle, loading, ready, unauthenticated, error
}

struct ProviderUsageCard: Codable, Identifiable {
    var id: ProviderID
    var planName: String
    var statusMessage: String
    var limits: [UsageLimit]
    var state: ProviderState
    var lastUpdated: Date?
    var authenticated: Bool

    var bestFraction: Double? {
        limits.compactMap(\.fraction).min()
    }

    static func placeholder(for id: ProviderID) -> ProviderUsageCard {
        ProviderUsageCard(
            id: id, planName: "Not connected", statusMessage: "Sign in to start",
            limits: [], state: .unauthenticated, lastUpdated: nil, authenticated: false
        )
    }
}

// MARK: - Scrape result

struct ProviderScrapeResult: Decodable {
    var authenticated: Bool?
    var planName: String?
    var statusMessage: String?
    var limits: [ScrapeLimit]?
    var remaining: Double?
    var used: Double?
    var total: Double?
    var headline: String?
    var footer: String?
    var resetText: String?
    var remainingFraction: Double?
}

struct ScrapeLimit: Decodable {
    var id: String
    var label: String
    var remaining: Double?
    var total: Double?
    var fraction: Double?
    var resetLabel: String?
}

enum ProviderError: LocalizedError {
    case authRequired(String)
    case invalidPayload(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .authRequired(let m): return m
        case .invalidPayload(let m): return m
        case .unavailable(let m): return m
        }
    }
}

struct PersistedUsageState: Codable {
    var cards: [ProviderUsageCard]
}

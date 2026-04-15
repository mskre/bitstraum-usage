import AppKit
import Foundation

enum ProviderID: String, CaseIterable, Codable, Identifiable {
    case chatgpt
    case claude
    // case gemini      // no usage counter exposed
    // case openrouter  // no usage counter exposed

    static var allCases: [ProviderID] { [.chatgpt, .claude] }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatgpt: return "ChatGPT"
        case .claude: return "Claude"
        }
    }

    var shortTitle: String {
        switch self {
        case .chatgpt: return "GPT"
        case .claude: return "Claude"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .chatgpt: return NSColor(white: 0.95, alpha: 1.0)
        case .claude: return NSColor(calibratedRed: 0.95, green: 0.50, blue: 0.19, alpha: 1.0)
        }
    }

    var loginURL: URL {
        switch self {
        case .chatgpt: return URL(string: "https://chatgpt.com/")!
        case .claude: return URL(string: "https://claude.ai/")!
        }
    }

    var usageURL: URL {
        switch self {
        case .chatgpt: return URL(string: "https://chatgpt.com/codex/cloud/settings/analytics")!
        case .claude: return URL(string: "https://claude.ai/settings/usage")!
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

import AppKit
import Foundation
import WebKit

struct DowndetectorDataPoint {
    let timestamp: Date
    let reports: Int
    let baseline: Int
}

enum DowndetectorStatusLevel: String {
    case success, warning, danger, unknown

    var label: String {
        switch self {
        case .success: return "No problems"
        case .warning: return "Possible problems"
        case .danger: return "Problems detected"
        case .unknown: return "Unknown"
        }
    }

    var hasProblems: Bool { self == .warning || self == .danger }
}

struct DowndetectorIndicator {
    let name: String
    let count: Int
    let percentage: Double
}

struct DowndetectorReport {
    var status: DowndetectorStatusLevel
    var dataPoints: [DowndetectorDataPoint]
    var reportsMax: Int
    var indicators: [DowndetectorIndicator]
    var fetchedAt: Date

    func isFresh(staleAfter: TimeInterval, now: Date = Date()) -> Bool {
        now.timeIntervalSince(fetchedAt) <= staleAfter
    }

    func alertStatus(
        baselinePercent: Double = 400,
        staleAfter: TimeInterval,
        now: Date = Date()
    ) -> DowndetectorStatusLevel {
        guard isFresh(staleAfter: staleAfter, now: now) else { return .unknown }
        return effectiveStatus(baselinePercent: baselinePercent)
    }

    /// Adjusts status based on whether the latest data point exceeds the baseline multiplier.
    func effectiveStatus(baselinePercent: Double = 400) -> DowndetectorStatusLevel {
        guard status.hasProblems else { return status }
        guard let latest = dataPoints.last else { return .success }

        let multiplier = baselinePercent / 100.0
        let hasCurrentProblems = latest.baseline > 0
            ? Double(latest.reports) >= Double(latest.baseline) * multiplier
            : latest.reports > 0
        return hasCurrentProblems ? status : .success
    }
}

enum DowndetectorFetchState: Equatable {
    case report
    case blocked
    case unavailable
}

enum DowndetectorTabState: Equatable {
    case report
    case blocked(slug: String)
    case unavailable
}

enum DowndetectorFetchResult {
    case report(DowndetectorReport)
    case blocked
    case unavailable
}

// MARK: - Service

@MainActor
final class UnlockWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = UnlockWindowDelegate()

    func windowWillClose(_ notification: Notification) {
        DowndetectorService.unlockWindowWillClose()
    }
}

@MainActor
enum DowndetectorService {

    fileprivate static var sharedWebView: WKWebView?
    fileprivate static var unlockWindow: NSWindow?
    fileprivate static var justClearedChallenge: Bool = false
    static var onUnlockWindowClosed: (@MainActor () -> Void)?

    fileprivate static func unlockWindowWillClose() {
        NSApp.setActivationPolicy(.accessory)
        justClearedChallenge = true
        onUnlockWindowClosed?()
    }

    private static func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let customUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: config)
        wv.customUserAgent = customUA
        return wv
    }

    private static func getSharedWebView() -> WKWebView {
        if let wv = sharedWebView { return wv }

        let wv = makeWebView()
        sharedWebView = wv
        return wv
    }

    static func fetch(slug: String) async -> DowndetectorReport? {
        switch await fetchResult(slug: slug) {
        case .report(let report):
            return report
        case .blocked, .unavailable:
            return nil
        }
    }

    static func fetchResult(slug: String) async -> DowndetectorFetchResult {
        guard let url = URL(string: "https://downdetector.com/status/\(slug)/") else { return .unavailable }

        let wv = getSharedWebView()

        let loader = DDNavigationLoader()
        wv.navigationDelegate = loader
        do {
            try await loader.load(url: url, in: wv)
        } catch {
            wv.navigationDelegate = nil
            return .unavailable
        }

        var html: String?
        var sawChallenge = false

        // If the user just solved a Cloudflare challenge, allow more wait time
        // for the cleared session + JS challenge solver to settle.
        let maxAttempts = justClearedChallenge ? 15 : 6
        justClearedChallenge = false

        for attempt in 0..<maxAttempts {
            let pageHTML = try? await wv.evaluateJavaScript(
                "document.documentElement.outerHTML"
            ) as? String

            if let pageHTML {
                switch classifyHTML(pageHTML) {
                case .report:
                    html = pageHTML
                case .blocked:
                    sawChallenge = true
                case .unavailable:
                    break
                }
            }

            if html != nil {
                break
            }

            if attempt >= maxAttempts - 1 {
                break
            }
            try? await Task.sleep(for: .seconds(1))
        }

        wv.navigationDelegate = nil

        guard let html else {
            return sawChallenge ? .blocked : .unavailable
        }

        guard let report = parse(html: html) else {
            return sawChallenge ? .blocked : .unavailable
        }

        return .report(report)
    }

    static func classifyHTML(_ html: String) -> DowndetectorFetchState {
        if isChallengePage(html) {
            return .blocked
        }

        if parse(html: html) != nil {
            return .report
        }

        return .unavailable
    }

    static func tabState(hasReportData: Bool, blockedSlug: String?) -> DowndetectorTabState {
        if let blockedSlug {
            return .blocked(slug: blockedSlug)
        }

        if hasReportData {
            return .report
        }

        return .unavailable
    }

    static func canPresentUnlockFlow(for state: DowndetectorFetchState) -> Bool {
        state == .blocked
    }

    static func presentUnlockWindow(for slug: String) {
        guard let url = URL(string: "https://downdetector.com/") else { return }

        let webView = getSharedWebView()
        let window = unlockWindow ?? NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        if unlockWindow == nil {
            window.title = "Downdetector"
            window.isReleasedWhenClosed = false
            window.level = .normal
            window.collectionBehavior = [.moveToActiveSpace, .managed]
            window.delegate = UnlockWindowDelegate.shared
            unlockWindow = window
        }

        webView.removeFromSuperview()
        webView.frame = window.contentView?.bounds ?? .zero
        webView.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
        window.contentView?.addSubview(webView)
        window.center()

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        webView.load(URLRequest(url: url))
    }

    private static func isChallengePage(_ html: String) -> Bool {
        let markers = [
            "Just a moment",
            "Verify you are human",
            "challenge-platform",
            "cf-challenge",
        ]
        return markers.contains { html.contains($0) }
    }

    private static func parse(html: String) -> DowndetectorReport? {
        let status = extractStatus(from: html)
        let dataPoints = extractDataPoints(from: html)
        let reportsMax = extractReportsMax(from: html) ?? dataPoints.map(\.reports).max() ?? 0
        let indicators = extractIndicators(from: html)

        guard !dataPoints.isEmpty else { return nil }

        return DowndetectorReport(
            status: status,
            dataPoints: dataPoints,
            reportsMax: reportsMax,
            indicators: indicators,
            fetchedAt: Date()
        )
    }

    private static func extractStatus(from html: String) -> DowndetectorStatusLevel {
        let pattern = #"CompanyStatsType.*?\\?"status\\?":\\?"(danger|warning|success)\\?""#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return .unknown
        }
        return DowndetectorStatusLevel(rawValue: String(html[range])) ?? .unknown
    }

    private static func extractDataPoints(from html: String) -> [DowndetectorDataPoint] {
        let pattern = #"\\?"timestampUtc\\?":\\?"([^\\"]+)\\?",\\?"reportsValue\\?":(\d+),\\?"baselineValue\\?":(\d+)"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        return matches.compactMap { match -> DowndetectorDataPoint? in
            guard match.numberOfRanges >= 4,
                  let tsRange = Range(match.range(at: 1), in: html),
                  let reportsRange = Range(match.range(at: 2), in: html),
                  let baselineRange = Range(match.range(at: 3), in: html),
                  let timestamp = formatter.date(from: String(html[tsRange])),
                  let reports = Int(html[reportsRange]),
                  let baseline = Int(html[baselineRange]) else {
                return nil
            }
            return DowndetectorDataPoint(timestamp: timestamp, reports: reports, baseline: baseline)
        }
    }

    private static func extractReportsMax(from html: String) -> Int? {
        let pattern = #"\\?"reportsMax\\?":(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html),
              let value = Int(html[range]) else {
            return nil
        }
        return value
    }

    private static func extractIndicators(from html: String) -> [DowndetectorIndicator] {
        let pattern = #"\\?"localizedName\\?":\\?"([^\\"]+)\\?",\\?"count\\?":(\d+),\\?"percentage\\?":([\d.]+)"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        return matches.compactMap { match -> DowndetectorIndicator? in
            guard match.numberOfRanges >= 4,
                  let nameRange = Range(match.range(at: 1), in: html),
                  let countRange = Range(match.range(at: 2), in: html),
                  let pctRange = Range(match.range(at: 3), in: html),
                  let count = Int(html[countRange]),
                  let percentage = Double(html[pctRange]) else {
                return nil
            }
            return DowndetectorIndicator(
                name: String(html[nameRange]),
                count: count,
                percentage: percentage
            )
        }
    }
}

@MainActor
private final class DDNavigationLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(url: URL, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

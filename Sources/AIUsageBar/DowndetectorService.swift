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

    /// Adjusts status based on recency and baseline threshold.
    func effectiveStatus(recencyMinutes: Double, baselinePercent: Double = 200) -> DowndetectorStatusLevel {
        guard status.hasProblems else { return status }

        let cutoff = Date().addingTimeInterval(-recencyMinutes * 60)
        let recentPoints = dataPoints.filter { $0.timestamp >= cutoff }

        guard let latest = (recentPoints.max(by: { $0.timestamp < $1.timestamp })
            ?? dataPoints.max(by: { $0.timestamp < $1.timestamp })) else {
            return .success
        }

        let multiplier = baselinePercent / 100.0
        let hasCurrentProblems = latest.baseline > 0
            ? Double(latest.reports) >= Double(latest.baseline) * multiplier
            : latest.reports > 0
        return hasCurrentProblems ? status : .success
    }
}

// MARK: - Service

@MainActor
enum DowndetectorService {

    private static var webView: WKWebView?
    private static var challengeWindow: NSWindow?
    private static var challengeSolved = false

    private static func getWebView() -> WKWebView {
        if let wv = webView { return wv }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 500), configuration: config)
        webView = wv
        return wv
    }

    private static func showChallengeWindow() {
        guard challengeWindow == nil else { return }
        guard let wv = webView else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Verifying Downdetector..."
        window.isReleasedWhenClosed = false
        wv.frame = window.contentView!.bounds
        wv.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(wv)
        window.center()

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        challengeWindow = window
    }

    private static func hideChallengeWindow() {
        guard let window = challengeWindow else { return }
        if let wv = webView {
            wv.removeFromSuperview()
        }
        window.close()
        challengeWindow = nil
        if NSApp.windows.filter({ $0.isVisible && $0 !== window }).isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    static func fetch(slug: String) async -> DowndetectorReport? {
        guard let url = URL(string: "https://downdetector.com/status/\(slug)/") else { return nil }

        let wv = getWebView()

        let loader = DDNavigationLoader()
        wv.navigationDelegate = loader
        do {
            try await loader.load(url: url, in: wv)
        } catch {
            wv.navigationDelegate = nil
            return nil
        }

        var html: String?
        var showedWindow = false

        for attempt in 0..<30 {
            let pageHTML = try? await wv.evaluateJavaScript(
                "document.documentElement.outerHTML"
            ) as? String

            if let h = pageHTML, h.contains("reportsValue") {
                html = h
                if showedWindow {
                    challengeSolved = true
                    hideChallengeWindow()
                }
                break
            }

            if attempt == 2, !challengeSolved {
                let isChallenge = pageHTML?.contains("Just a moment") == true
                if isChallenge {
                    showChallengeWindow()
                    showedWindow = true
                }
            }

            try? await Task.sleep(for: .seconds(1))
        }

        wv.navigationDelegate = nil

        if showedWindow && html == nil {
            hideChallengeWindow()
        }

        guard let html else { return nil }
        return parse(html: html)
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

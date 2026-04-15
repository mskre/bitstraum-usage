import AppKit
import Foundation
import WebKit

/// Manages one persistent WKWebView per provider.
/// The same webview is used for sign-in AND polling -- no cookie transfer needed.
@MainActor
final class WebAutomationService: NSObject {
    private var webViews: [ProviderID: WKWebView] = [:]
    private var signInWindows: [ProviderID: NSWindow] = [:]
    private let dataStore = WKWebsiteDataStore.default()

    /// Returns or creates the persistent WKWebView for a provider.
    private func webView(for provider: ProviderID) -> WKWebView {
        if let existing = webViews[provider] { return existing }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700), configuration: config)
        webViews[provider] = wv
        return wv
    }

    /// Opens the persistent WKWebView in a visible window for sign-in.
    /// When the user closes the window, onClose is called.
    /// The WKWebView stays alive -- only detached from the window.
    func signIn(for provider: ProviderID, onClose: @escaping () -> Void) {
        // If already showing, bring to front
        if let existing = signInWindows[provider] {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let wv = webView(for: provider)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to \(provider.title)"
        window.isReleasedWhenClosed = false
        window.center()

        // Attach the persistent WKWebView to this window
        wv.frame = window.contentView!.bounds
        wv.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(wv)

        // Navigate to login page
        wv.load(URLRequest(url: provider.loginURL))

        signInWindows[provider] = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Detach webview from window but keep it alive
                let wv = self.webView(for: provider)
                wv.removeFromSuperview()
                self.signInWindows.removeValue(forKey: provider)

                if self.signInWindows.isEmpty {
                    NSApp.setActivationPolicy(.accessory)
                }

                // Small delay to let the webview settle, then poll
                try? await Task.sleep(for: .seconds(1))
                onClose()
            }
        }
    }

    /// Uses the persistent WKWebView for this provider to navigate to a URL
    /// and run a JS script. Returns the JSON string from the script.
    func evaluateJSON(for provider: ProviderID, at url: URL, script: String) async throws -> String {
        let wv = webView(for: provider)

        // Navigate to the usage URL
        let loader = NavigationLoader()
        wv.navigationDelegate = loader
        try await loader.load(url: url, in: wv)

        // Wait for SPA content to render -- look for actual percentage data
        for _ in 0..<20 {
            try? await Task.sleep(for: .seconds(1))
            let found = try? await wv.evaluateJavaScript(
                "(/\\d{1,3}\\s*%\\s*(igjen|remaining|left|used)/i).test(document.body.innerText)"
            )
            if found as? Bool == true { break }
        }

        // Run the scraping script
        let result = try await wv.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)

        guard let string = result as? String else {
            throw ProviderError.invalidPayload("\(provider.title) did not return a JSON string")
        }

        return string
    }
}

// MARK: - Navigation helper

@MainActor
private final class NavigationLoader: NSObject, WKNavigationDelegate {
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

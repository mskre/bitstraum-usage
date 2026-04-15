import AppKit
import Foundation
import WebKit

/// Manages one persistent WKWebView per provider.
/// The same webview is used for sign-in AND polling -- no cookie transfer needed.
@MainActor
final class WebAutomationService: NSObject {
    private var webViews: [ProviderID: WKWebView] = [:]
    private var signInWindows: [ProviderID: NSWindow] = [:]
    private var signInDelegates: [ProviderID: SignInNavigationDelegate] = [:]
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
    /// `onAuth` is called when sign-in is detected (page navigates away from login).
    /// Also called when the window is closed.
    func signIn(for provider: ProviderID, onAuth: @escaping () -> Void) {
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
        window.hidesOnDeactivate = false
        window.center()

        wv.frame = window.contentView!.bounds
        wv.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(wv)

        // Watch navigations: detect when user finishes login
        let delegate = SignInNavigationDelegate(provider: provider, onAuth: onAuth)
        signInDelegates[provider] = delegate
        wv.navigationDelegate = delegate

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
                let wv = self.webView(for: provider)
                wv.removeFromSuperview()
                wv.navigationDelegate = nil
                self.signInWindows.removeValue(forKey: provider)
                self.signInDelegates.removeValue(forKey: provider)

                if self.signInWindows.isEmpty {
                    NSApp.setActivationPolicy(.accessory)
                }

                try? await Task.sleep(for: .seconds(1))
                onAuth()
            }
        }
    }

    /// Signs out from a provider by clearing its cookies/data and destroying its webview.
    func signOut(for provider: ProviderID) async {
        // Close sign-in window if open
        if let window = signInWindows[provider] {
            window.close()
            signInWindows.removeValue(forKey: provider)
            signInDelegates.removeValue(forKey: provider)
        }

        // Remove cached webview
        if let wv = webViews[provider] {
            wv.removeFromSuperview()
            wv.navigationDelegate = nil
            webViews.removeValue(forKey: provider)
        }

        // Clear website data for this provider's domain
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: allTypes)
        let domain = provider.loginURL.host ?? ""
        let matching = records.filter { record in
            record.displayName.contains(domain) ||
            domain.contains(record.displayName)
        }
        if !matching.isEmpty {
            await dataStore.removeData(ofTypes: allTypes, for: matching)
        }

        if signInWindows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Uses the persistent WKWebView for this provider to navigate to a URL
    /// and run a JS script. Returns the JSON string from the script.
    func evaluateJSON(for provider: ProviderID, at url: URL, script: String, waitForDOM: Bool = true) async throws -> String {
        let wv = webView(for: provider)

        // Clear the sign-in delegate so it doesn't interfere with polling navigation
        let savedDelegate = signInDelegates[provider]
        wv.navigationDelegate = nil

        // Navigate to the usage URL
        let loader = NavigationLoader()
        wv.navigationDelegate = loader
        try await loader.load(url: url, in: wv)

        // Wait for SPA content to render (only for DOM scrapers, not API fetchers)
        if waitForDOM {
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                let found = try? await wv.evaluateJavaScript(
                    "(/\\d{1,3}\\s*%\\s*(igjen|remaining|left|used)/i).test(document.body.innerText)"
                )
                if found as? Bool == true { break }
            }
        } else {
            // Brief pause for page JS to initialize
            try? await Task.sleep(for: .seconds(2))
        }

        // Run the scraping script
        let result = try await wv.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)

        // Restore sign-in delegate if window is still open
        if let saved = savedDelegate, signInWindows[provider] != nil {
            wv.navigationDelegate = saved
        }

        guard let string = result as? String else {
            throw ProviderError.invalidPayload("\(provider.title) did not return a JSON string")
        }

        return string
    }
}

// MARK: - Detects when user completes sign-in by watching URL changes

@MainActor
final class SignInNavigationDelegate: NSObject, WKNavigationDelegate {
    private let provider: ProviderID
    private let onAuth: () -> Void
    private var hasTriggered = false
    private var loadCount = 0

    init(provider: ProviderID, onAuth: @escaping () -> Void) {
        self.provider = provider
        self.onAuth = onAuth
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadCount += 1

        // Skip the first load (that's the login page itself)
        if loadCount <= 1 { return }

        // After the first navigation completes, the user likely signed in.
        // Trigger a refresh. Use a flag to avoid spamming.
        if !hasTriggered {
            hasTriggered = true
            // Delay slightly to let the page settle after auth redirect
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.onAuth()
                // Reset so subsequent navigations can trigger again
                try? await Task.sleep(for: .seconds(10))
                self.hasTriggered = false
            }
        }
    }
}

// MARK: - Navigation helper for polling

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

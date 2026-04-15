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
    private var signInUIDelegates: [ProviderID: SignInUIDelegate] = [:]
    private let dataStore = WKWebsiteDataStore.default()

    /// Returns or creates the persistent WKWebView for a provider.
    private func webView(for provider: ProviderID) -> WKWebView {
        if let existing = webViews[provider] { return existing }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

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

        // Watch navigations: detect when user finishes login + show URL in title
        let delegate = SignInNavigationDelegate(provider: provider, window: window, onAuth: onAuth)
        signInDelegates[provider] = delegate
        wv.navigationDelegate = delegate

        // UI delegate: enables password autofill popover and SSO popup windows
        let uiDelegate = SignInUIDelegate(provider: provider)
        signInUIDelegates[provider] = uiDelegate
        wv.uiDelegate = uiDelegate

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
                wv.uiDelegate = nil
                self.signInWindows.removeValue(forKey: provider)
                self.signInDelegates.removeValue(forKey: provider)
                self.signInUIDelegates.removeValue(forKey: provider)

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
        // Remove from tracking BEFORE closing window to prevent the
        // willCloseNotification observer from firing a spurious onAuth()
        signInDelegates.removeValue(forKey: provider)
        signInUIDelegates.removeValue(forKey: provider)

        // Close sign-in window if open
        if let window = signInWindows[provider] {
            signInWindows.removeValue(forKey: provider)
            window.close()
        }

        // Remove cached webview
        if let wv = webViews[provider] {
            wv.removeFromSuperview()
            wv.navigationDelegate = nil
            wv.uiDelegate = nil
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
    private weak var window: NSWindow?
    private let onAuth: () -> Void
    private var hasTriggered = false
    private var loadCount = 0

    init(provider: ProviderID, window: NSWindow, onAuth: @escaping () -> Void) {
        self.provider = provider
        self.window = window
        self.onAuth = onAuth
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Update window title with current URL
        guard let url = webView.url else { return }
        let host = url.host ?? url.absoluteString
        let path = url.path.lowercased()
        window?.title = "\(provider.title) — \(host)"

        // Only trigger auth when we're on the provider's domain
        let providerHost = provider.loginURL.host ?? ""
        guard host.hasSuffix(providerHost) || providerHost.hasSuffix(host) else { return }

        // Skip if we're on a login/auth page -- user hasn't finished signing in yet
        let authPaths = ["/login", "/signin", "/sign-in", "/signup", "/sign-up", "/auth", "/oauth"]
        if authPaths.contains(where: { path.hasPrefix($0) }) { return }

        // We're on the provider's domain and not on a login page.
        // Verify the user actually has a valid session before auto-closing.
        if !hasTriggered {
            hasTriggered = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))

                // Check if user is actually authenticated via a quick API probe
                let authJS: String
                switch self.provider {
                case .chatgpt:
                    authJS = """
                    var r = await fetch('/api/auth/session');
                    var s = await r.json();
                    return (s.accessToken || s.access_token) ? 'yes' : 'no';
                    """
                case .claude:
                    authJS = """
                    var r = await fetch('/api/account', {credentials: 'include'});
                    return r.ok ? 'yes' : 'no';
                    """
                }

                let result = try? await webView.callAsyncJavaScript(
                    authJS, arguments: [:], in: nil, contentWorld: .page
                ) as? String

                if result == "yes" {
                    self.window?.close()
                    self.onAuth()
                }

                try? await Task.sleep(for: .seconds(10))
                self.hasTriggered = false
            }
        }
    }
}

// MARK: - UI delegate: password autofill and SSO popup windows

@MainActor
final class SignInUIDelegate: NSObject, WKUIDelegate {
    private let provider: ProviderID

    init(provider: ProviderID) {
        self.provider = provider
    }

    /// Handle window.open() -- needed for Google/Apple SSO popup flows
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Load popup URLs in the same webview instead of opening a new window
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    /// Handle JavaScript alert()
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    /// Handle JavaScript confirm()
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
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

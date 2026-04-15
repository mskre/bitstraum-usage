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
    private var signInCloseObservers: [ProviderID: NSObjectProtocol] = [:]
    private var suppressedCloseCallbacks = Set<ProviderID>()
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
    /// `onAuth` is called whenever the sign-in window closes, regardless of whether authentication succeeds.
    /// Successful authentication automatically closes the window, which then triggers `onAuth`.
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
        let delegate = SignInNavigationDelegate(provider: provider, window: window)
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

        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let wv = self.webViews[provider] {
                    wv.removeFromSuperview()
                    wv.navigationDelegate = nil
                    wv.uiDelegate = nil
                }
                self.cleanupSignInSession(for: provider)

                if self.signInWindows.isEmpty {
                    NSApp.setActivationPolicy(.accessory)
                }

                let shouldNotify = self.suppressedCloseCallbacks.remove(provider) == nil
                guard shouldNotify else { return }

                try? await Task.sleep(for: .seconds(1))
                onAuth()
            }
        }
        signInCloseObservers[provider] = closeObserver
    }

    /// Signs out from a provider by clearing its cookies/data and destroying its webview.
    func signOut(for provider: ProviderID) async {
        // Close sign-in window if open; suppress the close observer's
        // onAuth callback so sign-out doesn't trigger a refresh.
        if let window = signInWindows[provider] {
            suppressedCloseCallbacks.insert(provider)
            window.close()
        } else {
            cleanupSignInSession(for: provider)
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

    private func cleanupSignInSession(for provider: ProviderID) {
        signInWindows.removeValue(forKey: provider)
        signInDelegates.removeValue(forKey: provider)
        signInUIDelegates.removeValue(forKey: provider)

        if let observer = signInCloseObservers.removeValue(forKey: provider) {
            NotificationCenter.default.removeObserver(observer)
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
    private weak var webView: WKWebView?
    private var authMonitorTask: Task<Void, Never>?

    init(provider: ProviderID, window: NSWindow) {
        self.provider = provider
        self.window = window
    }

    deinit {
        authMonitorTask?.cancel()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.webView = webView
        updateWindowTitle(for: webView)
        startAuthMonitorIfNeeded()
    }

    private func updateWindowTitle(for webView: WKWebView) {
        guard let url = webView.url else { return }
        let host = url.host ?? url.absoluteString
        window?.title = "\(provider.title) — \(host)"
    }

    private func startAuthMonitorIfNeeded() {
        guard authMonitorTask == nil else { return }

        authMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let webView = self.webView, let window = self.window, window.isVisible else {
                    return
                }

                self.updateWindowTitle(for: webView)

                if await self.isAuthenticated(in: webView) {
                    self.authMonitorTask?.cancel()
                    self.authMonitorTask = nil
                    window.close()
                    return
                }

                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func isAuthenticated(in webView: WKWebView) async -> Bool {
        guard let host = webView.url?.host else { return false }

        let providerHost = provider.loginURL.host ?? ""
        guard host.hasSuffix(providerHost) || providerHost.hasSuffix(host) else { return false }

        let authJS: String
        switch provider {
        case .chatgpt:
            authJS = """
            var r = await fetch('/api/auth/session', {credentials: 'include'});
            if (!r.ok) return 'no';
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
            authJS,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String

        return result == "yes"
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

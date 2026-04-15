# Browser Authentication Research for Bitstraum Usage

## Problem Statement

Bitstraum Usage uses an embedded `WKWebView` per provider for both sign-in and polling. The webview keeps cookies in `WKWebsiteDataStore.default()` and reuses them for `fetch()` calls. The problem: the embedded browser has no access to the user's password manager (Bitwarden extension, Safari Passwords, Chrome autofill), saved credentials, or existing browser sessions. Signing in is painful.

This document evaluates approaches for using the user's real browser instead.

---

## Current Architecture

```
WebAutomationService
├── One WKWebView per ProviderID (.chatgpt, .claude)
├── WKWebsiteDataStore.default() — shared cookie jar
├── signIn() — opens webview in NSWindow, user logs in manually
└── evaluateJSON() — navigates webview to usage URL, runs JS fetch/scrape
    ├── ChatGPT: fetch("/api/auth/session") → accessToken → fetch("/backend-api/wham/usage")
    └── Claude: DOM scrape for "X% used" patterns + fetch("/api/account")
```

The webview is **both** the auth mechanism and the data-fetching mechanism. Any alternative must either:
1. Get session cookies into the webview from elsewhere, or
2. Replace the webview's role in data fetching entirely

---

## Approach 1: ASWebAuthenticationSession

**What it is:** Apple's API (`AuthenticationServices` framework) for web-based authentication. Presents a system-provided browser sheet (Safari-backed) that shares cookies and credentials with Safari. Designed for OAuth flows but uses a standard browser under the hood.

**How it works:**
1. App creates `ASWebAuthenticationSession` with a URL and a callback URL scheme
2. System shows a Safari-backed sheet with the target URL
3. User authenticates (password manager, autofill, Touch ID all work)
4. When the page navigates to the callback URL scheme, the session completes and returns the callback URL to the app

**Feasibility for session-cookie auth:**

This is the core problem. `ASWebAuthenticationSession` is designed around **redirect-based OAuth flows** where the auth server eventually redirects to `myapp://callback?code=xyz`. It returns the final URL to the app, nothing else.

- **No cookie access.** The session runs in an isolated Safari context. The app cannot read cookies set during the session. There is no API to extract `Set-Cookie` headers or the cookie jar contents.
- **No way to detect "login complete" without a redirect.** ChatGPT and Claude don't redirect to a custom URL scheme after login — they just load their dashboard. `ASWebAuthenticationSession` has no "page loaded" callback; it only completes when the URL matches the callback scheme.
- **Isolated storage.** Starting in macOS 12+/iOS 15+, `ASWebAuthenticationSession` uses **ephemeral** storage by default (`prefersEphemeralWebBrowserSession = true`). Setting it to `false` shares cookies with Safari, but this means the session is in Safari's cookie jar, not the app's WKWebView.

**Could you make it work?**

Theoretically, you'd need ChatGPT/Claude to redirect to a custom URL scheme after login (they don't). You could try injecting a redirect via a proxy or man-in-the-middle, but that's fragile and likely blocked by HSTS/CSP.

**Verdict: Not viable.** ASWebAuthenticationSession is designed for OAuth redirect flows and provides no mechanism to extract session cookies for arbitrary websites. ChatGPT and Claude are not OAuth providers in this context.

| Criterion | Rating |
|---|---|
| Technical feasibility | Not feasible — no cookie extraction, no completion signal |
| Works for ChatGPT/Claude | No — these sites don't support redirect-based auth |
| Security | N/A |
| Sandbox compatibility | Excellent (Apple's blessed API) |
| UX quality | N/A |

---

## Approach 2: Open Default Browser Directly

**What it is:** Open `https://chatgpt.com/` in the user's default browser via `NSWorkspace.shared.open(url)`. The user logs in using their real browser with all extensions, password managers, and existing sessions. Then... what?

**The fundamental problem:** Once the user authenticates in their browser, the session cookies live in the browser's cookie jar (Safari, Chrome, Firefox). There is no standard mechanism on macOS to:
- Transfer cookies from the browser back to the app
- Get notified that the user completed authentication
- Observe the browser's navigation state

**How do Slack, Discord, Spotify, etc. do it?**

These apps use **OAuth 2.0** or similar token-based flows:
1. App opens `https://provider.com/oauth/authorize?redirect_uri=myapp://callback&...`
2. User authenticates in browser
3. Provider redirects to `myapp://callback?code=AUTH_CODE`
4. macOS routes the custom URL scheme to the app
5. App exchanges the code for an access token via a server-side API

The key insight: **these apps never need the browser's cookies.** They receive a token via redirect. The token is self-contained. This is fundamentally different from our use case where we need to impersonate an authenticated browser session to scrape web UIs.

**Verdict: Not viable on its own.** Opening the browser for login is trivial, but there's no way to get the session cookies back into the app. This approach only works when combined with one of the other approaches below (cookie extraction or localhost callback).

| Criterion | Rating |
|---|---|
| Technical feasibility | Login works; getting cookies back doesn't |
| Works for ChatGPT/Claude | Login yes; subsequent polling no |
| Security | N/A |
| Sandbox compatibility | Fine for opening URLs |
| UX quality | Login UX is excellent (real browser); dead end after that |

---

## Approach 3: Cookie Extraction from Real Browser

**What it is:** Programmatically read cookies from the user's installed browser (Safari, Chrome, Firefox) and inject them into the app's WKWebView or HTTP requests.

### Safari

- Cookies stored in `~/Library/Cookies/Cookies.binarycookies`
- **App Sandbox blocks access** — sandboxed apps cannot read files outside their container without explicit user permission (e.g., via `NSOpenPanel`)
- Even without sandbox, the file format is a binary plist with Apple's proprietary encoding
- Starting in macOS Sonoma, cookie files may have additional SIP/TCC protections
- Safari does not expose a programmatic cookie API to third-party apps
- **Verdict: Impractical and fragile**

### Chrome

- Cookies stored in `~/Library/Application Support/Google/Chrome/Default/Cookies` (SQLite database)
- Since Chrome 80 (2020), **all cookies are encrypted** using a key stored in the macOS Keychain under Chrome's access control. Only Chrome can decrypt them.
- Third-party tools that extract Chrome cookies (like `pycookiecheat`, `browser_cookie3`) work by accessing the Keychain entry — this requires the user to grant Keychain access, and Chrome periodically rotates the key
- Chrome has been progressively tightening this: App-Bound Encryption (2024+) ties the key to the Chrome app signature, making extraction even harder
- **Verdict: Technically possible but increasingly difficult, fragile, and ethically questionable**

### Firefox

- Cookies in `~/Library/Application Support/Firefox/Profiles/<profile>/cookies.sqlite`
- **Not encrypted** — plain SQLite database, readable if you can access the file
- App Sandbox still blocks access without user consent
- Profile directory name is random, requiring discovery
- **Verdict: Most accessible of the three, but still requires unsandboxed access and is fragile**

### General Cookie Extraction Issues

1. **Security/Ethics.** Reading another app's cookies is the exact behavior that malware performs. Apple's security model is designed to prevent this. macOS Sequoia and later further restrict cross-app data access.

2. **Cookie attributes.** Session cookies from ChatGPT/Claude use `HttpOnly`, `Secure`, `SameSite=Lax` or `Strict` attributes. Even if extracted, injecting them into a WKWebView requires them to be set correctly — `SameSite` enforcement in WKWebView may reject cookies that were set for a different origin context.

3. **Session tokens rotate.** ChatGPT's `__Secure-next-auth.session-token` and Claude's session cookies have expiration and rotation policies. Extracted cookies become stale.

4. **App Store rejection.** Apps that read other apps' data will be rejected from the Mac App Store. Even for direct distribution, this is the kind of behavior that macOS security features are designed to block.

**Verdict: Not recommended.** While technically possible (especially for Firefox), this approach is fragile, ethically problematic, increasingly blocked by OS-level protections, and would prevent App Store distribution.

| Criterion | Rating |
|---|---|
| Technical feasibility | Partially — Firefox yes, Chrome difficult, Safari very hard |
| Works for ChatGPT/Claude | In theory, if you can get the right cookies |
| Security | Terrible — mimics malware behavior |
| Sandbox compatibility | Incompatible with App Sandbox |
| UX quality | Poor — requires Keychain prompts, file access grants |

---

## Approach 4: Hybrid — Browser Login + Redirect with Token

**What it is:** Open the real browser for login, but instead of extracting cookies afterward, use a redirect mechanism to pass authentication data back to the app.

### Variant A: Custom URL Scheme Redirect

1. Register a custom URL scheme (e.g., `ai-usage-bar://`)
2. Open `https://chatgpt.com/` in the browser
3. After login, somehow redirect to `ai-usage-bar://auth?token=...`
4. App receives the URL via `application(_:open:)` or similar

**Problem:** ChatGPT and Claude won't redirect to a custom URL scheme after login. You don't control their auth flow. There's no way to inject a redirect without:
- A browser extension (which defeats the purpose of simplicity)
- A proxy server that rewrites responses (fragile, HTTPS issues)

### Variant B: Browser Extension

1. User installs a companion browser extension
2. Extension detects when user is logged into ChatGPT/Claude
3. Extension extracts session cookies and sends them to the native app (via native messaging, localhost HTTP, or custom URL scheme)

This actually works and is used by some tools (e.g., some AI wrapper apps use browser extensions to extract session tokens). However:
- Requires user to install and trust a browser extension
- Extension development/maintenance for each browser (Chrome, Safari, Firefox)
- Safari extension distribution requires Xcode + App Store or Developer ID
- Adds significant complexity
- Browser extensions have their own review processes

### Variant C: Bookmarklet

1. User logs into ChatGPT/Claude normally in their browser
2. User clicks a bookmarklet that extracts session cookies and sends them to `localhost` or a custom URL scheme
3. App receives the cookies and injects them into WKWebView

This is simpler than a full extension but:
- Manual step required every time cookies expire
- Users need to create and manage the bookmarklet
- Browsers increasingly restrict bookmarklet capabilities (CSP)
- `document.cookie` won't reveal `HttpOnly` cookies (which are the important ones)

**Verdict:** Variant B (browser extension) is the only one that's technically sound, but the complexity cost is very high for a personal menu bar utility. Variants A and C don't work for this use case.

| Criterion | Rating |
|---|---|
| Technical feasibility | Extension variant works; others don't |
| Works for ChatGPT/Claude | Extension: yes. Others: no |
| Security | Extension: acceptable. Others: N/A |
| Sandbox compatibility | Extension: fine. Needs native messaging setup |
| UX quality | Extension: decent but high friction to set up |

---

## Approach 5: Localhost Callback Server

**What it is:** Spin up a local HTTP server (e.g., on `http://127.0.0.1:PORT/`), open the browser to the provider's login page with a redirect to localhost, capture auth cookies/tokens from the redirect.

**This is the standard pattern for OAuth on desktop apps** (RFC 8252, Section 7.3 — Loopback Interface Redirection). Used by `gcloud auth login`, `gh auth login`, VS Code, and many CLI/desktop tools.

**The fundamental problem for our use case:**

This pattern requires the **auth server** to support redirecting to `http://127.0.0.1:PORT/callback`. The app registers a redirect URI with the OAuth provider, and after login the provider redirects there with an auth code.

ChatGPT and Claude do not offer:
- OAuth client registration for third-party apps
- Configurable redirect URIs
- Token exchange endpoints for third-party use

Without provider cooperation, the localhost server has nothing to capture. The browser navigates to `chatgpt.com`, the user logs in, and ChatGPT redirects to its own dashboard — never to `http://127.0.0.1:PORT/`.

**Could you make it work with a proxy?**

You could run a localhost proxy that:
1. Intercepts requests to `chatgpt.com` / `claude.ai`
2. Captures `Set-Cookie` headers during the auth flow
3. Forwards cookies to the app

But this requires:
- Configuring the browser to use the proxy (or system proxy settings)
- Installing a custom CA certificate for HTTPS MITM (since both sites use HTTPS)
- This is essentially building a debugging proxy like Charles/mitmproxy
- Massive security and trust implications
- Will trigger browser security warnings

**Verdict: Not viable without provider cooperation.** The localhost callback pattern works for OAuth flows where the provider supports redirect URIs. It doesn't work for scraping session cookies from websites that don't offer third-party auth.

| Criterion | Rating |
|---|---|
| Technical feasibility | Not feasible — no provider-side redirect support |
| Works for ChatGPT/Claude | No — neither offers OAuth for third-party usage scraping |
| Security | N/A (proxy variant would be terrible) |
| Sandbox compatibility | Localhost server is fine; proxy is not |
| UX quality | N/A |

---

## Summary Comparison

| Approach | Feasible? | ChatGPT/Claude? | Security | Sandbox | UX | Complexity |
|---|---|---|---|---|---|---|
| 1. ASWebAuthenticationSession | No | No | Good | Good | N/A | Low |
| 2. Open Browser Directly | Partially | No (no cookie return) | Fine | Fine | Login great | Low |
| 3. Cookie Extraction | Partially | In theory | Bad | Bad | Poor | High |
| 4a. Custom URL Redirect | No | No | N/A | Fine | N/A | Medium |
| 4b. Browser Extension | Yes | Yes | Acceptable | Fine | Setup friction | Very High |
| 4c. Bookmarklet | No | No (HttpOnly cookies) | N/A | Fine | N/A | Medium |
| 5. Localhost Callback | No | No | N/A | Fine | N/A | Medium |

---

## Recommendation

**None of these approaches provide a clean solution.** The fundamental issue is that ChatGPT and Claude are consumer web applications that authenticate via session cookies, not OAuth tokens. They don't offer third-party auth APIs, redirect URI support, or any mechanism for external apps to obtain authenticated sessions.

### Keep the current WKWebView approach but improve it

The embedded WKWebView approach is actually the correct architectural choice given the constraints. The pain point is specifically the sign-in UX. Targeted improvements:

1. **Password autofill support in WKWebView.** WKWebView on macOS supports iCloud Keychain autofill if the app has the Associated Domains entitlement configured. This gives users access to Safari's saved passwords. Requires adding the `webcredentials` Associated Domains entitlement and hosting an `apple-app-site-association` file — but since we don't control `chatgpt.com` or `claude.ai`, this won't help for those domains.

2. **Persistent WKWebView sessions.** The current approach already uses `WKWebsiteDataStore.default()` which persists cookies across app launches. Session longevity depends on the provider's cookie expiration. This is already implemented correctly.

3. **Better sign-in detection.** Improve the UX around when sign-in completes — detect auth faster, close the window automatically, begin polling immediately.

### Future: Watch for provider API changes

The right long-term solution is for these providers to offer:
- Official usage APIs with API key auth (OpenRouter already does this)
- OAuth flows for third-party usage monitoring

If/when ChatGPT or Claude offer public APIs for usage data, the app should switch to API-key-based auth, which eliminates the browser auth problem entirely.

### If the WKWebView sign-in UX is truly unacceptable

The **browser extension** approach (4b) is the only technically viable alternative that actually works. It's high complexity but achievable:

1. Build a Safari App Extension (requires Xcode project restructuring)
2. Extension detects login on ChatGPT/Claude
3. Extension uses native messaging to pass session data to the menu bar app
4. App uses session data for polling (either inject into WKWebView or switch to direct URLSession requests)

This is a significant engineering effort for a personal utility but is the only approach that gives real browser login with all its benefits while getting auth data back to the app.

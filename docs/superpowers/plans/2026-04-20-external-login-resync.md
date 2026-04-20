# External Login Resync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Claude and ChatGPT `Sign In` / `Reconnect` import fresh external credentials immediately when available, and otherwise prompt for external login and wait for those credentials to appear before refreshing.

**Architecture:** Keep app-owned credentials as the only runtime source of truth. Treat user-initiated `Sign In` as an external-login resync workflow: immediate import attempt, then provider-specific prompt-and-wait polling, then import into the app keychain and refresh when credentials appear.

**Tech Stack:** Swift, AppKit, SwiftUI, Security framework, Foundation

---

### Task 1: Add wait-and-import test harness

**Files:**
- Create: `Tests/ExternalLoginResyncTests.swift`
- Modify: `Sources/AIUsageBar/KeychainHelper.swift`
- Modify: `Sources/AIUsageBar/OpenAIAuthHelper.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ExternalLoginResyncTests.swift` with an executable harness that expects a polling helper to return imported credentials after a delayed provider update:

```swift
import Foundation

@main
struct ExternalLoginResyncTests {
    static func main() async throws {
        let claudeCreds = KeychainHelper.ClaudeCredentials(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: 1_800_000_000_000,
            subscriptionType: "max",
            rateLimitTier: "default_claude_max_20x",
            scopes: []
        )

        var claudeSource: KeychainHelper.ClaudeCredentials?
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            claudeSource = claudeCreds
        }

        let imported = try await waitForExternalCredentials(timeout: 0.5, interval: 0.05) {
            claudeSource
        }

        guard imported == claudeCreds else {
            fatalError("Expected wait helper to return fresh external credentials")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swiftc -parse-as-library Sources/AIUsageBar/AppCredentialStore.swift Sources/AIUsageBar/KeychainHelper.swift Sources/AIUsageBar/OpenAIAuthHelper.swift Tests/ExternalLoginResyncTests.swift -o .build/ExternalLoginResyncTests
```

Expected: FAIL because `waitForExternalCredentials` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

Add a small shared async polling helper near the bottom of `Sources/AIUsageBar/KeychainHelper.swift`:

```swift
func waitForExternalCredentials<T>(
    timeout: TimeInterval,
    interval: TimeInterval = 0.25,
    read: @escaping () -> T?
) async throws -> T? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let value = read() {
            return value
        }
        try await Task.sleep(for: .seconds(interval))
    }
    return read()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swiftc -parse-as-library Sources/AIUsageBar/AppCredentialStore.swift Sources/AIUsageBar/KeychainHelper.swift Sources/AIUsageBar/OpenAIAuthHelper.swift Tests/ExternalLoginResyncTests.swift -o .build/ExternalLoginResyncTests && ./.build/ExternalLoginResyncTests
```

Expected: PASS with no output.

### Task 2: Implement provider-specific external-login resync workflow

**Files:**
- Modify: `Sources/AIUsageBar/UsageStore.swift`
- Modify: `Sources/AIUsageBar/KeychainHelper.swift`
- Modify: `Sources/AIUsageBar/OpenAIAuthHelper.swift`

- [ ] **Step 1: Write the failing behavior expectation**

Add this second check to `Tests/ExternalLoginResyncTests.swift` so timeout behavior is specified before implementation:

```swift
let missing = try await waitForExternalCredentials(timeout: 0.1, interval: 0.05) {
    nil as KeychainHelper.ClaudeCredentials?
}

guard missing == nil else {
    fatalError("Expected wait helper to return nil after timeout")
}
```

- [ ] **Step 2: Run the harness to verify the new expectation fails if needed**

Run:

```bash
swiftc -parse-as-library Sources/AIUsageBar/AppCredentialStore.swift Sources/AIUsageBar/KeychainHelper.swift Sources/AIUsageBar/OpenAIAuthHelper.swift Tests/ExternalLoginResyncTests.swift -o .build/ExternalLoginResyncTests && ./.build/ExternalLoginResyncTests
```

Expected: PASS if the helper already satisfies timeout behavior, otherwise FAIL and then continue to Step 3.

- [ ] **Step 3: Write minimal implementation**

Update `Sources/AIUsageBar/UsageStore.swift` so `signIn(to:)` uses provider-specific external-login waiting instead of browser fallback for Claude and ChatGPT:

```swift
if provider == .claude {
    Task {
        await resyncFromClaudeCode()
    }
    return
}

if provider == .chatgpt {
    Task {
        await resyncFromCodex()
    }
    return
}
```

Add two private helpers in `UsageStore`:

```swift
private func resyncFromClaudeCode() async {
    if let _ = try? KeychainHelper.importClaudeCodeCredentials() {
        await refreshSingle(.claude)
        return
    }

    update(.claude) {
        $0.state = .unauthenticated
        $0.statusMessage = "Sign into Claude Code, then wait..."
        $0.limits = []
        $0.authenticated = false
    }

    if let creds = try? await waitForExternalCredentials(timeout: 30)({ KeychainHelper.readClaudeCodeCredentials() }),
       creds != nil,
       let _ = try? KeychainHelper.importClaudeCodeCredentials() {
        await refreshSingle(.claude)
        return
    }

    update(.claude) {
        $0.state = .unauthenticated
        $0.statusMessage = "Claude Code login not detected"
        $0.limits = []
        $0.authenticated = false
    }
}
```

```swift
private func resyncFromCodex() async {
    if let _ = try? OpenAIAuthHelper.importCodexCredentials() {
        await refreshSingle(.chatgpt)
        return
    }

    update(.chatgpt) {
        $0.state = .unauthenticated
        $0.statusMessage = "Sign into Codex, then wait..."
        $0.limits = []
        $0.authenticated = false
    }

    if let creds = try? await waitForExternalCredentials(timeout: 30)({ OpenAIAuthHelper.readCodexCredentials() }),
       creds != nil,
       let _ = try? OpenAIAuthHelper.importCodexCredentials() {
        await refreshSingle(.chatgpt)
        return
    }

    update(.chatgpt) {
        $0.state = .unauthenticated
        $0.statusMessage = "Codex login not detected"
        $0.limits = []
        $0.authenticated = false
    }
}
```

Keep all other providers on the current embedded-browser path.

- [ ] **Step 4: Run the targeted verification**

Run:

```bash
swiftc -parse-as-library Sources/AIUsageBar/AppCredentialStore.swift Sources/AIUsageBar/KeychainHelper.swift Sources/AIUsageBar/OpenAIAuthHelper.swift Tests/ExternalLoginResyncTests.swift -o .build/ExternalLoginResyncTests && ./.build/ExternalLoginResyncTests
```

Expected: PASS with no output.

### Task 3: Align provider messaging and reconnect behavior

**Files:**
- Modify: `Sources/AIUsageBar/ProviderClients.swift`
- Modify: `Sources/AIUsageBar/PopoverView.swift`
- Modify: `Sources/AIUsageBar/UsageStore.swift`

- [ ] **Step 1: Write the failing UX expectation**

Add these inline expectations to the plan implementation notes before editing:

```swift
// Claude missing external login should guide the user to Claude Code.
// ChatGPT missing external login should guide the user to Codex.
// Reconnect should use the same resync path as Sign In.
```

- [ ] **Step 2: Write minimal implementation**

Change provider auth-required strings in `ProviderClients.swift` to match the external-login flow:

```swift
throw ProviderError.authRequired("Sign into Claude Code")
throw ProviderError.authRequired("Sign into Codex")
```

Keep `PopoverView` action labels as `Connect` / `Reconnect`, but ensure the supporting status message shown under the card reflects the new prompts from `UsageStore`.

- [ ] **Step 3: Run full app build verification**

Run:

```bash
zsh Scripts/build.sh
```

Expected: build succeeds and bundles `Bitstraum Usage.app`.

### Task 4: Update docs for the new sign-in flow

**Files:**
- Modify: `/Users/mikkel/vaults/main/personal/AI Usage Bar.md`

- [ ] **Step 1: Document the new behavior**

Add bullets under authentication or notes covering:

```md
- Claude `Sign In` first imports Claude Code credentials if present.
- If Claude Code credentials are missing, the app asks the user to sign into Claude Code and waits briefly for those credentials to appear.
- ChatGPT `Sign In` follows the same pattern with Codex.
- The app does not fall back to embedded browser sign-in for Claude or ChatGPT while waiting for those external credentials.
```

- [ ] **Step 2: Run final verification**

Run:

```bash
swiftc -parse-as-library Sources/AIUsageBar/AppCredentialStore.swift Sources/AIUsageBar/KeychainHelper.swift Sources/AIUsageBar/OpenAIAuthHelper.swift Tests/ExternalLoginResyncTests.swift -o .build/ExternalLoginResyncTests && ./.build/ExternalLoginResyncTests
zsh Scripts/build.sh
```

Expected: both commands succeed.

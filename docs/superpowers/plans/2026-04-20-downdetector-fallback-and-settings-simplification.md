# Downdetector Fallback And Settings Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-app Downdetector recovery flow and replace the current settings control panel with a much shorter essentials-focused settings screen.

**Architecture:** Extend the existing Downdetector fetch classification into a real UI state with an explicit in-app unlock window that reuses the app’s shared `WKWebView` session. Simplify settings by keeping storage compatibility in `ColorSettings` while rewriting the SwiftUI settings view to expose only core controls and rely on opinionated defaults for the rest.

**Tech Stack:** Swift, AppKit, SwiftUI, WebKit, Foundation

---

### Task 1: Add Downdetector unlock-session plumbing

**Files:**
- Modify: `Sources/AIUsageBar/DowndetectorService.swift`
- Create: `Tests/DowndetectorUnlockFlowTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/DowndetectorUnlockFlowTests.swift` with a minimal executable harness that expects the service to expose whether a blocked challenge can be surfaced to the UI:

```swift
import Foundation
import WebKit

@main
struct DowndetectorUnlockFlowTests {
    static func main() {
        let html = "<html><body>Just a moment</body></html>"
        guard DowndetectorService.classifyHTML(html) == .blocked else {
            fatalError("Expected challenge page to classify as blocked")
        }

        guard DowndetectorService.canPresentUnlockFlow(for: .blocked) else {
            fatalError("Expected blocked fetch state to allow unlock flow")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swiftc -parse-as-library -framework WebKit -framework AppKit Sources/AIUsageBar/DowndetectorService.swift Tests/DowndetectorUnlockFlowTests.swift -o .build/DowndetectorUnlockFlowTests
```

Expected: FAIL because `canPresentUnlockFlow` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

In `Sources/AIUsageBar/DowndetectorService.swift`, add a small helper and explicit unlock presenter around the shared WebKit session:

```swift
static func canPresentUnlockFlow(for state: DowndetectorFetchState) -> Bool {
    state == .blocked
}

static func presentUnlockWindow(for slug: String) {
    guard let url = URL(string: "https://downdetector.com/status/\(slug)/") else { return }
    let webView = getWebView()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Downdetector"
    webView.removeFromSuperview()
    webView.frame = window.contentView?.bounds ?? .zero
    webView.autoresizingMask = [.width, .height]
    window.contentView?.addSubview(webView)
    window.center()
    window.makeKeyAndOrderFront(nil)
    webView.load(URLRequest(url: url))
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swiftc -parse-as-library -framework WebKit -framework AppKit Sources/AIUsageBar/DowndetectorService.swift Tests/DowndetectorUnlockFlowTests.swift -o .build/DowndetectorUnlockFlowTests && ./.build/DowndetectorUnlockFlowTests
```

Expected: PASS with no output.

### Task 2: Expose Downdetector UI state and recovery actions

**Files:**
- Modify: `Sources/AIUsageBar/UsageStore.swift`
- Modify: `Sources/AIUsageBar/DowndetectorService.swift`
- Test: `Tests/DowndetectorFetchStateTests.swift`

- [ ] **Step 1: Write the failing test**

Extend `Tests/DowndetectorFetchStateTests.swift` so blocked and unavailable states are distinguishable for UI use:

```swift
let unavailableHTML = "<html><body>No report data</body></html>"
guard DowndetectorService.classifyHTML(unavailableHTML) == .unavailable else {
    fatalError("Expected non-report HTML to classify as unavailable")
}
```

- [ ] **Step 2: Run the test to verify the failing/expected behavior**

Run:

```bash
swiftc -parse-as-library -framework WebKit -framework AppKit Sources/AIUsageBar/DowndetectorService.swift Tests/DowndetectorFetchStateTests.swift -o .build/DowndetectorFetchStateTests && ./.build/DowndetectorFetchStateTests
```

Expected: PASS if classification already works, otherwise FAIL and continue.

- [ ] **Step 3: Write minimal implementation**

In `Sources/AIUsageBar/UsageStore.swift`, publish a small tab state and retry/open actions:

```swift
@Published var downdetectorTabState: DowndetectorFetchState = .unavailable

func retryDowndetectorNow() async {
    await refreshDowndetector()
}

func openDowndetectorUnlockWindow() {
    guard let blockedProvider = ProviderID.allCases.first(where: { $0.downdetectorSlug != nil }) else { return }
    guard let slug = blockedProvider.downdetectorSlug else { return }
    DowndetectorService.presentUnlockWindow(for: slug)
}
```

Update `refreshDowndetector()` to set `downdetectorTabState` to `.blocked`, `.unavailable`, or `.report` based on the fetch results.

- [ ] **Step 4: Run the targeted regression tests**

Run:

```bash
swiftc -parse-as-library -framework WebKit -framework AppKit Sources/AIUsageBar/DowndetectorService.swift Tests/DowndetectorFetchStateTests.swift -o .build/DowndetectorFetchStateTests && ./.build/DowndetectorFetchStateTests
swiftc -parse-as-library -framework WebKit -framework AppKit Sources/AIUsageBar/DowndetectorService.swift Tests/DowndetectorUnlockFlowTests.swift -o .build/DowndetectorUnlockFlowTests && ./.build/DowndetectorUnlockFlowTests
```

Expected: both commands PASS.

### Task 3: Replace dead blocked-state UI with recovery actions

**Files:**
- Modify: `Sources/AIUsageBar/PopoverView.swift`
- Modify: `Sources/AIUsageBar/UsageStore.swift`

- [ ] **Step 1: Write the failing behavior expectation**

Define the expected blocked-state copy in the implementation step before editing:

```swift
// Downdetector tab blocked state should show explanation + Open Downdetector + Retry.
// Generic "will appear after the next refresh" copy should not be used for blocked state.
```

- [ ] **Step 2: Write minimal implementation**

Update `DowndetectorTabView` in `Sources/AIUsageBar/PopoverView.swift` to render a blocked-state action panel:

```swift
if store.downdetectorData.isEmpty {
    VStack(spacing: 10) {
        Text("Downdetector is blocking automated refresh right now.")
        Button("Open Downdetector") { store.openDowndetectorUnlockWindow() }
        Button("Retry") {
            Task { await store.retryDowndetectorNow() }
        }
    }
}
```

Keep the existing report sections unchanged when `downdetectorData` is not empty.

- [ ] **Step 3: Run full app build verification**

Run:

```bash
zsh Scripts/build.sh
```

Expected: build succeeds and bundles `Bitstraum Usage.app`.

### Task 4: Simplify settings to essentials only

**Files:**
- Modify: `Sources/AIUsageBar/PopoverView.swift`
- Modify: `Sources/AIUsageBar/ColorSettings.swift`

- [ ] **Step 1: Write the failing behavior expectation**

Add a brief inline checklist before editing so scope stays tight:

```swift
// Settings should only show: refresh interval, notifications, sensitive info, Downdetector, quit, reset.
// Color pickers and low-level tuning controls should be removed from the primary settings UI.
```

- [ ] **Step 2: Write minimal implementation**

Rewrite `ColorSettingsView` in `Sources/AIUsageBar/PopoverView.swift` to keep only the essentials:

```swift
settingsSection("Essentials") {
    settingsToggle("Show Downdetector", isOn: $colorSettings.showDowndetector)
    settingsToggle("Send notifications", isOn: $colorSettings.sendNotifications)
    settingsToggle("Show sensitive info", isOn: $colorSettings.showSensitiveInfo)
    settingsToggle("Alert dot on menu bar", isOn: $colorSettings.showAlertDot)
    VStack(alignment: .leading, spacing: 4) {
        Text("Refresh interval")
        Slider(value: $colorSettings.refreshIntervalMinutes, in: 1...30, step: 1)
    }
}
```

In `Sources/AIUsageBar/ColorSettings.swift`, make `resetToDefaults()` enforce the opinionated defaults from the spec:

```swift
dismissOnMouseExit = true
rememberLastView = false
showSensitiveInfo = true
maskSensitiveData = true
refreshIntervalMinutes = 5
showDowndetector = true
showAlertDot = true
sendNotifications = true
```

- [ ] **Step 3: Run full app build verification**

Run:

```bash
zsh Scripts/build.sh
```

Expected: build succeeds and the settings view compiles after the simplification.

### Task 5: Update documentation for the new app behavior

**Files:**
- Modify: `/Users/mikkel/vaults/main/personal/AI Usage Bar.md`

- [ ] **Step 1: Document the behavior changes**

Add bullets covering:

```md
- Downdetector blocked state now offers an in-app unlock window and retry action.
- The settings screen is now an essentials-only surface instead of a full tuning panel.
- Most visual and Downdetector threshold tweaks are no longer exposed in the main settings UI.
```

- [ ] **Step 2: Run final verification**

Run:

```bash
swiftc -parse-as-library -framework WebKit -framework AppKit Sources/AIUsageBar/DowndetectorService.swift Tests/DowndetectorFetchStateTests.swift -o .build/DowndetectorFetchStateTests && ./.build/DowndetectorFetchStateTests
swiftc -parse-as-library -framework WebKit -framework AppKit Sources/AIUsageBar/DowndetectorService.swift Tests/DowndetectorUnlockFlowTests.swift -o .build/DowndetectorUnlockFlowTests && ./.build/DowndetectorUnlockFlowTests
zsh Scripts/build.sh
```

Expected: all commands succeed.

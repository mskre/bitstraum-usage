# Privacy Mode Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current ambiguous privacy toggle with a single explicit account-info mode that supports hidden, visible, and masked states.

**Architecture:** Add a small `PrivacyMode` enum to `ColorSettings`, derive it from existing stored booleans for compatibility, and make the settings UI plus account-info rendering use that enum as the source of truth.

**Tech Stack:** Swift, SwiftUI, Foundation

---

### Task 1: Add failing privacy-mode migration regression

**Files:**
- Modify: `Tests/ColorSettingsDefaultsTests.swift`
- Modify: `Sources/AIUsageBar/ColorSettings.swift`

- [ ] **Step 1: Write the failing test**

Extend `Tests/ColorSettingsDefaultsTests.swift` with a migration regression:

```swift
@MainActor
private static func legacyPrivacySettingsMapToExplicitMode() {
    let suiteName = "ColorSettingsDefaultsTests.PrivacyMode"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set(false, forKey: "showSensitiveInfo")
    var settings = ColorSettings(defaults: defaults)
    guard settings.privacyMode == .hidden else {
        fatalError("Expected hidden mode when showSensitiveInfo is false")
    }

    defaults.set(true, forKey: "showSensitiveInfo")
    defaults.set(false, forKey: "maskSensitiveData")
    settings = ColorSettings(defaults: defaults)
    guard settings.privacyMode == .visible else {
        fatalError("Expected visible mode when info is shown and masking is off")
    }

    defaults.set(true, forKey: "maskSensitiveData")
    settings = ColorSettings(defaults: defaults)
    guard settings.privacyMode == .masked else {
        fatalError("Expected masked mode when info is shown and masking is on")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swiftc -parse-as-library -framework AppKit -framework SwiftUI Sources/AIUsageBar/Models.swift Sources/AIUsageBar/ColorSettings.swift Tests/ColorSettingsDefaultsTests.swift -o .build/ColorSettingsDefaultsTests && ./.build/ColorSettingsDefaultsTests
```

Expected: FAIL because `privacyMode` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

In `Sources/AIUsageBar/ColorSettings.swift`:
- add `enum PrivacyMode: String, CaseIterable`
- add `@Published var privacyMode`
- initialize it from legacy booleans

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.

Expected: PASS.

### Task 2: Make rendering and settings use the explicit privacy mode

**Files:**
- Modify: `Sources/AIUsageBar/PopoverView.swift`
- Modify: `Sources/AIUsageBar/ColorSettings.swift`

- [ ] **Step 1: Write the failing behavior expectation**

Add a small expectations block in the implementation notes before editing:

```swift
// hidden -> no account info
// visible -> full account info
// masked -> masked account info
```

- [ ] **Step 2: Write minimal implementation**

Update account-info display logic in `ProviderCardView` and settings UI to use `privacyMode`:
- settings row becomes a compact segmented or picker control for `Hidden`, `Visible`, `Masked`
- `showSensitiveInfo`/`maskSensitiveData` behavior is derived from `privacyMode`

- [ ] **Step 3: Run full build verification**

Run:

```bash
zsh Scripts/build.sh
```

Expected: build succeeds.

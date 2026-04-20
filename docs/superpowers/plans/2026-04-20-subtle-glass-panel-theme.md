# Smoked Glass Panel Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the detached Bitstraum Usage panel into a darker smoked-glass surface closer to the macOS Control Center reference while preserving the no-blue menu-bar behavior.

**Architecture:** Keep the detached `NSPanel` and adjust only the outer chrome in `PopoverView` and panel configuration in `AppMain`. The content layout stays intact; the visual work lives in the outer container, material layering, and edge treatment, with no visible notch/tab.

**Tech Stack:** Swift, AppKit, SwiftUI

---

### Task 1: Add failing regression for smoked-glass metrics

**Files:**
- Create: `Tests/DetachedPanelThemeTests.swift`
- Modify: `Sources/AIUsageBar/PopoverView.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/DetachedPanelThemeTests.swift` with a tiny harness that expects a darker smoked-glass configuration:

```swift
import Foundation

@main
struct DetachedPanelThemeTests {
    static func main() {
        let metrics = DetachedPanelChromeMetrics.subtleGlass
        guard metrics.cornerRadius <= 18 else {
            fatalError("Expected smoked-glass theme to keep the radius modest")
        }
        guard metrics.baseOpacity > 0.45 else {
            fatalError("Expected smoked-glass theme to use a darker base opacity")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swiftc -parse-as-library Sources/AIUsageBar/PopoverView.swift Tests/DetachedPanelThemeTests.swift -o .build/DetachedPanelThemeTests
```

Expected: FAIL because the smoked-glass metrics are not defined yet.

- [ ] **Step 3: Write minimal implementation**

In `PopoverView.swift`, add a small metrics struct for the outer chrome and use it instead of the hard-coded radius/material values.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swiftc -parse-as-library Sources/AIUsageBar/PopoverView.swift Tests/DetachedPanelThemeTests.swift -o .build/DetachedPanelThemeTests && ./.build/DetachedPanelThemeTests
```

Expected: PASS.

### Task 2: Restyle outer chrome to smoked glass and remove visible notch

**Files:**
- Modify: `Sources/AIUsageBar/PopoverView.swift`
- Modify: `Sources/AIUsageBar/AppMain.swift`

- [ ] **Step 1: Write the failing behavior expectation**

Define the expectations before editing:

```swift
// detached panel keeps no-blue menu-bar behavior
// outer radius stays modest
// no visible top notch/tab treatment
// content layout remains unchanged
```

- [ ] **Step 2: Write minimal implementation**

In `PopoverView.swift`:
- keep a modest outer corner radius
- use a darker smoked base with subtle background bleed
- add restrained internal top/bottom edge depth
- remove any visible notch/tab treatment

In `AppMain.swift`:
- keep the borderless detached panel presentation
- only adjust panel-level chrome if needed to support the SwiftUI glass surface cleanly

- [ ] **Step 3: Run full build verification**

Run:

```bash
zsh Scripts/build.sh
```

Expected: build succeeds.

### Task 3: Restart local app for visual verification

**Files:**
- Modify: none

- [ ] **Step 1: Restart the local build**

Run the local app from:

```bash
open "/Users/mikkel/Documents/dev/personal/bitstraum-usage/.build/Bitstraum Usage.app"
```

- [ ] **Step 2: Verify manually**

Check:
- no blue menu-bar selected background
- no visible notch/tab at the top edge
- panel has depth from internal glass layering, not a square halo shadow
- content layout still looks stable across main/settings/Downdetector

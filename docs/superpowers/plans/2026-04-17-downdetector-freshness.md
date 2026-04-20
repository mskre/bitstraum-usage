# Downdetector Freshness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Downdetector polling non-interruptive and ensure problem dots and notifications only reflect recent, still-active issue spikes.

**Architecture:** Keep the existing Downdetector fetch-and-parse flow, but add a shared freshness-aware alert helper on `DowndetectorReport` and remove automatic captcha window presentation from background fetches. Route all status bar, inline card, and notification decisions through that single helper.

**Tech Stack:** Swift, AppKit, SwiftUI, WebKit

---

### Task 1: Add freshness-aware report status

**Files:**
- Modify: `Sources/AIUsageBar/DowndetectorService.swift`
- Create: `Tests/DowndetectorFreshnessTests.swift`

- [ ] Write a failing executable test for fresh vs stale alert status.
- [ ] Run the harness compile command and confirm it fails.
- [ ] Add the minimal freshness helper to `DowndetectorReport`.
- [ ] Re-run the harness and confirm it passes.

### Task 2: Remove background captcha interruption

**Files:**
- Modify: `Sources/AIUsageBar/DowndetectorService.swift`

- [ ] Remove automatic challenge window presentation from background fetch.
- [ ] Keep fetch failure behavior non-interactive.
- [ ] Run `zsh Scripts/build.sh`.

### Task 3: Use fresh-only Downdetector alerts everywhere

**Files:**
- Modify: `Sources/AIUsageBar/StatusBarPreview.swift`
- Modify: `Sources/AIUsageBar/PopoverView.swift`
- Modify: `Sources/AIUsageBar/AppMain.swift`

- [ ] Route status bar dots through the freshness-aware helper.
- [ ] Route inline Downdetector card status through the same helper.
- [ ] Route notification decisions through the same helper.
- [ ] Run `zsh Scripts/build.sh`.

### Task 4: Update project docs

**Files:**
- Modify: `/Users/mikkel/vaults/main/personal/AI Usage Bar.md`

- [ ] Document that Downdetector refresh is now silent on captcha/challenge pages.
- [ ] Document that dots and notifications expire when the report is stale.

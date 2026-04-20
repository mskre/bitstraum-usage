# App-Owned Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Bitstraum Usage stop probing external credentials at launch by importing Claude/OpenAI credentials into app-owned storage and using those records for normal refreshes.

**Architecture:** Add a small app-owned keychain layer, use it as the only startup credential source, and limit external credential reads to explicit import actions. Keep browser sign-in as the fallback path for cases where import is unavailable.

**Tech Stack:** Swift, AppKit, SwiftUI, Security framework, WebKit

---

### Task 1: Add app-owned credential storage

**Files:**
- Create: `Sources/AIUsageBar/AppCredentialStore.swift`
- Modify: `Sources/AIUsageBar/KeychainHelper.swift`
- Modify: `Sources/AIUsageBar/OpenAIAuthHelper.swift`

- [ ] Write app-owned credential types and keychain read/write helpers.
- [ ] Add explicit import methods that copy Claude Code or Codex credentials into app-owned storage.
- [ ] Route token refresh persistence through app-owned storage.
- [ ] Build with `zsh Scripts/build.sh`.

### Task 2: Stop launch-time external probing

**Files:**
- Modify: `Sources/AIUsageBar/UsageStore.swift`
- Modify: `Sources/AIUsageBar/ProviderClients.swift`

- [ ] Change startup credential checks to read app-owned credentials only.
- [ ] Make provider selection use app-owned credentials for Claude/OpenAI.
- [ ] Keep external reads available only through explicit import paths.
- [ ] Build with `zsh Scripts/build.sh`.

### Task 3: Update connect and reconnect UX

**Files:**
- Modify: `Sources/AIUsageBar/UsageStore.swift`
- Modify: `Sources/AIUsageBar/PopoverView.swift`

- [ ] Make `Sign In` for Claude/OpenAI try explicit import before browser sign-in.
- [ ] Surface reconnect/import wording through existing card states without a large UI rewrite.
- [ ] Build with `zsh Scripts/build.sh`.

### Task 4: Remove startup permission noise and document behavior

**Files:**
- Modify: `Sources/AIUsageBar/AppMain.swift`
- Modify: `/Users/mikkel/vaults/main/personal/AI Usage Bar.md`

- [ ] Defer notification authorization until notifications are actually enabled.
- [ ] Update the vault note to document the new app-owned credential model.
- [ ] Build with `zsh Scripts/build.sh`.

# Touch ID App Keychain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Bitstraum Usage's app-owned credential store use a Touch ID-capable keychain configuration while preserving compatibility with existing stored items.

**Architecture:** Add a small protected-keychain query layer in `AppCredentialStore` that writes items with `.userPresence` access control and reads them with `LAContext`. Preserve compatibility by falling back to the legacy query once, then rewriting items into the protected format.

**Tech Stack:** Swift, Security, LocalAuthentication, Foundation

---

### Task 1: Add failing regression for protected keychain configuration

**Files:**
- Create: `Tests/AppCredentialStoreTouchIDTests.swift`
- Modify: `Sources/AIUsageBar/AppCredentialStore.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AppCredentialStoreTouchIDTests.swift` with a tiny harness that expects the store to expose a protected-item query builder:

```swift
import Foundation
import Security

@main
struct AppCredentialStoreTouchIDTests {
    static func main() throws {
        let store = AppCredentialStore(service: "com.bitstraum.usage.tests")
        let query = try store.makeProtectedItem("claude", data: Data("x".utf8))

        guard query[kSecAttrAccessControl as String] != nil else {
            fatalError("Expected protected item to include access control")
        }
        guard query[kSecAttrAccessible as String] as? String == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String) else {
            fatalError("Expected protected item to be device-local and unlocked-only")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swiftc -parse-as-library Sources/AIUsageBar/AppCredentialStore.swift Tests/AppCredentialStoreTouchIDTests.swift -o .build/AppCredentialStoreTouchIDTests
```

Expected: FAIL because `makeProtectedItem` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

In `Sources/AIUsageBar/AppCredentialStore.swift`:
- import `LocalAuthentication`
- add a small protected-item helper
- use `SecAccessControlCreateWithFlags(..., .userPresence, ...)`

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swiftc -parse-as-library Sources/AIUsageBar/AppCredentialStore.swift Tests/AppCredentialStoreTouchIDTests.swift -o .build/AppCredentialStoreTouchIDTests && ./.build/AppCredentialStoreTouchIDTests
```

Expected: PASS.

### Task 2: Use Touch ID-capable reads/writes with migration

**Files:**
- Modify: `Sources/AIUsageBar/AppCredentialStore.swift`

- [ ] **Step 1: Extend the test for migration-friendly read/write behavior**

Add a second expectation to the harness for protected read query construction:

```swift
let context = LAContext()
let readQuery = store.makeProtectedReadQuery("claude", context: context)

guard readQuery[kSecUseAuthenticationContext as String] != nil else {
    fatalError("Expected protected read query to include LAContext")
}
```

- [ ] **Step 2: Run the test to verify it fails if needed**

Run the same `swiftc` command from Task 1.

- [ ] **Step 3: Write minimal implementation**

Update `read(...)` and `write(...)` to:
- write protected items with access control
- read with `LAContext` plus `kSecUseOperationPrompt`
- fall back to the legacy query if no protected item is found
- rewrite legacy items into the protected format when decoded successfully

- [ ] **Step 4: Run test and build verification**

Run:

```bash
swiftc -parse-as-library Sources/AIUsageBar/AppCredentialStore.swift Tests/AppCredentialStoreTouchIDTests.swift -o .build/AppCredentialStoreTouchIDTests && ./.build/AppCredentialStoreTouchIDTests
zsh Scripts/build.sh
```

Expected: both commands succeed.

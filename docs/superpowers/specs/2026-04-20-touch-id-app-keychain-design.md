# Touch ID App Keychain Design

## Goal

Enable Bitstraum Usage's app-owned credentials to use a biometric-capable macOS keychain path so unlocking app-stored Claude/OpenAI credentials can use Touch ID instead of only the generic password prompt.

## Current Problem

- `AppCredentialStore` writes plain generic-password keychain items without access control.
- Reads use plain `SecItemCopyMatching` with no `LAContext` or operation prompt.
- Existing app-owned items therefore fall back to the standard keychain password dialog.
- External third-party items like `Claude Code-credentials` remain outside Bitstraum Usage's control.

## Design

### Scope

- Only app-owned credentials under `com.bitstraum.usage.credentials` are changed.
- External source credentials remain unchanged.

### Access Control

- Write app-owned items with `SecAccessControl` using `.userPresence`.
- Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so credentials stay local to the device.
- Reads should pass an `LAContext` and operation prompt so Touch ID can be used when available.

### Migration

- Existing app-owned entries may already exist without biometric access control.
- On read, if the Touch ID-configured path fails to find a migrated entry, fall back to a legacy read.
- If the legacy read succeeds, rewrite the item with the new protected configuration.

### UX

- The goal is not to force Touch ID every time, but to allow the app-owned credential read to use the system biometric path.
- This does not change how third-party keychain items prompt.

## Testing

- Add a focused regression around the keychain item configuration helpers used to build protected queries.
- Verify build succeeds after migration support is added.

# Privacy Mode Control Design

## Goal

Replace the current ambiguous account-info toggle with a single explicit privacy mode control that clearly supports hidden, visible, and masked states.

## Current Problem

- The simplified settings UI currently exposes only one privacy-facing toggle.
- Hidden masking behavior still affects what users see, so the visible label can disagree with the actual output.
- The user wants a clear model where visible content is actually visible, masked content is intentionally masked, and hidden content is fully hidden.

## Design

### Privacy Modes

- Introduce one explicit privacy mode with three values:
  - `hidden`
  - `visible`
  - `masked`
- This mode becomes the source of truth for account-info display.

### UI

- Replace the current privacy toggle in settings with a single compact control labeled `Account info`.
- The control should expose the three values directly rather than relying on override rules between two toggles.
- Keep the simplified settings screen compact; do not restore the old masking sliders or domain-only options.

### Display Behavior

- `hidden`: do not show account/email info.
- `visible`: show the full account/email info.
- `masked`: show the masked account/email info.

### Defaults And Migration

- Default mode becomes `visible`.
- Map existing stored settings into the new mode during initialization:
  - `showSensitiveInfo = false` -> `hidden`
  - `showSensitiveInfo = true` and `maskSensitiveData = false` -> `visible`
  - `showSensitiveInfo = true` and `maskSensitiveData = true` -> `masked`
- After migration, the explicit privacy mode should drive the UI and display logic.

## Why This Approach

- It removes confusing precedence rules.
- It makes the settings label truthful.
- It preserves the simplified settings direction while still supporting all three privacy outcomes.

## Testing

- Add a focused regression test for legacy-setting migration into the new privacy mode.
- Verify the simplified settings screen still builds cleanly after replacing the old toggle.

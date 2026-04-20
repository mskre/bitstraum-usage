# Smoked Glass Panel Theme Design

## Goal

Keep the detached panel architecture that avoids the blue selected menu-bar state, while restyling the Bitstraum Usage surface into a darker smoked-glass sheet closer to the macOS Control Center reference.

## Current Problems

- The detached panel solved the blue menu-bar highlight, but the current surface still feels too flat after removing the heavy outer shadow.
- The previous notch/tab direction was too custom and does not match the reference.
- The target look is closer to a dark smoked Control Center sheet with subtle internal depth, not a bright transparent glass card.

## Design

### Panel Surface

- Keep the detached panel/window approach so the status item is never selected blue.
- Use a darker smoked-glass treatment:
  - mostly opaque dark surface
  - restrained background bleed through the material
  - stronger internal light/dark layering for depth
  - no boxy external halo shadow
- Keep the outer corner radius modest and close to the Control Center reference.

### Top Edge

- Remove the visible notch/tab treatment entirely.
- The panel should read as one clean rounded sheet tucked under the menu bar, like the reference.

### Content Layout

- Keep the internal information architecture unchanged.
- Do not add new decorative chrome inside the provider content rows.
- Preserve readability first; the glass effect should live in the outer container, not overwhelm the usage data.

## Why This Approach

- It preserves the architectural fix for the blue status-item issue.
- It restores depth without reintroducing the ugly square shadow halo.
- It matches the darker smoked look of the reference more closely than the previous "subtle liquid" attempt.
- It keeps the app readable and understated instead of becoming glossy or overly transparent.

## Testing

- Build the app after the panel theme changes.
- Verify the menu-bar icon still avoids the blue selected background.
- Verify the top edge has no visible notch/tab treatment.
- Verify the panel still resizes and repositions correctly when switching between main, settings, and Downdetector views.

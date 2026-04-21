# 5-connections-shell-theme-refactor-p0

- Number: 5
- Slug: connections-shell-theme-refactor-p0

## Notes

### Implemented
- Refactored `RebootConnectionsViewController` styling to use semantic theme tokens instead of hardcoded colors.
- Introduced themed UI updates for:
  - connect bar and separator,
  - quick hosts card and host shortcut buttons,
  - session card and terminal preview panel,
  - primary/secondary controls (`CONNECT`, `Disconnect`, `Open Terminal`),
  - state color mapping (`connected/connecting/failed/idle`).
- Added live re-theme support:
  - updates on `adminThemeDidChange`
  - updates on light/dark trait transitions.

### UX Addition
- Added theme selector to `RebootProfileViewController` so users can immediately switch theme at runtime.

### Follow-up
- Bring `Vaults` and terminal chrome to the same token system to complete visual consistency.

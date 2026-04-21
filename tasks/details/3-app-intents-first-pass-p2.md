# 3-app-intents-first-pass-p2

- Number: 3
- Slug: app-intents-first-pass-p2

## Notes

### Implemented
- Added first-pass App Intents integration directly in app module:
  - `OpenWorkspaceIntent` (open app to target workspace),
  - `ConnectSavedHostIntent` (resolve saved host entity and route to connect flow),
  - `AdminConsoleShortcutsProvider` with discoverable App Shortcuts phrases.

### Entity Surface
- Added lightweight host entity model and query for system resolution:
  - `StoredHostEntity`,
  - `StoredHostEntityQuery` (`entities(for:)`, `suggestedEntities()`, `entities(matching:)`),
  - host data source from existing `TermiusReboot.HostStore.v1` snapshot in `UserDefaults`.

### Runtime Handoff
- Added predictable app-intent handoff surface:
  - `AppIntentRouteTarget`, `AppIntentRoute`, `AppIntentRouteStore`,
  - route consumption in `RebootRootViewController` (`viewDidAppear` and foreground entry),
  - explicit handling for `vaults/connections/profile/terminal/connectHost`.

### Discoverability / System Integration
- Hooked `updateAppShortcutParameters()` during launch.
- Verified metadata extraction now emits `Metadata.appintents` during build.

### Validation
- `make build` passes after App Intents additions.

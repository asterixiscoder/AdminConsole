# Xcode Project Structure

## Recommended Repository Layout

```text
AdminConsole/
├─ README.md
├─ docs/
│  ├─ 01-product-scope.md
│  ├─ 02-system-architecture.md
│  ├─ 03-module-map.md
│  ├─ 04-xcode-project-structure.md
│  ├─ 05-scenes-and-state-sync.md
│  ├─ 06-input-and-display-model.md
│  ├─ 07-feature-modules.md
│  ├─ 08-risks-and-decisions.md
│  ├─ 09-roadmap-mvp.md
│  └─ 10-testing-and-validation.md
├─ AdminConsole.xcworkspace
├─ AdminConsole.xcodeproj
├─ Packages/
│  └─ AppModules/
│     ├─ Package.swift
│     ├─ Sources/
│     └─ Tests/
└─ Resources/
```

## Xcode Targets

### `AdminConsoleApp`

Main iOS application target.

Responsibilities:

- app entry point
- scene configuration
- dependency wiring
- assets, entitlements, and Info.plist

### `AdminConsoleTests`

Unit and integration tests for:

- store reducers
- geometry rules
- input routing
- transport logic

### `AdminConsoleUITests`

UI smoke coverage for:

- scene launch
- basic window creation
- reconnect and restore paths

## Swift Package Layout

The majority of application code should live in a local Swift package to keep feature boundaries explicit and compile times manageable.

```text
Packages/AppModules/Sources/
├─ AppPlatform/
├─ DesktopDomain/
├─ DesktopStore/
├─ RuntimeRegistry/
├─ WindowManager/
├─ DesktopCompositor/
├─ InputKit/
├─ ConnectionKit/
├─ SSHKit/
├─ VNCKit/
├─ TerminalFeature/
├─ FilesFeature/
├─ BrowserFeature/
├─ VNCFeature/
├─ PersistenceKit/
├─ SecurityKit/
└─ TelemetryKit/
```

## Build Configuration Strategy

Recommended configurations:

- `Debug`
- `Release`
- optionally `Internal` for test flags and diagnostics

Recommended xcconfig split:

- base settings
- signing and bundle metadata
- debug diagnostics
- release optimization

## Resources Strategy

Resources should be separated by concern:

- app assets
- sample layouts
- keyboard shortcut manifests
- test fixtures

Large protocol fixtures such as terminal transcripts or VNC packets should live with the package tests that use them.

## Naming Conventions

- modules: `PascalCase`
- protocols: capability-oriented names such as `SessionRuntime`, `DesktopRenderable`
- IDs: typed wrappers such as `WindowID`, `SessionID`, `WorkspaceID`
- scenes: `ControlScene`, `DesktopScene`

## Dependency Management

Recommended external dependencies:

- `SwiftNIO`
- `SwiftNIO SSH`
- terminal rendering or parser dependency only if it passes performance review

The VNC dependency should remain isolated behind `VNCKit`, because this area is likely to change after prototyping.


# AdminConsole

[![iOS CI](https://github.com/asterixiscoder/AdminConsole/actions/workflows/ios-ci.yml/badge.svg)](https://github.com/asterixiscoder/AdminConsole/actions/workflows/ios-ci.yml)

AdminConsole is an iOS SSH client built with a mobile-first Termius-like UX.
The iPhone app is fully standalone for daily SSH usage (hosts, favorites/recents, connect, terminal input/output).
External display support is implemented as an add-on mirror for the active terminal session.

The repository currently contains:

- iOS app with reboot mobile shell (`Vaults`, `Connections`, `Profile`)
- host persistence with favorites/recents behavior
- live SSH runtime with Keychain-backed credential reuse and host key trust
- terminal UX hardening (stable keyboard input, backspace, command history recall, status row, soft keys)
- external display terminal mirroring (`UIWindowScene` for external screen)
- local Swift package (`Packages/AppModules`) with modular runtime/domain layers
- architecture and roadmap documentation
- app-creator adopted project tooling (`Makefile`, `scripts/`, `tasks/`)

## Current Status

- Mobile-first reboot flow is primary app path.
- SSH connect/disconnect/reconnect works on phone without external display dependency.
- Host catalog persistence is active (vault sections, favorites, recents).
- Terminal input pipeline uses `UIKeyInput` proxy for deterministic typing behavior.
- External display mirrors active terminal session and follows terminal resize updates.
- CI workflow is active for iOS build/package test checks.
- Local developer workflow supports `make diagnose/build/test`.

## Repository Layout

```text
AdminConsole/
├─ AdminConsole.xcodeproj
├─ AdminConsoleApp/
├─ AdminConsoleTests/
├─ AdminConsoleUITests/
├─ Packages/AppModules/
├─ docs/
├─ CONTRIBUTING.md
└─ .github/workflows/
```

## Getting Started

### Open In Xcode

Open `AdminConsole.xcodeproj` in Xcode.

The local `AppModules` package is already attached to the project as a Swift Package dependency.
Do not create or commit a separate top-level `.xcworkspace`; use the project directly for day-to-day development.

If Xcode resolves simulator architectures incorrectly on your machine, re-open the project and verify the app builds for Apple Silicon simulator (`arm64`) rather than `x86_64`.

### Local Checks

Project diagnostics/build/test:

```bash
make diagnose
make build
make test
```

Swift Package tests (direct):

```bash
cd Packages/AppModules
swift test --disable-sandbox
```

App build (direct):

```bash
xcodebuild -project AdminConsole.xcodeproj \
  -scheme AdminConsoleApp \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/AdminConsoleDerivedData \
  build CODE_SIGNING_ALLOWED=NO

Recommended for local consistency with CI cache paths:

```bash
env HOME=/tmp/adminconsole-home \
  CFFIXED_USER_HOME=/tmp/adminconsole-home \
  XDG_CACHE_HOME=/tmp/adminconsole-xdg \
  CLANG_MODULE_CACHE_PATH=/tmp/adminconsole-clang-cache \
  xcodebuild -project AdminConsole.xcodeproj \
  -scheme AdminConsoleApp \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/AdminConsoleDerivedData \
  build CODE_SIGNING_ALLOWED=NO
```
```

## Branching Model

- `main` is the stable branch
- `develop` is the integration branch
- feature work should branch from `develop`

Recommended branch prefixes:

- `feature/`
- `bugfix/`
- `spike/`
- `codex/`

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow.

## Documentation Index

- [Product Scope](docs/01-product-scope.md)
- [System Architecture](docs/02-system-architecture.md)
- [Module Map](docs/03-module-map.md)
- [Xcode Project Structure](docs/04-xcode-project-structure.md)
- [Scenes and State Sync](docs/05-scenes-and-state-sync.md)
- [Input and Display Model](docs/06-input-and-display-model.md)
- [Feature Modules](docs/07-feature-modules.md)
- [Risks and Decisions](docs/08-risks-and-decisions.md)
- [Roadmap MVP](docs/09-roadmap-mvp.md)
- [Testing and Validation](docs/10-testing-and-validation.md)
- [Termius Parity Roadmap](docs/11-termius-parity-roadmap.md)

## Solution Summary

- Platform foundation: `UIKit-first`, scene-based lifecycle, `Swift Concurrency`
- Product mode: mobile-first SSH client with Termius-like mental model
- Core runtime:
  - SSH terminal via `SwiftNIO SSH`
  - host persistence and credential security services
  - external monitor terminal mirror for active session
- UX focus:
  - fast connect from stored hosts/manual connections
  - readable terminal on phone
  - robust lifecycle handling on background/foreground transitions

## Guiding Principles

1. The desktop environment must live fully inside the app.
2. Scenes must not own business state.
3. Input must be centralized and routed predictably.
4. Windowing must use resolution-independent geometry.
5. Long-lived sessions must survive scene recreation and monitor reconnects.

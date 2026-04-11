# Contributing

## Branch Strategy

- `main`: stable branch
- `develop`: integration branch for ongoing work
- feature branches: short-lived branches created from `develop`

Recommended branch names:

- `feature/<area-or-goal>`
- `bugfix/<issue-or-scope>`
- `spike/<research-topic>`
- `codex/<task-name>`

Examples:

- `feature/terminal-runtime`
- `bugfix/display-reconnect`
- `spike/vnc-library-evaluation`
- `codex/phase-0-terminal-window`

## Workflow

1. Sync `develop`.
2. Create a feature branch from `develop`.
3. Keep commits focused and reviewable.
4. Open a pull request back into `develop`.
5. Merge `develop` into `main` for milestones or release-ready checkpoints.

## Pull Request Expectations

- keep CI green
- explain the user-facing or architectural impact
- call out risks and follow-up work
- avoid mixing unrelated changes in one PR

## Local Validation

Swift Package tests:

```bash
cd Packages/AppModules
swift test --disable-sandbox
```

App build:

```bash
xcodebuild -project AdminConsole.xcodeproj \
  -scheme AdminConsoleApp \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/AdminConsoleDerivedData \
  build CODE_SIGNING_ALLOWED=NO

If simulator build fails with mixed `x86_64/arm64` package modules, ensure Xcode targets Apple Silicon simulator (`arm64`) for this project configuration.
```

## Commit Guidance

- prefer small, descriptive commits
- mention the subsystem being changed when possible
- separate scaffolding, refactors, and feature work where practical

Good examples:

- `Add shared desktop snapshot stream`
- `Wire external scene to PhaseZeroCoordinator`
- `Add GitHub Actions iOS CI workflow`

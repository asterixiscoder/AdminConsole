# AdminConsole

AdminConsole - iOS application that turns an iPhone plus an external display into a unified desktop-like environment. The iPhone acts as the control surface, while the external display renders the desktop workspace with terminal, files, web, and remote desktop windows.

This repository currently contains the project definition and architecture documentation for the first implementation phase.

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

## Solution Summary

- Platform foundation: `UIKit-first`, scene-based lifecycle, `Swift Concurrency`
- Core principle: one shared desktop state for all scenes
- External display: rendered desktop surface managed by the app
- iPhone: control scene for cursor, keyboard, shortcuts, window management, and command flows
- Runtime stack:
  - terminal rendering with a custom surface and terminal adapter
  - SSH via `SwiftNIO SSH`
  - browser windows via `WKWebView`
  - VNC via a dedicated RFB runtime
- MVP scope:
  - one desktop workspace on an external display
  - terminal, files, VNC, and one browser window
  - hardware keyboard and pointer support
  - layout persistence and reconnect handling

## Guiding Principles

1. The desktop environment must live fully inside the app.
2. Scenes must not own business state.
3. Input must be centralized and routed predictably.
4. Windowing must use resolution-independent geometry.
5. Long-lived sessions must survive scene recreation and monitor reconnects.


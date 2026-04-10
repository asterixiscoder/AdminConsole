# Module Map

## Module Overview

The project should be split into focused modules with clear responsibilities and narrow dependencies.

## Core Modules

### `AppPlatform`

Responsibilities:

- app lifecycle
- scene registration
- dependency assembly
- environment setup
- app-wide feature flags

Depends on:

- `DesktopStore`
- `RuntimeRegistry`
- `PersistenceKit`
- `SecurityKit`

### `DesktopDomain`

Responsibilities:

- domain models for windows, workspaces, sessions, focus, geometry, shortcuts, and display profiles
- typed identifiers
- invariants and validation helpers

Should contain no UIKit or networking code.

### `DesktopStore`

Responsibilities:

- app state container
- action dispatcher
- reducers
- snapshot distribution to scenes
- workspace persistence hooks

Implementation notes:

- prefer `actor` isolation
- expose read-only snapshots
- never store heavy view instances

### `RuntimeRegistry`

Responsibilities:

- ownership of long-lived runtime objects
- runtime lookup by stable identifiers
- scene attach and detach semantics
- resource cleanup and recovery

Managed runtimes:

- `TerminalRuntime`
- `VNCRuntime`
- `BrowserRuntime`
- file browsing runtime helpers

### `WindowManager`

Responsibilities:

- create, close, move, resize, focus, and reorder windows
- snapping and layout rules
- fullscreen and tiling states
- logical desktop coordinate transforms

### `DesktopCompositor`

Responsibilities:

- render window chrome and content layers
- draw cursor and overlays
- translate logical desktop coordinates to screen coordinates
- manage surface updates efficiently

### `InputKit`

Responsibilities:

- unify touch gestures, keyboard input, and pointer events
- shortcut resolution
- text input routing
- focus-aware dispatch to active window runtimes

### `ConnectionKit`

Responsibilities:

- common session protocols
- connection metadata
- reconnect policies
- transport-neutral authentication models

Submodules:

- `SSHKit`
- `VNCKit`

### `PersistenceKit`

Responsibilities:

- workspace persistence
- window restoration
- session metadata storage
- user preferences and display profiles

### `SecurityKit`

Responsibilities:

- Keychain access
- SSH credential storage
- known hosts storage with trust-on-first-use validation
- secure credential references
- clipboard and secret redaction policy

### `TelemetryKit`

Responsibilities:

- logging
- performance counters
- crash breadcrumbs
- session diagnostics

## Feature Modules

### `TerminalFeature`

Responsibilities:

- terminal window UI
- terminal buffer attachment
- selection, copy, paste
- resize integration

### `FilesFeature`

Responsibilities:

- sandbox workspace browser
- file operations
- import and export flows
- file preview and metadata panels

### `BrowserFeature`

Responsibilities:

- browser window UI
- navigation model
- history and restore metadata
- web session coordination

### `VNCFeature`

Responsibilities:

- VNC window UI
- pointer and keyboard translation
- remote framebuffer presentation
- scaling and quality controls

## Dependency Rules

1. Feature modules may depend on core modules, but not on each other directly.
2. UIKit code stays out of domain modules.
3. Networking transport stays behind feature-neutral protocols.
4. View instances never enter `DesktopStore`.
5. Runtimes should be accessed via identifiers and interfaces, not by global singletons.

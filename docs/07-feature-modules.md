# Feature Modules

## Overview

The MVP includes four user-facing feature areas:

- terminal
- files
- browser
- VNC

Each module should own its UI and runtime integration, but must follow the same desktop contracts.

## Terminal Module

### Responsibilities

- render terminal content
- bind to terminal session runtime
- handle text selection, copy, paste, and search
- react to window resize

### Recommended Design

- dedicated terminal buffer runtime
- fixed-cell renderer, not a generic text view
- adapter layer for parser and terminal emulation logic

### Transport

- SSH transport via `SwiftNIO SSH`
- connection lifecycle managed outside the view layer

### MVP Scope

- one SSH-backed terminal window
- reconnect and resize support
- standard copy and paste
- host key validation with trust-on-first-use
- Keychain-backed password reuse for repeated SSH connections

## Files Module

### Responsibilities

- browse the app sandbox workspace
- create, rename, move, delete, and duplicate files
- import and export files
- show basic metadata and previews

### Recommended Design

- local file browser first
- explicit abstraction for future remote providers
- no File Provider extension in MVP

### MVP Scope

- local workspace browser
- basic file operations
- import from picker
- export and share

## Browser Module

### Responsibilities

- manage browser window chrome
- host and restore web sessions
- support basic navigation and session persistence

### Recommended Design

- scene-local `WKWebView` host
- shared browser metadata in store
- snapshot-based preview for non-owning scene

### MVP Scope

- one browser window at a time is acceptable
- back, forward, reload, URL entry
- cookies and website data via managed profile policy

### Main Risk

The browser is the riskiest MVP feature because the interactive web view is tied to scene UI objects, while the app architecture requires a shared desktop model across scenes.

## VNC Module

### Responsibilities

- open remote desktop sessions
- render remote framebuffer
- translate keyboard and pointer input
- expose scaling controls

### Recommended Design

- transport-independent `VNCRuntime`
- framebuffer renderer separated from network transport
- adapter layer around any third-party VNC core

### MVP Scope

- one active VNC session
- trackpad mode
- keyboard forwarding
- clipboard bridge
- quality presets

### Main Risk

VNC library selection must remain flexible until performance, licensing, and iOS integration are validated.

## Shared UX Rules Across Feature Modules

1. Every feature must integrate with window focus rules.
2. Every feature must expose a restorable session descriptor.
3. Every feature must participate in clipboard policy.
4. Every feature must report user-visible failures in a consistent way.
5. Every feature must tolerate scene recreation without corrupting core state.

# Product Scope

## Product Vision

AdminConsole is a single iOS application that creates a desktop-like workspace across two scenes:

- `Control Scene` on iPhone
- `Desktop Scene` on an external display

The app behaves as a self-contained operating environment inside the application sandbox. It does not depend on system windows, split view orchestration, or external app handoff for the primary user experience.

## Core User Scenario

The user connects an iPhone to an external monitor, opens AdminConsole, and gets a desktop workspace on the monitor. Using the iPhone, hardware keyboard, and pointer devices, the user can:

- switch work modes on iPhone (`SSH`, `VNC`, `Browser`) and keep control predictable
- operate the active runtime on iPhone and mirror it to the external display
- open and manage terminal, files, VNC, and browser windows when needed
- connect to remote systems via SSH
- view and control remote desktops via VNC

## Product Goals

1. Deliver a coherent desktop environment fully contained inside the app.
2. Ensure reliable state synchronization across iPhone and external display scenes.
3. Provide keyboard-first and pointer-friendly workflows.
4. Support different monitor resolutions without breaking layout or input mapping.
5. Build the system in modular layers that can evolve after MVP.

## Non-Goals for MVP

- local Linux userland or full shell emulation
- multi-user collaboration
- multi-monitor support beyond one external display
- File Provider extension and deep Files.app integration
- RDP support
- plugin system
- advanced browser tab sync across multiple windows

## Constraints

### Platform Constraints

- External display support on iOS must be implemented through scene-based lifecycle.
- External display interaction should be treated as app-managed rendering, not as an independently touch-driven scene.
- Keyboard, pointer, and scene lifecycle behavior must stay within public Apple APIs.

### Product Constraints

- The environment must remain fully inside the app.
- State must survive scene recreation and monitor reconnect when possible.
- Input behavior must remain deterministic even with multiple active windows.

## User Experience Principles

### One Desktop, Two Roles

The user should feel like there is one desktop workspace, not two disconnected screens:

- the iPhone is the controller
- the external display mirrors the active work context
- mode switch on iPhone must immediately update the mirrored window

### Keyboard-First Operation

The user should be able to perform core tasks without relying on touch-only flows.

### Predictable Windowing

Windows should move, resize, focus, and restore consistently across different monitor sizes.

### Stable Sessions

Network sessions must remain alive across UI transitions whenever possible.

## Success Criteria for MVP

The MVP is successful when the following are true:

1. The app can open a desktop scene on an external monitor and restore it after reconnect.
2. The iPhone can control cursor, focus, and window operations on the external display.
3. The iPhone mode switch (`SSH`, `VNC`, `Browser`) changes the active control target without ambiguous routing.
4. The user can open and use:
   - at least one terminal window backed by SSH
   - one file manager window for sandboxed files
   - one VNC window
   - one embedded browser window
5. The external display mirrors the active work window fullscreen and adapts to monitor resolution changes.
6. Keyboard, pointer, and monitor resolution changes behave correctly enough for daily workflows.

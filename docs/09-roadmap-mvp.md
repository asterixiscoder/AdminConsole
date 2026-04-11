# Roadmap MVP

## Roadmap Objective

Deliver the first usable version of AdminConsole with:

- external desktop scene
- iPhone control scene
- shared state
- terminal with SSH
- files browser
- one browser window
- one VNC window
- keyboard and pointer support
- reconnect-safe layout restore

## Progress Snapshot

Completed:

- Phase 0 technical spike
- Core desktop foundation and shared state wiring
- Input routing prototype for keyboard and pointer
- SSH terminal runtime with host key validation and Keychain credential reuse
- Files workspace with import and export
- VNC runtime with password auth, richer encodings, pointer/drag/wheel, clipboard bridge
- VNC reconnect flow with lifecycle pause/resume and desktop reconnect indicator

In progress:

- Browser module hardening beyond spike-level host
- Release hardening and QA matrix completion

## Delivery Strategy

The roadmap is structured around technical risk, not feature marketing order. The most uncertain foundations must be validated first.

## Phase 0: Technical Spike

Goal:

- validate platform assumptions before committing to full implementation

Deliverables:

- app bootstrap with two scenes
- external display attach and detach handling
- minimal shared `DesktopStore`
- keyboard routing prototype
- cursor model prototype
- browser interaction proof of concept using `WKWebView`
- VNC library spike report

Exit Criteria:

1. External display scene can be created, destroyed, and restored safely.
2. Keyboard input can be captured and routed without relying on text-field hacks.
3. Browser approach is either approved for MVP or moved out of MVP.
4. One VNC candidate is selected for implementation.

## Phase 1: Desktop Foundation

Goal:

- build the reusable core for desktop orchestration

Deliverables:

- `DesktopDomain`
- `DesktopStore`
- `RuntimeRegistry`
- `WindowManager`
- basic `DesktopCompositor`
- logical desktop coordinate system
- workspace persistence

Exit Criteria:

1. Windows can be created, moved, resized, focused, and restored.
2. Layout adapts across at least two monitor resolutions.
3. Scene recreation does not destroy authoritative state.

## Phase 2: Input System

Goal:

- establish reliable multi-source input behavior

Deliverables:

- `InputKit`
- keyboard shortcut routing
- text input routing
- pointer model
- iPhone trackpad mode
- focus hierarchy and tests

Exit Criteria:

1. Keyboard shortcuts do not leak into text entry by accident.
2. Pointer routing remains correct during drag, resize, and focus transitions.
3. Terminal, browser, and VNC can receive input through a common model.

## Phase 3: Terminal and SSH

Goal:

- provide the first production-valuable workflow

Deliverables:

- terminal window
- SSH session management
- host key validation and known host persistence
- Keychain-backed SSH credential reuse
- reconnect logic
- copy and paste
- terminal resize behavior

Exit Criteria:

1. A user can connect to an SSH host and work through a terminal window.
2. Terminal size follows window geometry.
3. Scene changes do not immediately kill the terminal session.

## Phase 4: Files Workspace

Goal:

- provide internal file operations for the app workspace

Deliverables:

- files browser window
- file operations
- import and export
- preview support for common text and image files

Exit Criteria:

1. A user can manage files inside the app workspace.
2. Import and export flows work reliably.
3. Files UI follows desktop window and focus rules.

## Phase 5: VNC

Goal:

- deliver remote desktop access inside the desktop environment

Deliverables:

- VNC session runtime
- framebuffer rendering
- keyboard forwarding
- pointer mapping
- clipboard bridge
- quality and scaling presets

Exit Criteria:

1. A user can connect to a VNC server and control it.
2. Input mapping is stable enough for practical use.
3. Performance is acceptable on at least Full HD and 1440p displays.

## Phase 6: Browser Window

Goal:

- add embedded web application support without breaking scene architecture

Deliverables:

- browser window chrome
- managed `WKWebView` host
- navigation controls
- session restore metadata
- browser snapshot support

Exit Criteria:

1. A user can browse and interact with web pages inside a window.
2. Browser input and desktop shortcuts coexist predictably.
3. Browser scene ownership rules are stable enough for ongoing development.

Current status:

- browser exists as a spike path and is not yet hardened to MVP-quality parity with terminal/files/VNC

## Phase 7: Hardening and Release Candidate

Goal:

- stabilize behavior under realistic usage and hardware conditions

Deliverables:

- crash and telemetry coverage
- performance tuning
- reconnect testing
- memory pressure handling
- QA matrix execution
- MVP release checklist

Exit Criteria:

1. External display reconnect is reliable.
2. State restoration is acceptable after app relaunch.
3. No blocker remains in input, rendering, or session stability.

Current next focus:

1. Browser hardening and restore behavior
2. Final external-display reconnect QA matrix
3. Performance profiling on high-resolution outputs

## Suggested Sequence and Duration

The exact calendar depends on team size, but the implementation order should remain:

1. Phase 0
2. Phase 1
3. Phase 2
4. Phase 3
5. Phase 4
6. Phase 5
7. Phase 6
8. Phase 7

Suggested initial planning assumption for one strong iOS engineer plus part-time design/product support:

- Phase 0: 1 week
- Phase 1: 2 weeks
- Phase 2: 2 weeks
- Phase 3: 2 to 3 weeks
- Phase 4: 1 to 2 weeks
- Phase 5: 2 to 3 weeks
- Phase 6: 1 to 2 weeks after browser gate approval
- Phase 7: 2 weeks

## MVP Release Criteria

The MVP can be considered release-ready when:

1. The core desktop shell is stable across supported monitor configurations.
2. Terminal and SSH workflows are production-usable.
3. Files workflows are complete for local workspace usage.
4. VNC meets minimum interaction quality.
5. Browser support is either stable or formally deferred from MVP.
6. Keyboard and pointer handling are reliable enough for sustained sessions.

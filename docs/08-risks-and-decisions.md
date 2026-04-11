# Risks and Decisions

## Confirmed Architectural Decisions

### Decision 1: UIKit-First Foundation

Status: accepted

Reason:

- better control over scenes, responders, pointer behavior, and low-level rendering

Impact:

- core shell stays in UIKit
- SwiftUI remains optional for settings and simple flows

### Decision 2: One Shared Desktop Store

Status: accepted

Reason:

- avoids divergent scene state and merge conflicts

Impact:

- scenes become replaceable renderers
- action serialization becomes a core requirement

### Decision 3: Runtime Objects Live Outside Scenes

Status: accepted

Reason:

- sessions must survive scene recreation and monitor reconnects

Impact:

- requires stable runtime identifiers
- introduces registry lifecycle management complexity

### Decision 4: In-House VNC Transport Layer

Status: accepted

Reason:

- remove dependency on unverified third-party VNC wrappers during MVP
- keep full control over protocol handling and reconnect behavior

Impact:

- `VNCKit` now owns RFB handshake, auth, encoding decode, and reconnect policy
- performance optimization remains an internal responsibility

## Key Risks

### Risk 1: Browser Window Ownership

Severity: high

Problem:

- `WKWebView` is not a serializable runtime object in the same way as SSH or VNC engines
- mirroring a fully interactive browser across scenes is not a safe assumption

Mitigation:

- keep browser host scene-local
- store only metadata and snapshots in shared state
- validate the browser interaction model in the first spike phase

Fallback:

- postpone browser from MVP if the control model is too brittle

### Risk 2: VNC Library Maturity and Licensing

Severity: high

Problem:

- some mature VNC stacks have restrictive licensing
- permissive options may require more adaptation work

Mitigation:

- isolate VNC behind `VNCKit`
- evaluate at least two candidates during prototyping
- avoid coupling UI to a specific library API

Fallback:

- ship VNC after terminal and files if library viability is not proven early

Current status:

- mitigated for MVP by shipping an in-house VNC transport layer inside `VNCKit`

### Risk 3: Input Complexity

Severity: high

Problem:

- desktop shortcuts, text input, remote keyboard forwarding, and browser input can conflict

Mitigation:

- build `InputRouter` before feature modules
- formalize focus levels
- create automated tests for routing logic

### Risk 4: External Display Reconnect and Resolution Changes

Severity: medium

Problem:

- monitor hot-plug, aspect ratio changes, and restored layouts can destabilize the desktop

Mitigation:

- use logical geometry
- validate restoration against visible bounds
- store display profiles separately from window layout
- pause and resume VNC runtimes on app background and foreground
- publish reconnect attempt/countdown state into shared desktop snapshot

### Risk 5: Performance at High Resolution

Severity: medium

Problem:

- VNC, browser, and window compositing may strain memory and rendering budgets on 4K displays

Mitigation:

- keep compositor abstraction flexible
- add telemetry early
- limit concurrent heavy windows during MVP if needed

## Security Decisions

### Credential Storage

- secrets must live in Keychain
- store references, not raw secrets, in normal persistence
- current MVP path stores SSH passwords in Keychain after a successful connection

### SSH Trust Model

- host keys must be verified and persisted
- trust-on-first-use is acceptable for MVP if clearly surfaced
- current SSH runtime rejects host key mismatch after first successful trust

### Clipboard Policy

- clipboard bridge must be explicit and controllable
- avoid silent propagation of sensitive content

## Open Questions

1. Whether browser support should remain in MVP after the initial interaction spike.
2. Which VNC library passes both licensing and performance review.
3. Whether the first compositor should be `CALayer`-based only or include an early Metal path.
4. Whether iPhone control should start in trackpad-only mode or include direct manipulation mode in MVP.

## Decision Gates

The following gates should be resolved before full implementation begins:

1. `WKWebView` control model viability
2. VNC adapter candidate selection
3. acceptable rendering budget on 1440p and 4K displays
4. keyboard routing stability across terminal, browser, and VNC

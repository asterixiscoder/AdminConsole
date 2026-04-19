# Termius Parity Roadmap (iOS + External Display)

## Goal
Build an iOS-first remote access client that is behaviorally close to Termius for core daily workflows, while keeping AdminConsole's external-display desktop model and adding explicit terminal mirroring controls.

## Product Principles
- Match user mental model from Termius: vaults, hosts, quick connect, persistent sessions, terminal-first workflows.
- Keep iPhone as control surface and external display as primary workspace.
- Prefer predictable state recovery over hidden background behavior.
- Ship in vertical slices with measurable parity checkpoints.

## Parity Scope
### P0 (must-have)
- iPhone navigation with three anchors: `Vaults`, `Connections`, `Profile`.
- Host catalog (vault/group + host cards) and quick fill into connection form.
- SSH connect/disconnect and stable interactive terminal session.
- External display live mirror of the active terminal window.
- Explicit mirror mode controls: active mode, focused window, forced terminal/VNC/browser.

### P1 (high-value)
- Multi-session terminal tabs and split panes.
- Identity management (password + key metadata model).
- Snippets and command history surface.
- SFTP browsing and transfer queue.

### P2 (advanced)
- Jump hosts / chained routing.
- Port forwarding presets and lifecycle controls.
- Session logging and timeline.
- Optional Mosh transport track.

## Architecture Plan
1. Domain state
- Extend `DesktopSnapshot` with mirror policy and later with vault/host metadata state references.
- Keep action-based store mutations and actor isolation for runtime side effects.

2. Control app shell
- Introduce a tab shell for iPhone (`Vaults`, `Connections`, `Profile`).
- Keep `Connections` as execution surface for SSH/VNC/browser forms until dedicated screens are split out.

3. Runtime layer
- Continue using `SSHTerminalRuntime` (`SwiftNIO SSH`) as canonical SSH runtime.
- Add protocol abstraction for future transport expansion (`Mosh`, serial adapters).

4. External display
- External scene renders based on mirror policy from shared snapshot.
- Fallback behavior always available when selected mirror target is absent.

## Implementation Phases
### Phase 1: Control shell + mirror policy (current)
Deliverables:
- Tab-based iPhone shell.
- Vault host list with handoff into connect form.
- Mirror policy in domain/store/coordinator.
- External scene target selection via mirror policy.

Definition of Done:
- User can select a vault host and open or auto-connect from `Connections`.
- `Profile` can switch mirror policy at runtime.
- External display immediately reflects chosen mirror mode.

### Phase 2: Termius-like connections UX
Deliverables:
- Dedicated host detail screen.
- Recent sessions and favorites sections.
- Better terminal connect presets (cols/rows/profile-driven).

Definition of Done:
- Connect flow is one-tap from host card for common case.
- Host edits and defaults persist locally.

### Phase 3: Terminal productivity layer
Deliverables:
- Snippets panel and command history model.
- Terminal accessory shortcuts and clipboard workflows.
- Session metadata badge strip (latency/state/title).

Definition of Done:
- User can run snippets and re-run history commands without leaving terminal context.

### Phase 4: File workflows (SFTP)
Deliverables:
- SFTP runtime abstraction.
- Remote tree browser + transfer queue.
- Unified progress and error reporting.

Definition of Done:
- Upload/download and folder navigation work across reconnects.

### Phase 5: Advanced networking
Deliverables:
- Jump host chain configuration.
- Port forwarding templates.
- Connection profile validation and diagnostics.

Definition of Done:
- Common bastion and forward scenarios are reproducible without manual shell plumbing.

## Testing Strategy
- Unit: parsing, mirror policy resolution, host preset transforms.
- Integration: SSH runtime lifecycle, reconnect, display profile propagation.
- UI: tab navigation, host handoff, mirror mode switching.
- Manual matrix: iPhone only, iPhone + external monitor, iPad stage manager layouts.

## Risks and Mitigations
- Scope risk from full parity ambition:
  - Mitigation: enforce phase gates and hard P0/P1 boundaries.
- iOS background constraints:
  - Mitigation: explicit resume/reconnect UX and persisted intent.
- UI complexity drift:
  - Mitigation: feature flags for experimental panes and modular controllers.

## Immediate Next Steps
1. Land Phase 1 code slice and pass local build.
2. Add host persistence model scaffold (local JSON/SQLite decision ADR).
3. Begin Phase 2 screen split (host details and recents).

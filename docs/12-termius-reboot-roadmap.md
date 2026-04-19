# Termius Reboot Roadmap (Mobile First)

## Product Goal
- Build a self-contained iOS SSH client with UX and mental model close to Termius.
- Reach reliable day-to-day phone usage first.
- Add external monitor terminal mirroring only after mobile parity baseline is stable.

## Non-Goals for Phase 1
- No split-control architecture where phone is only a remote.
- No dependency on external display for core flows.
- No mandatory desktop scene to make SSH usable.

## UX Parity Targets (Termius-like)
- Vault-oriented host organization.
- Host cards with note/tags/credentials fields.
- Favorites and recents behavior close to real usage.
- Quick connect from host details and from manual form.
- Persistent terminal transcript per active session.
- Simple profile/settings surface for identity and app preferences.

## Architecture (from scratch in current app shell)
- `RebootRootTabBarController`: primary shell (`Vaults`, `Connections`, `Profile`).
- `RebootHostStore`: local persistence (UserDefaults JSON snapshot for reboot stage).
- `RebootAppModel`: app state + SSH runtime bridge.
- `SSHTerminalRuntime`: terminal connection, send/receive, status lifecycle.
- UIKit-first implementation for fast deterministic parity of layout/interaction.

## Delivery Plan

### Phase 0: Reboot Baseline (in progress)
- Replace mobile entrypoint with reboot root controller.
- Disable external display scene in plist.
- Keep old orchestration code isolated but not on primary execution path.
- Persist hosts + favorites + recents.

Acceptance:
- App opens directly into reboot tabs.
- User can create/edit/delete hosts.
- Favorites and recents survive app relaunch.

### Phase 1: Core Termius-like Mobile MVP
- Vault list sections: Favorites, Recents, Vault groups.
- Host details screen with actions: favorite, edit, connect context.
- Connections screen for manual SSH credentials.
- Terminal screen with live transcript and command send.
- Connection status labeling (`idle/connecting/connected/failed`).

Acceptance:
- User can connect to SSH host on phone only and execute commands.
- No external monitor required for any core flow.

### Phase 2: Robustness and Realistic Behavior
- Secure credential storage migration path (Keychain-backed secrets).
- Better host validation/errors and connection retry UX.
- Session lifecycle improvements (foreground/background handling).
- Terminal ergonomics: larger buffer, copy/select, keyboard shortcuts.

Acceptance:
- Stable reconnect/disconnect behavior across app lifecycle.
- Usable for repeated daily SSH sessions.

### Phase 3: External Monitor Mirroring (feature add-on)
- Re-enable external display scene.
- Mirror terminal window content (not replacing phone usability).
- Keep phone as full standalone controller and terminal owner.
- Add mirror settings toggle and monitor-connection diagnostics.

Acceptance:
- External display shows mirrored terminal output of active session.
- Disconnecting monitor does not affect phone session continuity.

### Phase 4: Advanced Termius Parity Expansion
- Multi-host identity sets and credential templates.
- Snippets/shortcuts and command history UX.
- Host search and filtering across vaults.
- Optional SFTP/file operations (if in scope).

## Engineering Conventions
- Mobile-first feature flags for any display-specific behavior.
- No regression to phone-as-remote-only paradigm.
- Small composable view controllers; explicit app model boundaries.
- Every phase gated by acceptance criteria before next phase.

## Current Status Snapshot
- Branch: `codex/termius-reboot-clean`.
- Mobile root switched to reboot flow.
- Host persistence + favorites/recents implemented in reboot store.
- External display disabled for baseline parity stabilization.

# 1-ui-ux-audit

- Number: 1
- Slug: ui-ux-audit

## Notes

### Scope
- Audited main iOS UIKit UI surfaces for theme readiness, modern styling potential, and admin-focused usability.
- Verified presence/absence of App Intents layer for advanced user workflows.

### Current UI Findings
- UI is implemented in UIKit (`ControlRootViewController`, `DesktopRootViewController`, `SSHTerminalSessionViewController`), with many inline color/style literals.
- Visual language is inconsistent between screens:
  - `Connections` uses bright cards (`.white`, near-light gray backgrounds).
  - `Terminal` and desktop mirror use dark, dense operator-style surfaces.
  - Tab bar and controls rely on ad hoc local styles.
- Theme architecture is missing:
  - No centralized tokens for color, spacing, corner radius, typography, elevation.
  - Styles are repeated and hardcoded in controllers.
- UX is already strong in functional parts:
  - Keyboard-first terminal flow.
  - Quick connect and session status visibility.
  - Focus on dense information display.

### Key Risks
- Hardcoded colors and shape values increase maintenance cost and block rapid visual iterations.
- Mixed light/dark sections hurt coherence and perceived quality.
- Visual hierarchy can improve for admin-heavy scenarios (status severity, active session focus, action priority).

### Recommended Design Direction (admin-focused, minimal + stylish)
- Keep high information density and predictable controls.
- Use a restrained dark-first base with high-contrast accents for state signals:
  - success/connected, warning/reconnecting, failure/disconnected.
- Prefer subtle depth and contrast over decorative effects.
- Keep core interaction surfaces stable: command entry, session state, connect controls, quick host access.

### Implementation Plan
1. Create a design token layer:
   - `AdminTheme` + semantic tokens (`backgroundPrimary`, `surfacePrimary`, `textPrimary`, `accent`, `statusSuccess`, `statusWarning`, `statusError`).
   - Include spacing/radius/elevation/typography tokens.
2. Add `ThemeManager` with persisted selection:
   - Modes: `system`, `midnight`, `graphite`, `light-ops` (optional).
   - Store in `UserDefaults`, expose notification/observer for live updates.
3. Refactor core screens to semantic styling:
   - `RebootRootViewController` (tab chrome)
   - `RebootConnectionsViewController` (cards, connect bar, session panel)
   - `RebootTerminalViewController` (terminal chrome, soft keys, status row)
   - `DesktopRootViewController` (window panel/chrome consistency)
4. Introduce reusable UI building blocks:
   - `AdminCardView`, `StatusPillView`, `ThemedButtonFactory`.
5. Improve usability cues for advanced users:
   - Stronger state differentiation on session card.
   - Better quick-host scanning (meta line structure, optional host role chip).
   - Keep one-tap access to terminal and disconnect with clear primary/secondary action hierarchy.
6. Add a lightweight Appearance screen:
   - Theme selection + terminal font size + optional compact mode.
7. Add snapshot/UI tests for theming regressions.

### App Intents (skill-aligned observation)
- No App Intents layer currently present.
- Recommended first pass (post UI tokenization):
  - Intent: `Open Terminal` (open app to active terminal session).
  - Intent: `Connect to Host` (select from recent/favorite hosts).
  - App Shortcuts for power users via Shortcuts/Siri/Spotlight.
- This aligns with advanced admin workflows and reduces friction for repetitive tasks.

### Priority Order
- P0: Token layer + theme manager + refactor `Connections` and tab shell.
- P1: Terminal/desktop visual consistency + reusable components.
- P2: Appearance settings + App Intents for fast external entry points.

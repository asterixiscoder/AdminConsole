# Tasks

## Task IDs

1. ui-ux-audit
   Id: 1-ui-ux-audit
   Scope: UI audit, theming architecture, usability improvements for admin-focused iOS app
   Files: AdminConsole/**, tasks/**
   Note: Completed UI/UX + theming audit with prioritized implementation roadmap; no code behavior changes
   Detail: tasks/details/1-ui-ux-audit.md
   Claimed by: CODEX
   Claimed at: 2026-04-21T08:29:58Z
   Done by: CODEX
   Done at: 2026-04-21T08:31:10Z

3. app-intents-first-pass-p2
   Id: 3-app-intents-first-pass-p2
   Scope: Design first App Intents for Open Terminal and Connect Host
   Files: AdminConsoleApp/**, docs/**, tasks/**
   Note: Implemented first App Intents pass (open workspace + connect saved host + shortcuts + route handoff); make build PASS
   Detail: tasks/details/3-app-intents-first-pass-p2.md
   Claimed by: CODEX
   Claimed at: 2026-04-21T08:53:13Z
   Done by: CODEX
   Done at: 2026-04-21T08:57:20Z

4. theme-foundation-p0
   Id: 4-theme-foundation-p0
   Scope: Create AdminTheme tokens + ThemeManager with persistence and live updates
   Files: AdminConsoleApp/ViewControllers/ControlRootViewController.swift, docs/12-termius-reboot-roadmap.md, tasks/**
   Note: Implemented AdminTheme/AdminThemeManager foundation + shell/Profile integration; make build PASS
   Detail: tasks/details/4-theme-foundation-p0.md
   Claimed by: CODEX
   Claimed at: 2026-04-21T08:35:46Z
   Done by: CODEX
   Done at: 2026-04-21T08:41:25Z

5. connections-shell-theme-refactor-p0
   Id: 5-connections-shell-theme-refactor-p0
   Scope: Refactor tab shell and Connections screen to semantic theme tokens
   Files: AdminConsoleApp/ViewControllers/ControlRootViewController.swift, tasks/**
   Note: Refactored Connections and tab shell to semantic theme tokens with live updates; make build PASS
   Detail: tasks/details/5-connections-shell-theme-refactor-p0.md
   Claimed by: CODEX
   Claimed at: 2026-04-21T08:36:19Z
   Done by: CODEX
   Done at: 2026-04-21T08:41:30Z

6. workspace-usability-theme-p1
   Id: 6-workspace-usability-theme-p1
   Scope: Apply modern themed workspace organization to Vaults and Terminal surfaces
   Files: AdminConsoleApp/ViewControllers/ControlRootViewController.swift, tasks/**, docs/**
   Note: Implemented P1 themed workspace UX in Vaults + Terminal; modern palettes + layout readability; make build PASS
   Detail: tasks/details/6-workspace-usability-theme-p1.md
   Claimed by: CODEX
   Claimed at: 2026-04-21T08:45:43Z
   Done by: CODEX
   Done at: 2026-04-21T08:48:33Z

7. full-form-theme-coverage
   Id: 7-full-form-theme-coverage
   Scope: Apply AdminTheme to all remaining user forms and host card surfaces
   Files: AdminConsoleApp/ViewControllers/*.swift, AdminConsoleApp/AppDelegate.swift, tasks/**
   Note: Applied theme to host card, password prompt, host editor/details, and SSH session form; make build PASS
   Detail: tasks/details/7-full-form-theme-coverage.md
   Claimed by: CODEX
   Claimed at: 2026-04-21T09:13:07Z
   Done by: CODEX
   Done at: 2026-04-21T09:15:31Z

8. documentation-cleanup-2026-04-21
   Id: 8-documentation-cleanup-2026-04-21
   Scope: docs
   Files: README.md,docs/12-termius-reboot-roadmap.md,docs/13-project-analysis-2026-04-20.md
   Note: Updated README/docs roadmap index + analysis addendum; make build PASS
   Detail: tasks/details/8-documentation-cleanup-2026-04-21.md
   Claimed by: CODEX
   Claimed at: 2026-04-21T09:20:24Z
   Done by: CODEX
   Done at: 2026-04-21T09:21:29Z

9. terminal-mirror-mc-regression
   Id: 9-terminal-mirror-mc-regression
   Scope: Fix phone/external mirror rendering regressions and mc layout
   Files: AdminConsoleApp/ViewControllers/ControlRootViewController.swift,AdminConsoleApp/DesktopSceneDelegate.swift,Packages/AppModules/Sources/DesktopDomain/Models.swift
   Note: Patched mobile-first PTY sizing and mirror read-only behavior; swift test passed; xcodebuild build passed; xcodebuild test command hangs in UI test runner in this environment.
   Detail: tasks/details/9-terminal-mirror-mc-regression.md
   Claimed by: CODEX
   Claimed at: 2026-04-21T12:37:42Z
   Done by: CODEX
   Done at: 2026-04-21T12:44:20Z

10. external-display-fit-colors-fkeys
   Id: 10-external-display-fit-colors-fkeys
   Scope: External display full-screen rendering, MC colors, hardware F1-F12
   Files: AdminConsoleApp/DesktopSceneDelegate.swift,AdminConsoleApp/ViewControllers/ControlRootViewController.swift
   Note: Implemented external full-screen adaptive font fit, enabled ANSI background colors for mc, and added hardware F1-F12 mapping. swift test passed, xcodebuild build passed.
   Detail: tasks/details/10-external-display-fit-colors-fkeys.md
   Claimed by: CODEX
   Claimed at: 2026-04-21T12:52:46Z
   Done by: CODEX
   Done at: 2026-04-21T12:54:36Z

11. external-mirror-mc-fullwidth
   Id: 11-external-mirror-mc-fullwidth
   Scope: Fix external mirror width for alternate-screen TUI and expose visible soft F1-F12 keys
   Files: AdminConsoleApp/ViewControllers/ControlRootViewController.swift
   Note: Done. Added resize re-apply on normal<->alternate screen transition; reordered soft keys to explicit F1-F12 first. Validation: swift test (54/54), xcodebuild AdminConsoleApp build succeeded.
   Detail: tasks/details/11-external-mirror-mc-fullwidth.md
   Claimed by: CODEX
   Claimed at: 2026-04-21T13:22:47Z
   Done by: CODEX
   Done at: 2026-04-21T13:23:14Z

12. backspace-phone-mc-fix
   Id: 12-backspace-phone-mc-fix
   Scope: Fix hardware backspace mapping and stabilize phone alternate-screen mc render
   Files: AdminConsoleApp/ViewControllers/ControlRootViewController.swift,Packages/AppModules/Sources/SSHKit/TerminalEmulator.swift
   Note: Fixed hardware Backspace mapping (removed forward-delete keybinding) and stabilized phone alternate-screen rendering via plain-text mode on iPhone. Validation: swift test PASS (55 tests), xcodebuild AdminConsoleApp build PASS.
   Detail: tasks/details/12-backspace-phone-mc-fix.md
   Claimed by: CODEX
   Claimed at: 2026-04-21T15:46:39Z
   Done by: CODEX
   Done at: 2026-04-21T15:50:32Z

13. phone-fit-fix-after-mc-stabilization
   Id: 13-phone-fit-fix-after-mc-stabilization
   Scope: Fix phone terminal layout fit while keeping external monitor mc rendering stable
   Files: AdminConsoleApp/ViewControllers/ControlRootViewController.swift,Packages/AppModules/Sources/DesktopDomain/Models.swift,AdminConsoleApp/DesktopSceneDelegate.swift,tasks/**
   Note: Adjusted phone alternate-screen fit: disabled attributed wrapping, compact insets, adaptive min font for external-mirror mc; swift test + xcodebuild passed.
   Detail: tasks/details/13-phone-fit-fix-after-mc-stabilization.md
   Claimed by: CODEX
   Claimed at: 2026-04-21T17:05:21Z
   Done by: CODEX
   Done at: 2026-04-21T17:28:04Z

14. dual-screen-terminal-grid
   Id: 14-dual-screen-terminal-grid
   Scope: Fix phone readability when external monitor connected by introducing canonical PTY geometry + per-screen rendering fit
   Files: AdminConsoleApp/ViewControllers/ControlRootViewController.swift,AdminConsoleApp/DesktopSceneDelegate.swift,Packages/AppModules/Sources/SSHKit/TerminalEmulator.swift,Packages/AppModules/Sources/DesktopDomain/Models.swift
   Note: Implemented canonical PTY grid + per-screen font-fit strategy; no-wrap attributed rendering on external; mirror phone control override for alternate-screen readability. swift test + xcodebuild passed.
   Detail: tasks/details/14-dual-screen-terminal-grid.md
   Claimed by: CODEX
   Claimed at: 2026-04-21T17:40:05Z
   Done by: CODEX
   Done at: 2026-04-21T18:09:01Z

15. external-first-dual-screen-mc
   Id: 15-external-first-dual-screen-mc
   Scope: Dual-screen terminal render profiles, external-first PTY sizing, phone pan viewport, MC stability
   Files: AdminConsoleApp/ViewControllers/ControlRootViewController.swift,AdminConsoleApp/DesktopSceneDelegate.swift,Packages/AppModules/Sources/DesktopDomain/Models.swift,Packages/AppModules/Sources/SSHKit/TerminalEmulator.swift,Packages/AppModules/Tests
   Note: Implemented external-first dual-screen render flow, phone pan viewport preservation, external geometry fallback/profile resolver, hardware backspace intercept, buffer write guard; passed: swift test (AppModules), xcodebuild build AdminConsoleApp, xcodebuild tests AdminConsoleTests + AdminConsoleUITests/testLaunch
   Detail: tasks/details/15-external-first-dual-screen-mc.md
   Claimed by: CODEX
   Claimed at: 2026-04-21T20:20:50Z
   Done by: CODEX
   Done at: 2026-04-21T21:02:45Z

16. terminal-ux-hardening
   Id: 16-terminal-ux-hardening
   Scope: Audit and fix weak spots in terminal functional UX after external-first layout
   Files: AdminConsoleApp/ViewControllers/ControlRootViewController.swift,AdminConsoleApp/DesktopSceneDelegate.swift,Packages/AppModules/Sources/DesktopDomain/TerminalRenderProfile.swift,Packages/AppModules/Tests
   Note: Fixed terminal render UX weak spots: phone standalone fit, external companion pan, stable alternate viewport anchoring, hardware Backspace fallback. Tests: swift test AppModules passed; iOS simulator generic build passed.
   Detail: tasks/details/16-terminal-ux-hardening.md
   Claimed by: CODEX
   Claimed at: 2026-04-25T22:44:44Z
   Done by: CODEX
   Done at: 2026-04-25T23:06:08Z

17. phone-mc-viewport-stability
   Id: 17-phone-mc-viewport-stability
   Scope: Stabilize phone-only alternate-screen viewport when launching mc without external monitor
   Files: AdminConsoleApp/ViewControllers/ControlRootViewController.swift,Packages/AppModules/Tests
   Note: Stabilized phone-only mc launch by resetting alternate-screen viewport on canvas transition. Tests: swift test AppModules passed; iOS simulator generic build passed.
   Detail: tasks/details/17-phone-mc-viewport-stability.md
   Claimed by: CODEX
   Claimed at: 2026-04-26T13:05:12Z
   Done by: CODEX
   Done at: 2026-04-26T13:11:56Z


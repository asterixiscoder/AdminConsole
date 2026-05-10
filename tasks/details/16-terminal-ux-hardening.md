# 16-terminal-ux-hardening

- Number: 16
- Slug: terminal-ux-hardening

## Notes

## Audit summary

- The terminal renderer had two mixed UX modes: phone standalone and phone companion were both using the same base font behavior. That made MC either shrink into a thumbnail or require accidental offsets after external display changes.
- Alternate-screen viewport restoration treated "no scrollable overflow" as "already near the right/bottom edge". On the next frame, when MC produced a larger canvas, the view could jump to the bottom/right and create apparent dead zones or stair-step offsets.
- Hardware Backspace relied mostly on responder propagation. The soft Backspace path was stable, but external/hardware keyboards could bypass the local terminal backspace handler depending on focus.
- Grid stability already had good low-level repair guards; I added one more regression test around repeated resize + wide writes because this is the path that previously caused index crashes during TUI resize/update races.

## Changes

- Phone standalone alternate-screen now fits the terminal grid into the available phone terminal area with compact insets and a bounded minimum font size.
- Phone companion mode, when external display is connected, keeps the external canvas at normal terminal scale and exposes it as a pan viewport instead of shrinking it into a miniature.
- External display alternate-screen viewport now starts from top-left unless the user actually pans or there was real overflow before the frame update.
- Right/bottom stickiness is now only persisted when the terminal content is truly scrollable.
- Hardware Backspace is explicitly mapped through the same terminal backspace handler as soft Backspace.
- Added tests for phone-only render profile bounds and terminal grid stability across repeated resize/write cycles.

## Verification

- `swift test --package-path Packages/AppModules`: passed, 61 tests.
- `xcodebuild -project AdminConsole.xcodeproj -scheme AdminConsoleApp -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/AdminConsoleDerivedData build CODE_SIGNING_ALLOWED=NO`: passed.

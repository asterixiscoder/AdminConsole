# 17-phone-mc-viewport-stability

- Number: 17
- Slug: phone-mc-viewport-stability

## Notes

## Fix

- The phone terminal now treats the transition into alternate-screen as a new canvas.
- On the first `mc` frame, the old shell scroll offset is discarded and the viewport is reset to top-left.
- After that first frame, user panning is preserved normally.
- The same transition-safe reset is applied to the external mirror renderer to keep both surfaces aligned.

## Verification

- `swift test --package-path Packages/AppModules`: passed, 61 tests.
- `xcodebuild -project AdminConsole.xcodeproj -scheme AdminConsoleApp -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/AdminConsoleDerivedData build CODE_SIGNING_ALLOWED=NO`: passed.

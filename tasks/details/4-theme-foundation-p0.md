# 4-theme-foundation-p0

- Number: 4
- Slug: theme-foundation-p0

## Notes

### Implemented
- Added shared visual token model:
  - `AdminThemeStyle` (`system`, `midnight`, `graphite`, `lightOps`)
  - `AdminTheme` semantic palette
  - `AdminThemeManager` with persisted selection in `UserDefaults`
- Added global theme change notification path (`adminThemeDidChange`) for live UI refresh.

### Integration
- Integrated base shell theming into `RebootRootViewController`:
  - themed background/surface/stroke usage for shell and tab container
  - theme-aware tab selection colors
  - runtime updates on theme change + trait change

### Follow-up
- Expand token adoption to `Vaults`, `Terminal`, and external desktop mirror views.
- Extract token/theme code into a dedicated UI module/file after first stabilization pass.

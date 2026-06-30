# Codex Notes

- After making code or project file changes, run `scripts/package-app.sh`.
- Commit completed changes with git after packaging succeeds, unless the user explicitly asks not to commit.
- Keep each commit focused on one theme. Bug fixes, refactors, and feature work should be committed separately.
- When a completed change is suitable for users and packaging succeeds, proactively publish a new version at an appropriate stopping point unless the user says not to release.

## UI Design Style

Vellum uses a compact Tokyo Night inspired macOS interface. New pages, panels, and overlays should feel like they belong to the existing reader, settings, search, and tab-switcher surfaces.

- Use the shared `TokyoNight` palette from `Sources/VellumCore/Support/TokyoNight.swift`. Prefer `background`, `backgroundDeep`, `panel`, `panelElevated`, `selection`, `border`, `foreground`, `muted`, `blue`, `cyan`, `purple`, and `red` instead of introducing new color families.
- Keep the app dark, calm, and reading-focused. Avoid bright marketing-style layouts, large decorative gradients, colorful illustration blocks, oversized hero text, or unrelated accent colors.
- Build dense but breathable tool surfaces: constrained content widths, 12-24 px outer padding, 8-16 px section spacing, and compact controls that support repeated use.
- Follow the existing hierarchy: page headers use an SF Symbol in a small 36 px elevated square, a 20 pt semibold title, and 12-13 pt muted supporting text. Body labels are usually 12-13 pt, semibold only for names or primary row text.
- Use shallow surfaces. Page backgrounds use `TokyoNight.backgroundColor`; sidebars and tab bars use `backgroundDeepColor`; grouped panels use `panelColor.opacity(0.8)` or `panelElevatedColor` with a 1 px `borderColor` stroke.
- Keep corner radii restrained: 8 px for panels, overlays, tabs, and header icon wells; 7 px for rows and inputs; 5-6 px for keycaps, pills, and small choices. Do not use large rounded cards.
- Prefer full-width bands, split panes, and direct tool layouts over nested cards. Cards are acceptable for repeated items or contained settings groups, but do not put cards inside cards.
- Use SF Symbols/lucide-like icon semantics consistently: small icons inside headers, rows, and buttons should communicate the action or category. Do not add explanatory feature text when a familiar control and icon are enough.
- Use custom-styled controls that match the app instead of raw Apple defaults when building visible settings controls: Tokyo Night backgrounds, subtle borders, explicit hover/focus/selected states, and generous hit targets.
- Hit targets should feel easy with a mouse: rows and buttons should use `.contentShape(Rectangle())` or an equivalent AppKit hit area; small icon buttons need hover feedback and should not require clicking the glyph center.
- Hover states should be subtle but visible: increase panel/row opacity, strengthen the border, or tint the icon/text with `cyan`/`blue`; destructive hover states may use `red` sparingly.
- Search, switcher, and transient command UI should use HUD-like glass only when readability remains strong. Pair material blur with an opaque Tokyo Night tint; never make overlays so transparent that document text competes with the control.
- Keep window chrome consistent with the main reader: hidden title text, full-size content view, dark background, custom top drag regions, and no stray native top or bottom bars.
- Preserve draggable regions intentionally. Top chrome should be draggable except where interactive controls live; text/PDF selection areas must not accidentally drag the window.
- Text must not truncate important setting explanations when the view can reasonably wrap. Prefer vertical growth and `.fixedSize(horizontal: false, vertical: true)` for subtitles and explanatory copy.
- When adding a new page, first look for reusable local patterns such as `SettingsPanel`, `GeneralSettingsPanel`, `StyledTextField`, `StyledSecureField`, `GeneralOptionRow`, `GeneralToggleRow`, `TokyoNightDivider`, `TabSwitcherOverlay`, and the reader tab/toolbar components.
- New UI must support both English and Chinese app UI language where user-visible text is involved. Add strings through `AppLanguage.swift` rather than hardcoding one language in the view.
- Before finishing UI work, inspect the result for accidental native controls, transparent gaps, oversized padding, weak hit targets, text clipping, and inconsistent top/bottom chrome.

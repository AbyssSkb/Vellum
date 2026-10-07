# Codex Notes

- After making code or project file changes, run `scripts/package-app.sh`.
- Commit completed changes with git after packaging succeeds, unless the user explicitly asks not to commit.
- Keep each commit focused on one theme. Bug fixes, refactors, and feature work should be committed separately.
- Run relevant tests before packaging; use `swift test --no-parallel` for the full suite because AppKit/PDFKit tests share application focus and the main run loop.
- After packaging succeeds, provide the local app for the user to test. Publish a new version after the user confirms that local testing passed.
- Build and open each local preview at a fresh app path with an independent bundle identifier and preferences, keeping existing Vellum instances running.
- Use an ephemeral signing key for isolated local update fixtures and the CI signing key for production releases.
- Write public GitHub release titles and notes in English. Keep commit subjects used to generate release notes in English as well.
- Continue the 0.8.x release series, choosing the next version after the latest published release.
- Express language and presentation preferences as positive desired outcomes in AI project instructions.
- Keep README, user guides, and GitHub About aligned with the shipped features. Present AI assistance as an optional experiment, with configuration covered in the user guide.
- Use the original PDF in `docs/samples/` for feature screenshots. Capture native macOS windows with clean corners and the pointer outside the image, showing the English UI for the primary README.

## UI Design Style

Vellum uses a compact, subtly cool ink-black macOS interface with restrained Linear-inspired component hierarchy. New pages, panels, and overlays should feel like they belong to the existing reader, settings, search, and tab-switcher surfaces.

- Use the shared `TokyoNight` palette from `Sources/VellumCore/Support/TokyoNight.swift`. Prefer `background`, `backgroundDeep`, `panel`, `panelElevated`, `selection`, `border`, `foreground`, `muted`, `blue`, `cyan`, `purple`, and `red` instead of introducing new color families.
- The palette keeps its existing API name. Use subtly cool surfaces and soft white text for ordinary chrome, and the muted steel-blue `blue` for focus and selected controls. Keep `cyan`, `purple`, and `red` values stable because PDF highlight colors depend on them.
- Use a native semantic green for successful update status and `red` for errors.
- Keep the app dark, calm, and reading-focused, with restrained typography, shallow surfaces, and subtle tonal differences.
- Build dense but breathable tool surfaces: constrained content widths, 12-24 px outer padding, 8-16 px section spacing, and compact controls that support repeated use.
- Follow the existing hierarchy: page headers use a plain muted SF Symbol, a 20 pt medium title, and 12-13 pt regular muted supporting text. Settings names and current items are usually 12-13 pt medium; ordinary navigation and list items use regular weight. Group labels are smaller and muted.
- Use shallow surfaces. Page backgrounds use `TokyoNight.backgroundColor`; sidebars and tab bars use `backgroundDeepColor`; the reading canvas uses the slightly brighter `panelColor` with native PDF page shadows. Settings groups use independent labels and flat rows separated by subtle horizontal rules; reserve filled surfaces and borders for inputs, buttons, and overlays. Floating overlays use a soft border and shallow shadow to separate them from the content.
- Keep corner radii restrained: 8 px for panels, overlays, tabs, and header icon wells; 7 px for rows and inputs; 5-6 px for keycaps, pills, and small choices. Follow the shared adaptive reader geometry for the main canvas.
- Prefer full-width bands, split panes, and direct tool layouts. Use a single surface for repeated items or contained settings groups.
- Use SF Symbols/lucide-like icon semantics consistently: small icons inside headers, rows, and buttons should communicate the action or category. Keep familiar controls concise and self-explanatory.
- Use custom-styled controls that match the app instead of raw Apple defaults when building visible settings controls: Tokyo Night backgrounds, subtle borders, explicit hover/focus/selected states, and generous hit targets.
- Hit targets should feel easy with a mouse: rows and buttons should use `.contentShape(Rectangle())` or an equivalent AppKit hit area; small icon buttons need hover feedback and a generous clickable area.
- Hover states should be subtle but visible: increase panel/row opacity, strengthen the border, or tint the icon/text with `cyan`/`blue`; destructive hover states may use `red` sparingly.
- Search, switcher, and transient command UI should pair HUD-like material blur with an opaque Tokyo Night tint that keeps controls clearly readable against the document.
- Keep window chrome consistent with the main reader: hidden title text, full-size content view, dark background, and custom top drag regions. The empty and document views share equal adaptive outer insets, related inner/outer radii, and stable traffic-light placement.
- Preserve draggable regions intentionally. Top chrome supports dragging around interactive controls; text and PDF areas support selection.
- Let important setting explanations wrap, using vertical growth and `.fixedSize(horizontal: false, vertical: true)` for subtitles and explanatory copy.
- When adding a new page, first look for reusable local patterns such as `SettingsPanel`, `GeneralSettingsPanel`, `StyledTextField`, `StyledSecureField`, `GeneralOptionRow`, `GeneralToggleRow`, `TokyoNightDivider`, `TabSwitcherOverlay`, and the reader tab/toolbar components.
- New UI must support both English and Chinese app UI language where user-visible text is involved. Add strings through `AppLanguage.swift` rather than hardcoding one language in the view.
- Keep tab titles typographic, with visible separators and the active tab joined naturally to the reader. Long titles scroll once when opened, activated, or hovered so the reading surface stays calm.
- Keep outline focus indicators aligned with each item's indentation, page numbers in a stable trailing column, and native row typography consistent from the first frame. Use shared focus routing for reader, outline, and gallery keyboard interaction.
- Fit-width reading fills the inner canvas width; first/last-page navigation aligns the corresponding paper edge with the viewport. Preserve natural top/bottom anchoring during fit transitions and continuous scaling during window resizing.
- Make the immersive gallery's entry, page changes, and return feel continuous with the reading canvas, with a large, clear current-page preview and visible neighbors.
- Manual and background updates share the custom Sparkle window. Size brief status results to their content, constrain release-note width, and keep the scrollable body ending at its last line. Show button letter shortcuts beside their labels; keep Vim scrolling controls familiar and unobtrusive.
- Before finishing UI work, verify consistent custom controls and chrome, continuous surfaces, balanced padding, generous hit targets, readable text, and smooth transitions.

# Vellum

Vellum is a native macOS PDF reader built with SwiftUI and PDFKit. It is designed for keyboard-first reading, Vim-style navigation, lightweight tabs, fast outline browsing, highlights, and optional AI explanations for selected passages.

## Features

- Native macOS app powered by SwiftUI, AppKit, and PDFKit
- Vim-style movement for scrolling, paging, jumping, zooming, and tab switching
- Multi-tab PDF reading with restore-last-closed-tab support
- Keyboard-driven outline sidebar with jump history
- Highlight creation, deletion, and color cycling
- Optional AI explanations for selected text or highlights through an OpenAI-compatible API
- Local release app bundle generation with icon packaging and ad-hoc signing

## Requirements

- macOS 14 or newer
- Swift 6.2 toolchain or newer
- Xcode command line tools

## Build And Run

Run the app directly during development:

```sh
swift run
```

Build a double-clickable release app bundle:

```sh
scripts/package-app.sh
```

The packaged app is written to:

```text
dist/Vellum.app
```

The packaging script builds the SwiftPM executable, generates `AppIcon.icns` from `Resources/AppIcon/icon.png`, writes a minimal `Info.plist`, and ad-hoc signs the app when `codesign` is available.

## AI Configuration

Open Vellum settings and configure an OpenAI-compatible provider:

- Base URL, for example `https://api.openai.com/v1`
- API key
- Model name

The settings screen can fetch available models and test the configured chat completions endpoint. AI features are optional; the core PDF reader works without an API key.

## Keyboard Shortcuts

| Key | Action |
| --- | --- |
| `o` | Open PDF |
| `O` | Open PDF in a new tab |
| `x` | Close tab |
| `X` | Restore last closed PDF |
| `Tab` / `t` | Toggle contents sidebar |
| `j` / `k` | Scroll down / up |
| `d` / `u` | Large scroll down / up; `d` deletes selected highlights when text is selected |
| `h` / `l` | Scroll left / right |
| `Space` / `f` | Move forward one page |
| `b` | Move back one page |
| `gg` | First page |
| `G` | Last page |
| `[num]G` | Jump to page number |
| `Control-O` / `Control-I` | Jump back / forward |
| `m` | Highlight selected text |
| `a` | Explain selected highlight/text with AI |
| `c` | Cycle highlight color |
| `+` / `-` | Zoom in / out |
| `0` | Fit whole page |
| `z` | Fit width |
| `]` / `[` | Next / previous tab |
| `L` / `H` | Next / previous tab |
| `gt` / `gT` | Next / previous tab |

When the outline sidebar has focus, `j` / `k` move through outline items, `h` / `l` collapse and expand parent items, and `Enter` jumps to the selected destination. Outline jumps are included in `Control-O` / `Control-I` history.

Standard macOS shortcuts are also wired for opening files, closing tabs, and switching tabs from the menu bar.

## Project Structure

```text
Resources/AppIcon
    Source artwork for the macOS app icon
Sources/Vellum/App
    App entry, app delegate, URL relay, and open panels
Sources/Vellum/AI/Client
    OpenAI-compatible requests, responses, streaming, and errors
Sources/Vellum/AI/Configuration
    AI provider configuration and persisted settings keys
Sources/Vellum/AI/Context
    Selected-text and annotation context for AI explanations
Sources/Vellum/AI/UI
    AI explanation popovers, WebView rendering, and layout helpers
Sources/Vellum/Documents
    Document coordination and PDF loading services
Sources/Vellum/Input
    Vim-style key maps, key state, and input controller
Sources/Vellum/Outline
    Outline data models
Sources/Vellum/PDF/Geometry
    Scroll, zoom, and animation geometry helpers
Sources/Vellum/PDF/Highlighting
    Highlight geometry and annotation behavior
Sources/Vellum/PDF/Selection
    Text selection, word navigation, and visual-line geometry
Sources/Vellum/PDF/View
    PDFKit view integration, navigation, scrolling, zooming, and AI hooks
Sources/Vellum/Reader
    Shared reader models
Sources/Vellum/Stores
    App-wide observable state and command dispatching
Sources/Vellum/Support
    Shared styling and small extensions
Sources/Vellum/Tabs
    Closed-tab history models
Sources/Vellum/Views/Reader
    Main reader SwiftUI views and AppKit wrappers
Sources/Vellum/Views/Settings
    Settings screens and settings view models
Sources/Vellum/Views/Outline
    Outline AppKit bridge, coordinator, keyboard handling, and row styling
Sources/Vellum/Views/Components
    Reusable SwiftUI/AppKit components
Tests/VellumTests
    Tests mirrored by feature area
scripts
    Packaging and icon generation helpers
```

## Development

Useful commands:

```sh
swift build
swift test
swift run
scripts/package-app.sh
```

Generated build outputs live in `.build/` and packaged apps live in `dist/`. Both are ignored by git.

## Status

Vellum is an early-stage personal macOS reader. It is usable for local PDF reading workflows, but distribution packaging is intentionally simple: the app is ad-hoc signed and not notarized.

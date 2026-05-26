# Vellum

A native macOS PDF reader built with SwiftUI and PDFKit, designed around Vim-style keyboard navigation and lightweight multi-tab reading.

## Run

Build a double-clickable release macOS app bundle:

```sh
scripts/package-app.sh
```

The app is created at:

```text
dist/Vellum.app
```

For development, you can also run the executable directly:

```sh
swift run
```

The debug binary is produced at:

```text
.build/arm64-apple-macosx/debug/Vellum
```

## Project Structure

```text
Sources/Vellum/App       App entry, app delegate, URL relay, and open panels
Sources/Vellum/AI        AI explanation configuration, client, popovers, and HTML rendering
Sources/Vellum/Models    Shared reader, outline, tab, highlight, and Vim command models
Sources/Vellum/PDF       PDFKit integration, highlight geometry, and PDF view behavior
Sources/Vellum/Services  Document loading services
Sources/Vellum/Stores    App-wide observable state and input routing
Sources/Vellum/Support   Shared styling and small extensions
Sources/Vellum/Views     SwiftUI views and AppKit wrappers
scripts                  Packaging and icon generation helpers
```

## Keys

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
| `Space` or `f` | Move forward one page |
| `b` | Move back one page |
| `gg` | First page |
| `G` | Last page |
| `[num]G` | Jump to page number |
| `Control-O` / `Control-I` | Jump back / forward |
| `m` | Highlight selected text |
| `+` / `-` | Zoom in / out |
| `0` | Fit whole page |
| `z` | Fit width |
| `]` / `[` | Next / previous tab |
| `L` / `H` | Next / previous tab |
| `gt` / `gT` | Next / previous tab |

When the contents sidebar has focus, `j` / `k` move through outline items, `h` / `l` collapse and expand parent items, and `Enter` jumps to the selected destination. Outline jumps are included in `Control-O` / `Control-I` history.

Standard macOS shortcuts are also wired for opening files, closing tabs, and switching tabs from the menu bar.

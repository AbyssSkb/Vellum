# Vellum

English | [简体中文](README.zh-CN.md)

**A native macOS PDF reader for staying with the page.**

Vellum brings smooth Vim-style navigation, a keyboard-driven outline, and an immersive page gallery to a quiet, compact reading interface. Built with SwiftUI, AppKit, and PDFKit.

[Download for macOS](https://github.com/AbyssSkb/Vellum/releases/latest) · [User guide](docs/USER_GUIDE.md) · [Report an issue](https://github.com/AbyssSkb/Vellum/issues)

![Vellum's reading canvas with compact document tabs and highlight colors](docs/images/vellum-reader.png)

## Read at your own pace

Tap or hold `j` and `k` to scroll smoothly. Fit the page or its width, zoom continuously, jump to a page with `12G`, and retrace your reading with `Control-O` and `Control-I`. Select text with the mouse, then refine the selection by line or word from the keyboard.

Keep several documents close with compact tabs. `T` opens a searchable tab switcher, and `X` restores the last closed file. Each file has one tab; reopening an updated PDF reloads its current contents. Long tab titles scroll once when opened, activated, or hovered.

## A map when you need one

Press `t` to show or hide the contents sidebar. Tap `Tab` to move keyboard focus between the page and outline, opening the sidebar if needed. Browse with `j` and `k`, fold with `h`, and expand with `l`. Press `Enter` to jump and resume reading. The outline also supports Vim's `zo`, `zc`, `zO`, `zC`, `zr`, `zm`, `zR`, and `zM`, including recursive folds and count prefixes. `H` and `L` switch documents while the outline stays open.

![Vellum's hierarchical contents sidebar beside the document and tabs](docs/images/vellum-outline-tabs.png)

## See the pages around you

Hold `Tab` to enter the immersive gallery. A large current-page preview sits between its neighbors, keeping the document's layout easy to recognize. Use `h` / `l` to move one page or `k` / `j` to move three pages. Release `Tab` to return to the selected page with a continuous transition back to the reading canvas, or press `Esc` to return to where you started.

![Immersive page gallery showing the current page and its neighboring pages](docs/images/vellum-gallery.png)

## Keep the useful parts

Search with `/`, move through matches with `n` and `N`, and press `v` to select a match. Copy with `y` or highlight with `m`; five highlight colors are available. Annotations save back to the PDF automatically, with recovery options if the file cannot be saved or has changed on disk.

![Search matches with a compact query field and result counter](docs/images/vellum-search.png)

*Screenshots show the current native interface with an original [sample PDF](docs/samples/the-shape-of-attention.pdf).*

## Experimental AI

AI assistance is an optional experiment. Its workflow and output quality are still being explored and refined, so it is not part of Vellum's core feature showcase. Existing in-app tools remain available for those who want to try them; configuration and current behavior are covered in the [user guide](docs/USER_GUIDE.md#experimental-ai).

## Get started

1. Download the latest DMG from [Releases](https://github.com/AbyssSkb/Vellum/releases/latest), then drag Vellum into Applications.
2. Open a PDF with `o` or `Command-O`. Use `O` to open files in new tabs.
3. Press `z` to fit the width or `0` to fit the whole page, then move with `j` and `k`.

| Key | Action |
| --- | --- |
| `j` / `k`, `d` / `u` | Scroll down / up; larger steps with `d` / `u` |
| `Space` / `f`, `b` | Next / previous page |
| `gg`, `G`, `12G` | First page, last page, page 12 |
| `=` / `-`, `0`, `z` | Zoom in / out, fit page, fit width |
| `t` | Show / hide the contents sidebar |
| Tap `Tab` | Switch focus between the reader and contents |
| Hold `Tab` | Open the page gallery |
| `H` / `L`, `T` | Previous / next tab; searchable tab switcher |
| `/`, `n` / `N` | Search; next / previous match |
| `m`, `c`, `y` | Highlight, change highlight color, copy |

Letter shortcuts apply to the focused reading surface. Search fields and conversation inputs accept normal typing. The [user guide](docs/USER_GUIDE.md) covers selection, outline folds, focus behavior, and the full shortcut set.

## Preferences and updates

Settings include English and Chinese UI, default file-opening behavior, initial page fit, highlight color, optional session restoration, and AI configuration. Session restoration is off by default.

Sparkle handles automatic updates, with checks enabled by default. A new version downloads and prepares in the background, then Vellum offers to restart and update now or install when you normally quit. Manual checks from the Vellum menu or General settings use the same update window, with Vim-style release-note scrolling and letter shortcuts shown on its buttons. Brief status messages use a compact window that fits its content; a green check confirms that Vellum is up to date. See the [update controls](docs/USER_GUIDE.md#settings-and-updates).

## Build from source

Requires macOS 14 or later and a Swift 6.2 toolchain. Release downloads support Apple silicon and Intel Macs.

```sh
git clone https://github.com/AbyssSkb/Vellum.git
cd Vellum
swift test --no-parallel
scripts/package-app.sh
open dist/Vellum.app
```

The packaging script builds a universal macOS app in `dist/Vellum.app`.

## Feedback

Report bugs or suggest improvements through [GitHub Issues](https://github.com/AbyssSkb/Vellum/issues). For rendering or navigation problems, include the macOS version, steps to reproduce, and a sample PDF you can share.

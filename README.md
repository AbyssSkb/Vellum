# Vellum

[简体中文](README.zh-CN.md) | English

Vellum is a native macOS PDF reader shaped around fast, keyboard-first reading. It combines Vim-style navigation, lightweight tabs, outline browsing, search, highlights, and optional AI explanations for selected text.

![Vellum reader screenshot placeholder](docs/images/vellum-reader.png)

## Highlights

- Read PDFs with smooth Vim-style movement, paging, jumping, zooming, and tab switching.
- Browse document outlines from the keyboard and include outline jumps in back/forward history.
- Search inside PDFs, jump between matches, and turn a match into a selectable text range.
- Highlight selected passages, switch highlight colors, copy text, and delete existing highlights.
- Ask an OpenAI-compatible model to explain selected text or saved highlights.
- Keep several PDFs open with compact tabs and restore the last closed PDF.

## Quick Start

[Download the latest release](https://github.com/AbyssSkb/Vellum/releases/latest), open the DMG, and launch Vellum.

Open a PDF, then use the reading keys:

| Key | Action |
| --- | --- |
| `o` / `O` | Open a PDF in the current tab / new tabs |
| `j` / `k` | Scroll down / up |
| `d` / `u` | Large scroll down / up |
| `D` / `U` | Extra large scroll down / up |
| `Space` / `f` / `b` | Page forward / backward |
| `gg` / `G` / `[num]G` | First page / last page / page number |
| `/` / `n` / `N` | Search / next match / previous match |
| `Tab` / `t` | Toggle contents |
| `m` / `y` / `a` | Highlight / copy / explain selected text |
| `=` / `-` / `0` / `z` | Zoom in / out / fit page / fit width |

## Documentation

Read the full guide:

- [User Guide](docs/USER_GUIDE.md)

## Feedback

If you run into any problem while using Vellum, please feel welcome to send feedback through [GitHub Issues](https://github.com/AbyssSkb/Vellum/issues).

## Screenshots

![Outline and tabs screenshot placeholder](docs/images/vellum-outline-tabs.png)

![AI explanation screenshot placeholder](docs/images/vellum-ai-explanation.png)

## Requirements

- macOS 14 or newer
- A PDF file to read
- Optional: an OpenAI-compatible API provider for AI explanations

## Note

Vellum is a personal reader made through vibe coding: guided by taste, iteration, and the momentum of building with AI.

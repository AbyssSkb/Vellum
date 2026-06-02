# Vellum User Guide

[简体中文](USER_GUIDE.zh-CN.md) | English

Vellum is designed for people who spend real time inside PDFs: papers, manuals, references, and long documents. The main idea is simple: keep your hands on the keyboard, keep the page moving smoothly, and keep useful reading actions close.

![Vellum reader screenshot placeholder](images/vellum-reader.png)

## 1. Start Reading

Open Vellum and choose a PDF from the empty reader screen, or press `o` to open a file in the current tab.

You can also open multiple PDFs at once with `O`. Each selected file opens in its own tab.

Common file and tab keys:

| Key | Action |
| --- | --- |
| `o` | Open a PDF in the current tab |
| `O` | Open PDFs in new tabs |
| `x` | Close the current tab |
| `X` | Restore the last closed PDF |
| `]` / `[` | Next / previous tab |
| `L` / `H` | Next / previous tab |
| `gt` / `gT` | Next / previous tab |
| `Command-O` | Open PDF |
| `Command-W` | Close tab |
| `Command-]` / `Command-[` | Next / previous tab |

## 2. Move Around the PDF

Vellum uses Vim-style movement for reading. Short taps move a little; holding movement keys keeps the page moving smoothly.

| Key | Action |
| --- | --- |
| `j` / `k` | Smooth scroll down / up |
| `d` / `u` | Large smooth scroll down / up |
| `D` / `U` | Extra large smooth scroll down / up |
| `h` / `l` | Horizontal scroll left / right |
| `Space` / `f` | Move forward one page |
| `b` | Move back one page |
| `gg` | Jump to the first page |
| `G` | Jump to the last page |
| `[num]G` | Jump to a page number, for example `12G` |
| `Control-O` | Jump back |
| `Control-I` | Jump forward |

The jump history includes regular page navigation and outline jumps, so you can explore a document and quickly return.

## 3. Zoom and Fit

Use zoom keys when a PDF is too small, too wide, or better read page by page.

| Key | Action |
| --- | --- |
| `=` / `+` | Zoom in |
| `-` | Zoom out |
| `0` | Fit the whole page |
| `z` | Fit width |

Holding `=` or `-` zooms continuously.

## 4. Use the Contents Sidebar

Press `Tab` or `t` to show or hide the contents sidebar. When the sidebar has focus, it has its own keyboard behavior.

![Outline screenshot placeholder](images/vellum-outline-tabs.png)

| Key | Action in contents |
| --- | --- |
| `j` / `k` | Move the selected outline item down / up |
| `h` | Collapse the selected item, or move to its parent |
| `l` | Expand the selected item |
| `Enter` | Jump to the selected destination |
| `Tab` | Hide the contents sidebar |

Tip: after jumping from the outline, use `Control-O` to return to the previous reading position.

## 5. Page Overview

Hold `Tab` briefly to open the page overview. While holding `Tab`, use movement keys to choose a nearby page, then release `Tab` to finish.

| Key | Action in page overview |
| --- | --- |
| Hold `Tab` | Open page overview |
| `h` / `l` | Move to previous / next page |
| `k` / `j` | Move to previous / next row |
| Release `Tab` | Close page overview at the selected page |

## 6. Search

Press `/` to open search. Type a query and press `Enter` to commit. Search matches stay visible as highlights, and Vellum keeps track of the active match.

| Key | Action |
| --- | --- |
| `/` | Start search |
| `Enter` | Commit the query |
| `Esc` | Cancel search or clear visible search state |
| `n` | Jump to the next match |
| `N` | Jump to the previous match |
| `v` | Turn the active match into a text selection |
| `y` | Copy the active search match when available |

Use `v` when you want to highlight, copy, or explain a search result as normal selected text.

## 7. Select Text

You can select text with the pointer, then refine the selection from the keyboard.

When text is selected, several movement keys switch from page movement to selection movement:

| Key | Action with selected text |
| --- | --- |
| `h` / `l` | Move the selection endpoint left / right |
| `j` / `k` | Move the selection endpoint down / up by visual line |
| `w` / `b` / `e` | Move the endpoint by word |
| `Esc` | Clear the text selection |

This mode is useful for tightening a selection before highlighting, copying, or asking AI to explain it.

## 8. Highlight and Copy

The highlight toolbar in the tab bar lets you choose the current highlight color. Keyboard commands use the selected color.

| Key | Action |
| --- | --- |
| `m` | Highlight selected text |
| `c` | Cycle highlight color |
| `y` | Copy selected text |
| `d` | Delete the selected highlight when a text selection intersects it |

Available highlight colors are yellow, green, cyan, purple, and pink.

## 9. AI Explanations

AI explanations are optional. Configure an OpenAI-compatible provider in Settings before using them.

![AI explanation screenshot placeholder](images/vellum-ai-explanation.png)

To configure AI:

1. Open Vellum Settings.
2. Go to the AI tab.
3. Enter a Base URL, API Key, and Model.
4. Use Fetch Models if your provider supports model listing.
5. Use Test Connection to confirm the chat endpoint works.

To use AI while reading:

| Key | Action |
| --- | --- |
| `a` | Explain selected text or selected highlight |
| `j` / `k` | Scroll inside the AI explanation |
| `m` | Save the explained text as a highlight |
| `c` | Cycle highlight color while the explanation is active |
| `Esc` | Dismiss the explanation |

Saved AI explanations are attached to highlights. Hover an AI-backed highlight to reveal its explanation again.

## 10. Settings and Shortcut Reference

Open Settings to access:

- AI provider configuration.
- Connection diagnostics.
- The built-in shortcut reference.

The shortcut reference is the fastest way to refresh your memory while using the app.

## 11. Suggested Reading Flow

1. Open a PDF with `o`.
2. Press `z` for fit-width reading.
3. Move with `j`, `k`, `d`, and `u`.
4. Use `Tab` to browse the contents when the document has an outline.
5. Search with `/`, then use `n` and `N` to move between matches.
6. Use `v` on an active search match if you want to treat it as selected text.
7. Highlight important passages with `m`, copy with `y`, or explain with `a`.
8. Use `Control-O` and `Control-I` to move through your reading history.

## 12. Troubleshooting

If letter keys do not move the PDF, check whether focus is inside search, settings, the contents sidebar, or an AI explanation. Those areas intentionally use their own keyboard behavior.

If AI explanations fail, check the Base URL, API key, model name, and Test Connection result in Settings.

If a PDF has no contents sidebar entries, the file likely does not include an outline.

If search does not find expected text, the PDF may contain scanned pages or text encoded in a way that PDFKit cannot extract reliably.

## 13. Project Note

Vellum is a personal reader made through vibe coding: guided by taste, iteration, and the momentum of building with AI.

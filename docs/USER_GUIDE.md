# Vellum User Guide

[简体中文](USER_GUIDE.zh-CN.md) | English · [README](../README.md)

Vellum is a native macOS PDF reader with keyboard navigation, an immersive page gallery, searchable tabs, outlines, and highlights. It requires macOS 15 or later and runs on Apple silicon and Intel Macs.

![The Vellum reader](images/vellum-reader.png)

## Open files and manage tabs

Download the app from [GitHub Releases](https://github.com/AbyssSkb/Vellum/releases/latest), open the disk image, and drag Vellum to Applications. Launch it and press `o` to open a PDF.

`Command-O`, or `o` when no text is selected, follows **Settings → General → Default open mode**, initially set to replace the current tab. With text selected in the reader, `o` switches the selection endpoint being adjusted; `Command-O` still opens a PDF. `O` opens PDFs in new tabs and supports selecting several files at once. Files opened through Finder also open in new tabs.

Each file has one tab. Opening an already open file selects its existing tab. If it has changed on disk, reopening reloads its current contents after protecting any unsaved annotations. `X` restores the most recently closed PDF from disk.

| Key | Action |
| --- | --- |
| `o` / `Command-O` | Open using the configured default mode (`o` requires no text selection) |
| `O` | Open PDFs in new tabs |
| `x` / `Command-W` | Close the current tab |
| `X` | Restore the last closed PDF |
| `H` / `L` | Previous / next tab |
| `[` / `]` | Previous / next tab |
| `gT` / `gt` | Previous / next tab from the reader |
| `Command-[` / `Command-]` | Previous / next tab |
| `T` | Open the searchable tab switcher |

In the tab switcher, type part of a filename to filter the list. Use `↑` / `↓` or click a row to preview that document's last-read page. Press `Enter`, click the selected page preview, or double-click a row to switch files. `Esc` returns to your original document and focus. Letters are search input while this overlay is open.

Long tab titles scroll once when opened or selected, and can be revealed again by hovering. Enable **Restore previous tabs** in General settings to reopen your session on the next launch; it is initially off.

## Navigate and zoom

Short taps move the page; holding a scroll or zoom key continues the movement.

| Key | Action in the reader |
| --- | --- |
| `j` / `k` | Smooth scroll down / up |
| `d` / `u` | Larger scroll down / up |
| `D` / `U` | Extra-large scroll down / up |
| `h` / `l` | Horizontal scroll left / right |
| `Space` / `f` | Forward one page |
| `b` | Back one page |
| `gg` / `G` | First page at the document's top / last page at its bottom |
| `[number]G` / `[number]gg` | Jump to a page, for example `12G` or `12gg` |
| `Control-O` / `Control-I` | Back / forward through jump history |
| `=` / `+` / `-` | Zoom in / out |
| `0` | Fit the whole page |
| `z` | Fit page width |

Page jumps and outline destinations are included in jump history. Numeric page jumps use the PDF's one-based page position. Fitting preserves the page's proportions: `z` fills the reading width, while `0` keeps the whole page visible. General settings let you choose Fit width or Fit page when opening a file.

Reader motions accept counts: `10j` scrolls ten steps, `5f` moves five pages, and `3n` / `3N` move three search matches forward / backward. Page movement stops at the first or last page; search wraps through the results. With text selected, `3w` repeats the word motion three times; counts also apply to `h` / `j` / `k` / `l` / `b` / `e`. Counts execute once, up to 1,000 steps per command. Bare scroll keys still support holding. `Esc` clears a pending count, and `12G` / `12gg` remain absolute page jumps.

### Follow PDF links

Press `F` in the reader to label links currently in view. Type a label to follow that link, use `Backspace` to correct a partial label, or press `Esc` to cancel. `Enter` follows the first remaining link. Internal links use the reading history, so `Control-O` returns to the source; web links open through the system's URL handler. Scrolling, resizing, or zooming cancels the labels. This uses links embedded in the PDF; plain reference text without a link is not detected. If no links are visible, a brief notification appears and keyboard navigation remains available.

## Browse the contents

Press `t` to show or hide the contents sidebar. Opening it focuses the outline and aligns its cursor with the current reading section; closing it focuses the reader. A quick tap on plain `Tab` switches focus between the reader and outline, opening the sidebar if it is hidden. These focus switches keep the sidebar visible and preserve the browsing cursor.

Select an entry and press `Enter` to jump and focus the reader. In the outline, `Esc` first clears a pending count or command prefix; with no pending input, it returns focus to the reader while keeping the sidebar open. You can also click either pane to focus it.

The reading-section marker and outline browsing cursor have separate roles. During scrolling, the current section follows the horizontal center line of the reading area, usually changing when a section heading crosses it. While the reader has focus, entering another section aligns the outline cursor with that section. While the outline has focus, its browsing cursor, scroll position, and folds stay under your control as the reading marker updates. A section inside a closed fold is marked through its nearest visible ancestor, preserving the fold state.

![The contents sidebar and document tabs](images/vellum-outline-tabs.png)

| Key | Action with outline focus |
| --- | --- |
| `j` / `k` or `↓` / `↑` | Next / previous visible entry |
| `h` or `←` | Close one fold containing the cursor, like `zc` |
| `l` or `→` | Open one closed fold containing the cursor; otherwise move down one entry |
| `gg` / `G` or `Home` / `End` | First / last visible entry |
| `[number]G` / `[number]gg` | Select that visible entry |
| `d` / `u` | Move down / up half a sidebar viewport |
| `D` / `U`, `f` / `b`, `Page Down` / `Page Up` | Move down / up one viewport |
| `Space` | Move down one viewport |
| `Enter` | Jump to the selected destination and focus the reader |
| `H` / `L` or `[` / `]` | Previous / next file |
| `Control-O` / `Control-I` | Back / forward through PDF jump history |
| `Tab` | Focus the reader, keeping the sidebar open |
| `Esc` | Clear a pending count or prefix; otherwise focus the reader |
| `t` | Close the sidebar and focus the reader |

Counts apply to outline movement: `10j` moves down ten visible entries; `10G` selects the tenth visible entry. The page number beside an entry identifies its destination in the PDF.

### Fold the outline

Vellum uses Vim's fold commands. Type the keys in sequence; uppercase letters matter.

| Command | Action |
| --- | --- |
| `zo` | Open one closed fold containing the cursor |
| `zc` | Close the innermost open fold containing the cursor |
| `zO` | Open the first closed fold containing the cursor and all its descendants |
| `zC` | Close all folds containing the cursor |
| `zr` / `zm` | Increase / decrease the global visible fold level |
| `zR` / `zM` | Open / close all folds |

Put counts **before** `z`: `2zo` opens up to two containing folds, `2zc` closes up to two, and `2zr` / `2zm` adjusts the global level by two. `zO`, `zC`, `zR`, and `zM` already operate recursively or globally; a count does not extend their action.

Closing a containing fold keeps the logical cursor at its original entry, even if an ancestor becomes the visible selection. A following `zo` can reveal that entry again. `zc` also works on a leaf by closing its containing branch. Local fold changes preserve hidden descendant states; `zr`, `zm`, `zR`, and `zM` apply a level to the whole outline. Each open tab remembers its outline state while you switch files.

`Option-→` / `Option-←` recursively opens / closes the selected branch. On a leaf, it uses the parent branch. Add `Shift` to apply this to the entire outline.

## Use the immersive page gallery

Hold plain `Tab` from the reader or outline to preview the selected page and its neighbors in the gallery.

![The immersive page gallery](images/vellum-gallery.png)

| Key | Action while holding `Tab` |
| --- | --- |
| `h` / `l` | Previous / next page |
| `k` / `j` | Back / forward three pages |
| Release `Tab` | Commit the selected page and focus the reader |
| `Esc` | Cancel and restore the original reading position and focus |

A quick tap on plain `Tab` switches pane focus instead. Leaving the gallery preserves whether the sidebar was visible. `Shift-Tab` and Tab inside text controls retain their native behavior.

## Search and select text

Press `/`, type a query, and press `Enter`. Matches stay highlighted after leaving the search field.

![PDF search with match highlighting and a result counter](images/vellum-search.png)

| Key | Action |
| --- | --- |
| `/` | Open the search field |
| `*` | Search selected text immediately |
| `Enter` | Confirm the query |
| `n` / `N` | Next / previous match |
| `v` | Turn the active match into a text selection |
| `y` | Copy selected text or the active search match |
| `o` with text selected | Switch the endpoint adjusted by selection motions |
| `Esc` | Leave search or clear its visible state |

Select text with the pointer, or use `v` on a search result. With text selected, `h` / `l` adjusts the selection endpoint horizontally, `j` / `k` moves it by visual line, and `w` / `b` / `e` moves it by word. Press `o` to switch to adjusting the other end without changing the selected range. Press `Esc` to clear the selection and resume normal page movement.

Press `*` to search a selected word or phrase without opening the search field. Search ignores case and treats punctuation literally. Matches stay within a single PDF page, so a phrase spanning pages will not match. The source selection clears so page motions resume; use `n` / `N` to move through matches and `v` to select the current one. With no selected text, a brief notification explains why search cannot start.

### Select a visible word

1. With the reader focused, press `s` and type the beginning of a word on screen. Matching ignores case.
2. Matching words receive letter labels. Type the target's label to select the whole word. For a multi-letter label, enter its letters in order; its position and size stay stable while you type.
3. Use `h` / `j` / `k` / `l` or `w` / `b` / `e` to adjust the selection, `y` to copy, or `m` to highlight.

![Visible words highlighted with letter labels for keyboard selection](images/vellum-word-jump.png)

Labels adapt to the displayed text size and avoid letters that could continue the word prefix. Keep typing the word to narrow a crowded set of matches.

| Key while word jump is open | Action |
| --- | --- |
| `Backspace` | Remove the last entered label letter; otherwise remove the last word-prefix character |
| `Enter` | Select the first remaining match |
| `Esc` | Cancel word jump, preserving the previous text selection |

Word jump uses extractable PDF text. Scanned pages need a text layer before words can be targeted.

## Highlight and save

Choose a color from the circular swatches in the tab bar, or press `c` to cycle through yellow, green, cyan, purple, and pink.

| Key | Action |
| --- | --- |
| `m` | Highlight the selected text |
| `c` | Cycle highlight color |
| `y` | Copy the selection |
| `d` | Delete highlights intersecting the text selection |
| `M` | Search highlights in the current PDF |
| `gn` / `gN` | Select the next / previous highlight in document order |

The highlight list includes ordinary highlights and highlights with saved AI answers. Type original text or a page number to filter it, use `↑` / `↓` to select a row, and press `Enter` to jump to the passage. `Esc` returns to your previous focus. A selected passage supports the existing `y`, `a`, `i`, and `d` actions. Highlights without extractable text can still be located, but text actions require a text layer.

Annotations save automatically to the PDF in the background. If saving fails or the file changes on disk, Vellum preserves the in-memory annotations and offers **Retry** or **Save a Copy**. Closing the tab or quitting waits for pending changes to be saved or copied.

## Experimental AI

AI is an optional experimental feature. To configure a provider, open Settings with `Command-,`.

1. In **AI Providers**, select a preset or a custom OpenAI-compatible endpoint. HTTP providers use a Base URL and API key.
2. For the **Codex** preset, supply the executable path of an installed, authenticated Codex CLI. Vellum uses the CLI's existing authentication. With Codex CLI 0.162.1, leave **Codex Profile** empty.
3. In **AI Explanation** and **AI Conversation**, choose the provider and model independently. Use **Fetch Models** to view available choices and **Test Model** to verify the configuration. The Codex model field can be empty to use the CLI's configured default.
4. For Codex, choose **Reasoning Depth** separately for explanations and conversations. Explanations default to **Medium** and conversations to **High**. Each page remembers your chosen depth. Available levels come from Codex's model catalog; use **Fetch Models** to refresh the choices.
5. Choose the target output language and, optionally, customize each prompt template. Output language is independent of Vellum's English / Chinese interface setting.

AI requests send the selection and extracted nearby context, such as its page, outline heading, and surrounding paragraphs, to the configured provider. Models accessed through the local Codex CLI may use a remote service.

### Commands and saved answers

| Key | Action from the reader |
| --- | --- |
| `a` | Explain selected text or a selected highlight |
| `i` | Start a conversation about the selected text or highlight |
| `A` | Browse explanation history for the current PDF |
| `I` | Browse conversation history for the current PDF |

Double-clicking text can trigger an explanation or translation; this is enabled by default and can be changed in General settings. A middle click on selected text is another explanation trigger.

In an explanation, use `j` / `k` to scroll, `c` to choose a highlight color, and `m` to save the passage and answer together as a PDF highlight. `Esc` dismisses the explanation. Hover a highlight with a saved explanation to reopen its answer.

For a word or short term, the explanation can include pronunciation and translation. AI Explanation settings provide optional automatic pronunciation with American or British English voices.

In a conversation, type a follow-up question and press `Enter` to send. `Shift-Enter` inserts a newline; `Esc` closes the conversation. Conversations and unsaved explanations are kept for the current app session. Answers saved to highlights are embedded in the PDF and remain available when it is reopened.

## Settings and updates

**General** contains the interface language, tab restoration, default open mode, initial page fit, default highlight color, double-click translation, update checks, and AI logs. **AI Providers**, **AI Explanation**, and **AI Conversation** configure AI. **Shortcuts** contains an in-app key reference.

Operation feedback appears as a Toast at the top of the window and disappears after a few seconds. It keeps the current keyboard focus, so you can continue reading or typing. Update check results use the same notifications; an error offers a details action. Ongoing update progress and annotation save recovery keep their interaction windows so you can finish or resolve them.

Unavailable keyboard actions explain the reason, such as missing selected text, highlights, a search query, or jump history. Copying text briefly confirms success. Repeating the same notification does not extend its display time. Failed file opens, restores, and reloads report the filename and a confirmed reason; batch failures appear together. Hover over a long message or use accessibility to read its full contents.

Sparkle handles updates, with automatic checks enabled initially. New versions download and prepare in the background. Once ready, choose **Restart and Update** to install immediately, or **Later** to keep reading; a prepared update can also install when you normally quit Vellum. Manual checks in General settings or the Vellum menu use the same update window. Choose **Update and Restart** to download, install, and restart in one step. Vellum saves annotations and the reading session before restarting.

A Toast with a green checkmark confirms Vellum is up to date. Scroll long release notes with the keys below; the action buttons stay visible. Press a letter shown on a button to activate it; lowercase and uppercase both work.

| Key | Action in the update window |
| --- | --- |
| `j` / `k` | Scroll down / up; counts work, for example `10j` |
| `gg` / `G` | Beginning / end of the release notes |
| `Control-D` / `Control-U` | Scroll down / up half a viewport |
| `Control-F` / `Control-B` | Scroll down / up one viewport |
| `U` | Download, install, and restart |
| `R` | Restart and update, or retry after an error |
| `L` | Later |
| `C` | Cancel or close, as shown on the button |
| `O` | Open the release page |
| `Tab` / `Shift-Tab` | Focus the next / previous button |
| `Enter` | Activate the focused button, or the primary action if none is focused |

AI diagnostics are stored at `~/Library/Application Support/Vellum/Logs/ai-requests.jsonl`. Use **Open Log** or **Clear Log** in General settings. Logs include request / response excerpts and can contain document text; credential headers are redacted. Review the contents before sharing a log with a bug report.

## Troubleshooting

- **Keys move the wrong area:** keyboard actions follow focus. Click the PDF to navigate it, click the outline to navigate entries, and use `Esc` to dismiss transient overlays. While typing in a search or chat field, letters are text input.
- **An externally edited PDF still looks old:** reopen it using the file picker or Finder. Resolve any pending annotation-save prompt so the latest disk contents can be loaded.
- **No contents entries:** the PDF may not contain an embedded outline.
- **Search or selection misses text:** a scanned page or unusual text encoding may prevent PDFKit from extracting it. Vellum's search and AI selection features depend on extractable text.
- **AI requests fail:** check the selected provider, endpoint / executable, authentication, and model with Test Endpoint or Test Codex; inspect the diagnostic log for the failure.

For bugs and feature requests, use [GitHub Issues](https://github.com/AbyssSkb/Vellum/issues). Include the steps to reproduce, macOS version, Vellum version, and a shareable sample PDF when relevant.

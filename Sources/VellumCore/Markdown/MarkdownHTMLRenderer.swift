import Foundation

enum MarkdownHTMLRenderer {
    static func html(for document: MarkdownDocument) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <base href="\(htmlAttribute(document.url.deletingLastPathComponent().absoluteString))">
          <link rel="stylesheet" href="\(resourceURL("katex.min.css"))">
          <link rel="stylesheet" href="\(resourceURL("highlight-tokyo-night-dark.min.css"))">
          <script src="\(resourceURL("markdown-it.min.js"))"></script>
          <script src="\(resourceURL("markdown-it-footnote.min.js"))"></script>
          <script src="\(resourceURL("markdown-it-task-lists.min.js"))"></script>
          <script src="\(resourceURL("markdownItAnchor.umd.js"))"></script>
          <script src="\(resourceURL("katex.min.js"))"></script>
          <script src="\(resourceURL("texmath.min.js"))"></script>
          <script src="\(resourceURL("highlight-common.min.js"))"></script>
          <script src="\(resourceURL("mermaid.min.js"))"></script>
          <style>\(css)</style>
        </head>
        <body>
          <main id="content"></main>
          <script>
            window.vellumMarkdownSource = \(jsonString(document.source));
            window.vellumLineCount = \(max(1, document.lineCount));
          </script>
          <script>\(javascript)</script>
        </body>
        </html>
        """
    }

    private static func jsonString(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded
    }

    private static func resourceURL(_ fileName: String) -> String {
        Bundle.module
            .url(forResource: fileName, withExtension: nil, subdirectory: "MarkdownRenderer")?
            .absoluteString ?? ""
    }

    private static func htmlAttribute(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static let css = """
    :root {
      color-scheme: dark;
      --bg: #1a1b26;
      --bg-deep: #16161e;
      --panel: #24283b;
      --panel-elevated: #292e42;
      --border: #414868;
      --fg: #c0caf5;
      --muted: #9aa5ce;
      --blue: #7aa2f7;
      --cyan: #7dcfff;
      --purple: #bb9af7;
      --red: #f7768e;
      --green: #9ece6a;
      --yellow: #e0af68;
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; min-height: 100%; background: var(--bg); color: var(--fg); }
    body {
      font: 15px/1.68 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
      overflow-wrap: anywhere;
    }
    main {
      width: min(880px, calc(100vw - 48px));
      margin: 0 auto;
      padding: 30px 0 64px;
    }
    h1, h2, h3, h4, h5, h6 {
      color: var(--fg);
      line-height: 1.25;
      margin: 1.4em 0 0.55em;
      font-weight: 650;
      scroll-margin-top: 28px;
    }
    h1 { font-size: 2.05em; border-bottom: 1px solid rgba(65,72,104,0.7); padding-bottom: 0.28em; }
    h2 { font-size: 1.55em; border-bottom: 1px solid rgba(65,72,104,0.45); padding-bottom: 0.22em; }
    h3 { font-size: 1.23em; }
    h4, h5, h6 { font-size: 1em; color: var(--muted); }
    p, ul, ol, table, pre, blockquote, details { margin: 0.76em 0; }
    a { color: var(--cyan); text-decoration-color: rgba(125,207,255,0.45); }
    a:hover { color: var(--blue); }
    img, video { max-width: 100%; height: auto; border-radius: 8px; border: 1px solid rgba(65,72,104,0.5); }
    hr { border: 0; border-top: 1px solid rgba(65,72,104,0.75); margin: 1.7em 0; }
    blockquote {
      margin-left: 0;
      padding: 0.2em 1em;
      color: var(--muted);
      border-left: 3px solid var(--purple);
      background: rgba(36,40,59,0.55);
      border-radius: 0 8px 8px 0;
    }
    code {
      font-family: "SF Mono", ui-monospace, Menlo, Consolas, monospace;
      font-size: 0.92em;
      color: var(--cyan);
      background: rgba(36,40,59,0.92);
      border: 1px solid rgba(65,72,104,0.55);
      border-radius: 5px;
      padding: 0.11em 0.32em;
    }
    pre {
      background: rgba(22,22,30,0.96);
      border: 1px solid rgba(65,72,104,0.65);
      border-radius: 8px;
      padding: 13px 14px;
      overflow: auto;
    }
    pre code { background: transparent; border: 0; padding: 0; color: inherit; }
    table {
      width: 100%;
      border-collapse: collapse;
      background: rgba(36,40,59,0.56);
      border: 1px solid rgba(65,72,104,0.7);
      border-radius: 8px;
      overflow: hidden;
      display: table;
    }
    th, td { border: 1px solid rgba(65,72,104,0.72); padding: 7px 10px; vertical-align: top; }
    th { background: rgba(41,46,66,0.92); font-weight: 650; color: var(--fg); }
    tr:nth-child(even) td { background: rgba(22,22,30,0.24); }
    input[type="checkbox"] { accent-color: var(--cyan); transform: translateY(1px); }
    .task-list-item { list-style-type: none; margin-left: -1.3em; }
    .footnotes { color: var(--muted); font-size: 0.92em; border-top: 1px solid rgba(65,72,104,0.55); margin-top: 2em; }
    .katex-display { overflow-x: auto; overflow-y: hidden; padding: 0.25em 0; }
    .mermaid {
      background: rgba(36,40,59,0.45);
      border: 1px solid rgba(65,72,104,0.55);
      border-radius: 8px;
      padding: 12px;
    }
    mark.md-search-match {
      background: rgba(122,162,247,0.36);
      color: var(--fg);
      border-radius: 3px;
      padding: 0 1px;
    }
    mark.md-search-match.active {
      background: rgba(224,175,104,0.68);
      color: #11131b;
    }
    ::selection { background: rgba(122,162,247,0.42); color: var(--fg); }
    """

    private static let javascript = """
    (function () {
      function slugify(s) {
        return String(s).trim().toLowerCase()
          .replace(/[^\\p{L}\\p{N}\\s-]/gu, "")
          .replace(/\\s+/g, "-")
          .replace(/-+/g, "-") || "section";
      }

      const md = window.markdownit({
        html: true,
        linkify: true,
        typographer: true,
        breaks: false,
        highlight: function (str, lang) {
          if (lang === "mermaid") {
            return '<div class="mermaid">' + md.utils.escapeHtml(str) + '</div>';
          }
          if (window.hljs) {
            try {
              if (lang && hljs.getLanguage(lang)) {
                return '<pre class="hljs"><code>' + hljs.highlight(str, { language: lang, ignoreIllegals: true }).value + '</code></pre>';
              }
              return '<pre class="hljs"><code>' + hljs.highlightAuto(str).value + '</code></pre>';
            } catch (_) {}
          }
          return '<pre><code>' + md.utils.escapeHtml(str) + '</code></pre>';
        }
      });
      if (window.markdownitFootnote) md.use(window.markdownitFootnote);
      if (window.markdownitTaskLists) md.use(window.markdownitTaskLists, { enabled: false, label: true });
      if (window.markdownItAnchor) md.use(window.markdownItAnchor, { slugify });
      if (window.texmath && window.katex) md.use(window.texmath, { engine: window.katex, delimiters: "dollars", katexOptions: { throwOnError: false } });

      md.core.ruler.push("vellum_source_lines", function (state) {
        state.tokens.forEach(function (token) {
          if (token.map && token.nesting !== -1) {
            token.attrSet("data-source-line", String(token.map[0] + 1));
          }
        });
      });

      const content = document.getElementById("content");
      content.innerHTML = md.render(window.vellumMarkdownSource || "");
      if (window.mermaid) {
        mermaid.initialize({ startOnLoad: false, theme: "dark" });
        mermaid.run({ querySelector: ".mermaid" }).catch(function () {});
      }

      let matches = [];
      let activeMatch = -1;

      function sourceLineElements() {
        return Array.from(document.querySelectorAll("[data-source-line]"))
          .map(function (el) { return { el: el, line: Number(el.getAttribute("data-source-line")) || 1 }; })
          .sort(function (a, b) { return a.line - b.line; });
      }

      window.vellumJumpToLine = function (line) {
        const targetLine = Math.max(1, Math.min(Number(line) || 1, window.vellumLineCount || 1));
        const elements = sourceLineElements();
        let target = elements[0] && elements[0].el;
        for (const item of elements) {
          if (item.line <= targetLine) target = item.el;
          else break;
        }
        if (target) {
          target.scrollIntoView({ block: "start" });
          target.animate([{ backgroundColor: "rgba(125,207,255,0.22)" }, { backgroundColor: "transparent" }], { duration: 650 });
        } else {
          window.scrollTo(0, 0);
        }
      };

      window.vellumSnapshot = function () {
        return { y: window.scrollY, line: window.vellumCurrentLine(), fontScale: Number(document.documentElement.dataset.fontScale || "1") };
      };

      window.vellumRestore = function (snapshot) {
        if (!snapshot) return;
        if (snapshot.fontScale) window.vellumSetFontScale(snapshot.fontScale);
        if (typeof snapshot.y === "number") window.scrollTo(0, snapshot.y);
        else if (snapshot.line) window.vellumJumpToLine(snapshot.line);
      };

      window.vellumCurrentLine = function () {
        const y = window.scrollY + 48;
        let current = 1;
        for (const item of sourceLineElements()) {
          if (item.el.getBoundingClientRect().top + window.scrollY <= y) current = item.line;
          else break;
        }
        return current;
      };

      window.vellumScrollBy = function (x, y) { window.scrollBy(x || 0, y || 0); };
      window.vellumPageBy = function (delta) { window.scrollBy(0, (delta || 1) * window.innerHeight * 0.86); };
      window.vellumFirst = function () { window.scrollTo(0, 0); };
      window.vellumLast = function () { window.scrollTo(0, document.documentElement.scrollHeight); };
      window.vellumSetFontScale = function (scale) {
        const next = Math.max(0.78, Math.min(1.65, Number(scale) || 1));
        document.documentElement.dataset.fontScale = String(next);
        document.body.style.fontSize = (15 * next) + "px";
      };
      window.vellumZoomBy = function (factor) {
        window.vellumSetFontScale((Number(document.documentElement.dataset.fontScale || "1")) * (Number(factor) || 1));
      };
      window.vellumSelectedText = function () {
        const selection = String(window.getSelection ? window.getSelection() : "").trim();
        if (selection) return selection;
        if (matches[activeMatch]) return matches[activeMatch].textContent.trim();
        return "";
      };
      window.vellumContext = function () {
        const line = window.vellumCurrentLine();
        const selected = window.vellumSelectedText();
        const active = matches[activeMatch] || null;
        const el = active || document.elementFromPoint(Math.floor(window.innerWidth / 2), 80) || document.body;
        const block = el.closest("p,li,blockquote,pre,table,h1,h2,h3,h4,h5,h6") || el;
        const section = Array.from(document.querySelectorAll("h1,h2,h3,h4,h5,h6")).reverse().find(function (h) {
          return h.getBoundingClientRect().top <= 72;
        });
        return { selectedText: selected, line: line, currentParagraph: block.innerText || "", outlineTitle: section ? section.innerText : "", nearbyText: (block.parentElement ? block.parentElement.innerText : document.body.innerText).slice(0, 5000) };
      };
      window.vellumClearSelection = function () {
        if (window.getSelection) window.getSelection().removeAllRanges();
      };

      function clearSearch() {
        document.querySelectorAll("mark.md-search-match").forEach(function (mark) {
          const text = document.createTextNode(mark.textContent);
          mark.replaceWith(text);
        });
        document.normalize();
        matches = [];
        activeMatch = -1;
      }

      function walkTextNodes(root) {
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
          acceptNode: function (node) {
            if (!node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
            if (node.parentElement && node.parentElement.closest("script,style,mark.md-search-match")) return NodeFilter.FILTER_REJECT;
            return NodeFilter.FILTER_ACCEPT;
          }
        });
        const nodes = [];
        while (walker.nextNode()) nodes.push(walker.currentNode);
        return nodes;
      }

      window.vellumSearch = function (query) {
        clearSearch();
        const q = String(query || "").trim();
        if (!q) return { count: 0, active: 0 };
        const lower = q.toLowerCase();
        walkTextNodes(content).forEach(function (node) {
          const text = node.nodeValue;
          let index = text.toLowerCase().indexOf(lower);
          if (index < 0) return;
          const fragment = document.createDocumentFragment();
          let cursor = 0;
          while (index >= 0) {
            fragment.appendChild(document.createTextNode(text.slice(cursor, index)));
            const mark = document.createElement("mark");
            mark.className = "md-search-match";
            mark.textContent = text.slice(index, index + q.length);
            fragment.appendChild(mark);
            cursor = index + q.length;
            index = text.toLowerCase().indexOf(lower, cursor);
          }
          fragment.appendChild(document.createTextNode(text.slice(cursor)));
          node.replaceWith(fragment);
        });
        matches = Array.from(document.querySelectorAll("mark.md-search-match"));
        activeMatch = matches.length ? 0 : -1;
        activateMatch();
        return { count: matches.length, active: activeMatch + 1 };
      };

      function activateMatch() {
        matches.forEach(function (m) { m.classList.remove("active"); });
        if (matches[activeMatch]) {
          matches[activeMatch].classList.add("active");
          matches[activeMatch].scrollIntoView({ block: "center" });
        }
      }

      window.vellumSearchMove = function (delta) {
        if (!matches.length) return { count: 0, active: 0 };
        activeMatch = (activeMatch + delta + matches.length) % matches.length;
        activateMatch();
        return { count: matches.length, active: activeMatch + 1 };
      };

      window.vellumMaterializeSearchSelection = function () {
        const match = matches[activeMatch];
        if (!match || !window.getSelection) return "";
        const range = document.createRange();
        range.selectNodeContents(match);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        return selection.toString();
      };

      window.vellumClearSearch = clearSearch;

      let notifySnapshot = function () {
        if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.vellumSnapshotChanged) return;
        window.webkit.messageHandlers.vellumSnapshotChanged.postMessage(window.vellumSnapshot());
      };
      let throttledSnapshot = (function () {
        let pending = false;
        return function () {
          if (pending) return;
          pending = true;
          window.requestAnimationFrame(function () {
            pending = false;
            notifySnapshot();
          });
        };
      })();
      window.addEventListener("scroll", throttledSnapshot, { passive: true });
      window.addEventListener("load", notifySnapshot);
    })();
    """
}

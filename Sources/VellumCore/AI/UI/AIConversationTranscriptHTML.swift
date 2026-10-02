enum AIConversationTranscriptHTML {
    static let document = #"""
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <script>
        window.MathJax = {
          tex: { inlineMath: [['$', '$'], ['\\(', '\\)']], displayMath: [['$$', '$$'], ['\\[', '\\]']] },
          options: { skipHtmlTags: ['script','noscript','style','textarea','pre','code'] }
        };
      </script>
      <script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js"></script>
      <style>
        :root { color-scheme: dark; }
        html, body {
          margin: 0;
          padding: 0;
          background: transparent;
          color: \#(TokyoNight.cssHex(TokyoNight.foreground));
          font: 13px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          line-height: 1.55;
          overflow-y: auto;
          scrollbar-width: none;
        }
        html::-webkit-scrollbar,
        body::-webkit-scrollbar,
        *::-webkit-scrollbar {
          width: 0;
          height: 0;
          display: none;
        }
        body { box-sizing: border-box; }
        #content {
          padding: 14px;
          box-sizing: border-box;
        }
        .messages {
          display: flex;
          flex-direction: column;
          gap: 14px;
        }
        .row {
          display: flex;
          width: 100%;
          box-sizing: border-box;
        }
        .row.user {
          justify-content: flex-end;
        }
        .row.assistant,
        .row.error {
          justify-content: flex-start;
        }
        .user-bubble {
          max-width: calc(100% - 68px);
          box-sizing: border-box;
          padding: 9px 12px;
          border: 1px solid \#(TokyoNight.cssHex(TokyoNight.border));
          border-radius: 8px;
          background: \#(TokyoNight.cssHex(TokyoNight.selection));
          color: \#(TokyoNight.cssHex(TokyoNight.foreground));
          white-space: pre-wrap;
          overflow-wrap: anywhere;
        }
        .assistant-markdown {
          width: 100%;
          box-sizing: border-box;
          color: \#(TokyoNight.cssHex(TokyoNight.foreground));
          overflow-wrap: anywhere;
        }
        .assistant-markdown > :first-child { margin-top: 0; }
        .assistant-markdown > :last-child { margin-bottom: 0; }
        .thinking {
          color: \#(TokyoNight.cssHex(TokyoNight.muted));
          font-style: italic;
          margin: 0;
        }
        h1, h2, h3 {
          color: \#(TokyoNight.cssHex(TokyoNight.foreground));
          margin: 0.8em 0 0.35em;
          line-height: 1.25;
          font-weight: 650;
        }
        h1 { font-size: 16px; }
        h2 { font-size: 15px; }
        h3 { font-size: 14px; }
        p { margin: 0 0 0.72em; }
        ul, ol {
          margin: 0 0 0.82em 1.25em;
          padding: 0;
        }
        li { margin: 0.18em 0; }
        blockquote {
          margin: 0.7em 0;
          padding: 0.2em 0 0.2em 0.8em;
          border-left: 2px solid \#(TokyoNight.cssHex(TokyoNight.blue));
          color: \#(TokyoNight.cssHex(TokyoNight.muted));
        }
        code {
          background: \#(TokyoNight.cssHex(TokyoNight.background));
          color: \#(TokyoNight.cssHex(TokyoNight.cyan));
          padding: 1px 4px;
          border-radius: 4px;
          font-family: "SF Mono", Menlo, monospace;
          font-size: 12px;
        }
        pre {
          background: \#(TokyoNight.cssHex(TokyoNight.background));
          border: 1px solid \#(TokyoNight.cssHex(TokyoNight.border));
          border-radius: 7px;
          padding: 10px;
          overflow-x: auto;
          scrollbar-width: none;
        }
        pre code {
          background: transparent;
          padding: 0;
        }
        strong { color: \#(TokyoNight.cssHex(TokyoNight.foreground)); }
        em { color: \#(TokyoNight.cssHex(TokyoNight.foreground)); }
        a { color: \#(TokyoNight.cssHex(TokyoNight.blue)); }
        .math-display {
          margin: 0.85em 0;
          overflow-x: auto;
          scrollbar-width: none;
        }
        mjx-container {
          color: \#(TokyoNight.cssHex(TokyoNight.foreground));
        }
        .error-bubble {
          box-sizing: border-box;
          max-width: 100%;
          padding: 8px 11px;
          border: 1px solid \#(TokyoNight.cssHex(TokyoNight.red))61;
          border-radius: 7px;
          background: \#(TokyoNight.cssHex(TokyoNight.red))1C;
          color: \#(TokyoNight.cssHex(TokyoNight.red));
          white-space: pre-wrap;
        }
      </style>
    </head>
    <body>
      <main id="content"><div class="messages"></div></main>
      <script>
        function escapeHTML(value) {
          return String(value || '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
        }
        function safeLinkURL(href) {
          try {
            const url = new URL(href);
            return ['http:', 'https:', 'mailto:'].includes(url.protocol) ? url : null;
          } catch (_) { return null; }
        }
        // MathJax can add anchors after Markdown has rendered.
        document.addEventListener('click', function(event) {
          const anchor = event.target.closest && event.target.closest('a');
          if (!anchor) { return; }
          const href = anchor.getAttribute('href') || anchor.getAttribute('xlink:href');
          const url = safeLinkURL(href);
          if (url) {
            anchor.setAttribute('href', url.href);
            anchor.removeAttribute('xlink:href');
          } else {
            anchor.removeAttribute('href');
            anchor.removeAttribute('xlink:href');
            event.preventDefault();
            event.stopImmediatePropagation();
          }
        }, true);
        function restoreTokens(value, tokens) {
          for (const token of tokens) {
            value = value.split(token.placeholder).join(token.html);
          }
          return value;
        }
        function protectInlineMath(value, tokenPrefix) {
          const tokens = [];
          value = value.replace(/(\\\([\s\S]*?\\\)|\$[^\n$]+\$)/g, (match, _group, offset, source) => {
            if (match.startsWith('$') && (source[offset - 1] === '$' || source[offset + match.length] === '$')) {
              return match;
            }
            const placeholder = `${tokenPrefix}INLINE_MATH_${tokens.length}@@`;
            tokens.push({ placeholder, html: match });
            return placeholder;
          });
          return { value, tokens };
        }
        function inlineMarkdown(value, tokenPrefix) {
          const protectedMath = protectInlineMath(value, tokenPrefix);
          value = protectedMath.value
            .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
            .replace(/\*([^*]+)\*/g, '<em>$1</em>')
            .replace(/\[([^\]]+)\]\(([^\)]+)\)/g, (_, label, href) => {
              if (safeLinkURL(href)) {
                // Keep Markdown token restoration out of link destinations.
                return `<a href="${href.replace(/@/g, '&#64;')}">${label}</a>`;
              }
              return label;
            });
          return restoreTokens(value, protectedMath.tokens);
        }
        function renderMarkdown(markdown) {
          const blocks = [];
          const inlineCodes = [];
          let text = escapeHTML(markdown || '');
          let tokenPrefix = '@@';
          while (text.includes(tokenPrefix)) { tokenPrefix += '@'; }
          const blockPattern = new RegExp(`^${tokenPrefix}BLOCK_[0-9]+@@$`);
          function stashBlock(html) {
            const placeholder = `${tokenPrefix}BLOCK_${blocks.length}@@`;
            blocks.push({ placeholder, html });
            return placeholder;
          }

          text = text.replace(/```[^\n]*\n([\s\S]*?)```/g, (_, code) => {
            return stashBlock(`<pre><code>${code.trim()}</code></pre>`);
          });
          text = text.replace(/`([^`\n]+)`/g, (_, code) => {
            const placeholder = `${tokenPrefix}INLINE_CODE_${inlineCodes.length}@@`;
            inlineCodes.push({ placeholder, html: `<code>${code}</code>` });
            return placeholder;
          });
          text = text.replace(/(\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\])/g, match => {
            return stashBlock(`<div class="math-display">${match}</div>`);
          });

          const lines = text.split(/\n/);
          let html = '';
          let list = null;
          function closeList() {
            if (list) { html += `</${list}>`; list = null; }
          }

          for (const raw of lines) {
            const line = raw.trim();
            if (!line) { closeList(); continue; }
            if (blockPattern.test(line)) {
              closeList();
              html += line;
              continue;
            }

            let match;
            if ((match = line.match(/^(#{1,3})\s+(.+)$/))) {
              closeList();
              html += `<h${match[1].length}>${inlineMarkdown(match[2], tokenPrefix)}</h${match[1].length}>`;
            } else if ((match = line.match(/^[-*]\s+(.+)$/))) {
              if (list !== 'ul') { closeList(); html += '<ul>'; list = 'ul'; }
              html += `<li>${inlineMarkdown(match[1], tokenPrefix)}</li>`;
            } else if ((match = line.match(/^\d+\.\s+(.+)$/))) {
              if (list !== 'ol') { closeList(); html += '<ol>'; list = 'ol'; }
              html += `<li>${inlineMarkdown(match[1], tokenPrefix)}</li>`;
            } else if ((match = line.match(/^&gt;\s*(.+)$/))) {
              closeList();
              html += `<blockquote>${inlineMarkdown(match[1], tokenPrefix)}</blockquote>`;
            } else {
              closeList();
              html += `<p>${inlineMarkdown(line, tokenPrefix)}</p>`;
            }
          }
          closeList();
          return restoreTokens(restoreTokens(html, blocks), inlineCodes);
        }
        function renderMessage(message, thinkingText) {
          const role = message.role || 'assistant';
          const content = String(message.content || '');
          if (role === 'user') {
            return `<div class="row user"><div class="user-bubble">${escapeHTML(content).replace(/\n/g, '<br>')}</div></div>`;
          }
          const body = content.trim()
            ? renderMarkdown(content)
            : `<p class="thinking">${escapeHTML(thinkingText || 'Thinking...')}</p>`;
          return `<div class="row assistant"><div class="assistant-markdown">${body}</div></div>`;
        }
        window.vellumSetConversation = function(payload, followBottom) {
          const content = document.getElementById('content');
          const messages = Array.isArray(payload && payload.messages) ? payload.messages : [];
          const thinkingText = payload && payload.thinkingText ? payload.thinkingText : 'Thinking...';
          const previousScrollY = window.scrollY || window.pageYOffset || 0;
          const wasNearBottom = isNearBottom();
          let html = `<div class="messages">${messages.map(message => renderMessage(message, thinkingText)).join('')}`;
          if (payload && payload.errorMessage) {
            html += `<div class="row error"><div class="error-bubble">${escapeHTML(payload.errorMessage)}</div></div>`;
          }
          html += '</div>';
          content.innerHTML = html;
          requestAnimationFrame(() => afterRender(followBottom, wasNearBottom, previousScrollY));
          if (window.MathJax && window.MathJax.typesetPromise) {
            window.MathJax.typesetPromise([content])
              .then(() => { afterRender(followBottom, wasNearBottom, previousScrollY); })
              .catch(() => { afterRender(followBottom, wasNearBottom, previousScrollY); });
          }
        };
        function afterRender(followBottom, wasNearBottom, previousScrollY) {
          reportContentHeight();
          if ((followBottom || wasNearBottom) && isContentOverflowing()) {
            scrollToBottom();
            requestAnimationFrame(scrollToBottom);
          } else {
            restoreScrollPosition(previousScrollY);
            requestAnimationFrame(() => restoreScrollPosition(previousScrollY));
          }
        }
        function isContentOverflowing() {
          const height = Math.max(
            document.documentElement.scrollHeight,
            document.body.scrollHeight
          );
          return height - window.innerHeight > 8;
        }
        function isNearBottom() {
          const height = Math.max(
            document.documentElement.scrollHeight,
            document.body.scrollHeight
          );
          const maxScroll = Math.max(0, height - window.innerHeight);
          const currentScroll = window.scrollY || window.pageYOffset || 0;
          return maxScroll - currentScroll <= 10;
        }
        function scrollToBottom() {
          const height = Math.max(
            document.documentElement.scrollHeight,
            document.body.scrollHeight
          );
          const maxScroll = Math.max(0, height - window.innerHeight);
          window.scrollTo(0, maxScroll <= 8 ? 0 : maxScroll);
        }
        function restoreScrollPosition(previousScrollY) {
          const height = Math.max(
            document.documentElement.scrollHeight,
            document.body.scrollHeight
          );
          const maxScroll = Math.max(0, height - window.innerHeight);
          window.scrollTo(0, Math.max(0, Math.min(previousScrollY, maxScroll)));
        }
        function postVellumMessage(message) {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vellumConversation) {
            window.webkit.messageHandlers.vellumConversation.postMessage(message);
          }
        }
        function reportContentHeight() {
          const content = document.getElementById('content');
          const height = content ? content.getBoundingClientRect().height : 0;
          postVellumMessage({ command: 'contentHeight', height: Math.ceil(height) });
        }
        window.addEventListener('resize', reportContentHeight);
      </script>
    </body>
    </html>
    """#
}

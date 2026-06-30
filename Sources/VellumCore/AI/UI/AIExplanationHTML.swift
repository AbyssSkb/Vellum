enum AIExplanationHTML {
    static let document = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <script>
        window.MathJax = {
          tex: { inlineMath: [['$', '$'], ['\\\\(', '\\\\)']], displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']] },
          options: { skipHtmlTags: ['script','noscript','style','textarea','pre','code'] }
        };
      </script>
      <script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js"></script>
      <style>
        :root { color-scheme: dark; }
        html, body {
          margin: 0;
          padding: 0;
          background: #292E42;
          color: #C0CAF5;
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
        body { padding: 0 14px; box-sizing: border-box; }
        #content {
          padding: 18px 0;
          box-sizing: border-box;
        }
        #content > :first-child { margin-top: 0; }
        #content > :last-child { margin-bottom: 0; }
        h1, h2, h3 { color: #E0E7FF; margin: 0.8em 0 0.35em; line-height: 1.25; }
        h1 { font-size: 18px; } h2 { font-size: 16px; } h3 { font-size: 14px; }
        p { margin: 0 0 0.75em; }
        ul, ol { margin: 0 0 0.85em 1.25em; padding: 0; }
        li { margin: 0.2em 0; }
        blockquote {
          margin: 0.7em 0;
          padding: 0.2em 0 0.2em 0.8em;
          border-left: 3px solid #7AA2F7;
          color: #A9B1D6;
        }
        code {
          background: #1A1B26;
          color: #7DCFFF;
          padding: 1px 4px;
          border-radius: 4px;
          font-family: "SF Mono", Menlo, monospace;
          font-size: 12px;
        }
        pre {
          background: #1A1B26;
          border: 1px solid #3B4261;
          border-radius: 7px;
          padding: 10px;
          overflow-x: auto;
          scrollbar-width: none;
        }
        pre code { background: transparent; padding: 0; }
        strong { color: #E0E7FF; }
        a { color: #7AA2F7; }
        .empty { color: #565F89; }
        .heading-row {
          display: inline-flex;
          align-items: center;
          gap: 7px;
        }
        .speak-button {
          appearance: none;
          width: 22px;
          height: 22px;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          margin: -2px 0 0 1px;
          padding: 0;
          border: 1px solid #3B4261;
          border-radius: 6px;
          background: #24283B;
          color: #7DCFFF;
          font: 12px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          line-height: 1;
          cursor: default;
        }
        .speak-button:hover {
          border-color: #7AA2F7;
          color: #C0CAF5;
          background: #33467C;
        }
        .speak-button:active {
          transform: translateY(1px);
        }
      </style>
    </head>
    <body>
      <main id="content" class="empty">...</main>
      <script>
        const scrollState = {
          direction: 0,
          frame: null,
          lastTime: 0,
          velocity: 672
        };
        var pronunciationSpeechText = '';
        var pronunciationSpeakTitle = 'Speak pronunciation';
        function tickScroll(now) {
          if (!scrollState.direction) { return; }
          const previous = scrollState.lastTime || now;
          const deltaSeconds = Math.min(0.05, Math.max(0, (now - previous) / 1000));
          scrollState.lastTime = now;
          window.scrollBy(0, scrollState.direction * scrollState.velocity * deltaSeconds);
          scrollState.frame = requestAnimationFrame(tickScroll);
        }
        window.vellumStartScroll = function(direction) {
          direction = direction < 0 ? -1 : 1;
          if (scrollState.direction === direction && scrollState.frame !== null) { return; }
          window.vellumStopScroll();
          scrollState.direction = direction;
          scrollState.lastTime = performance.now();
          window.scrollBy(0, direction * 28);
          scrollState.frame = requestAnimationFrame(tickScroll);
        };
        window.vellumStopScroll = function() {
          scrollState.direction = 0;
          scrollState.lastTime = 0;
          if (scrollState.frame !== null) {
            cancelAnimationFrame(scrollState.frame);
            scrollState.frame = null;
          }
        };
        window.vellumPulseScroll = function(direction) {
          direction = direction < 0 ? -1 : 1;
          window.scrollBy(0, direction * 28);
        };
        function escapeHTML(value) {
          return value.replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
        }
        function inlineMarkdown(value) {
          return value
            .replace(/`([^`]+)`/g, '<code>$1</code>')
            .replace(/\\*\\*([^*]+)\\*\\*/g, '<strong>$1</strong>')
            .replace(/\\*([^*]+)\\*/g, '<em>$1</em>')
            .replace(/\\[([^\\]]+)\\]\\(([^\\)]+)\\)/g, '<a href="$2">$1</a>');
        }
        function isPronunciationHeading(value) {
          const normalized = value
            .replace(/<[^>]*>/g, '')
            .replace(/[:：]\\s*$/, '')
            .trim()
            .toLowerCase();
          return normalized === '音标'
            || normalized === 'pronunciation'
            || normalized === 'reading';
        }
        function speakButtonHTML() {
          if (!pronunciationSpeechText.trim()) { return ''; }
          const title = escapeHTML(pronunciationSpeakTitle || 'Speak pronunciation');
          return `<button class="speak-button" type="button" title="${title}" aria-label="${title}" onclick="postVellumCommand('speakPronunciation')">▶</button>`;
        }
        function renderMarkdown(markdown) {
          const fenceMap = [];
          let text = escapeHTML(markdown || '...');
          text = text.replace(/```([\\s\\S]*?)```/g, (_, code) => {
            const token = `@@CODE_${fenceMap.length}@@`;
            fenceMap.push(`<pre><code>${code.trim()}</code></pre>`);
            return token;
          });
          const lines = text.split(/\\n/);
          let html = '';
          let list = null;
          function closeList() {
            if (list) { html += `</${list}>`; list = null; }
          }
          for (const raw of lines) {
            const line = raw.trim();
            if (!line) { closeList(); continue; }
            let match;
            if ((match = line.match(/^(#{1,3})\\s+(.+)$/))) {
              closeList();
              const heading = inlineMarkdown(match[2]);
              const action = isPronunciationHeading(match[2]) ? speakButtonHTML() : '';
              html += `<h${match[1].length}><span class="heading-row">${heading}${action}</span></h${match[1].length}>`;
            } else if ((match = line.match(/^[-*]\\s+(.+)$/))) {
              if (list !== 'ul') { closeList(); html += '<ul>'; list = 'ul'; }
              html += `<li>${inlineMarkdown(match[1])}</li>`;
            } else if ((match = line.match(/^\\d+\\.\\s+(.+)$/))) {
              if (list !== 'ol') { closeList(); html += '<ol>'; list = 'ol'; }
              html += `<li>${inlineMarkdown(match[1])}</li>`;
            } else if ((match = line.match(/^&gt;\\s*(.+)$/))) {
              closeList();
              html += `<blockquote>${inlineMarkdown(match[1])}</blockquote>`;
            } else {
              closeList();
              html += `<p>${inlineMarkdown(line)}</p>`;
            }
          }
          closeList();
          for (let i = 0; i < fenceMap.length; i++) {
            html = html.replace(`@@CODE_${i}@@`, fenceMap[i]);
          }
          return html;
        }
        window.vellumSetMarkdown = function(markdown, followBottom) {
          const content = document.getElementById('content');
          content.className = markdown && markdown.trim() ? '' : 'empty';
          content.innerHTML = renderMarkdown(markdown);
          requestAnimationFrame(() => afterRender(followBottom));
          if (window.MathJax && window.MathJax.typesetPromise) {
            window.MathJax.typesetPromise([content])
              .then(() => { afterRender(followBottom); })
              .catch(() => { afterRender(followBottom); });
          }
        };
        window.vellumSetPronunciationSpeech = function(text, title) {
          pronunciationSpeechText = text || '';
          pronunciationSpeakTitle = title || 'Speak pronunciation';
        };
        function afterRender(followBottom) {
          reportContentHeight();
          if (followBottom && isContentOverflowing()) {
            scrollToBottom();
            requestAnimationFrame(scrollToBottom);
          }
        }
        function isContentOverflowing() {
          const height = Math.max(
            document.documentElement.scrollHeight,
            document.body.scrollHeight
          );
          return height - window.innerHeight > 8;
        }
        function scrollToTop() {
          window.scrollTo(0, 0);
        }
        function scrollToBottom() {
          const height = Math.max(
            document.documentElement.scrollHeight,
            document.body.scrollHeight
          );
          const maxScroll = Math.max(0, height - window.innerHeight);
          window.scrollTo(0, maxScroll <= 8 ? 0 : maxScroll);
        }
        window.vellumScrollToTop = function() {
          scrollToTop();
          requestAnimationFrame(scrollToTop);
        };
        window.vellumScrollToBottom = function() {
          scrollToBottom();
          requestAnimationFrame(scrollToBottom);
        };
        function postVellumCommand(command) {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vellum) {
            window.webkit.messageHandlers.vellum.postMessage(command);
          }
        }
        function postVellumMessage(message) {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vellum) {
            window.webkit.messageHandlers.vellum.postMessage(message);
          }
        }
        function reportContentHeight() {
          const content = document.getElementById('content');
          const bodyStyle = window.getComputedStyle(document.body);
          const paddingTop = parseFloat(bodyStyle.paddingTop) || 0;
          const paddingBottom = parseFloat(bodyStyle.paddingBottom) || 0;
          const contentHeight = content ? content.getBoundingClientRect().height : 0;
          const height = contentHeight + paddingTop + paddingBottom;
          postVellumMessage({ command: 'contentHeight', height: Math.ceil(height) });
        }
        document.addEventListener('keydown', function(event) {
          if (event.metaKey || event.ctrlKey || event.altKey) { return; }

          if (event.key === 'j') {
            event.preventDefault();
            postVellumCommand('startScrollDown');
          } else if (event.key === 'k') {
            event.preventDefault();
            postVellumCommand('startScrollUp');
          } else if (event.key === 'm') {
            event.preventDefault();
            postVellumCommand('highlight');
          } else if (event.key === 'c') {
            event.preventDefault();
            postVellumCommand('cycleColor');
          } else if (event.key === 'Escape') {
            event.preventDefault();
            postVellumCommand('dismiss');
          }
        }, true);
        document.addEventListener('keyup', function(event) {
          if (event.metaKey || event.ctrlKey || event.altKey) { return; }

          if (event.key === 'j' || event.key === 'k') {
            event.preventDefault();
            postVellumCommand('stopScroll');
          }
        }, true);
        window.addEventListener('blur', function() {
          postVellumCommand('stopScroll');
        });
        window.addEventListener('resize', reportContentHeight);
      </script>
    </body>
    </html>
    """
}

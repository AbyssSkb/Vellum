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
          background: transparent;
          color: \(VellumColors.cssHex(VellumColors.foreground));
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
        h1, h2, h3 { color: \(VellumColors.cssHex(VellumColors.foreground)); margin: 0.8em 0 0.35em; line-height: 1.25; }
        h1 { font-size: 18px; } h2 { font-size: 16px; } h3 { font-size: 14px; }
        p { margin: 0 0 0.75em; }
        .loading-row {
          min-height: 28px;
          display: flex;
          align-items: center;
          gap: 9px;
          color: \(VellumColors.cssHex(VellumColors.muted));
          font-size: 12.5px;
          line-height: 1;
        }
        .loading-spinner {
          width: 13px;
          height: 13px;
          border: 1.5px solid \(VellumColors.cssHex(VellumColors.border));
          border-top-color: \(VellumColors.cssHex(VellumColors.blue));
          border-radius: 50%;
          animation: vellum-spin 0.8s linear infinite;
          flex: none;
        }
        .loading-model {
          display: inline-flex;
          align-items: center;
          min-height: 16px;
          color: \(VellumColors.cssHex(VellumColors.foreground));
          font-weight: 600;
          line-height: 1;
        }
        @keyframes vellum-spin {
          to { transform: rotate(360deg); }
        }
        .pronunciation-line {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          column-gap: 8px;
          row-gap: 5px;
        }
        ul, ol { margin: 0 0 0.85em 1.25em; padding: 0; }
        li { margin: 0.2em 0; }
        blockquote {
          margin: 0.7em 0;
          padding: 0.2em 0 0.2em 0.8em;
          border-left: 2px solid \(VellumColors.cssHex(VellumColors.blue));
          color: \(VellumColors.cssHex(VellumColors.muted));
        }
        code {
          background: \(VellumColors.cssHex(VellumColors.background));
          color: \(VellumColors.cssHex(VellumColors.foreground));
          padding: 1px 4px;
          border-radius: 4px;
          font-family: "SF Mono", Menlo, monospace;
          font-size: 12px;
        }
        pre {
          background: \(VellumColors.cssHex(VellumColors.background));
          border: 1px solid \(VellumColors.cssHex(VellumColors.border));
          border-radius: 7px;
          padding: 10px;
          overflow-x: auto;
          scrollbar-width: none;
        }
        pre code { background: transparent; padding: 0; }
        strong { color: \(VellumColors.cssHex(VellumColors.foreground)); }
        a { color: \(VellumColors.cssHex(VellumColors.blue)); }
        .math-display {
          margin: 0.85em 0;
          overflow-x: auto;
          scrollbar-width: none;
        }
        mjx-container { color: \(VellumColors.cssHex(VellumColors.foreground)); }
        .empty { color: \(VellumColors.cssHex(VellumColors.muted)); }
        .heading-row {
          display: inline-flex;
          align-items: center;
          gap: 7px;
        }
        .speak-button {
          appearance: none;
          min-width: 24px;
          height: 20px;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          margin: 0;
          padding: 0 6px;
          border: 1px solid \(VellumColors.cssHex(VellumColors.border));
          border-radius: 5px;
          background: \(VellumColors.cssHex(VellumColors.background));
          color: \(VellumColors.cssHex(VellumColors.foreground));
          font: 11px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          font-weight: 600;
          line-height: 1;
          cursor: default;
        }
        .speak-button:hover {
          border-color: \(VellumColors.cssHex(VellumColors.blue));
          color: \(VellumColors.cssHex(VellumColors.foreground));
          background: \(VellumColors.cssHex(VellumColors.selection));
        }
        .speak-button:active {
          transform: translateY(1px);
        }
        .speak-actions {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          flex: none;
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
        var pronunciationSpeakUSTitle = 'Speak American pronunciation';
        var pronunciationSpeakUKTitle = 'Speak British pronunciation';
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
        \(AIMarkdownJavaScript.source)
        function loadingHTML(markdown) {
          if (!markdown || !markdown.startsWith('vellum-loading:')) { return null; }
          try {
            const payload = JSON.parse(markdown.slice('vellum-loading:'.length) || '{}');
            const provider = escapeHTML(payload.provider || '');
            const model = escapeHTML(payload.model || '');
            const label = [provider, model].filter(Boolean).join(' · ');
            return `<div class="loading-row"><span class="loading-spinner" aria-hidden="true"></span><span class="loading-model">${label || 'AI'}</span></div>`;
          } catch (_) {
            return `<div class="loading-row"><span class="loading-spinner" aria-hidden="true"></span><span class="loading-model">AI</span></div>`;
          }
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
          const usTitle = escapeHTML(pronunciationSpeakUSTitle || 'Speak American pronunciation');
          const ukTitle = escapeHTML(pronunciationSpeakUKTitle || 'Speak British pronunciation');
          return `<span class="speak-actions"><button class="speak-button" type="button" title="${usTitle}" aria-label="${usTitle}" onclick="postVellumCommand('speakPronunciationUS')">US</button><button class="speak-button" type="button" title="${ukTitle}" aria-label="${ukTitle}" onclick="postVellumCommand('speakPronunciationUK')">UK</button></span>`;
        }
        function renderExplanationMarkdown(markdown) {
          const loading = loadingHTML(markdown);
          if (loading !== null) { return loading; }
          return renderMarkdown(markdown || '...',
            (heading, level) => `<h${level}><span class="heading-row">${heading}</span></h${level}>`,
            (paragraph, precedingHeading) => {
              const actions = precedingHeading !== null && isPronunciationHeading(precedingHeading) ? speakButtonHTML() : '';
              const className = actions ? ' class="pronunciation-line"' : '';
              return `<p${className}><span>${paragraph}</span>${actions}</p>`;
            });
        }
        window.vellumSetMarkdown = function(markdown, followBottom) {
          const content = document.getElementById('content');
          content.className = markdown && markdown.trim() ? '' : 'empty';
          content.innerHTML = renderExplanationMarkdown(markdown);
          requestAnimationFrame(() => afterRender(followBottom));
          if (window.MathJax && window.MathJax.typesetPromise) {
            window.MathJax.typesetPromise([content])
              .then(() => { afterRender(followBottom); })
              .catch(() => { afterRender(followBottom); });
          }
        };
        window.vellumSetPronunciationSpeech = function(text, usTitle, ukTitle) {
          pronunciationSpeechText = text || '';
          pronunciationSpeakUSTitle = usTitle || 'Speak American pronunciation';
          pronunciationSpeakUKTitle = ukTitle || 'Speak British pronunciation';
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

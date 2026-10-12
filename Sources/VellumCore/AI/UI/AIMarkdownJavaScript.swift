enum AIMarkdownJavaScript {
    static let source = #"""
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
        function renderMarkdown(markdown, renderHeading, renderParagraph) {
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
          let precedingHeading = null;
          function closeList() {
            if (list) { html += `</${list}>`; list = null; }
          }

          for (const raw of lines) {
            const line = raw.trim();
            if (!line) { closeList(); continue; }
            if (blockPattern.test(line)) {
              closeList();
              html += line;
              precedingHeading = null;
              continue;
            }

            let match;
            if ((match = line.match(/^(#{1,3})\s+(.+)$/))) {
              closeList();
              const heading = inlineMarkdown(match[2], tokenPrefix);
              const level = match[1].length;
              html += renderHeading ? renderHeading(heading, level) : `<h${level}>${heading}</h${level}>`;
              precedingHeading = match[2];
            } else if ((match = line.match(/^[-*]\s+(.+)$/))) {
              if (list !== 'ul') { closeList(); html += '<ul>'; list = 'ul'; }
              html += `<li>${inlineMarkdown(match[1], tokenPrefix)}</li>`;
              precedingHeading = null;
            } else if ((match = line.match(/^\d+\.\s+(.+)$/))) {
              if (list !== 'ol') { closeList(); html += '<ol>'; list = 'ol'; }
              html += `<li>${inlineMarkdown(match[1], tokenPrefix)}</li>`;
              precedingHeading = null;
            } else if ((match = line.match(/^&gt;\s*(.+)$/))) {
              closeList();
              html += `<blockquote>${inlineMarkdown(match[1], tokenPrefix)}</blockquote>`;
              precedingHeading = null;
            } else {
              closeList();
              const paragraph = inlineMarkdown(line, tokenPrefix);
              html += renderParagraph ? renderParagraph(paragraph, precedingHeading) : `<p>${paragraph}</p>`;
              precedingHeading = null;
            }
          }
          closeList();
          return restoreTokens(restoreTokens(html, blocks), inlineCodes);
        }
    """#
}

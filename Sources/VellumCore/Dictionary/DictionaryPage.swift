import Foundation
import UniformTypeIdentifiers
import WebKit

enum DictionaryPage {
    static let scheme = "vellum-dictionary"
    static let host = "dictionary"

    static func entryURL(id: UUID) -> URL {
        URL(string: "\(scheme)://\(host)/index.html?\(id.uuidString)")!
    }

    static func isEntryURL(_ url: URL?, id: UUID) -> Bool {
        guard let url else { return false }
        return url.scheme == scheme && url.host == host && url.path == "/index.html" && url.query == id.uuidString
    }

    static func link(_ raw: String) -> (kind: String, value: String, anchor: String?)? {
        guard raw.utf8.count <= 8_192,
              let separator = raw.range(of: "://") else { return nil }
        let kind = raw[..<separator.lowerBound].lowercased()
        guard kind == "entry" || kind == "sound" else { return nil }
        let remainder = String(raw[separator.upperBound...])
        if kind == "sound" {
            return (kind, remainder, nil)
        }
        let parts = remainder.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let word = String(parts[0]).removingPercentEncoding ?? String(parts[0])
        guard !word.isEmpty else { return nil }
        let anchor = parts.count > 1 ? String(parts[1]).removingPercentEncoding ?? String(parts[1]) : nil
        return (kind, word, anchor)
    }

    static func resourcePath(_ url: URL) -> String? {
        guard url.scheme == scheme, url.host == host,
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              !path.contains("\0") else { return nil }
        return path
    }

    static func mimeType(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "js": return "text/javascript"
        case "css": return "text/css"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        default: return UTType(filenameExtension: (path as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }

    @MainActor
    static func document(_ html: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src \(scheme): 'unsafe-inline' 'unsafe-eval'; style-src \(scheme): 'unsafe-inline'; img-src \(scheme): data: blob:; font-src \(scheme): data:; media-src 'none'; connect-src \(scheme):; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
        <style>:root {color-scheme:dark} html,body {margin:0;background:\(VellumColors.cssHex(VellumColors.panel));color:\(VellumColors.cssHex(VellumColors.foreground));font-family:-apple-system,sans-serif} body {padding:12px} </style>
        </head><body>\(html)</body></html>
        """
    }

    static let linkCaptureScript = #"""
    document.addEventListener('click', event => {
      const anchor = event.target.closest?.('a[href]');
      const href = anchor?.getAttribute('href') || '';
      if (!/^(sound|entry):\/\//i.test(href)) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      window.webkit.messageHandlers.dictionary.postMessage(href);
    }, true);
    """#

    static let pronunciationScript = #"""
    (() => {
      const result = {};
      for (const [accent, suffix] of [['american','us'], ['british','uk']]) {
        const links = document.querySelectorAll('.phonetics a.sound.pron-' + suffix + ', .webtop a.sound.pron-' + suffix);
        const link = Array.from(links).find(a => !a.closest('.examples') && !a.classList.contains('app') && !a.classList.contains('app-ext') && /^sound:\/\//i.test(a.getAttribute('href') || ''));
        if (link) result[accent] = link.getAttribute('href');
      }
      return result;
    })();
    """#

    static let presentationScript = #"""
    (() => {
      let pending = false, observedBody = null, previousHeight = -1;
      const requestFrame = window.requestAnimationFrame.bind(window);
      const resizeObserver = new ResizeObserver(schedule);
      function report() {
        pending = false;
        const body = document.body;
        if (!body) return;
        if (observedBody !== body) {
          resizeObserver.disconnect();
          resizeObserver.observe(body);
          observedBody = body;
          document.fonts?.ready.then(schedule);
        }
        if (document.readyState !== 'complete' && Array.from(document.querySelectorAll('link[rel~="stylesheet"]')).some(link => !link.sheet && !link.disabled)) return;
        const style = getComputedStyle(body);
        let bottom = -Infinity;
        function include(rect) {
          if (rect.width > 0 && rect.height > 0) bottom = Math.max(bottom, rect.bottom);
        }
        function measure(node) {
          if (node.nodeType === Node.TEXT_NODE) {
            if (!node.textContent.trim() || getComputedStyle(node.parentElement).visibility !== 'visible') return;
            const range = document.createRange();
            range.selectNodeContents(node);
            Array.from(range.getClientRects()).forEach(include);
          } else if (node.nodeType === Node.ELEMENT_NODE) {
            const childStyle = getComputedStyle(node);
            if (childStyle.display === 'none') return;
            if (childStyle.visibility === 'visible') include(node.getBoundingClientRect());
            // Clipped descendants cannot extend the container's visible bounds.
            if (childStyle.overflowY !== 'visible') return;
            node.childNodes.forEach(measure);
          }
        }
        body.childNodes.forEach(measure);
        if (!Number.isFinite(bottom)) return;
        const height = Math.ceil(bottom + scrollY + (parseFloat(style.paddingBottom) || 0) + (parseFloat(style.marginBottom) || 0));
        if (height !== previousHeight) {
          previousHeight = height;
          window.webkit.messageHandlers.dictionary.postMessage({type: 'layout', height});
        }
        return height;
      }
      function schedule() {
        if (pending) return;
        pending = true;
        queueMicrotask(report);
      }
      window.vellumDictionaryPresentation = {
        async prepare() {
          if (document.readyState !== 'complete') {
            await new Promise(resolve => window.addEventListener('load', resolve, {once: true}));
          }
          await document.fonts.ready;
          return report();
        },
        async paint(anchor) {
          if (anchor) document.getElementById(anchor)?.scrollIntoView();
          const images = Array.from(document.images).filter(image => {
            const rect = image.getBoundingClientRect();
            return image.getClientRects().length && getComputedStyle(image).visibility === 'visible'
              && rect.bottom >= 0 && rect.top <= innerHeight && rect.right >= 0 && rect.left <= innerWidth;
          });
          await Promise.allSettled(images.map(image => image.decode()));
          await document.fonts.ready;
          await new Promise(resolve => requestFrame(() => requestFrame(resolve)));
        }
      };
      new MutationObserver(schedule).observe(document, {subtree: true, childList: true, attributes: true, characterData: true});
      document.addEventListener('readystatechange', schedule);
      window.addEventListener('resize', schedule);
      window.addEventListener('load', schedule, true);
      schedule();
    })();
    """#

    static let scrollScript = #"""
    (() => {
      let frame = null, lastTime = 0;
      let directionX = 0, directionY = 0, targetX = 0, targetY = 0;
      let positionX = 0, positionY = 0;
      function tick(now) {
        const dt = Math.min(0.05, Math.max(0, (now - lastTime) / 1000));
        lastTime = now;
        const speed = 672;
        targetX += directionX * speed * dt;
        targetY += directionY * speed * dt;
        const content = document.scrollingElement;
        targetX = Math.max(0, Math.min(targetX, content.scrollWidth - innerWidth));
        targetY = Math.max(0, Math.min(targetY, content.scrollHeight - innerHeight));
        const settled = !directionX && !directionY && Math.abs(targetX - positionX) < 0.5 && Math.abs(targetY - positionY) < 0.5;
        const progress = settled ? 1 : 1 - Math.exp(-dt / 0.055);
        // Keep fractional progress because WebKit rounds the rendered scroll position.
        positionX += (targetX - positionX) * progress;
        positionY += (targetY - positionY) * progress;
        window.scrollTo({left: positionX, top: positionY, behavior: 'instant'});
        frame = settled ? null : requestAnimationFrame(tick);
      }
      function animate() {
        if (frame !== null) return;
        positionX = scrollX;
        positionY = scrollY;
        lastTime = performance.now();
        frame = requestAnimationFrame(tick);
      }
      function cancel() {
        if (frame !== null) cancelAnimationFrame(frame);
        frame = null;
        directionX = directionY = 0;
        targetX = scrollX;
        targetY = scrollY;
      }
      window.vellumDictionaryScroll = {
        start(x, y) {
          cancel();
          directionX = x;
          directionY = y;
          targetX += x * 72;
          targetY += y * 72;
          animate();
        },
        end() { directionX = directionY = 0; },
        cancel,
        by(x, y) {
          if (frame === null) { targetX = scrollX; targetY = scrollY; }
          directionX = directionY = 0;
          targetX += x;
          targetY += y;
          animate();
        },
        edge(bottom) {
          cancel();
          targetY = bottom ? document.scrollingElement.scrollHeight : 0;
          animate();
        }
      };
      window.addEventListener('wheel', cancel, {passive: true});
      window.addEventListener('blur', cancel);
    })();
    """#
}

@MainActor
final class DictionaryResourceHandler: NSObject, WKURLSchemeHandler {
    var location = URL(fileURLWithPath: "/")
    private var documentURL: URL?
    private var documentData = Data()
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    func setDocument(_ html: String, at url: URL, location: URL) {
        stop()
        self.location = location
        documentURL = url
        documentData = Data(DictionaryPage.document(html).utf8)
    }

    func stop() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask)
        guard let url = urlSchemeTask.request.url,
              let path = DictionaryPage.resourcePath(url) else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }
        let location = location
        let document = url == documentURL ? documentData : nil
        tasks[key] = Task { [weak self] in
            defer { self?.tasks.removeValue(forKey: key) }
            do {
                let data: Data
                let mimeType: String
                if let document {
                    data = document
                    mimeType = "text/html"
                } else {
                    guard let resource = try await DictionaryStore.shared.resource(path, at: location) else {
                        throw URLError(.fileDoesNotExist)
                    }
                    data = resource
                    mimeType = DictionaryPage.mimeType(for: path)
                }
                guard !Task.isCancelled else { return }
                urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: mimeType.hasPrefix("text/") ? "utf-8" : nil))
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                guard !Task.isCancelled else { return }
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }
}

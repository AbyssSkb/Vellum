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

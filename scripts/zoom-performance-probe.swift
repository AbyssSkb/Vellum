@preconcurrency import AppKit
import PDFKit
import SwiftUI
@testable import VellumCore

private let measuredPhases = ["tap-in", "tap-out", "hold-in", "settle-in", "hold-out", "settle-out", "taps-in"]

private func checkPhases(_ phases: [[String: Any]], completed: Bool, limit: Double) -> [String] {
    var failures = completed ? [] : ["Input sequence did not complete"]
    for name in measuredPhases {
        guard let phase = phases.first(where: { $0["stage"] as? String == name }),
              let active = phase["active_samples"] as? Int, active > 0,
              let changes = phase["changed_frames"] as? Int, changes >= 2,
              let heartbeat = phase["active_tick_max_ms"] as? Double, heartbeat.isFinite,
              let geometry = phase["geometry_gap_max_ms"] as? Double, geometry.isFinite else {
            failures.append("\(name): missing measurements or no continuous zoom")
            continue
        }
        if heartbeat > limit { failures.append("\(name): main-loop gap \(heartbeat) ms exceeds \(limit) ms") }
        if geometry > limit { failures.append("\(name): geometry-change gap \(geometry) ms exceeds \(limit) ms") }
    }
    return failures
}

@MainActor private final class ZoomPerformanceProbe: NSObject, NSApplicationDelegate {
    var state: AppState!
    var window: NSWindow!
    var view: VellumPDFView!
    var host: NSHostingView<AnyView>!
    var anchor: PDFDestination!
    var timer: Timer?
    var samples: [[String: Any]] = []
    var failures: [String] = []
    var actions: [(Double, String, () -> Void)] = []
    var nextAction = 0
    var heldKey: String?
    var stage = "warmup"
    var opened = 0.0
    var preparedAt: Double?
    var visibleSince: Double?
    var started = 0.0
    var lastSample = 0.0
    var lastAnimating = false
    var lastGeometry = 0.0
    var lastGeometryChange = 0.0
    var initialScale = 0.0
    var initialPaperWidth = 0.0
    var initialWindowFrame = NSRect.zero
    var initialViewSize = NSSize.zero
    var initialBackingScale = 0.0
    var pageCount = 0
    let suite = "VellumZoomProbe.\(UUID().uuidString)"
    let resultURL: URL
    let gapLimit: Double

    init(resultURL: URL, gapLimit: Double) {
        self.resultURL = resultURL
        self.gapLimit = gapLimit
    }

    func now() -> Double { ProcessInfo.processInfo.systemUptime }
    var foregroundVisible: Bool {
        NSApp.isActive && window?.isKeyWindow == true && window?.isVisible == true
            && window?.occlusionState.contains(.visible) == true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        opened = now()
        guard let path = Bundle.main.object(forInfoDictionaryKey: "ProbePDF") as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: path)),
              document.pageCount > 0, !document.isLocked else {
            failures.append("PDF must be readable, unlocked, and contain at least one page")
            finish()
            return
        }
        pageCount = document.pageCount
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(AppUILanguage.english.rawValue, forKey: AppPreferenceKeys.appLanguage)
        state = AppState(sessionDefaults: defaults, keyboardController: KeyboardController(
            installsKeyMonitor: false, installsOpenURLObserver: false,
            notificationCenter: NotificationCenter(), openURLRelay: OpenURLRelay()
        ))
        state.didRestorePreviousTabs = true
        NSApp.appearance = NSAppearance(named: .darkAqua)
        _ = state.tabStore.openInNewTabs([PDFTab(url: URL(fileURLWithPath: path), document: document)])
        window = NSWindow(contentRect: NSScreen.main?.visibleFrame ?? NSRect(x: 60, y: 60, width: 1100, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Vellum Zoom Performance Check"
        state.readerWindow = window
        host = NSHostingView(rootView: AnyView(ContentView().environmentObject(state)
            .defaultAppStorage(defaults).frame(minWidth: 900, minHeight: 620)))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.waitForForeground() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func waitForForeground() {
        let t = now()
        if t - opened >= 30 {
            failures.append("Reader did not become ready and foreground-visible within 30 seconds")
            finish()
            return
        }
        guard let candidate = state.activeReaderController as? VellumPDFView,
              candidate.window === window, candidate.pendingRestoreAction == nil else { return }
        view = candidate
        if preparedAt == nil {
            guard view.applyWidthFitScaleNow(for: view.document?.page(at: 0)) else {
                failures.append("Initial width fit failed")
                finish()
                return
            }
            view.goToFirstPage(nil)
            view.scrollToDocumentEdge(.top)
            view.focus()
            preparedAt = t
            return
        }
        guard foregroundVisible else { visibleSince = nil; return }
        if visibleSince == nil { visibleSince = t }
        guard t - preparedAt! >= 12, t - visibleSince! >= 0.5 else { return }
        timer?.invalidate()
        guard let destination = view.centerDestination(), let page = destination.page,
              view.document?.index(for: page) == 0 else {
            failures.append("Use a portrait PDF whose first page contains the width-fit viewport center")
            finish()
            return
        }
        view.focus()
        anchor = destination
        initialScale = Double(view.scaleFactor)
        initialPaperWidth = Double(view.convert(page.bounds(for: view.displayBox), from: page).width)
        initialWindowFrame = window.frame
        initialViewSize = view.bounds.size
        initialBackingScale = window.backingScaleFactor
        started = now()
        lastSample = started
        lastGeometryChange = started
        lastGeometry = initialPaperWidth
        actions = [
            (1, "tap-in", { self.tap("=") }),
            (1.8, "tap-out", { self.checkSettled(); self.tap("-") }),
            (2.6, "hold-in", { self.checkSettled(); self.press("=") }),
            (4.6, "settle-in", { self.release() }),
            (5.4, "hold-out", { self.checkSettled(); self.press("-") }),
            (7.4, "settle-out", { self.release() })
        ]
        for index in 0..<10 {
            actions.append((8.2 + Double(index) * 0.1, "taps-in", { self.tap("=") }))
        }
        actions.append((10.1, "done", { self.checkSettled(); self.finish() }))
        timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func event(_ type: NSEvent.EventType, _ key: String) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: now(),
                        windowNumber: window.windowNumber, context: nil, characters: key,
                        charactersIgnoringModifiers: key, isARepeat: false, keyCode: key == "=" ? 24 : 27)!
    }

    func press(_ key: String) {
        heldKey = key
        if !state.handleKeyEvent(event(.keyDown, key)) { failures.append("Key down was not routed") }
    }

    func release() {
        if let key = heldKey {
            if !state.handleKeyEvent(event(.keyUp, key)) { failures.append("Key up was not routed") }
            heldKey = nil
        }
    }

    func tap(_ key: String) { press(key); release() }
    func checkSettled() {
        if view.animationState.zoomTargetScale != nil { failures.append("Zoom did not settle after \(stage)") }
    }

    func tick() {
        let t = now()
        let intervalAnimating = lastAnimating
        let heartbeatGap = (t - lastSample) * 1000
        if intervalAnimating, heartbeatGap > gapLimit {
            failures.append("\(stage): main-loop gap \(heartbeatGap) ms exceeds \(gapLimit) ms")
        }
        guard foregroundVisible, window.frame == initialWindowFrame,
              view.bounds.size == initialViewSize, window.backingScaleFactor == initialBackingScale,
              let responder = window.firstResponder as? NSView,
              responder === view || responder.isDescendant(of: view) else {
            failures.append("Reader lost foreground focus or its window/display geometry changed")
            finish()
            return
        }
        while nextAction < actions.count, t - started >= actions[nextAction].0 {
            let action = actions[nextAction]
            nextAction += 1
            stage = action.1
            action.2()
            if stage == "done" { return }
        }
        let scale = Double(view.scaleFactor)
        let page = anchor.page!
        let paperWidth = Double(view.convert(page.bounds(for: view.displayBox), from: page).width)
        if abs(paperWidth / initialPaperWidth - scale / initialScale) > 0.000001 {
            failures.append("PDF scale and paper geometry diverged")
        }
        let animating = view.animationState.zoomTargetScale != nil
        let changed = abs(paperWidth - lastGeometry) > 0.000001
        var geometryGap = 0.0
        if animating || intervalAnimating {
            if !intervalAnimating { lastGeometryChange = t }
            geometryGap = (t - lastGeometryChange) * 1000
            if changed { lastGeometryChange = t }
        } else { lastGeometryChange = t }
        samples.append([
            "t": t - started, "stage": stage, "dt_ms": (t - lastSample) * 1000,
            "scale": scale, "paper_width": paperWidth, "paper_changed": changed,
            "active": animating || intervalAnimating, "interval_active": intervalAnimating,
            "geometry_gap_ms": geometryGap
        ])
        lastSample = t
        lastGeometry = paperWidth
        lastAnimating = animating
    }

    func finish() {
        timer?.invalidate()
        release()
        view?.stopZoomState()
        state?.keyboardController.cancelInput()
        let completed = stage == "done"
        let phases: [[String: Any]] = measuredPhases.map { name in
            let active = samples.filter { $0["stage"] as? String == name && $0["active"] as? Bool == true }
            return [
                "stage": name, "active_samples": active.count,
                "changed_frames": active.filter { $0["paper_changed"] as? Bool == true }.count,
                "active_tick_max_ms": active.filter { $0["interval_active"] as? Bool == true }
                    .compactMap { $0["dt_ms"] as? Double }.max() ?? 0,
                "geometry_gap_max_ms": active.compactMap { $0["geometry_gap_ms"] as? Double }.max() ?? 0
            ]
        }
        failures += checkPhases(phases, completed: completed, limit: gapLimit)
        let code: Int32 = failures.isEmpty ? 0 : 2
        var output: [String: Any] = [
            "schema_version": 1, "profile": "keyboard-zoom-v1", "completed": completed,
            "exit_code": code, "gap_limit_ms": gapLimit, "failures": failures,
            "system": ProcessInfo.processInfo.operatingSystemVersionString,
            "build": "debug", "pages": pageCount, "initial_page_index": 0,
            "initial_scale": initialScale, "backing_scale": initialBackingScale,
            "window_frame": [initialWindowFrame.origin.x, initialWindowFrame.origin.y,
                             initialWindowFrame.width, initialWindowFrame.height],
            "view_dimensions": [initialViewSize.width, initialViewSize.height],
            "backing_dimensions": [initialViewSize.width * initialBackingScale,
                                   initialViewSize.height * initialBackingScale],
            "phases": phases, "samples": samples
        ]
        for key in ["ProbeRevision", "ProbeArchitecture", "ProbePDFSHA256", "ProbeZoomSourceSHA256"] {
            output[key] = Bundle.main.object(forInfoDictionaryKey: key)
        }
        do {
            try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
                .write(to: resultURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("Cannot write performance result: \(error)\n".utf8))
            exit(1)
        }
        view?.saveBeforeDismantle = nil
        view?.readerStateSaveWorkItem?.cancel()
        view?.readingPositionReportWorkItem?.cancel()
        view?.cancelPendingRestore()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        exit(code)
    }
}

@main private struct Program {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        if arguments.dropFirst().first == "--self-test" {
            let valid: [[String: Any]] = measuredPhases.map {
                ["stage": $0, "active_samples": 30, "changed_frames": 15,
                 "active_tick_max_ms": 9.0, "geometry_gap_max_ms": 26.0]
            }
            precondition(checkPhases(valid, completed: true, limit: 50).isEmpty)
            var slow = valid
            slow[0]["geometry_gap_max_ms"] = 83.0
            precondition(!checkPhases(slow, completed: true, limit: 50).isEmpty)
            var noZoom = valid
            noZoom[0]["changed_frames"] = 0
            precondition(!checkPhases(noZoom, completed: true, limit: 50).isEmpty)
            precondition(!checkPhases([], completed: true, limit: 50).isEmpty)
            precondition(!checkPhases(valid, completed: false, limit: 50).isEmpty)
            print("Zoom performance verdict self-check passed")
            return
        }
        if arguments.dropFirst().first == "--check-result", arguments.count == 3 {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
                guard let report = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      report["schema_version"] as? Int == 1,
                      let completed = report["completed"] as? Bool,
                      let phases = report["phases"] as? [[String: Any]],
                      let limit = report["gap_limit_ms"] as? Double, limit.isFinite, limit > 0,
                      let failures = report["failures"] as? [String],
                      let code = report["exit_code"] as? Int, [0, 2].contains(code) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let errors = failures + checkPhases(phases, completed: completed, limit: limit)
                guard code == 0, errors.isEmpty else {
                    print("FAIL: \(Array(Set(errors)).sorted().joined(separator: "; "))")
                    exit(2)
                }
                let maximum = phases.compactMap { $0["geometry_gap_max_ms"] as? Double }.max()!
                print("PASS: maximum geometry-change gap \(maximum) ms; result: \(arguments[2])")
                return
            } catch {
                FileHandle.standardError.write(Data("Missing or invalid performance result: \(error)\n".utf8))
                exit(1)
            }
        }
        guard let path = Bundle.main.object(forInfoDictionaryKey: "ProbeResult") as? String,
              let rawLimit = Bundle.main.object(forInfoDictionaryKey: "ProbeGapLimit") as? String,
              let limit = Double(rawLimit), limit.isFinite, limit > 0 else {
            FileHandle.standardError.write(Data("Build the probe with scripts/check-zoom-performance.sh\n".utf8))
            exit(1)
        }
        // Also bound synchronous PDF loading, before the main-run-loop watchdog can run.
        DispatchQueue.global().asyncAfter(deadline: .now() + 90) { exit(3) }
        let app = NSApplication.shared
        let delegate = ZoomPerformanceProbe(resultURL: URL(fileURLWithPath: path), gapLimit: limit)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

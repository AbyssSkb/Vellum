@preconcurrency import AppKit
import SwiftUI
import QuartzCore

@MainActor
public final class SettingsNavigation: ObservableObject {
    enum Level { case sidebar, rows, controls, reading }

    @Published public var page: SettingsPage = .general {
        didSet {
            guard page != oldValue else { return }
            level = .sidebar
            rowID = rememberedRows[page]
            controlID = nil
            scrollTarget = nil
        }
    }
    @Published private(set) var level: Level = .sidebar
    @Published private(set) var rowID: String?
    @Published private(set) var controlID: String?
    private var rememberedRows: [SettingsPage: String] = [:]
    private var rememberedTargets: [SettingsPage: String] = [:]
    private var anchors: [UUID: WeakSettingsAnchor] = [:]
    weak var keyboardView: NSView?
    fileprivate var scrollTarget: NSPoint?
    fileprivate var interactionRevision = 0

    public init() {}

    var isSidebarFocused: Bool { level == .sidebar }

    var focusedControlID: String? {
        level == .rows || level == .controls ? controlID : nil
    }

    var focusedRowID: String? {
        guard level == .rows || level == .reading, focusedControlID == nil else { return nil }
        return rowID
    }

    public func selectPage(_ page: SettingsPage) {
        self.page = page
    }

    public func focusSidebar() {
        level = .sidebar
        controlID = nil
        if let item = anchors.values.compactMap(\.view).first(where: { $0.role == .sidebar && $0.id == page.rawValue && $0.window != nil }) {
            item.focus?()
        } else {
            keyboardView?.window?.makeFirstResponder(keyboardView)
        }
    }

    func didFocusSidebar(_ page: SettingsPage) {
        selectPage(page)
        level = .sidebar
        controlID = nil
    }

    fileprivate func register(_ anchor: SettingsAnchorView) {
        anchors[anchor.token] = WeakSettingsAnchor(anchor)
    }

    func controlBecameUnavailable(_ anchor: SettingsAnchorView) {
        guard level != .sidebar, controlID == anchor.id, let row = parentRow(of: anchor) else { return }
        let rowID = row.id
        let page = page
        let revision = interactionRevision
        let window = anchor.window
        // SwiftUI relocates native focus when disabling a button; keep it in the same setting.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, window?.isKeyWindow == true, self.page == page, self.level != .sidebar,
                  self.interactionRevision == revision,
                  let row = self.rows.first(where: { $0.id == rowID }) else { return }
            self.focusRow(row)
        }
    }

    private var currentAnchors: [SettingsAnchorView] {
        anchors = anchors.filter { $0.value.view != nil }
        return anchors.values.compactMap(\.view).filter {
            $0.page == page && $0.window != nil && !$0.isHiddenOrHasHiddenAncestor && $0.enabled
        }
    }

    private func sorted(_ items: [SettingsAnchorView]) -> [SettingsAnchorView] {
        items.sorted {
            let a = $0.convert($0.bounds, to: nil)
            let b = $1.convert($1.bounds, to: nil)
            if abs(a.maxY - b.maxY) > 3 { return a.maxY > b.maxY }
            return a.minX < b.minX
        }
    }

    private var rows: [SettingsAnchorView] {
        sorted(currentAnchors.filter { $0.role == .row || $0.role == .reading })
    }

    private func parentRow(of control: SettingsAnchorView) -> SettingsAnchorView? {
        let rect = control.convert(control.bounds, to: nil)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return rows.filter { $0.convert($0.bounds, to: nil).insetBy(dx: -1, dy: -1).contains(center) }
            .min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    private func controls(in row: SettingsAnchorView) -> [SettingsAnchorView] {
        sorted(currentAnchors.filter {
            ($0.role == .control || $0.role == .field) && parentRow(of: $0) === row
        })
    }

    private var targets: [SettingsAnchorView] {
        sorted(currentAnchors.filter { $0.role == .control || $0.role == .field || $0.role == .reading })
    }

    private var currentTarget: SettingsAnchorView? {
        if let controlID { return targets.first { $0.id == controlID } }
        return rows.first { $0.id == rowID }
    }

    fileprivate func didFocus(_ anchor: SettingsAnchorView, editing: Bool = false) {
        guard anchor.page == page else { return }
        rememberedTargets[page] = anchor.id
        if anchor.role == .row || anchor.role == .reading {
            remember(anchor)
            controlID = nil
            level = anchor.role == .reading ? .reading : .rows
        } else if let row = parentRow(of: anchor) {
            remember(row)
            controlID = anchor.id
            level = anchor.role == .field && editing ? .controls : .rows
        }
    }

    private func remember(_ row: SettingsAnchorView) {
        rowID = row.id
        rememberedRows[page] = row.id
    }

    private func focusRow(_ row: SettingsAnchorView) {
        remember(row)
        let items = controls(in: row)
        if let control = items.first(where: { $0.id == rememberedTargets[page] })
            ?? items.first(where: { $0.isSelected == true }) ?? items.first {
            focusControl(control)
            return
        }
        didFocus(row)
        row.window?.makeFirstResponder(row)
        reveal(row)
    }

    private func focusControl(_ control: SettingsAnchorView) {
        didFocus(control)
        if control.role == .field { control.window?.makeFirstResponder(control) }
        else { control.focus?() }
        reveal(control)
    }

    private func focusTarget(_ target: SettingsAnchorView) {
        if target.role == .control || target.role == .field { focusControl(target) }
        else { focusRow(target) }
    }

    private func rect(of anchor: SettingsAnchorView) -> NSRect { anchor.convert(anchor.bounds, to: nil) }

    private func sameVisualRow(_ first: NSRect, _ second: NSRect) -> Bool {
        min(first.maxY, second.maxY) - max(first.minY, second.minY) > min(first.height, second.height) / 2
    }

    private func moveTargetVertically(_ delta: Int, revealMore: Bool = true) {
        guard let current = currentTarget else { return }
        let origin = rect(of: current)
        let candidates = targets.filter {
            let candidate = rect(of: $0)
            return !sameVisualRow(origin, candidate) && (delta > 0 ? candidate.maxY < origin.maxY : candidate.maxY > origin.maxY)
        }
        if revealMore, let group = parentRow(of: current), controls(in: group).count > 1,
           !candidates.contains(where: { parentRow(of: $0) === group }),
           delta > 0 ? rect(of: group).minY < origin.minY - 8 : rect(of: group).maxY > origin.maxY + 8,
           let scroll = scrollView(for: current) {
            let start = scrollTarget ?? scroll.contentView.bounds.origin
            let direction: CGFloat = scroll.documentView?.isFlipped == false ? -1 : 1
            let proposed = NSPoint(x: start.x, y: start.y + direction * CGFloat(delta) * scroll.contentView.bounds.height / 2)
            let target = scroll.contentView.constrainBoundsRect(NSRect(origin: proposed, size: scroll.contentView.bounds.size)).origin
            if abs(target.y - start.y) > 1 {
                let page = page
                let id = current.id
                let role = current.role
                let window = current.window
                let revision = interactionRevision
                self.scroll(to: target, in: scroll) { [weak self, weak window] in
                    guard let self, let window, window.isKeyWindow, self.page == page, self.level != .controls,
                          self.interactionRevision == revision,
                          self.currentTarget?.id == id, self.currentTarget?.role == role else { return }
                    window.contentView?.layoutSubtreeIfNeeded()
                    self.moveTargetVertically(delta, revealMore: false)
                }
                return
            }
        }
        guard let closest = candidates.min(by: { abs(rect(of: $0).maxY - origin.maxY) < abs(rect(of: $1).maxY - origin.maxY) }) else { return }
        let y = rect(of: closest).maxY
        if let next = candidates.filter({ abs(rect(of: $0).maxY - y) < 3 })
            .min(by: { abs(rect(of: $0).midX - origin.midX) < abs(rect(of: $1).midX - origin.midX) }) {
            focusTarget(next)
        }
    }

    private func move(_ delta: Int) {
        switch level {
        case .sidebar:
            let pages = SettingsPage.allCases
            guard let index = pages.firstIndex(of: page) else { return }
            selectPage(pages[min(max(index + delta, 0), pages.count - 1)])
            focusSidebar()
        case .rows, .controls:
            moveTargetVertically(delta)
        case .reading:
            guard let row = rows.first(where: { $0.id == rowID }), let scroll = scrollView(for: row) else { return }
            let origin = scrollTarget ?? scroll.contentView.bounds.origin
            let proposed = NSPoint(x: origin.x, y: origin.y + (scroll.documentView?.isFlipped == false ? -1 : 1) * CGFloat(delta) * 48)
            let target = scroll.contentView.constrainBoundsRect(NSRect(origin: proposed, size: scroll.contentView.bounds.size)).origin
            if abs(target.y - origin.y) > 1 { self.scroll(to: target, in: scroll) }
            else { moveTargetVertically(delta) }
        }
    }

    private func enter() {
        switch level {
        case .sidebar:
            if let remembered = targets.first(where: { $0.id == rememberedTargets[page] }) { focusTarget(remembered) }
            else if let row = rows.first { focusRow(row) }
        case .rows, .controls:
            guard let control = currentTarget else { return }
            if control.role == .field {
                level = .controls
                control.focus?()
            } else if control.role == .control { control.action?() }
        case .reading:
            break
        }
    }

    private func moveControl(_ delta: Int) {
        guard level != .sidebar else {
            if delta > 0 { enter() }
            return
        }
        guard let current = currentTarget else { return }
        let origin = rect(of: current)
        let next = targets.filter {
            let candidate = rect(of: $0)
            return $0 !== current && sameVisualRow(origin, candidate)
                && (delta > 0 ? candidate.midX > origin.midX : candidate.midX < origin.midX)
        }.min { abs(rect(of: $0).midX - origin.midX) < abs(rect(of: $1).midX - origin.midX) }
        if let next { focusTarget(next) }
        else if delta < 0 { focusSidebar() }
    }

    private func back() {
        if level == .controls, let target = currentTarget { focusTarget(target) }
        else { focusSidebar() }
    }

    fileprivate func mouseDown(_ event: NSEvent) {
        interactionRevision += 1
        let targets = currentAnchors.filter { $0.convert($0.bounds, to: nil).contains(event.locationInWindow) }
        if let control = targets.first(where: { $0.role == .control || $0.role == .field }) {
            didFocus(control, editing: control.role == .field)
        } else if let row = targets.filter({ $0.role == .row || $0.role == .reading })
            .min(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) {
            focusRow(row)
        }
    }

    @discardableResult
    func handle(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard event.window === window, window.isKeyWindow else { return false }
        interactionRevision += 1
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        if let editor = window.firstResponder as? NSTextView, editor.isEditable {
            guard event.keyCode == 53, !editor.hasMarkedText() else { return false }
            back()
            return true
        }
        if let field = window.firstResponder as? NSTextField, field.isEditable { return false }
        switch event.keyCode {
        case 53: back()
        case 123: moveControl(-1)
        case 124: moveControl(1)
        case 125: move(1)
        case 126: move(-1)
        case 36, 76:
            if !event.isARepeat { enter() }
        case 49:
            if !event.isARepeat, currentTarget?.role != .field { enter() }
        default:
            switch event.charactersIgnoringModifiers {
            case "j": move(1)
            case "k": move(-1)
            case "h": moveControl(-1)
            case "l": moveControl(1)
            default: return false
            }
        }
        return true
    }

    private func scrollView(for anchor: NSView) -> NSScrollView? {
        if let scroll = anchor.enclosingScrollView { return scroll }
        func descendants(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(descendants)
        }
        return anchor.window?.contentView.flatMap { descendants($0).max { $0.bounds.height * $0.bounds.width < $1.bounds.height * $1.bounds.width } }
    }

    private func reveal(_ anchor: NSView) {
        scrollTarget = nil
        guard let scroll = scrollView(for: anchor), let document = scroll.documentView else { return }
        let rect = anchor.convert(anchor.bounds, to: document).insetBy(dx: 0, dy: -10)
        let visible = scroll.documentVisibleRect
        var y = visible.minY
        if rect.minY < visible.minY { y = rect.minY }
        else if rect.maxY > visible.maxY { y = min(rect.minY, rect.maxY - visible.height) }
        guard abs(y - visible.minY) > 1 else { return }
        self.scroll(to: NSPoint(x: visible.minX, y: y), in: scroll)
    }

    private func scroll(to origin: NSPoint, in scroll: NSScrollView, completion: (@MainActor () -> Void)? = nil) {
        let target = scroll.contentView.constrainBoundsRect(NSRect(origin: origin, size: scroll.contentView.bounds.size)).origin
        scrollTarget = target
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            scroll.contentView.animator().setBoundsOrigin(target)
        } completionHandler: {
            if let completion { DispatchQueue.main.async { completion() } }
        }
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

private final class WeakSettingsAnchor {
    weak var view: SettingsAnchorView?
    init(_ view: SettingsAnchorView) { self.view = view }
}

@MainActor
final class SettingsAnchorView: NSView {
    enum Role { case sidebar, row, control, field, reading }
    let token = UUID()
    var id = ""
    var page = SettingsPage.general
    var role = Role.row
    var enabled = true
    var isSelected: Bool?
    var action: (() -> Void)?
    var focus: (() -> Void)?
    weak var navigation: SettingsNavigation?

    override var acceptsFirstResponder: Bool { role == .row || role == .field || role == .reading }
    override var canBecomeKeyView: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func becomeFirstResponder() -> Bool {
        navigation?.didFocus(self)
        return true
    }
}

private struct SettingsAnchor: NSViewRepresentable {
    @EnvironmentObject private var navigation: SettingsNavigation
    @Environment(\.isEnabled) private var enabled
    let id: String
    let role: SettingsAnchorView.Role
    var isSelected: Bool? = nil
    var action: (() -> Void)? = nil
    var focus: (() -> Void)? = nil

    func makeNSView(context: Context) -> SettingsAnchorView { SettingsAnchorView() }
    func updateNSView(_ view: SettingsAnchorView, context: Context) {
        let becameDisabled = view.enabled && !enabled
        view.id = id
        view.page = navigation.page
        view.role = role
        view.enabled = enabled
        view.isSelected = isSelected
        view.action = action
        view.focus = focus
        view.navigation = navigation
        navigation.register(view)
        if becameDisabled { navigation.controlBecameUnavailable(view) }
    }
}

private struct SettingsRowModifier: ViewModifier {
    @EnvironmentObject private var navigation: SettingsNavigation
    let id: String
    var reading = false

    func body(content: Content) -> some View {
        content
            .background(SettingsAnchor(id: id, role: reading ? .reading : .row))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(navigation.focusedRowID == id ? VellumColors.blueColor.opacity(0.65) : .clear, lineWidth: 1)
                    .padding(-4)
                    .allowsHitTesting(false)
            }
    }
}

private struct SettingsControlModifier: ViewModifier {
    @EnvironmentObject private var navigation: SettingsNavigation
    @FocusState private var focused: Bool
    let id: String
    let isSelected: Bool?
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .background(SettingsAnchor(id: id, role: .control, isSelected: isSelected, action: action, focus: { focused = true }))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(navigation.focusedControlID == id ? VellumColors.blueColor : .clear, lineWidth: 1)
                    .padding(-2)
                    .allowsHitTesting(false)
            }
            .onChange(of: focused) { _, value in
                if value { navigation.focusedControl(id) }
            }
            .simultaneousGesture(TapGesture().onEnded { focused = true; navigation.focusedControl(id) })
    }
}

private struct SettingsFieldModifier: ViewModifier {
    @EnvironmentObject private var navigation: SettingsNavigation
    let id: String
    let focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .focused(focused)
            .background(SettingsAnchor(id: id, role: .field, focus: { focused.wrappedValue = true }))
            .onChange(of: focused.wrappedValue) { _, value in
                if value { navigation.focusedControl(id, editing: true) }
            }
    }
}

private extension SettingsNavigation {
    func focusedControl(_ id: String, editing: Bool = false) {
        if let anchor = currentAnchors.first(where: { $0.id == id && ($0.role == .control || $0.role == .field) }) {
            didFocus(anchor, editing: editing && anchor.window?.firstResponder !== anchor)
        }
    }
}

extension View {
    func settingsSidebarItem(_ page: SettingsPage, focused: FocusState<Bool>.Binding) -> some View {
        background(SettingsAnchor(id: page.rawValue, role: .sidebar, focus: { focused.wrappedValue = true }))
    }
    func settingsRow(_ id: String) -> some View { modifier(SettingsRowModifier(id: id)) }
    func settingsReadingArea(_ id: String) -> some View { modifier(SettingsRowModifier(id: id, reading: true)) }
    func settingsControl(_ id: String, isSelected: Bool? = nil, action: @escaping () -> Void) -> some View {
        modifier(SettingsControlModifier(id: id, isSelected: isSelected, action: action))
    }
    func settingsField(_ id: String, focused: FocusState<Bool>.Binding) -> some View { modifier(SettingsFieldModifier(id: id, focused: focused)) }
}

struct SettingsKeyboardBridge: NSViewRepresentable {
    let navigation: SettingsNavigation

    func makeNSView(context: Context) -> KeyboardView { KeyboardView(navigation: navigation) }
    func updateNSView(_ nsView: KeyboardView, context: Context) {}

    final class KeyboardView: NSView {
        private let navigation: SettingsNavigation
        nonisolated(unsafe) private var monitor: Any?

        init(navigation: SettingsNavigation) {
            self.navigation = navigation
            super.init(frame: .zero)
            navigation.keyboardView = self
        }
        required init?(coder: NSCoder) { nil }
        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel, .leftMouseDown]) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self, let window = self.window, event.window === window else { return false }
                    if event.type == .scrollWheel {
                        self.navigation.interactionRevision += 1
                        self.navigation.scrollTarget = nil
                        return false
                    }
                    if event.type == .leftMouseDown { self.navigation.mouseDown(event); return false }
                    return self.navigation.handle(event, in: window)
                }
                return handled ? nil : event
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

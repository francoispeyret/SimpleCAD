import SwiftUI
import AppKit

private let toolbarLeftMargin: CGFloat = 42
private let panelTopMargin: CGFloat = 16
private let panelBottomMargin: CGFloat = 16
private let sidebarWidth: CGFloat = 260
private let panelDragHandleHeight: CGFloat = 18

struct ContentView: View {
    @EnvironmentObject var document: CADDocument
    @State private var keyboardMonitor: Any?
    @State private var isSidebarVisible = true
    @State private var toolbarPosition: CGPoint?
    @State private var sidebarPosition: CGPoint?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                WindowDocumentTitleBinder(
                    fileURL: document.currentFileURL,
                    isEdited: document.isDirty
                )
                .frame(width: 0, height: 0)

                // ── Couche 0 : canvas plein écran ─────────────────
                CanvasScrollView()
                    .frame(width: geo.size.width, height: geo.size.height)

                // ── Couche 1 : bouton de masquage du panneau droit ───
                SidebarVisibilityButton(isVisible: isSidebarVisible) {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        if !isSidebarVisible {
                            sidebarPosition = nil
                        }
                        toolbarPosition = nil
                        isSidebarVisible.toggle()
                    }
                }
                .position(sidebarTogglePosition(in: geo.size))
                .zIndex(3)

                // ── Couche 2 : toolbar flottante ───────────────────
                FloatingPanel(
                    position: $toolbarPosition,
                    defaultPosition: defaultToolbarPosition(in: geo.size),
                    panelSize: toolbarPanelSize,
                    containerSize: geo.size
                ) {
                    GlassEffectContainer {
                        VStack(spacing: 0) {
                            FloatingPanelHandle()
                            ToolbarView()
                        }
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .zIndex(2)

                // ── Couche 3 : sidebar flottante ───────────────────
                if isSidebarVisible {
                    FloatingPanel(
                        position: $sidebarPosition,
                        defaultPosition: defaultSidebarPosition(in: geo.size),
                        panelSize: sidebarPanelSize(in: geo.size),
                        containerSize: geo.size
                    ) {
                        GlassEffectContainer {
                            VStack(spacing: 0) {
                                FloatingPanelHandle()
                                SidebarView()
                            }
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
                }
            }
        }
        .frame(minWidth: 960, minHeight: 680)
        .onAppear {
            maximiseWindow()
            setupKeyboardShortcuts()
        }
        .onDisappear {
            if let keyboardMonitor {
                NSEvent.removeMonitor(keyboardMonitor)
                self.keyboardMonitor = nil
            }
        }
    }

    private func maximiseWindow() {
        DispatchQueue.main.async {
            guard let screen = NSScreen.main,
                  let window = NSApp.windows.first else { return }
            WindowTabPolicy.configure(window)
            let frame = screen.visibleFrame.insetBy(dx: 40, dy: 40)
            window.setFrame(frame, display: true)
            window.center()
        }
    }

    private var toolbarPanelSize: CGSize {
        CGSize(width: toolbarWidth, height: toolbarContentHeight + panelDragHandleHeight)
    }

    private func sidebarPanelSize(in containerSize: CGSize) -> CGSize {
        CGSize(width: sidebarWidth, height: max(360, containerSize.height - panelTopMargin - panelBottomMargin))
    }

    private var toolbarContentHeight: CGFloat {
        532
    }

    private func defaultToolbarPosition(in containerSize: CGSize) -> CGPoint {
        CGPoint(x: toolbarLeftMargin, y: panelTopMargin)
    }

    private func defaultSidebarPosition(in containerSize: CGSize) -> CGPoint {
        let size = sidebarPanelSize(in: containerSize)
        return CGPoint(
            x: max(12, containerSize.width - size.width - 28),
            y: panelTopMargin
        )
    }

    private func sidebarTogglePosition(in containerSize: CGSize) -> CGPoint {
        let sidebar = sidebarPanelSize(in: containerSize)
        let x = isSidebarVisible
            ? max(72, containerSize.width - sidebar.width - 54)
            : max(72, containerSize.width - 54)
        return CGPoint(x: x, y: panelTopMargin + 17)
    }

    private func setupKeyboardShortcuts() {
        guard keyboardMonitor == nil else { return }

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleNumpadZoom(event) { return nil }
            guard let tool = toolShortcut(for: event) else { return event }

            document.currentTool = tool
            if tool.shapeType != nil {
                document.deselectAll()
            }
            return nil
        }
    }

    /// Intercepte Cmd+[+/-/0] du pavé numérique (.numericPad flag ignoré par keyboardShortcut).
    private func handleNumpadZoom(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              event.modifierFlags.contains(.numericPad)
        else { return false }

        switch event.charactersIgnoringModifiers {
        case "+": document.zoomIn();    return true
        case "-": document.zoomOut();   return true
        case "0": document.resetZoom(); return true
        default:  return false
        }
    }

    private func toolShortcut(for event: NSEvent) -> Tool? {
        guard !isTextInputActive(),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return nil }

        switch key {
        case "v": return .select
        case "a": return .pointSelect
        case "r": return .rectangle
        case "e": return .ellipse
        case "t": return .triangle
        case "l": return .line
        default:  return nil
        }
    }

    private func isTextInputActive() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView || responder is NSTextField { return true }

        if let view = responder as? NSView {
            return sequence(first: view, next: { $0.superview }).contains {
                $0 is NSTextField || $0 is NSComboBox || $0 is NSSearchField
            }
        }
        return false
    }
}

// MARK: - Floating Panels

private struct FloatingPanel<Content: View>: View {
    @Binding var position: CGPoint?

    let defaultPosition: CGPoint
    let panelSize: CGSize
    let containerSize: CGSize
    let content: Content

    @State private var dragStartPosition: CGPoint?

    init(position: Binding<CGPoint?>,
         defaultPosition: CGPoint,
         panelSize: CGSize,
         containerSize: CGSize,
         @ViewBuilder content: () -> Content) {
        self._position = position
        self.defaultPosition = defaultPosition
        self.panelSize = panelSize
        self.containerSize = containerSize
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: panelSize.width, height: panelSize.height, alignment: .top)
            .overlay(alignment: .top) {
                Color.clear
                    .frame(height: panelDragHandleHeight)
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
            }
            .position(
                x: resolvedPosition.x + panelSize.width / 2,
                y: resolvedPosition.y + panelSize.height / 2
            )
    }

    private var resolvedPosition: CGPoint {
        clamped(position ?? defaultPosition)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if dragStartPosition == nil {
                    dragStartPosition = position ?? defaultPosition
                }

                guard let start = dragStartPosition else { return }
                position = clamped(
                    CGPoint(
                        x: start.x + value.translation.width,
                        y: start.y + value.translation.height
                    )
                )
            }
            .onEnded { _ in
                position = resolvedPosition
                dragStartPosition = nil
            }
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        let margin: CGFloat = 8
        let maxX = max(margin, containerSize.width - panelSize.width - margin)
        let maxY = max(margin, containerSize.height - panelSize.height - margin)

        return CGPoint(
            x: min(max(point.x, margin), maxX),
            y: min(max(point.y, margin), maxY)
        )
    }
}

private struct FloatingPanelHandle: View {
    var body: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 28, height: 3)
            Spacer()
        }
        .frame(height: panelDragHandleHeight)
        .contentShape(Rectangle())
        .help("Faire glisser pour déplacer le panneau")
    }
}

private struct SidebarVisibilityButton: View {
    let isVisible: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isVisible ? "sidebar.right" : "sidebar.trailing")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color(NSColor.windowBackgroundColor).opacity(isHovering ? 0.95 : 0.82))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isVisible ? "Masquer la fenêtre de droite" : "Afficher la fenêtre de droite")
    }
}

// MARK: - WindowDocumentTitleBinder

private struct WindowDocumentTitleBinder: NSViewRepresentable {
    let fileURL: URL?
    let isEdited: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            updateWindow(from: view)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            updateWindow(from: view)
        }
    }

    private func updateWindow(from view: NSView) {
        guard let window = view.window else { return }

        let title = fileURL?.lastPathComponent ?? "Sans titre"
        window.title = title
        window.representedURL = fileURL
        window.isDocumentEdited = isEdited
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        installCenteredTitle(on: window, title: title)
    }

    private func installCenteredTitle(on window: NSWindow, title: String) {
        guard let titlebarView = titlebarView(for: window) else { return }

        let titleView: CenteredWindowTitleView
        if let existing = titlebarView.subviews.compactMap({ $0 as? CenteredWindowTitleView }).first {
            titleView = existing
        } else {
            titleView = CenteredWindowTitleView()
            titleView.translatesAutoresizingMaskIntoConstraints = false
            titlebarView.addSubview(titleView)

            NSLayoutConstraint.activate([
                titleView.centerXAnchor.constraint(equalTo: titlebarView.centerXAnchor),
                titleView.centerYAnchor.constraint(equalTo: titlebarView.centerYAnchor),
                titleView.heightAnchor.constraint(equalToConstant: 22),
                titleView.widthAnchor.constraint(lessThanOrEqualTo: titlebarView.widthAnchor, multiplier: 0.42),
                titleView.leadingAnchor.constraint(greaterThanOrEqualTo: titlebarView.leadingAnchor, constant: 120),
                titleView.trailingAnchor.constraint(lessThanOrEqualTo: titlebarView.trailingAnchor, constant: -120)
            ])
        }

        titleView.fileURL = fileURL
        titleView.title = title
    }

    private func titlebarView(for window: NSWindow) -> NSView? {
        guard let closeButton = window.standardWindowButton(.closeButton) else { return nil }

        var candidate = closeButton.superview
        while let next = candidate?.superview,
              next.bounds.width >= candidate?.bounds.width ?? 0 {
            candidate = next
            if next.bounds.width >= window.frame.width * 0.5 {
                break
            }
        }

        return candidate
    }
}

private final class CenteredWindowTitleView: NSView {
    var fileURL: URL?
    var title: String = "" {
        didSet {
            label.stringValue = title
            invalidateIntrinsicContentSize()
        }
    }

    private let label: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.alignment = .center
        field.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        field.lineBreakMode = .byTruncatingMiddle
        field.maximumNumberOfLines = 1
        field.textColor = .labelColor
        return field
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        return NSSize(width: min(max(labelSize.width + 12, 80), 520), height: 22)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command),
              let fileURL else {
            window?.performDrag(with: event)
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}

// MARK: - SidebarView

private enum SidebarTab { case layers, history }

private struct SidebarView: View {
    @State private var tab: SidebarTab = .layers

    var body: some View {
        VStack(spacing: 0) {
            SidebarCanvasOptionsView()

            Divider()

            // ── Sélecteur d'onglet ────────────────────────────────
            HStack(spacing: 6) {
                SidebarTabButton(label: "Calques",    isSelected: tab == .layers)  { tab = .layers  }
                SidebarTabButton(label: "Historique", isSelected: tab == .history) { tab = .history }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // ── Contenu ───────────────────────────────────────────
            switch tab {
            case .layers:  ShapeListView()
            case .history: HistoryPanelView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - SidebarCanvasOptionsView

private struct SidebarCanvasOptionsView: View {
    @EnvironmentObject var document: CADDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan de travail")
                .font(.system(size: 12, weight: .semibold))

            gridModeMenu
            dimensionModeMenu
            unitPicker
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gridModeMenu: some View {
        LabeledSidebarControl(label: "Grille") {
            Menu {
                ForEach(GridDisplayMode.allCases) { mode in
                    Button {
                        document.gridDisplayMode = mode
                    } label: {
                        HStack {
                            Text(mode.title)
                            if document.gridDisplayMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                SidebarMenuLabel(
                    icon: document.gridDisplayMode.sfSymbol,
                    title: document.gridDisplayMode.shortTitle
                )
            }
            .buttonStyle(.plain)
            .help("Afficher la grille")
        }
    }

    private var dimensionModeMenu: some View {
        LabeledSidebarControl(label: "Cotes") {
            Menu {
                ForEach(DimensionDisplayMode.allCases) { mode in
                    Button {
                        document.dimensionDisplayMode = mode
                    } label: {
                        HStack {
                            Text(mode.title)
                            if document.dimensionDisplayMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                SidebarMenuLabel(
                    icon: document.dimensionDisplayMode.sfSymbol,
                    title: document.dimensionDisplayMode.shortTitle
                )
            }
            .buttonStyle(.plain)
            .help("Afficher les cotes")
        }
    }

    private var unitPicker: some View {
        LabeledSidebarControl(label: "Dimensions") {
            Menu {
                ForEach(DocumentUnit.allCases) { unit in
                    Button {
                        document.unit = unit
                    } label: {
                        HStack {
                            Text(unit.rawValue)
                            if document.unit == unit {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                SidebarMenuLabel(
                    icon: "ruler.fill",
                    title: document.unit.rawValue
                )
            }
            .buttonStyle(.plain)
            .help("Choisir l'unité des dimensions")
        }
    }
}

private struct LabeledSidebarControl<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            content
        }
    }
}

private struct SidebarMenuLabel: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 14)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(NSColor.controlColor))
        )
    }
}

// MARK: - SidebarTabButton

private struct SidebarTabButton: View {
    let label:      String
    let isSelected: Bool
    let action:     () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? Color.accentColor : Color(NSColor.controlColor))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CanvasScrollView

struct CanvasScrollView: View {
    @EnvironmentObject var document: CADDocument

    var body: some View {
        CanvasScrollRepresentable()
            .background(Color(NSColor.underPageBackgroundColor))
    }
}

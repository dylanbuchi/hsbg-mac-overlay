import AppKit
import SwiftUI

/// Where the hover handles sit on the NEXT OPPONENT card, in game-window coordinates (top-left origin).
enum CardHandleGeometry {
    static let gripSize = CGSize(width: 36, height: 14)
    static let cornerSize = CGSize(width: 18, height: 18)
    static let inset: CGFloat = 3
    /// The handles stay up while the mouse is this close to the card, so reaching for them never hides them.
    static let hoverMargin: CGFloat = 10

    /// The move grip: a small bar centered on the card's top edge, just inside it.
    static func grip(card: CGRect) -> CGRect {
        CGRect(x: card.midX - gripSize.width / 2, y: card.minY + inset, width: gripSize.width, height: gripSize.height)
    }

    /// The resize handle in the bottom-right corner, just inside the card.
    static func corner(card: CGRect) -> CGRect {
        CGRect(x: card.maxX - cornerSize.width - inset, y: card.maxY - cornerSize.height - inset,
               width: cornerSize.width, height: cornerSize.height)
    }

    static func showsHandles(at point: CGPoint, card: CGRect) -> Bool {
        !card.isEmpty && card.insetBy(dx: -hoverMargin, dy: -hoverMargin).contains(point)
    }

    /// True over either handle; the minion zoom stays out of their way.
    static func isOnHandle(_ point: CGPoint, card: CGRect) -> Bool {
        !card.isEmpty && (grip(card: card).contains(point) || corner(card: card).contains(point))
    }

    /// A canvas rect (top-left origin) in screen coordinates (Cocoa: bottom-left origin).
    static func screenFrame(_ rect: CGRect, canvasCocoaFrame canvas: CGRect) -> CGRect {
        CGRect(x: canvas.minX + rect.minX, y: canvas.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// Shows a move grip and a resize corner on the card while the mouse is over it. The overlay stays
/// click-through: only the two small handle panels take the mouse, and they are nonactivating and never key,
/// so the game keeps focus and keeps every other click.
@MainActor
final class CardHandleController {
    static let fade: TimeInterval = 0.15

    private let model: OverlayModel
    private let canvasFrame: () -> CGRect?
    private let isBlocked: () -> Bool
    private let tracker: CardDragTracker
    private var monitors: [Any] = []
    private var grip: NSPanel?
    private var corner: NSPanel?
    private var followTimer: Timer?
    private(set) var isShown = false

    /// `isBlocked` is true while "Move Card…" has its own handles up.
    init(model: OverlayModel, canvasFrame: @escaping () -> CGRect?, isBlocked: @escaping () -> Bool) {
        self.model = model
        self.canvasFrame = canvasFrame
        self.isBlocked = isBlocked
        tracker = CardDragTracker(model: model, canvasFrame: canvasFrame)
    }

    func start() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            Task { @MainActor in self?.refresh() }
            return event
        }) { monitors.append(local) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        hide(animated: false)
    }

    /// Shows or hides the handles for the current mouse position; also called on the overlay's timer.
    func refresh() {
        guard !isBlocked(), let canvas = canvasFrame(), let card = model.cardFrame else {
            hide(animated: false)
            return
        }
        let mouse = MinionZoomGeometry.canvasPoint(fromScreen: NSEvent.mouseLocation, canvasCocoaFrame: canvas)
        if tracker.isDragging || CardHandleGeometry.showsHandles(at: mouse, card: card) {
            show(card: card, canvas: canvas)
        } else {
            hide(animated: true)
        }
    }

    private func show(card: CGRect, canvas: CGRect) {
        let grip = self.grip ?? makePanel(resize: false)
        let corner = self.corner ?? makePanel(resize: true)
        self.grip = grip
        self.corner = corner
        grip.setFrame(CardHandleGeometry.screenFrame(CardHandleGeometry.grip(card: card), canvasCocoaFrame: canvas), display: true)
        corner.setFrame(CardHandleGeometry.screenFrame(CardHandleGeometry.corner(card: card), canvasCocoaFrame: canvas), display: true)
        guard !isShown else { return }
        isShown = true
        // While shown, follow the card at 30 Hz: it moves under a drag, and mouse-moved events stop during one.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
        for panel in [grip, corner] {
            panel.alphaValue = Self.reducesMotion ? 1 : 0
            panel.orderFrontRegardless()
        }
        guard !Self.reducesMotion else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fade
            grip.animator().alphaValue = 1
            corner.animator().alphaValue = 1
        }
    }

    private func hide(animated: Bool) {
        guard isShown else { return }
        isShown = false
        followTimer?.invalidate()
        followTimer = nil
        let panels = [grip, corner].compactMap { $0 }
        guard animated, !Self.reducesMotion else {
            panels.forEach { $0.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fade
            panels.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isShown else { return }
                panels.forEach { $0.orderOut(nil) }
            }
        })
    }

    private static var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func drag(_ phase: CardEditView.Phase, resize: Bool) {
        tracker.update(phase, resize: resize)
        refresh()
    }

    func makePanel(resize: Bool) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .aboveGameOverlay
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = CardHandleView(resize: resize) { [weak self] phase in self?.drag(phase, resize: resize) }
        return panel
    }
}

/// One handle. Plain AppKit mouse handling: it takes the first click even though this app is not active,
/// and never asks to become key.
final class CardHandleView: NSView {
    private let resize: Bool
    private let onDrag: (CardEditView.Phase) -> Void
    private var dragging = false

    init(resize: Bool, onDrag: @escaping (CardEditView.Phase) -> Void) {
        self.resize = resize
        self.onDrag = onDrag
        super.init(frame: .zero)
        let art = NSHostingView(rootView: CardHandleArt(resize: resize))
        art.translatesAutoresizingMaskIntoConstraints = false
        addSubview(art)
        NSLayoutConstraint.activate([
            art.leadingAnchor.constraint(equalTo: leadingAnchor), art.trailingAnchor.constraint(equalTo: trailingAnchor),
            art.topAnchor.constraint(equalTo: topAnchor), art.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.handle)
        setAccessibilityLabel(resize ? "Resize the next opponent card" : "Move the next opponent card")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: resize ? .crosshair : .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        dragging = false
        if !resize { NSCursor.closedHand.push() }
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag(dragging ? .changed : .began)
        dragging = true
    }

    override func mouseUp(with event: NSEvent) {
        if !resize { NSCursor.pop() }
        if dragging { onDrag(.ended) }
        dragging = false
    }
}

private struct CardHandleArt: View {
    let resize: Bool

    var body: some View {
        if resize {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(EdgeInkPalette.gold, in: RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(EdgeInkPalette.gold, in: Capsule())
        }
    }
}

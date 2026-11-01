import AppKit
import SwiftUI

extension Notification.Name {
    static let moveNextOpponentCard = Notification.Name("moveNextOpponentCard")
    static let resetNextOpponentCard = Notification.Name("resetNextOpponentCard")
}

/// Pure math for moving and resizing the card by hand, in game-window coordinates (top-left origin).
enum CardEditGeometry {
    static let hintHeight: CGFloat = 28
    static let handleSize: CGFloat = 16

    /// Mouse travel in screen coordinates (Cocoa: y up) as a move in the game window (y down).
    static func canvasDelta(fromScreen start: CGPoint, to current: CGPoint) -> CGSize {
        CGSize(width: current.x - start.x, height: start.y - current.y)
    }

    static func moved(_ frame: CGRect, by delta: CGSize, canvas: CGSize) -> CardPlacement {
        let scale = frame.width / NextOpponentLayout.designWidth
        let origin = CGPoint(x: frame.minX + delta.width, y: frame.minY + delta.height)
        return CardPlacement.make(origin: clamped(origin, size: frame.size, canvas: canvas), scale: scale, canvas: canvas)
    }

    /// Dragging the bottom-right corner: the card keeps its aspect, so only the width counts.
    static func resized(_ frame: CGRect, by delta: CGSize, canvas: CGSize) -> CardPlacement {
        let scale = (frame.width + delta.width) / NextOpponentLayout.designWidth
        return CardPlacement.make(origin: frame.origin, scale: scale, canvas: canvas)
    }

    private static func clamped(_ origin: CGPoint, size: CGSize, canvas: CGSize) -> CGPoint {
        CGPoint(x: max(0, min(origin.x, canvas.width - size.width)), y: max(0, min(origin.y, canvas.height - size.height)))
    }

    /// The editing panel in screen coordinates: over the card, with the hint bar just above it.
    static func panelFrame(card: CGRect, canvasCocoaFrame canvas: CGRect) -> CGRect {
        CGRect(x: canvas.minX + card.minX, y: canvas.maxY - card.maxY,
               width: max(card.width, 220), height: card.height + hintHeight)
    }
}

/// Lets the user move and resize the NEXT OPPONENT card. The overlay itself stays click-through; a separate
/// nonactivating panel sits over the card only while editing, so the game keeps being the active app and
/// gets its clicks and keys back as soon as editing ends.
@MainActor
final class CardEditController {
    private let model: OverlayModel
    private let canvasFrame: () -> CGRect?
    private var panel: EditPanel?
    private var timer: Timer?
    private var keyMonitor: Any?
    private let tracker: CardDragTracker

    var isEditing: Bool { panel != nil }

    init(model: OverlayModel, canvasFrame: @escaping () -> CGRect?) {
        self.model = model
        self.canvasFrame = canvasFrame
        tracker = CardDragTracker(model: model, canvasFrame: canvasFrame)
    }

    func start() {
        guard panel == nil else { return }
        model.isEditingCard = true
        let panel = EditPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: CardEditView(
            onMove: { [weak self] phase in self?.drag(phase, resize: false) },
            onResize: { [weak self] phase in self?.drag(phase, resize: true) },
            onReset: { [weak self] in self?.model.resetCardPlacement() },
            onDone: { [weak self] in self?.stop() }))
        self.panel = panel
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // Esc
            Task { @MainActor in self?.stop() }
            return nil
        }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.follow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        follow()
        panel.makeKeyAndOrderFront(nil)
    }

    func stop() {
        guard let panel else { return }
        timer?.invalidate()
        timer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel.orderOut(nil)
        self.panel = nil
        model.isEditingCard = false
    }

    /// Keeps the panel over the card, which moves as the user drags and when the window changes.
    private func follow() {
        guard let panel else { return }
        guard let canvas = canvasFrame(), let card = model.cardFrame else {
            // The game went to the background or the card has no room: hide the handles until it is back.
            panel.orderOut(nil)
            return
        }
        let frame = CardEditGeometry.panelFrame(card: card, canvasCocoaFrame: canvas)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.makeKeyAndOrderFront(nil) }
    }

    private func drag(_ phase: CardEditView.Phase, resize: Bool) {
        tracker.update(phase, resize: resize)
        follow()
    }
}

/// Turns a drag on a handle into a saved placement: move or resize from where the card was when the drag
/// began, written to the defaults on release. Shared by the edit mode and the hover handles.
@MainActor
final class CardDragTracker {
    private let model: OverlayModel
    private let canvasFrame: () -> CGRect?
    private var start: (mouse: CGPoint, frame: CGRect)?

    var isDragging: Bool { start != nil }

    init(model: OverlayModel, canvasFrame: @escaping () -> CGRect?) {
        self.model = model
        self.canvasFrame = canvasFrame
    }

    func update(_ phase: CardEditView.Phase, resize: Bool) {
        guard let canvas = canvasFrame(), let card = model.cardFrame else {
            start = nil
            model.isDraggingCard = false
            return
        }
        let mouse = NSEvent.mouseLocation
        switch phase {
        case .began:
            start = (mouse, card)
            model.isDraggingCard = true
        case .changed, .ended:
            guard let start else { self.start = (mouse, card); return }
            let delta = CardEditGeometry.canvasDelta(fromScreen: start.mouse, to: mouse)
            let placement = resize ? CardEditGeometry.resized(start.frame, by: delta, canvas: canvas.size)
                : CardEditGeometry.moved(start.frame, by: delta, canvas: canvas.size)
            model.saveCardPlacement(placement, canvas: canvas.size, persist: phase == .ended)
            if phase == .ended {
                self.start = nil
                model.isDraggingCard = false
            }
        }
    }
}

/// A borderless panel that can take Esc while editing without activating the app.
final class EditPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Outline, hint, drag area and resize handle drawn over the card while it is being placed.
struct CardEditView: View {
    enum Phase { case began, changed, ended }

    let onMove: (Phase) -> Void
    let onResize: (Phase) -> Void
    let onReset: () -> Void
    let onDone: () -> Void
    @State private var moving = false
    @State private var resizing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Drag to move · drag the corner to resize · Esc or Done to finish")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                Button("Reset", action: onReset).controlSize(.small)
                Button("Done", action: onDone).controlSize(.small).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 8)
            .frame(height: CardEditGeometry.hintHeight)
            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    // Not fully clear, so the whole card area takes the drag.
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(EdgeInkPalette.gold, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            onMove(moving ? .changed : .began)
                            moving = true
                        }
                        .onEnded { _ in
                            onMove(.ended)
                            moving = false
                        })
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                    .frame(width: CardEditGeometry.handleSize, height: CardEditGeometry.handleSize)
                    .background(EdgeInkPalette.gold, in: RoundedRectangle(cornerRadius: 3))
                    .padding(2)
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            onResize(resizing ? .changed : .began)
                            resizing = true
                        }
                        .onEnded { _ in
                            onResize(.ended)
                            resizing = false
                        })
                    .accessibilityLabel("Resize the card")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Placing the next opponent card")
    }
}

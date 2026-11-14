import AppKit
import SwiftUI

/// Borderless, always-on-top floating panel that hosts the widget's SwiftUI content.
final class WidgetPanel: NSPanel {
    /// Frame autosave name used to remember the dragged position between launches.
    private static let autosaveName = "EasyPeasyWidget"

    /// Gap between the panel and the bottom of the screen's visible frame (above the Dock).
    private static let bottomMargin: CGFloat = 24

    /// Creates the panel sized to fit the given SwiftUI content.
    init(content: some View) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        appearance = NSAppearance(named: .darkAqua)

        let host = NSHostingView(rootView: content)
        contentView = host
        setContentSize(host.fittingSize)
    }

    /// Borderless panels refuse key status by default; allow it so controls can take input.
    override var canBecomeKey: Bool { true }

    /// Centres the panel horizontally on the main screen, just above the Dock.
    func placeAtBottomCenter() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = frame.size
        let origin = NSPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: visible.minY + Self.bottomMargin
        )
        setFrameOrigin(origin)
    }

    /// Restores the last dragged position if one was saved, otherwise uses the default
    /// bottom-centre placement. The current (content-fitted) size is always kept.
    func restoreOrPlaceAtBottomCenter() {
        let name = Self.autosaveName
        let size = frame.size
        if setFrameUsingName(name) {
            // Keep the restored origin but discard any stale saved size.
            setFrame(NSRect(origin: frame.origin, size: size), display: true)
        } else {
            placeAtBottomCenter()
        }
        setFrameAutosaveName(name)
    }
}

/// Translucent HUD-style blur background that also lets the user drag the widget
/// by pressing anywhere on it.
struct WidgetBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = DraggableVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Visual effect view that starts a window drag on mouse down.
private final class DraggableVisualEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

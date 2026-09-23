import AppKit
import SwiftUI

/// Borderless floating panel, Spotlight-style. Closes on Esc / click-away.
final class Panel: NSPanel, NSWindowDelegate {
    init(model: SearchModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        delegate = self
        contentView = NSHostingView(rootView: SearchView(model: model))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func present() {
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - frame.height - f.height * 0.15))
        }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    /// Hide the app too, so focus returns to the app the user was in (like Spotlight).
    func dismiss(restoreFocus: Bool = true) {
        orderOut(nil)
        if restoreFocus && NSApp.isActive { NSApp.hide(nil) }
    }

    func windowDidResignKey(_ notification: Notification) {
        // A scan (hidden launch / menu expansion) may grab focus → take it back instead of closing.
        guard Scanner.holdingFocus > 0 else { return dismiss() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.makeKeyAndOrderFront(nil)
        }
    }
}

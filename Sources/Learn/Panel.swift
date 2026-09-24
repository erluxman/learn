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
    var onDismiss: () -> Void = {}

    /// App to hand focus back to on close (nil: Learn's own Settings was in front).
    var returnTo: NSRunningApplication?

    /// Closes only the panel — never hides Learn (that would hide an open Settings window too).
    func dismiss(restoreFocus: Bool = true) {
        let wasVisible = isVisible
        orderOut(nil)
        onDismiss()
        guard restoreFocus, wasVisible, NSApp.isActive else { return }
        if let app = returnTo, !app.isTerminated {
            NSApp.yieldActivation(to: app)
            app.activate()
        } else if let settings = NSApp.windows.first(where: { $0.isVisible && $0.title == SettingsWindow.title }) {
            settings.makeKeyAndOrderFront(nil)
        } else {
            NSApp.hide(nil)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // A scan (hidden launch / menu expansion) may grab focus → take it back instead of closing.
        guard Scanner.holdingFocus > 0 else { return dismiss(restoreFocus: false) }   // user clicked elsewhere: don't steal it back
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.makeKeyAndOrderFront(nil)
        }
    }
}

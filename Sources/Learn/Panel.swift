import AppKit
import SwiftUI

/// Borderless floating panel, Spotlight-style. Closes on Esc / click-away.
final class Panel: NSPanel, NSWindowDelegate {
    init(model: SearchModel) {
        let m = JellyMotion.margin   // clear room around the glass so it can wobble when dragged
        super.init(contentRect: NSRect(x: 0, y: 0, width: 720 + 2 * m, height: 520 + 2 * m),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false   // glass draws its own; a window shadow would outline the transparent frame
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        delegate = self
        motion.attach(self)
        contentView = NSHostingView(rootView: AppearanceRoot { SearchView(model: model).modifier(Jelly(motion: motion)).padding(m) })
    }

    private let motion = JellyMotion()

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func present() {
        var origin = frame.origin
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            origin = NSPoint(x: f.midX - frame.width / 2, y: f.maxY - frame.height - f.height * 0.15)
        }
        setFrameOrigin(origin)
        let entering = !isVisible
        if entering { alphaValue = 0 }   // SwiftUI springs the glass in; the window only fades
        // Like Spotlight: the panel takes the keyboard without activating Learn, so the app you were in stays
        // frontmost and its menu bar stays there and usable (Learn has no menus of its own to show).
        makeKeyAndOrderFront(nil)
        guard entering else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            animator().alphaValue = 1
        }
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
        // Cancelled (⎋, hotkey again): Ghostty's quick terminal comes back if the panel hid it. Clicked away: it stays gone.
        if restoreFocus && wasVisible { QuickTerminal.restore() } else { QuickTerminal.forget() }
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
            // Give the menu bar back to the app you were in, then take the keyboard again (without activating Learn).
            if let app = self.returnTo, !app.isTerminated, !app.isActive { app.activate() }
            self.makeKeyAndOrderFront(nil)
        }
    }
}

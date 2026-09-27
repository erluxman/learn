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
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self else { return }
            self.lastClickElsewhere = CACurrentMediaTime()
            if self.withoutKeyboard, self.isVisible { self.dismiss(restoreFocus: false) }   // no focus to lose: a click away closes it
        }
        contentView = NSHostingView(rootView: AppearanceRoot { SearchView(model: model).modifier(Jelly(motion: motion)).padding(m) })
    }

    private let motion = JellyMotion()
    private var presentedSpace = 0
    private(set) var withoutKeyboard = false
    private var lastClickElsewhere: CFTimeInterval = 0   // mouse down in another app (global monitor)
    private var clickMonitor: Any?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// `takeKey` false: shown without taking the keyboard (over Ghostty's quick terminal, which hides when it loses it);
    /// keys then arrive through Learn's key tap, and a click anywhere else closes the panel.
    func present(takeKey: Bool = true) {
        withoutKeyboard = !takeKey
        becomesKeyOnlyIfNeeded = !takeKey   // clicking a row mustn't take the keyboard either
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
        presentedSpace = Debug.space
        if takeKey { makeKeyAndOrderFront(nil) } else { orderFrontRegardless() }
        Debug.log("panel present key=\(isKeyWindow) space=\(Debug.space) front=\(Debug.front)")
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
        // Decided before hiding: hiding makes the panel lose focus, which must not wipe the note.
        let quickTerminalBack = wasVisible && restoreFocus && QuickTerminal.take()
        if wasVisible { QuickTerminal.forget() }
        Debug.log("panel dismiss restoreFocus=\(restoreFocus) wasVisible=\(wasVisible) space=\(Debug.space) front=\(Debug.front) from=\(Thread.callStackSymbols.dropFirst().prefix(3).map { $0.split(separator: " ").dropFirst(3).first.map(String.init) ?? "" })")
        orderOut(nil)
        onDismiss()
        // Cancelled (⎋, hotkey again): Ghostty's quick terminal comes back if the panel hid it. Clicked away: it stays gone.
        if quickTerminalBack { QuickTerminal.bringBack() }
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

    func windowDidBecomeKey(_ notification: Notification) {
        Debug.log("panel key space=\(Debug.space) front=\(Debug.front)")
    }

    func windowDidResignKey(_ notification: Notification) {
        let clicked = CACurrentMediaTime() - lastClickElsewhere < 0.6
        let switched = NSEvent.modifierFlags.contains(.command) || Debug.space != presentedSpace   // ⌘Tab, another desktop
            || NSApp.keyWindow.map { $0 !== self } == true   // one of Learn's own windows (Settings)
        Debug.log("panel resignKey clicked=\(clicked) switched=\(switched) space=\(Debug.space) front=\(Debug.front) visible=\(isVisible)")
        guard isVisible else { return }   // it's closing
        // Only you close it by leaving: a click in another app, ⌘Tab, another desktop. Anything else took the keyboard on its
        // own — e.g. Ghostty's quick terminal sliding away and macOS handing focus to the app behind it — so take it back.
        if !clicked && !switched && Scanner.holdingFocus == 0 {
            DispatchQueue.main.async { [weak self] in if let self, self.isVisible { self.makeKeyAndOrderFront(nil) } }
            return
        }
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

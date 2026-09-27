import AppKit

/// Where a terminal's character cells really are on screen. Terminals don't expose per-character bounds, and the text
/// area's frame includes the window padding, so dividing the frame by rows × columns drifts by up to a couple of cells
/// toward the right and bottom. Ghostty lays out whole-pixel cells inside its padding (`window-padding-x/y`), and with
/// `window-padding-balance` centres the grid horizontally with the top padding capped at the left one — recreated here.
struct TerminalGrid {
    let origin: CGPoint   // top-left of cell (0, 0), AX coords
    let cell: CGSize      // points

    func frame(row: Int, col: Int, length: Int) -> CGRect {
        CGRect(x: origin.x + CGFloat(col) * cell.width, y: origin.y + CGFloat(row) * cell.height,
               width: CGFloat(length) * cell.width, height: cell.height)
    }

    /// `frame`: the text area (AX coords). `pid`: the terminal's process, for its padding settings.
    static func make(frame f: CGRect, rows: Int, cols: Int, pid: pid_t) -> TerminalGrid {
        let app = NSRunningApplication(processIdentifier: pid)
        guard app?.bundleIdentifier == "com.mitchellh.ghostty", let exe = app?.executableURL else {
            return TerminalGrid(origin: f.origin, cell: CGSize(width: f.width / CGFloat(cols), height: f.height / CGFloat(rows)))
        }
        let pad = GhosttyPadding.current(exe)
        let s = scale(of: f)
        let w = f.width * s, h = f.height * s   // device pixels, where Ghostty does its layout
        // The cell size (whole pixels) that gives exactly this many columns/rows inside the padding.
        let cw = ((w - (pad.left + pad.right) * s) / CGFloat(cols)).rounded(.down)
        let ch = ((h - (pad.top + pad.bottom) * s) / CGFloat(rows)).rounded(.down)
        guard cw > 0, ch > 0 else { return TerminalGrid(origin: f.origin, cell: CGSize(width: f.width / CGFloat(cols), height: f.height / CGFloat(rows))) }
        var left = pad.left * s, top = pad.top * s
        if pad.balance {
            left = ((w - CGFloat(cols) * cw) / 2).rounded(.down)
            top = min(left, ((h - CGFloat(rows) * ch) / 2).rounded(.down))
        }
        return TerminalGrid(origin: CGPoint(x: f.minX + left / s, y: f.minY + top / s), cell: CGSize(width: cw / s, height: ch / s))
    }

    /// Backing scale of the screen the frame is on (AX coords: top-left origin of the primary screen).
    private static func scale(of f: CGRect) -> CGFloat {
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let mid = CGPoint(x: f.midX, y: primary - f.midY)
        return (NSScreen.screens.first { $0.frame.contains(mid) } ?? NSScreen.main)?.backingScaleFactor ?? 2
    }
}

/// Ghostty's window padding, from `ghostty +show-config` (the resolved config, includes and defaults applied).
/// Cached for a minute: it's read on every on-screen scan.
private enum GhosttyPadding {
    struct Value { var left = 2.0, right = 2.0, top = 2.0, bottom = 2.0, balance = false }   // Ghostty's defaults

    private static var cache: (at: Date, value: Value)?

    static func current(_ exe: URL) -> Value {
        if let c = cache, Date().timeIntervalSince(c.at) < 60 { return c.value }
        var v = Value()
        let p = Process(), out = Pipe()
        p.executableURL = exe
        p.arguments = ["+show-config"]
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil {
            let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            for line in text.split(separator: "\n") {
                let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard kv.count == 2 else { continue }
                let nums = kv[1].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                switch kv[0] {
                case "window-padding-x" where !nums.isEmpty: v.left = nums[0]; v.right = nums.last!   // "16" or "16,20"
                case "window-padding-y" where !nums.isEmpty: v.top = nums[0]; v.bottom = nums.last!
                case "window-padding-balance": v.balance = kv[1] == "true"
                default: break
                }
            }
        }
        cache = (Date(), v)
        return v
    }
}

# Learn — Spotlight-style shortcut launcher for macOS

## Goal
Floating search panel (Spotlight look). Type app name → pick app → searchable list of that app's
keyboard shortcuts → Enter/click runs the shortcut in that app. Shortcut DB stays in sync with
system + app changes; per-app "Refresh".

## Architecture (Swift Package, AppKit + SwiftUI, no deps)
| File | Job |
|---|---|
| `Package.swift` | exec target `Learn`, macOS 14+ |
| `Sources/Learn/main.swift` | NSApplication bootstrap, accessory (no Dock icon) |
| `AppDelegate.swift` | wiring: hotkey, panel, watchers, status-bar menu, reopen handling |
| `HotKey.swift` | global hotkey via Carbon `RegisterEventHotKey` (default ⌥Space) |
| `Panel.swift` | borderless floating `NSPanel`, Esc/click-away closes |
| `SearchView.swift` | SwiftUI: search field + list; two modes: apps → shortcuts |
| `Models.swift` | `AppEntry`, `Shortcut` (menu path, key, modifiers, source) |
| `AppCatalog.swift` | enumerate `.app` in /Applications, /System/Applications(+Utilities), ~/Applications, /System/Library/CoreServices (Finder) |
| `MenuScanner.swift` | Accessibility API: walk `AXMenuBar` → every item with `AXMenuItemCmdChar/VirtualKey/Modifiers` |
| `SystemShortcuts.swift` | parse `com.apple.symbolichotkeys` (Mission Control, Spotlight, screenshots…) + `NSUserKeyEquivalents` custom overrides |
| `ShortcutStore.swift` | DB = JSON per bundle id in `~/Library/Application Support/Learn/db/` (+ in-memory cache) |
| `Watchers.swift` | FSEvents-like `DispatchSource` watch on `~/Library/Preferences` → system/custom shortcut change → re-sync; `NSWorkspace` app-activate → background rescan of that app |
| `Executor.swift` | activate target app, `AXPress` matching menu item (exact), fallback: synthesize key via `CGEvent` |
| `Fuzzy.swift` | tiny fuzzy scorer (subsequence + prefix bonus) |
| `build.sh` | `swift build -c release` → assemble `Learn.app` (Info.plist, LSUIElement) → codesign w/ Apple Development id → copy to `~/Applications` (so Spotlight finds it) |

## Behavior
1. **Trigger**: ⌥Space hotkey, or open "Learn" from Spotlight (reopen event → show panel), or menu-bar icon.
2. **Apps mode**: all installed apps, running ones first, fuzzy search, ↑↓ Enter / click.
3. **Shortcuts mode**: header w/ app icon + "Refresh ⌘R" button. List: `⌘⇧N  File ▸ New Folder`.
   Search matches title + menu path + key glyphs. Esc / ⌫ on empty → back to apps.
   - Cached → show instantly. Not cached → scan (app running: direct; not running: launch hidden,
     scan, quit again).
4. **Execute**: if app running → activate + press menu item via AX (works even if key changed).
   If not running → launch then execute. System shortcuts → post keystroke.
5. **Sync**:
   - symbolichotkeys / NSUserKeyEquivalents plist change → rebuild System entry + mark affected app stale.
   - app activation → silent rescan if cache older than 10 min (catches internal changes).
   - "Refresh" button → force rescan now.
   - menu-bar menu: "Scan all running apps", "Scan ALL installed apps (launches each hidden)".
6. **Permissions**: Accessibility prompt on first launch (needed for read + execute).

## Steps
1. Scaffold package + models + build script → builds empty app
2. Hotkey + panel + app catalog + apps list UI
3. MenuScanner (AX) + store → shortcuts list UI
4. System shortcuts + custom overrides parser
5. Executor
6. Watchers + refresh + bulk scan + status menu
7. Build, sign, install to ~/Applications, smoke test

## Status (all steps done)
Build/install: `./build.sh` → `~/Applications/Learn.app`. DB: `~/Library/Application Support/Learn/db/*.json`.

## Known limits
- Only shortcuts that appear in the menu bar are readable. In-editor keybindings (VS Code, JetBrains,
  terminals, games) that have no menu item are invisible to AX.
- Menus built lazily (only when opened) may be partly missing until the app has built them.
- Hotkey is fixed at ⌥Space (`AppDelegate.swift`, `HotKey(...)`).

## Custom shortcuts (⌘↩ on a row)
Recorder → binding saved in Learn's own `~/Library/Application Support/Learn/bindings.json` (app + menu path + combo).
A global CGEvent tap (`KeyTap` in `Bindings.swift`) catches the combo in the frontmost app, swallows it and presses the
menu item via AX (opening lazy submenus first if needed). Works instantly, no app restart, in any app with a menu bar.
Nothing is written into the apps' own preferences.

## On-screen elements
- `ElementScanner`: walks visible windows' AX tree (0.6s / 4000-node budget, clipped to scroll areas) for
  buttons, rows, tabs, fields, links, pressable icons. Enables `AXManualAccessibility` for Electron.
- Learn panel lists them ("screen" tag) with menu items; selection draws a highlight box; ↩ presses/focuses/
  selects (real click as last resort); ⌘↩ binds (located later by role + text).
- Label mode (`HintMode`, default ⌘⇧Space, rebindable via the "Learn ▸ Label clickable items on screen" row):
  yellow letter labels over every element; type a label to click. Keys captured by the KeyTap interceptor.
- Limits: Chromium browsers (Brave) expose only toolbar items, not page content; canvas UIs expose nothing;
  only windows on the current Space are visible to AX.

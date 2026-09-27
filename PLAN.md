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
| `SearchView.swift` | SwiftUI, native Spotlight look (macOS 26): one plain glass shape, 640pt wide — 54pt search pill when nothing typed, grows into 56pt rows (36pt icon, 17pt title, 15pt grey subtitle, keys as grey text on the right), inline "— top hit" tag after the typed text, top-hit icon on the right. No header/footer/section titles; glass/font from Settings ▸ Appearance (defaults = Spotlight). Two modes: apps → shortcuts |
| `Models.swift` | `AppEntry`, `Shortcut` (menu path, key, modifiers, source) |
| `AppCatalog.swift` | enumerate `.app` in /Applications, /System/Applications(+Utilities), ~/Applications, /System/Library/CoreServices (Finder) |
| `MenuScanner.swift` | Accessibility API: walk `AXMenuBar` → every item with `AXMenuItemCmdChar/VirtualKey/Modifiers` |
| `SystemShortcuts.swift` | parse `com.apple.symbolichotkeys` (Mission Control, Spotlight, screenshots…) + `NSUserKeyEquivalents` custom overrides |
| `ShortcutStore.swift` | DB = JSON per bundle id in `~/Library/Application Support/Learn/db/` (+ in-memory cache) |
| `Watchers.swift` | FSEvents-like `DispatchSource` watch on `~/Library/Preferences` → system/custom shortcut change → re-sync; `NSWorkspace` app-activate → background rescan of that app |
| `Executor.swift` | activate target app, `AXPress` matching menu item (exact), fallback: synthesize key via `CGEvent` |
| `PointerMode.swift` | keyboard mouse (Learn command, default ⌥⇧Space): HJKL/arrows move (hold = accelerate, ⇧ slow, ⌥ scroll), Space click, D double, R right-click, V drag, hotkey again = next screen, ⎋ exit |
| `Bindings.swift` KeyTap chord | left ⌃ + right ⌃ pressed together, released with no other key → right-click at pointer (Settings toggle) |
| `KeyHUD.swift` | bottom-centre bubble: shortcut pressed / recorded / run by Learn + its command name; sticky pointer-mode hint |
| `SpotlightKey.swift` | optional ⌘Space takeover: rewrites Spotlight's symbolichotkeys #64 (off, or moved to ⌥Space) + `activateSettings -u`; uninstall.sh restores |
| `Answers.swift` | instant answers in top-level search: calculator (own parser, no NSExpression), unit conversions (Measurement), definitions (DCSCopyTextDefinition) |
| `FileSearch.swift` | home-folder file search via NSMetadataQuery (Spotlight index); icons from UTI so no folder-access prompts |
| `HUDStyleView.swift` | `HUDStyleSections`: shortcut bubble look, embedded in Settings ▸ On Screen; live mini-screen preview (tap a spot = position), backdrop (default "Spotlight": plain dark Liquid Glass, SF 26/15pt, radius 26), font, sizes, colors, frosted (Liquid Glass), padding, corners, shadow, duration, fade/slide/pop/none. Stored as `HUDStyle` JSON in prefs |
| `Usage.swift` | `UsageStore`: per-app use counts (run from Learn or pressed in the app, via the key tap), 2-week half-life → "Frequently used" rows at the top of an app's list / the top level. Saved in `usage.json` |
| `Relevance.swift` | `RelevanceStore`: on-device relevance per shortcut, recomputed after every scan — NLEmbedding similarity to a sample of always-useful commands, prevalence across your apps, your use elsewhere, key simplicity, menu depth, app "signature" keys; basics/housekeeping sink. ⇥ on an empty search shows the top 12 as "Suggested" |
| `Sounds.swift` | click + shortcut-run sounds (Settings ▸ Sounds): 7 synthesized in code (WAV in memory, no files) + macOS system sounds; volume. Clicks: liquid/row/glass buttons, toggles; runs: Executor, custom bindings, on-screen items, answer copy |
| `ThemeDesigner.swift` | Arc-style theme designer (Settings ▸ Appearance ▸ Theme): hue/saturation wheel with 1–3 draggable dots (first turns the rest), intensity, darkness, grain, presets, shuffle. Glass is tinted with the colors' blend; 2–3 colors add a light gradient sheen + optional tiled grain on the glass |
| `Texture.swift` | Settings ▸ Appearance ▸ Glass & texture (Glass: Liquid | Frosted switch + Opacity for every blur; defaults = Spotlight, "Reset to Spotlight Look"): `BlurStyle` (Liquid Glass ×2, SwiftUI materials ×5, AppKit behind-window ×10, none) + amount; `GrainStyle` (11 generated seamless tiles, each with its blend) + amount + size |
| `Theme.swift` | design system: radii, springs, `liquidGlass(in:)` (macOS 26 glass, material fallback), `GlassGroup`, `Keycaps`, `IconTile`, `KeyHint` |
| `SettingsView.swift` | sidebar Settings (Permissions · Hotkeys · Learn Panel · On Screen · Search · Advanced · My Shortcuts), hero per pane, `KeyRecorder` |
| `TerminalGrid.swift` | where a terminal's character cells really are (Ghostty: whole-pixel cells inside `window-padding-x/y` from `ghostty +show-config`, balanced padding = centred, top ≤ left), so on-screen terminal text (herdr buttons) is outlined and clicked exactly |
| `Fuzzy.swift` | tiny fuzzy scorer (subsequence + prefix bonus) |
| `build.sh` | `swift build -c release` → assemble `Learn.app` (Info.plist, LSUIElement) → codesign w/ Apple Development id → copy to `/Applications` (so Spotlight finds it; removes any old `~/Applications` copy) |

## Behavior
1. **Trigger**: ⌥Space hotkey, or open "Learn" from Spotlight (reopen event → show panel), or menu-bar icon.
2. **Apps mode**: all installed apps, running ones first, fuzzy search, ↑↓ Enter / click.
3. **Shortcuts mode**: header w/ app icon + "Refresh ⌘R" button. List: `⌘⇧N  File ▸ New Folder`.
   Search matches title + menu path + key glyphs. Esc / ⌫ on empty → back to apps.
   - Cached → show instantly. Not cached → scan (app running: direct; not running: launch hidden,
     scan, quit again).
   - **From anywhere**: any query (3+ chars) also ranks every scanned app's shortcuts (app name counts as a search word,
     e.g. "brave profile", "record screen"). Top level: after apps named like the query; inside an app: after its own items
     (max 8). Duplicates of standard items (Emoji & Symbols…) listed once, running apps preferred. Index built on panel
     open (search text cached), ranked off main per keystroke. ↩ = Executor: activates or launches the app, presses the item.
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
7. Build, sign, install to /Applications, smoke test

## Status (all steps done)
Build/install: `./build.sh` → `/Applications/Learn.app`. DB: `~/Library/Application Support/Learn/db/*.json`.

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

## Settings (⌘, in panel · menu bar ▸ Settings… · "Learn ▸ Open Learn Settings" row)
- Permissions: Accessibility, post events, Input Monitoring (live, 1s refresh, Grant buttons), launch at login.
  Opens automatically at launch when Accessibility is missing.
- General: recordable panel hotkey (Prefs.panelKey, Carbon; warns when taken) + labels hotkey (global binding),
  show on-screen items / key-less menu commands, rescan interval, scan buttons, debug log toggle.
- Shortcuts: all recorded bindings grouped by app, removable.
- `Prefs.swift` (UserDefaults), `SettingsView.swift`; `Recorder.active` pauses hotkey + key tap while recording.

## Packaging
- `./package.sh` → `dist/Learn.dmg` + `dist/Learn.zip` (universal arm64+x86_64, signed with the first Apple
  Development identity). Icon: `Resources/AppIcon.icns` (regenerate: `swift scripts/make_icon.swift <out.iconset>`
  + `iconutil -c icns`).
- `./uninstall.sh [--purge]` → quits, removes /Applications + ~/Applications copies, `tccutil reset`
  Accessibility / ListenEvent / PostEvent; `--purge` also deletes data + settings.
- `./build.sh` is the dev loop (installs to /Applications, replacing the DMG copy there).
- Opening the app → Settings (Permissions tab if anything's missing); the hotkey → search. Silent at login.

## On-screen items
- Typing inside an app ranks on-screen items one Fuzzy tier up (`onScreenBoost`), so ⌘Space → type finds the button without ⇥. ⎋ closes in one press (⌫ on empty = back to the app list).
- ⇥ on an empty search inside an app: search only what's on screen (buttons, links, text) — no shortcuts, apps or files. ⇥ / ⌫ / ⎋ on empty leaves it. ⇧⇥: frequently used ↔ suggested shortcuts.
- Chromium browsers (Brave, Chrome, Edge, Arc…) expose page contents only after `AXEnhancedUserInterface` is turned on, and forget it on restart. Learn keeps it on, never off: at launch, when a browser launches, whenever one comes to the front, and in the scan (which rescans ≤ 4 × 0.8 s while a freshly enabled browser builds its page tree, ~2 s).
- Ghostty's quick terminal (`QuickTerminal.swift`) hides when it loses key status (`quick-terminal-autohide`), which the panel always causes. Learn grabs it before the panel opens and scans only it; before running a shortcut / click in Ghostty, or when the panel is cancelled, it closes the panel first, then brings it back via Ghostty's AppleScript (`perform action "toggle_quick_terminal"`, needs Automation permission) and waits for the slide-in.
- On a desktop with no Ghostty window, macOS refuses Ghostty's activation when the quick terminal slides in (ghostty#2409): it has the keyboard but the previous app stays "frontmost". So a quick terminal on screen = you're in Ghostty (`ghosttyIfOnScreen`), whatever `frontmostApplication` says.
- Over the quick terminal the panel opens **without taking the keyboard** (`present(takeKey: false)`), so the drop-down keeps focus and stays visible. `KeyTap.panelKeys` hands the panel every key press/release (same handler as the focused panel: arrows, ↩, ⇥, chord, ⎋; typing / ⌫ / ⌘⌫ / ⌘V edit the query) and swallows them; the panel hotkey passes through. A click anywhere else closes it.
- The panel closes on losing focus only when you left: a click in another app (global mouse monitor), ⌘Tab, another desktop, or one of Learn's own windows. Anything else (Ghostty handing focus to the app behind it) → it takes focus back.

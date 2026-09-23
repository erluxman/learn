import SwiftUI

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !model.trusted { permissionBanner }
            list
                .overlay { if let r = model.recording { recorder(r) } }
            Divider()
            footer
        }
        .frame(width: 720, height: 480)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.12)))
        .onAppear { focused = true }
        .onChange(of: model.focusTick) { focused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let app = model.currentApp {
                HStack(spacing: 6) {
                    Image(nsImage: AppCatalog.icon(app)).resizable().frame(width: 22, height: 22)
                    Text(app.name).font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
            } else {
                Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(.secondary)
            }
            TextField(model.currentApp == nil ? "Search apps" : "Search shortcuts", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .light))
                .focused($focused)
            if model.scanning { ProgressView().controlSize(.small) }
            if model.currentApp != nil {
                Button { model.refresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise").font(.system(size: 12))
                }
                .help("Re-read this app's shortcuts (⌘R)")
                .disabled(model.scanning)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var permissionBanner: some View {
        HStack {
            Image(systemName: "lock.shield").foregroundStyle(.orange)
            Text("Learn needs Accessibility access to read and run shortcuts.").font(.system(size: 12))
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.orange.opacity(0.12))
    }

    // Rows are identified by element id only (never by index) so filtering/mode changes can't show stale rows.
    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if model.currentApp != nil {
                        ForEach(Array(model.shortcuts.enumerated()), id: \.element.id) { i, s in
                            ShortcutRow(s: s, selected: i == model.selection)
                                .onTapGesture { model.activate(i) }
                        }
                    } else {
                        ForEach(Array(model.apps.enumerated()), id: \.element.id) { i, a in
                            AppRow(app: a, selected: i == model.selection)
                                .onTapGesture { model.activate(i) }
                        }
                    }
                }
                .padding(6)
            }
            .id(model.currentApp?.id ?? "apps")   // fresh list per mode
            .onChange(of: model.selection) { _, _ in
                if let id = model.selectedID { proxy.scrollTo(id) }
            }
        }
    }

    private func recorder(_ item: Shortcut) -> some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.35))
            VStack(spacing: 14) {
                Text("New shortcut for").font(.system(size: 12)).foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    Text(item.title).font(.system(size: 17, weight: .semibold))
                    if !item.location.isEmpty { Text(item.location).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Text(model.recordedShortcut?.display ?? "Press keys…")
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .foregroundStyle(model.recordedShortcut == nil ? .secondary : .primary)
                    .frame(minWidth: 220, minHeight: 56)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                if item.hasKey { Text("Current: \(item.display)\(item.isCustom ? " (custom)" : "")").font(.system(size: 11)).foregroundStyle(.secondary) }
                if let c = model.conflicts.first {
                    Label("Already used by \((c.path).joined(separator: " ▸ "))", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
                Text("Works right away in \(model.currentApp?.name ?? "the app") — Learn runs the menu item.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text(item.isCustom ? "↩ save   ⌫ remove custom   ⎋ cancel" : "↩ save   ⎋ cancel").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 20)
        }
    }

    private var footer: some View {
        HStack {
            Text(model.notice ?? model.info)
            Spacer()
            Text(model.currentApp == nil ? "↑↓ select  ↩ open  ⎋ close" : "↩ run  ⌘↩ set shortcut  ⌘R refresh  ⌫/⎋ all apps")
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 7)
    }
}

private struct AppRow: View {
    let app: AppEntry
    let selected: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppCatalog.icon(app)).resizable().frame(width: 28, height: 28)
            Text(app.name).font(.system(size: 15))
            Spacer()
            if app.runningApp != nil { Circle().fill(.green).frame(width: 6, height: 6) }
            if let e = ShortcutStore.shared.get(app.id) {
                Text("\(e.shortcuts.count)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .rowStyle(selected)
    }
}

private struct ShortcutRow: View {
    let s: Shortcut
    let selected: Bool
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title).font(.system(size: 14))
                if !s.location.isEmpty {
                    Text(s.location).font(.system(size: 11)).foregroundStyle(selected ? .white.opacity(0.75) : .secondary)
                }
            }
            Spacer()
            if let orig = s.original {
                Text(orig.isEmpty ? "custom" : "custom · was \(orig)")
                    .font(.system(size: 10)).foregroundStyle(selected ? .white.opacity(0.7) : .secondary)
            }
            if s.hasKey {
                Text(s.display)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((selected ? Color.white : Color.primary).opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            } else {
                Text(s.path.first == ElementScanner.marker ? "screen" : s.path.first == LearnActions.group ? "learn" : "menu")
                    .font(.system(size: 11)).foregroundStyle(selected ? .white.opacity(0.7) : .secondary)
            }
        }
        .rowStyle(selected)
    }
}

private extension View {
    func rowStyle(_ selected: Bool) -> some View {
        padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(selected ? .white : .primary)
            .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

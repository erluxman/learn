import SwiftUI

/// Three-stop gradients, picked from a dot: per page beside its title (Settings pages and Cleaner modules), and for
/// the shortcut keys in Settings ▸ General. Collected from uiGradients and webgradients (two-stop ones got their
/// midpoint as the third stop), in three groups, each ordered by hue. Picks are stored in Prefs (pageGradients,
/// keyGradient), readable with `defaults read com.erluxman.learn`.
struct GradientPreset: Identifiable, Hashable {
    enum Group: String, CaseIterable {
        case vivid, similar, muted
        var title: String {
            switch self { case .vivid: "Vivid"; case .similar: "Similar tones"; case .muted: "Soft & muted" }
        }
    }
    let name: String
    let hex: [UInt32]
    let group: Group
    var id: String { name }
    var colors: [Color] { hex.map { Color(hex: $0) } }

    static func named(_ name: String) -> GradientPreset? { all.first { $0.name == name } }
    /// The gradient picked for `page` ("settings.appearance", "cleaner.cleanup", …), if any.
    static func pick(_ page: String) -> GradientPreset? { Prefs.shared.pageGradients[page].flatMap(named) }

    static let all: [GradientPreset] = [
        GradientPreset(name: "Instagram", hex: [0x833AB4, 0xFD1D1D, 0xFCB045], group: .vivid),
        GradientPreset(name: "King Yna", hex: [0x1A2A6C, 0xB21F1F, 0xFDBB2D], group: .vivid),
        GradientPreset(name: "Angel Care", hex: [0xFFE29F, 0xFFA99F, 0xFF719A], group: .vivid),
        GradientPreset(name: "MegaTron", hex: [0xC6FFDD, 0xFBD786, 0xF7797D], group: .vivid),
        GradientPreset(name: "Subu", hex: [0x0CEBEB, 0x20E3B2, 0x29FFC6], group: .vivid),
        GradientPreset(name: "Supreme Sky", hex: [0xD4FFEC, 0x57F2CC, 0x4596FB], group: .vivid),
        GradientPreset(name: "Hazel", hex: [0x77A1D3, 0x79CBCA, 0xE684AE], group: .vivid),
        GradientPreset(name: "Burning Spring", hex: [0x4FB576, 0x28A9AE, 0x432C39], group: .vivid),
        GradientPreset(name: "Aqua Guidance", hex: [0x007ADF, 0x00B3CE, 0x00ECBC], group: .vivid),
        GradientPreset(name: "Stripe", hex: [0x1FA2FF, 0x12D8FA, 0xA6FFCB], group: .vivid),
        GradientPreset(name: "Arielle's Smile", hex: [0x16D9E3, 0x30C7EC, 0x46AEF7], group: .vivid),
        GradientPreset(name: "Space Shift", hex: [0x3D3393, 0x2CACD1, 0x35EB93], group: .vivid),
        GradientPreset(name: "Moonlit Asteroid", hex: [0x0F2027, 0x203A43, 0x2C5364], group: .vivid),
        GradientPreset(name: "Dense Water", hex: [0x3AB5B0, 0x3D99BE, 0x56317A], group: .vivid),
        GradientPreset(name: "Lunada", hex: [0x5433FF, 0x20BDFF, 0xA5FECB], group: .vivid),
        GradientPreset(name: "Mind Crawl", hex: [0x473B7B, 0x3584A7, 0x30D2BE], group: .vivid),
        GradientPreset(name: "Jodhpur", hex: [0x9CECFB, 0x65C7F7, 0x0052D4], group: .vivid),
        GradientPreset(name: "Royal Blue + Petrol", hex: [0xBBD2C5, 0x536976, 0x292E49], group: .vivid),
        GradientPreset(name: "Crystal River", hex: [0x22E1FF, 0x1D8FE1, 0x625EB1], group: .vivid),
        GradientPreset(name: "Morpheus Den", hex: [0x30CFD0, 0x326C9C, 0x330867], group: .vivid),
        GradientPreset(name: "Sea Strike", hex: [0x77FFD2, 0x6297DB, 0x1EECFF], group: .vivid),
        GradientPreset(name: "Omolon", hex: [0x091E3A, 0x2F80ED, 0x2D9EE0], group: .vivid),
        GradientPreset(name: "Deep Relief", hex: [0x7085B6, 0x87A7D9, 0xDEF3F8], group: .vivid),
        GradientPreset(name: "Azur Lane", hex: [0x7F7FD5, 0x86A8E7, 0x91EAE4], group: .vivid),
        GradientPreset(name: "Cold Evening", hex: [0x0C3483, 0xA2B6DF, 0x6B8CCE], group: .vivid),
        GradientPreset(name: "Black Sea", hex: [0x2CD8D5, 0x6B8DD6, 0x8E37D7], group: .vivid),
        GradientPreset(name: "Midnight Bloom", hex: [0x2B5876, 0x3C4E76, 0x4E4376], group: .vivid),
        GradientPreset(name: "Bluelagoo", hex: [0x0052D4, 0x4364F7, 0x6FB1FC], group: .vivid),
        GradientPreset(name: "Sky Glider", hex: [0x88D3CE, 0x7B8CD8, 0x6E45E2], group: .vivid),
        GradientPreset(name: "October Silence", hex: [0xB721FF, 0x6C7AFE, 0x21D4FD], group: .vivid),
        GradientPreset(name: "Memariani", hex: [0xAA4B6B, 0x6B6B83, 0x3B8D99], group: .vivid),
        GradientPreset(name: "Perfect Blue", hex: [0x3D4E81, 0x5753C9, 0x6E7FF3], group: .vivid),
        GradientPreset(name: "Sea Lord", hex: [0x2CD8D5, 0xC5C1FF, 0xFFBAC3], group: .vivid),
        GradientPreset(name: "Lawrencium", hex: [0x0F0C29, 0x302B63, 0x24243E], group: .vivid),
        GradientPreset(name: "Plum Plate", hex: [0x667EEA, 0x6E64C6, 0x764BA2], group: .vivid),
        GradientPreset(name: "Sleepless Night", hex: [0x5271C4, 0xB19FFF, 0xECA1FE], group: .vivid),
        GradientPreset(name: "Frozen Heat", hex: [0xFF057C, 0x7C64D5, 0x4CC3FF], group: .vivid),
        GradientPreset(name: "Lily Meadow", hex: [0x65379B, 0x886AEA, 0x6457C6], group: .vivid),
        GradientPreset(name: "Magic", hex: [0x59C173, 0xA17FE0, 0x5D26C1], group: .vivid),
        GradientPreset(name: "Night Party", hex: [0x0250C5, 0x6B48A9, 0xD43F8D], group: .vivid),
        GradientPreset(name: "Mars Party", hex: [0x5F72BD, 0x7D4AD4, 0x9B23EA], group: .vivid),
        GradientPreset(name: "Smart Indigo", hex: [0xB224EF, 0x944EF7, 0x7579FF], group: .vivid),
        GradientPreset(name: "Wide Matrix", hex: [0xFF7882, 0x7046AA, 0x0C1DB8], group: .vivid),
        GradientPreset(name: "Night Call", hex: [0xAC32E4, 0x7918F2, 0x4801FF], group: .vivid),
        GradientPreset(name: "Fabled Sunset", hex: [0x231557, 0x44107A, 0xFF1361], group: .vivid),
        GradientPreset(name: "Magic Ray", hex: [0xFF3CAC, 0x562B7C, 0x2B86C5], group: .vivid),
        GradientPreset(name: "Red Sunset", hex: [0x355C7D, 0x6C5B7B, 0xC06C84], group: .vivid),
        GradientPreset(name: "Radar", hex: [0xA770EF, 0xCF8BF3, 0xFDB99B], group: .vivid),
        GradientPreset(name: "JShine", hex: [0x12C2E9, 0xC471ED, 0xF64F59], group: .vivid),
        GradientPreset(name: "Norse Beauty", hex: [0xEC77AB, 0xB275D0, 0x7873F5], group: .vivid),
        GradientPreset(name: "Gagarin View", hex: [0x69EACB, 0xEACCF8, 0x6654F1], group: .vivid),
        GradientPreset(name: "New Retrowave", hex: [0x3B41C5, 0xA981BB, 0xFFC8A9], group: .vivid),
        GradientPreset(name: "Plum Bath", hex: [0xCC208E, 0x9A1AB0, 0x6713D2], group: .vivid),
        GradientPreset(name: "Sweet Dessert", hex: [0x7742B2, 0xF180FF, 0xFD8BD9], group: .vivid),
        GradientPreset(name: "Atlas", hex: [0xFEAC5E, 0xC779D0, 0x4BC0C8], group: .vivid),
        GradientPreset(name: "Teen Party", hex: [0xFF057C, 0x8D0B93, 0x321575], group: .vivid),
        GradientPreset(name: "Star Wine", hex: [0xB465DA, 0xCF6CC9, 0xEE609C], group: .vivid),
        GradientPreset(name: "Sweet Period", hex: [0x3F51B1, 0xA86AA4, 0xF7C978], group: .vivid),
        GradientPreset(name: "Racker", hex: [0xEB0000, 0x95008A, 0x3300FC], group: .vivid),
        GradientPreset(name: "Soft Cherish", hex: [0xE7627D, 0x801357, 0x1C1A27], group: .vivid),
        GradientPreset(name: "Red Salvation", hex: [0xF43B47, 0x9C3A6E, 0x453A94], group: .vivid),
        GradientPreset(name: "Sugar Lollipop", hex: [0xA445B2, 0xD41872, 0xFF0066], group: .vivid),
        GradientPreset(name: "Young Passion", hex: [0xFF8177, 0xCF556C, 0xB12A5B], group: .vivid),
        GradientPreset(name: "Amour Amour", hex: [0xF77062, 0xFA607C, 0xFE5196], group: .vivid),
        GradientPreset(name: "Wiretap", hex: [0x8A2387, 0xE94057, 0xF27121], group: .vivid),
        GradientPreset(name: "Relay", hex: [0x3A1C71, 0xD76D77, 0xFFAF7B], group: .vivid),
        GradientPreset(name: "Namn", hex: [0xA73737, 0x903030, 0x7A2828], group: .similar),
        GradientPreset(name: "YouTube", hex: [0xE52D27, 0xCC201F, 0xB31217], group: .similar),
        GradientPreset(name: "A Lost Memory", hex: [0xDE6262, 0xEE8D77, 0xFFB88C], group: .similar),
        GradientPreset(name: "Sylvia", hex: [0xFF4B1F, 0xFF6E44, 0xFF9068], group: .similar),
        GradientPreset(name: "Koko Caramel", hex: [0xD1913C, 0xE8B168, 0xFFD194], group: .similar),
        GradientPreset(name: "Pale Wood", hex: [0xEACDA3, 0xE0BE8F, 0xD6AE7B], group: .similar),
        GradientPreset(name: "Light Orange", hex: [0xFFB75E, 0xF6A330, 0xED8F03], group: .similar),
        GradientPreset(name: "Juicy Orange", hex: [0xFF8008, 0xFFA420, 0xFFC837], group: .similar),
        GradientPreset(name: "Coffee Gold", hex: [0x554023, 0x8F6C34, 0xC99846], group: .similar),
        GradientPreset(name: "Mango Pulp", hex: [0xF09819, 0xEEBB3B, 0xEDDE5D], group: .similar),
        GradientPreset(name: "Rea", hex: [0xFFE000, 0xBCC006, 0x799F0C], group: .similar),
        GradientPreset(name: "Parklife", hex: [0xADD100, 0x94B205, 0x7B920A], group: .similar),
        GradientPreset(name: "Lush", hex: [0x56AB2F, 0x7FC649, 0xA8E063], group: .similar),
        GradientPreset(name: "Mojito", hex: [0x1D976C, 0x58C892, 0x93F9B9], group: .similar),
        GradientPreset(name: "Cinnamint", hex: [0x4AC29A, 0x84E0C6, 0xBDFFF3], group: .similar),
        GradientPreset(name: "Sea Blizz", hex: [0x1CD8D2, 0x58E2CC, 0x93EDC7], group: .similar),
        GradientPreset(name: "Crystalline", hex: [0x00CDAC, 0x46D4C0, 0x8DDAD5], group: .similar),
        GradientPreset(name: "Orca", hex: [0x44A08D, 0x266B62, 0x093637], group: .similar),
        GradientPreset(name: "Aqualicious", hex: [0x50C9C3, 0x73D4CE, 0x96DEDA], group: .similar),
        GradientPreset(name: "Maldives", hex: [0xB2FEFA, 0x60E8F8, 0x0ED2F7], group: .similar),
        GradientPreset(name: "Decent", hex: [0x4CA1AF, 0x88C0CA, 0xC4E0E5], group: .similar),
        GradientPreset(name: "Sexy Blue", hex: [0x2193B0, 0x47B4CE, 0x6DD5ED], group: .similar),
        GradientPreset(name: "Blue Raspberry", hex: [0x00B4DB, 0x009CC6, 0x0083B0], group: .similar),
        GradientPreset(name: "From Ice To Fire", hex: [0x72C6EF, 0x398ABF, 0x004E8F], group: .similar),
        GradientPreset(name: "Party Bliss", hex: [0x4481EB, 0x24A0F4, 0x04BEFE], group: .similar),
        GradientPreset(name: "Blue Skies", hex: [0x56CCF2, 0x42A6F0, 0x2F80ED], group: .similar),
        GradientPreset(name: "Landing Aircraft", hex: [0x5D9FFF, 0xB8DCFF, 0x6BBBFF], group: .similar),
        GradientPreset(name: "Royal", hex: [0x141E30, 0x1C2C42, 0x243B55], group: .similar),
        GradientPreset(name: "Very Blue", hex: [0x0575E6, 0x0448B0, 0x021B79], group: .similar),
        GradientPreset(name: "Great Whale", hex: [0xA3BDED, 0x86A7DA, 0x6991C7], group: .similar),
        GradientPreset(name: "Night Sky", hex: [0x1E3C72, 0x244785, 0x2A5298], group: .similar),
        GradientPreset(name: "Venice", hex: [0x6190E8, 0x84A8E8, 0xA7BFE8], group: .similar),
        GradientPreset(name: "Pinot Noir", hex: [0x4B6CB7, 0x324A80, 0x182848], group: .similar),
        GradientPreset(name: "Moon Purple", hex: [0x4E54C8, 0x6E74E2, 0x8F94FB], group: .similar),
        GradientPreset(name: "Amin", hex: [0x8E2DE2, 0x6C16E1, 0x4A00E0], group: .similar),
        GradientPreset(name: "Twitch", hex: [0x6441A5, 0x472475, 0x2A0845], group: .similar),
        GradientPreset(name: "Purplin", hex: [0x6A3093, 0x853AC9, 0xA044FF], group: .similar),
        GradientPreset(name: "80's Purple", hex: [0x41295A, 0x38184E, 0x2F0743], group: .similar),
        GradientPreset(name: "Farhan", hex: [0x9400D3, 0x7000AA, 0x4B0082], group: .similar),
        GradientPreset(name: "Purple Dream", hex: [0xBF5AE0, 0xB436DD, 0xA811DA], group: .similar),
        GradientPreset(name: "Black Rosé", hex: [0xF4C4F3, 0xF896F6, 0xFC67FA], group: .similar),
        GradientPreset(name: "Aubergine", hex: [0xAA076B, 0x860665, 0x61045F], group: .similar),
        GradientPreset(name: "Neuromancer", hex: [0xF953C6, 0xD9389C, 0xB91D73], group: .similar),
        GradientPreset(name: "Cherryblossoms", hex: [0xFBD3E9, 0xDB85B3, 0xBB377D], group: .similar),
        GradientPreset(name: "Purple", hex: [0xC84E89, 0xDC5681, 0xF15F79], group: .similar),
        GradientPreset(name: "Playing with Reds", hex: [0xD31027, 0xDE243A, 0xEA384D], group: .similar),
        GradientPreset(name: "Sin City Red", hex: [0xED213A, 0xC0252C, 0x93291E], group: .similar),
        GradientPreset(name: "Firewatch", hex: [0xCB2D3E, 0xDD3A3C, 0xEF473A], group: .similar),
        GradientPreset(name: "Copper", hex: [0xB79891, 0xA6847E, 0x94716B], group: .muted),
        GradientPreset(name: "Selenium", hex: [0x3C3B3F, 0x4E4C3E, 0x605C3C], group: .muted),
        GradientPreset(name: "Sand Strike", hex: [0xC1C161, 0xCACA89, 0xD4D4B1], group: .muted),
        GradientPreset(name: "Shifty", hex: [0x636363, 0x82875E, 0xA2AB58], group: .muted),
        GradientPreset(name: "Earthly", hex: [0x649173, 0xA0B38C, 0xDBD5A4], group: .muted),
        GradientPreset(name: "Little Leaf", hex: [0x76B852, 0x82BD60, 0x8DC26F], group: .muted),
        GradientPreset(name: "Anwar", hex: [0x334D50, 0x7F8C7A, 0xCBCAA5], group: .muted),
        GradientPreset(name: "Space Light Green", hex: [0x9FA0A8, 0x7E8C7D, 0x5C7852], group: .muted),
        GradientPreset(name: "Between The Clouds", hex: [0x73C8A9, 0x558276, 0x373B44], group: .muted),
        GradientPreset(name: "Moor", hex: [0x616161, 0x7E9392, 0x9BC5C3], group: .muted),
        GradientPreset(name: "Petrol", hex: [0xBBD2C5, 0x879E9E, 0x536976], group: .muted),
        GradientPreset(name: "Deep Sea Space", hex: [0x2C3E50, 0x3C7080, 0x4CA1AF], group: .muted),
        GradientPreset(name: "Winter", hex: [0xE6DADA, 0x868D90, 0x274046], group: .muted),
        GradientPreset(name: "Forever Lost", hex: [0x5D4157, 0x828688, 0xA8CABA], group: .muted),
        GradientPreset(name: "Solid Stone", hex: [0x243949, 0x3A5C76, 0x517FA4], group: .muted),
        GradientPreset(name: "Lizard", hex: [0x304352, 0x848A8F, 0xD7D2CC], group: .muted),
        GradientPreset(name: "Dark Skies", hex: [0x4B79A1, 0x3A5C79, 0x283E51], group: .muted),
        GradientPreset(name: "ServQuick", hex: [0x485563, 0x384450, 0x29323C], group: .muted),
        GradientPreset(name: "50 Shades of Grey", hex: [0xBDC3C7, 0x74808C, 0x2C3E50], group: .muted),
        GradientPreset(name: "Raccoon Back", hex: [0xBCC5CE, 0xA7B2BE, 0x929EAD], group: .muted),
        GradientPreset(name: "Titanium", hex: [0x283048, 0x566270, 0x859398], group: .muted),
        GradientPreset(name: "Royal Blue", hex: [0x536976, 0x3E4C60, 0x292E49], group: .muted),
        GradientPreset(name: "Dania", hex: [0xBE93C5, 0x9CACC8, 0x7BC6CC], group: .muted),
        GradientPreset(name: "Dirty Beauty", hex: [0x6A85B6, 0x92A6CB, 0xBAC8E0], group: .muted),
        GradientPreset(name: "Mystic", hex: [0x757F9A, 0xA6AEC1, 0xD7DDE8], group: .muted),
        GradientPreset(name: "Ash", hex: [0x606C88, 0x505C7A, 0x3F4C6B], group: .muted),
        GradientPreset(name: "Spiky Naga", hex: [0x505285, 0x585E92, 0x65689F], group: .muted),
        GradientPreset(name: "Polite Rumors", hex: [0xA7A6CB, 0x9898C2, 0x8989BA], group: .muted),
        GradientPreset(name: "Kashmir", hex: [0x614385, 0x59538D, 0x516395], group: .muted),
        GradientPreset(name: "Steel Gray", hex: [0x1F1C2C, 0x58546C, 0x928DAB], group: .muted),
        GradientPreset(name: "Jungle Day", hex: [0x8BAAAA, 0x9C9AA3, 0xAE8B9C], group: .muted),
        GradientPreset(name: "Amethyst", hex: [0x9D50BB, 0x864CB2, 0x6E48AA], group: .muted),
        GradientPreset(name: "Mauve", hex: [0x42275A, 0x5A3964, 0x734B6D], group: .muted),
        GradientPreset(name: "Poncho", hex: [0x403A3E, 0x7F4954, 0xBE5869], group: .muted),
    ]
}

/// A circle filled with the chosen gradient (nil: `fallback`); click it to pick another from every preset.
struct GradientPicker: View {
    @SwiftUI.Binding var selection: String?
    let fallback: [Color]
    var size: CGFloat = 20
    @State private var open = false
    @State private var hovered: GradientPreset?

    var body: some View {
        let current = selection.flatMap(GradientPreset.named)
        Button { open.toggle() } label: {
            Self.swatch(current?.colors ?? fallback, size: size)
        }
        .buttonStyle(.plain)
        .help("Gradient: \(current?.name ?? "Default")")
        .popover(isPresented: $open, arrowEdge: .bottom) { picker(current) }
    }

    private func picker(_ current: GradientPreset?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text((hovered ?? current)?.name ?? "Default").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Default") { selection = nil }.disabled(current == nil)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(GradientPreset.Group.allCases, id: \.self) { g in
                        Text(g.title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 8), spacing: 8) {
                            ForEach(GradientPreset.all.filter { $0.group == g }) { p in
                                Button { withAnimation(Theme.smooth) { selection = p.name } } label: {
                                    Self.swatch(p.colors, size: 34)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: 2.5).padding(-4).opacity(current == p ? 1 : 0))
                                }
                                .buttonStyle(.plain)
                                .onHover { h in hovered = h ? p : (hovered == p ? nil : hovered) }
                            }
                        }
                    }
                }
                .padding(6)
            }
            .frame(height: 380)
        }
        .padding(14)
        .frame(width: 360)
    }

    static func swatch(_ colors: [Color], size: CGFloat) -> some View {
        Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

/// Small circle right after a page's title, filled with the page's gradient; click it to pick another.
struct GradientDot: View {
    let page: String
    let fallback: [Color]   // the page's own colors, shown while nothing is picked
    @ObservedObject private var prefs = Prefs.shared
    var body: some View {
        GradientPicker(selection: SwiftUI.Binding(get: { prefs.pageGradients[page] }, set: { prefs.pageGradients[page] = $0 }),
                       fallback: fallback)
    }
}

/// On glass, a page's color washing in from the top: its picked gradient across, else its own color.
struct PageWash: View {
    let page: String
    let color: Color
    @ObservedObject private var prefs = Prefs.shared
    var body: some View {
        let colors = GradientPreset.pick(page)?.colors ?? [color, color]
        LinearGradient(colors: colors.map { $0.opacity(0.16) }, startPoint: .leading, endPoint: .trailing)
            .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            .frame(height: 320)
    }
}

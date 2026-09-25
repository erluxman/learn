import Foundation
import CoreServices

/// Spotlight-style instant answers for the search field: arithmetic, unit and currency conversions, definitions.
/// Local except currency rates (fetched by `Rates`, cached for 12 h).
struct Answer: Hashable {
    enum Kind { case calc, convert, define }
    let kind: Kind
    let title: String    // "= 42", "5 km = 3.107 mi", "serendipity"
    let detail: String   // expression / definition text
    let value: String    // what ↩ copies (calc, convert) or the word to look up (define)

    var symbol: String {
        switch kind { case .calc: "equal.circle.fill"; case .convert: "arrow.left.arrow.right.circle.fill"; case .define: "book.circle.fill" }
    }
}

enum Answers {
    /// Calculator and conversions: shown above everything else.
    static func instant(_ q: String) -> Answer? {
        let q = q.trimmingCharacters(in: .whitespaces)
        if let a = convert(q) ?? currency(q) { return a }
        guard q.rangeOfCharacter(from: .decimalDigits) != nil, q.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^%×÷(")) != nil,
              let v = Calc.evaluate(q), v.isFinite else { return nil }
        let s = format(v, digits: 10)
        return Answer(kind: .calc, title: "= " + s, detail: q, value: s)
    }

    /// Single English-ish word → first part of its dictionary entry.
    static func define(_ q: String) -> Answer? {
        let w = q.trimmingCharacters(in: .whitespaces)
        guard w.count >= 3, w.count <= 30, w.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "'" }) else { return nil }
        guard let def = DCSCopyTextDefinition(nil, w as CFString, CFRange(location: 0, length: (w as NSString).length))?
            .takeRetainedValue() as String? else { return nil }
        let text = def.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return Answer(kind: .define, title: w, detail: String(text.prefix(220)), value: w)
    }

    static func format(_ v: Double, digits: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = digits
        f.usesGroupingSeparator = abs(v) >= 10_000
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    // MARK: Units

    /// "5 km to mi", "70f in c", "2.5 cups as ml"
    private static func convert(_ q: String) -> Answer? {
        let re = try! NSRegularExpression(pattern: #"^(-?[\d.,]+)\s*([a-z°/ ]+?)\s+(?:to|in|as|=)\s+([a-z°/ ]+)$"#, options: .caseInsensitive)
        let ns = q as NSString
        guard let m = re.firstMatch(in: q, range: NSRange(location: 0, length: ns.length)),
              let n = Double(ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")),
              let from = unit(ns.substring(with: m.range(at: 2))), let to = unit(ns.substring(with: m.range(at: 3))),
              type(of: from) == type(of: to) else { return nil }
        let v = Measurement(value: n, unit: from).converted(to: to).value
        let out = format(v, digits: 4)
        return Answer(kind: .convert, title: "\(format(n, digits: 6)) \(from.symbol) = \(out) \(to.symbol)", detail: q, value: out)
    }

    // MARK: Currency

    /// "100 usd to npr", "$50 in eur", "20 euros to rupees", "100 usd" (→ this Mac's currency).
    private static func currency(_ q: String) -> Answer? {
        let sym = "$€£¥₹"
        let re = try! NSRegularExpression(pattern: "^([\(sym)]?)\\s*(-?[\\d.,]+)\\s*([a-z\(sym)]*)(?:\\s+(?:to|in|as|=)\\s+([a-z\(sym)]+))?$",
                                          options: .caseInsensitive)
        let ns = q as NSString
        guard let m = re.firstMatch(in: q, range: NSRange(location: 0, length: ns.length)),
              let n = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ",", with: "")) else { return nil }
        func part(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
        let rates = Rates.shared
        rates.refreshIfStale()   // before parsing: currency codes are recognised from the rate table
        let local = Locale.current.currency?.identifier ?? "USD"
        guard let from = code(part(1).isEmpty ? part(3) : part(1)),
              let to = part(4).isEmpty ? (from == local ? nil : local) : code(part(4)), from != to else { return nil }
        guard let rf = rates.table[from], let rt = rates.table[to] else { return nil }
        let v = n / rf * rt
        let out = format(v, digits: abs(v) < 1 ? 4 : 2)
        let ago = rates.updated.map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()) } ?? ""
        return Answer(kind: .convert, title: "\(format(n, digits: 2)) \(from) = \(out) \(to)", detail: "\(q) · rates updated \(ago)", value: out)
    }

    private static func code(_ raw: String) -> String? {
        let s = raw.lowercased()
        guard !s.isEmpty else { return nil }
        let rupee = ["NPR", "PKR", "LKR"].contains(Locale.current.currency?.identifier ?? "") ? Locale.current.currency!.identifier : "INR"
        let names = ["$": "USD", "dollar": "USD", "buck": "USD", "€": "EUR", "euro": "EUR", "£": "GBP", "pound": "GBP",
                     "¥": "JPY", "yen": "JPY", "yuan": "CNY", "rmb": "CNY", "₹": "INR", "rupee": rupee, "rs": rupee]
        if let c = names[s] ?? (s.hasSuffix("s") ? names[String(s.dropLast())] : nil) { return c }
        return s.count == 3 && Rates.shared.table[s.uppercased()] != nil ? s.uppercased() : nil
    }

    private static func unit(_ raw: String) -> Dimension? {
        let s = raw.lowercased().trimmingCharacters(in: .whitespaces)
        return units[s] ?? (s.hasSuffix("s") ? units[String(s.dropLast())] : nil)
    }

    private static let units: [String: Dimension] = {
        var u: [String: Dimension] = [:]
        func add(_ d: Dimension, _ names: String...) { names.forEach { u[$0] = d } }
        add(UnitLength.millimeters, "mm", "millimeter", "millimetre"); add(UnitLength.centimeters, "cm", "centimeter", "centimetre")
        add(UnitLength.meters, "m", "meter", "metre"); add(UnitLength.kilometers, "km", "kilometer", "kilometre")
        add(UnitLength.inches, "in", "inch", "inche", "\""); add(UnitLength.feet, "ft", "foot", "feet", "'")
        add(UnitLength.yards, "yd", "yard"); add(UnitLength.miles, "mi", "mile")
        add(UnitMass.milligrams, "mg", "milligram"); add(UnitMass.grams, "g", "gram"); add(UnitMass.kilograms, "kg", "kilo", "kilogram")
        add(UnitMass.pounds, "lb", "lbs", "pound"); add(UnitMass.ounces, "oz", "ounce"); add(UnitMass.stones, "st", "stone")
        add(UnitTemperature.celsius, "c", "°c", "celsius"); add(UnitTemperature.fahrenheit, "f", "°f", "fahrenheit")
        add(UnitTemperature.kelvin, "k", "kelvin")
        add(UnitVolume.milliliters, "ml", "milliliter", "millilitre"); add(UnitVolume.liters, "l", "liter", "litre")
        add(UnitVolume.gallons, "gal", "gallon"); add(UnitVolume.quarts, "qt", "quart"); add(UnitVolume.pints, "pt", "pint")
        add(UnitVolume.cups, "cup"); add(UnitVolume.fluidOunces, "floz", "fl oz", "fluid ounce")
        add(UnitVolume.tablespoons, "tbsp", "tablespoon"); add(UnitVolume.teaspoons, "tsp", "teaspoon")
        add(UnitSpeed.kilometersPerHour, "kmh", "km/h", "kph"); add(UnitSpeed.milesPerHour, "mph")
        add(UnitSpeed.metersPerSecond, "m/s"); add(UnitSpeed.knots, "kn", "knot")
        add(UnitInformationStorage.bytes, "b", "byte"); add(UnitInformationStorage.kilobytes, "kb", "kilobyte")
        add(UnitInformationStorage.megabytes, "mb", "megabyte"); add(UnitInformationStorage.gigabytes, "gb", "gigabyte")
        add(UnitInformationStorage.terabytes, "tb", "terabyte")
        add(UnitDuration.seconds, "s", "sec", "second"); add(UnitDuration.minutes, "min", "minute"); add(UnitDuration.hours, "h", "hr", "hour")
        add(UnitArea.squareMeters, "m2", "sqm", "square meter"); add(UnitArea.squareFeet, "ft2", "sqft", "square foot", "square feet")
        add(UnitArea.acres, "acre"); add(UnitArea.hectares, "ha", "hectare")
        return u
    }()
}

/// Exchange rates (base USD) from open.er-api.com — free, no key, ~160 currencies incl. NPR.
/// Cached in ~/Library/Application Support/Learn/rates.json, refreshed when older than 12 h. Main-thread only.
final class Rates {
    static let shared = Rates()
    static let changed = Notification.Name("LearnRatesChanged")
    private(set) var table: [String: Double] = [:]
    private(set) var updated: Date?
    private var loading = false
    private let file = ShortcutStore.shared.dir.deletingLastPathComponent().appendingPathComponent("rates.json")

    private init() {
        guard let d = try? Data(contentsOf: file), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let r = j["rates"] as? [String: Double], let t = j["updated"] as? Double else { return }
        table = r
        updated = Date(timeIntervalSince1970: t)
    }

    func refreshIfStale() {
        guard !loading, (updated?.timeIntervalSinceNow ?? -.infinity) < -12 * 3600 else { return }
        loading = true
        URLSession.shared.dataTask(with: URL(string: "https://open.er-api.com/v6/latest/USD")!) { data, _, _ in
            let rates = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["rates"] as? [String: Double]
            DispatchQueue.main.async {
                self.loading = false
                guard let rates, !rates.isEmpty else { return }
                self.table = rates
                self.updated = Date()
                let j: [String: Any] = ["rates": rates, "updated": Date().timeIntervalSince1970]
                try? JSONSerialization.data(withJSONObject: j).write(to: self.file, options: .atomic)
                NotificationCenter.default.post(name: Self.changed, object: nil)
            }
        }.resume()
    }
}

/// Tiny arithmetic parser (+ − × ÷ ^ %, parentheses, unary minus, sqrt, pi). NSExpression is avoided:
/// it raises Objective-C exceptions on half-typed input, which would crash the app.
private struct Calc {
    private let s: [Character]
    private var i = 0

    static func evaluate(_ text: String) -> Double? {
        let cleaned = text.lowercased().replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
        var p = Calc(s: Array(cleaned))
        guard let v = p.expr(), p.i == p.s.count else { return nil }
        return v
    }

    private init(s: [Character]) { self.s = s }

    private mutating func eat(_ c: Character) -> Bool {
        guard i < s.count, s[i] == c else { return false }
        i += 1
        return true
    }

    private mutating func expr() -> Double? {
        guard var v = term() else { return nil }
        while true {
            if eat("+") { guard let r = term() else { return nil }; v += r }
            else if eat("-") { guard let r = term() else { return nil }; v -= r }
            else { return v }
        }
    }

    private mutating func term() -> Double? {
        guard var v = power() else { return nil }
        while true {
            if eat("*") { guard let r = power() else { return nil }; v *= r }
            else if eat("/") { guard let r = power() else { return nil }; v /= r }
            else if eat("%") { guard let r = power() else { return nil }; v = v.truncatingRemainder(dividingBy: r) }
            else { return v }
        }
    }

    private mutating func power() -> Double? {
        guard let b = unary() else { return nil }
        if eat("^") { guard let e = power() else { return nil }; return pow(b, e) }   // right-associative
        return b
    }

    private mutating func unary() -> Double? {
        if eat("-") { return unary().map { -$0 } }
        if eat("+") { return unary() }
        return atom()
    }

    private mutating func atom() -> Double? {
        if eat("(") { guard let v = expr(), eat(")") else { return nil }; return v }
        if word("sqrt") { guard eat("("), let v = expr(), eat(")") else { return nil }; return v.squareRoot() }
        if word("pi") { return .pi }
        let start = i
        while i < s.count, s[i].isNumber || s[i] == "." { i += 1 }
        return i > start ? Double(String(s[start..<i])) : nil
    }

    private mutating func word(_ w: String) -> Bool {
        let c = Array(w)
        guard i + c.count <= s.count, Array(s[i..<i + c.count]) == c else { return false }
        i += c.count
        return true
    }
}

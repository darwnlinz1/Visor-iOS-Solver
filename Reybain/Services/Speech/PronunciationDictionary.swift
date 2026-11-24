// Reybain - PronunciationDictionary.swift
// Default Vietnamese readings (letters, functions, Greek letters, units, symbols) plus the user's
// overrides from Settings (PLAN.md §4.3). Lookups are by WHOLE token, never by substring.

import Foundation

struct PronunciationDictionary {
    enum Category: String, CaseIterable {
        case letters, functions, greek, units, symbols
    }

    struct Entry: Equatable {
        var key: String
        var spoken: String
        var category: Category
    }

    // MARK: - Defaults

    /// Vietnamese letter names (decision D3). Capitals read like small letters.
    static let letterNames: [Character: String] = [
        "a": "a", "b": "bê", "c": "xê", "d": "đê", "e": "e", "f": "ép", "g": "giê", "h": "hát", "i": "i",
        "j": "gi", "k": "ca", "l": "lờ", "m": "mờ", "n": "nờ", "o": "o", "p": "pê", "q": "quy", "r": "rờ",
        "s": "ét", "t": "tê", "u": "u", "v": "vê", "w": "vê kép", "x": "ích", "y": "i", "z": "dét",
    ]

    /// Function names. "logarit" is the word used when a base is written (`\log_2 8`).
    static let functions: [String: String] = [
        "sin": "sin", "cos": "cốt", "tan": "tang", "tg": "tang", "cot": "cô-tang", "cotg": "cô-tang",
        "sec": "sec", "csc": "cô-sec", "arcsin": "ác-sin", "arccos": "ác-cốt", "arctan": "ác-tang",
        "arctg": "ác-tang", "arccot": "ác-cô-tang", "arccotg": "ác-cô-tang", "sinh": "sin hy-pe-bôn",
        "cosh": "cốt hy-pe-bôn", "tanh": "tang hy-pe-bôn", "log": "lốc", "logarit": "lô-ga-rít",
        "ln": "lốc nê-pe", "lg": "lốc", "exp": "e mũ", "max": "max", "min": "min",
        "gcd": "ước chung lớn nhất", "lcm": "bội chung nhỏ nhất", "det": "định thức", "sgn": "dấu",
        "lim": "giới hạn",
    ]

    static let greek: [String: String] = {
        let names: [String: String] = [
            "alpha": "an-pha", "beta": "bê-ta", "gamma": "gam-ma", "delta": "đen-ta", "epsilon": "ép-xi-lon",
            "zeta": "dê-ta", "eta": "ê-ta", "theta": "tê-ta", "iota": "i-ô-ta", "kappa": "káp-pa",
            "lambda": "lam-đa", "mu": "muy", "nu": "nuy", "xi": "xi", "omicron": "ô-mi-crôn", "pi": "pi",
            "rho": "rô", "sigma": "xích-ma", "tau": "tô", "upsilon": "úp-xi-lon", "phi": "phi", "chi": "khi",
            "psi": "psi", "omega": "ô-mê-ga",
        ]
        var table = names
        for (name, spoken) in names {
            table[name.prefix(1).uppercased() + name.dropFirst()] = spoken
        }
        return table
    }()

    static let units: [String: String] = [
        "mm": "mi-li-mét", "cm": "xen-ti-mét", "dm": "đề-xi-mét", "m": "mét", "km": "ki-lô-mét",
        "mg": "mi-li-gam", "g": "gam", "kg": "ki-lô-gam", "ml": "mi-li-lít", "mL": "mi-li-lít", "l": "lít",
        "L": "lít", "s": "giây", "ms": "mi-li-giây", "min": "phút", "h": "giờ", "ha": "héc-ta",
        "N": "niu-tơn", "kN": "ki-lô-niu-tơn", "J": "jun", "kJ": "ki-lô-jun", "W": "oát", "kW": "ki-lô-oát",
        "kWh": "ki-lô-oát giờ", "Wh": "oát giờ", "V": "vôn", "mV": "mi-li-vôn", "kV": "ki-lô-vôn",
        "A": "am-pe", "mA": "mi-li-am-pe", "Hz": "héc", "kHz": "ki-lô-héc", "Pa": "pát-xcan",
        "kPa": "ki-lô-pát-xcan", "atm": "át-mốt-phe", "mol": "mol", "K": "ken-vin", "cal": "ca-lo",
        "kcal": "ki-lô-ca-lo", "rad": "ra-đi-an", "Ω": "ôm",
    ]

    static let symbols: [String: String] = [
        "infty": "vô cùng", "emptyset": "tập rỗng", "forall": "với mọi", "exists": "tồn tại",
        "nexists": "không tồn tại", "neg": "phủ định", "therefore": "vậy", "because": "vì",
        "dots": "ba chấm", "partial": "đê", "ℝ": "tập số thực", "ℕ": "tập số tự nhiên",
        "ℤ": "tập số nguyên", "ℚ": "tập số hữu tỉ", "ℂ": "tập số phức", "circ": "độ", "prime": "phẩy",
        "%": "phần trăm", "°": "độ",
    ]

    /// Every default reading, for the Settings dictionary screen ("khôi phục mặc định").
    static let defaultEntries: [Entry] = {
        var entries: [Entry] = []
        for (letter, spoken) in letterNames.sorted(by: { $0.key < $1.key }) {
            entries.append(Entry(key: String(letter), spoken: spoken, category: .letters))
        }
        for (table, category) in [(functions, Category.functions), (greek, .greek), (units, .units), (symbols, .symbols)] {
            for (key, spoken) in table.sorted(by: { $0.key < $1.key }) {
                entries.append(Entry(key: key, spoken: spoken, category: category))
            }
        }
        return entries
    }()

    // MARK: - Overrides

    /// User overrides with normalised keys.
    let overrides: [String: String]

    init(overrides: [String: String] = [:]) {
        var normalized: [String: String] = [:]
        for (rawKey, rawValue) in overrides {
            let key = Self.normalizedKey(rawKey)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }  // an empty reading is ignored
            normalized[key] = value
        }
        self.overrides = normalized
    }

    /// One spelling per token: "\cos" and "cos" are the same key, "Δ" is "Delta", "≤" is "le",
    /// "\mathbb{R}" is "ℝ".
    static func normalizedKey(_ raw: String) -> String {
        var key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.count == 1, let c = key.first {
            if let greek = MathLexer.greekCharacters[c] { return greek }
            if let replacement = MathLexer.unicodeReplacements[c], !["ℝ", "ℕ", "ℤ", "ℚ", "ℂ"].contains(c) {
                key = replacement.trimmingCharacters(in: .whitespaces)
            }
        }
        if key.hasPrefix("\\mathbb{"), key.hasSuffix("}"), key.count == 10 {
            let letter = key[key.index(key.startIndex, offsetBy: 8)]
            if let set = ["R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ"][String(letter)] { return set }
        }
        if key.hasPrefix("\\") {
            key.removeFirst()
            if let greek = MathLexer.greekNames[key] { return greek }
            key = MathLexer.aliases[key] ?? key
        }
        return key
    }

    /// The user's reading for a token. Single letters fall back to the small letter ("X" → "x").
    func override(for key: String) -> String? {
        if let exact = overrides[key] { return exact }
        if key.count == 1, let lower = key.lowercased().first, String(lower) != key {
            return overrides[String(lower)]
        }
        return nil
    }

    // MARK: - Readings

    /// A Latin letter as a variable or a point name.
    func letter(_ letter: String, style: MathReadingStyle.LetterStyle) -> String {
        if let custom = override(for: letter) { return custom }
        guard style == .vietnameseNames, let c = letter.lowercased().first, letter.count == 1,
              let name = Self.letterNames[c] else { return letter }
        return name
    }

    func greekLetter(_ name: String) -> String {
        override(for: name) ?? Self.greek[name] ?? name
    }

    func function(_ name: String) -> String {
        override(for: name) ?? Self.functions[name] ?? name
    }

    func symbol(_ name: String) -> String {
        override(for: name) ?? Self.symbols[name] ?? ""
    }

    /// A word for an operator or other fixed token, overridable by its canonical key ("le", "+").
    func word(_ key: String, default spoken: String) -> String {
        override(for: key) ?? spoken
    }

    /// "cm" → "xen-ti-mét", "km/h" → "ki-lô-mét trên giờ", "cm^2" → "xen-ti-mét vuông",
    /// "m/s^2" → "mét trên giây bình phương".
    func unit(_ symbol: String) -> String {
        if let custom = override(for: symbol) { return custom }
        let parts = symbol.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return parts.enumerated().map { index, part -> String in
            var base = part
            var suffix = ""
            if part.hasSuffix("^2") || part.hasSuffix("^3") {
                base = String(part.dropLast(2))
                let square = part.hasSuffix("^2")
                if MathParser.lengthUnits.contains(base) {
                    suffix = square ? " vuông" : " khối"
                } else {
                    suffix = square ? " bình phương" : " lập phương"
                }
            }
            let word = override(for: base) ?? Self.units[base] ?? base
            return (index == 0 ? "" : "trên ") + word + suffix
        }.joined(separator: " ")
    }
}

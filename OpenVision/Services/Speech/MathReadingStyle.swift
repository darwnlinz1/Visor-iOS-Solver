// OpenVision - MathReadingStyle.swift
// How formulas are read aloud (PLAN.md §4.3), built from the raw settings strings of §4.6.

import Foundation

struct MathReadingStyle: Equatable {
    enum Verbosity: String, CaseIterable {
        /// "x cộng 1, trên x trừ 1"
        case natural
        /// Adds "hết căn", "hết mũ", "hết phân số", "mở ngoặc … đóng ngoặc".
        case explicit
    }

    /// Word for a fraction with letters ("a trên b" / "a phần b"). Numeric fractions are always
    /// "một phần hai".
    enum SymbolicFraction: String, CaseIterable {
        case tren
        case phan

        var word: String { self == .tren ? "trên" : "phần" }
    }

    /// Word for a unary minus ("âm 3" / "trừ 3").
    enum NegativeWord: String, CaseIterable {
        case am
        case tru

        var word: String { self == .am ? "âm" : "trừ" }
    }

    enum LetterStyle: String, CaseIterable {
        /// Vietnamese letter names: x → "ích", b → "bê" (decision D3).
        case vietnameseNames
        /// Latin letters handed to the voice as written.
        case asWritten
    }

    var verbosity: Verbosity
    var symbolicFraction: SymbolicFraction
    var negativeWord: NegativeWord
    var letterStyle: LetterStyle
    /// The user's pronunciation dictionary (Settings): whole token → spoken words.
    var pronunciationOverrides: [String: String]

    init(verbosity: Verbosity = .natural,
         symbolicFraction: SymbolicFraction = .tren,
         negativeWord: NegativeWord = .am,
         letterStyle: LetterStyle = .vietnameseNames,
         pronunciationOverrides: [String: String] = [:]) {
        self.verbosity = verbosity
        self.symbolicFraction = symbolicFraction
        self.negativeWord = negativeWord
        self.letterStyle = letterStyle
        self.pronunciationOverrides = pronunciationOverrides
    }

    /// From the raw `AppSettings` strings (`mathVerbosity`, `symbolicFractionWord`, `negativeWord`,
    /// `letterStyle`). Unknown or empty values fall back to the defaults, so a damaged settings file
    /// never changes how math is read (rule N18).
    init(mathVerbosity: String,
         symbolicFractionWord: String,
         negativeWord: String,
         letterStyle: String,
         pronunciationOverrides: [String: String] = [:]) {
        self.init(verbosity: Self.option(mathVerbosity, default: .natural, aliases: [:]),
                  symbolicFraction: Self.option(symbolicFractionWord, default: .tren,
                                                aliases: ["trên": .tren, "phần": .phan]),
                  negativeWord: Self.option(negativeWord, default: .am, aliases: ["âm": .am, "trừ": .tru]),
                  letterStyle: Self.option(letterStyle, default: .vietnameseNames, aliases: [:]),
                  pronunciationOverrides: pronunciationOverrides)
    }

    static let `default` = MathReadingStyle()

    /// Case- and space-insensitive lookup of a raw setting value.
    private static func option<T: RawRepresentable & CaseIterable>(_ raw: String, default fallback: T,
                                                                  aliases: [String: T]) -> T where T.RawValue == String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let match = T.allCases.first(where: { $0.rawValue.lowercased() == key }) { return match }
        return aliases[key] ?? fallback
    }
}

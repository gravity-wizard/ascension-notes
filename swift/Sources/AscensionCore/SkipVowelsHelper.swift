import Foundation

public struct SkipVowelsSuggestion: Hashable, Sendable, Identifiable {
    public var id: String { "\(token)->\(normalized):\(source)" }
    public let token: String
    public let normalized: String
    public let source: String
    public let isExactMatch: Bool

    public init(token: String, normalized: String, source: String, isExactMatch: Bool) {
        self.token = token
        self.normalized = normalized
        self.source = source
        self.isExactMatch = isExactMatch
    }
}

public enum SkipVowelsHelper: Sendable {
    public static let builtInMappings: [String: String] = [
        "WhrNrmA": "Where's Norma A",
        "WhrNrmB": "Where's Norma B",
        "WhrNrm": "Where's Norma",
        "NrmA": "Norma A",
        "NrmB": "Norma B",
        "Nrm": "Norma",
        "Anotes": "Ascension Notes",
        "AscNts": "Ascension Notes",
        "GSii": "GSii",
        "FrmryCstl": "Formicary Castle",
    ]

    public static let builtInLexicon: [String] = [
        "Where's Norma A",
        "Where's Norma B",
        "Where's Norma",
        "Norma A",
        "Norma B",
        "Norma",
        "Ascension Notes",
        "Formicary Castle",
        "Seven Aunts",
        "Jesus Clock",
        "Hydrogen4",
        "Base38",
        "March 8 Miracle",
        "GSii",
    ]

    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u"]

    /// Extracts a lowercase consonant-and-digit skeleton used to match vowel-skipped tokens
    /// against known phrases and A3odex canonicals.
    public static func consonantSkeleton(_ text: String, includeLeadingVowel: Bool = false) -> String {
        let stripped = text
            .replacingOccurrences(of: "'s", with: "")
            .replacingOccurrences(of: "\u{2019}s", with: "")
        var out = ""
        var isFirstLetter = true
        for ch in stripped.lowercased() {
            guard ch.isASCII && (ch.isLetter || ch.isNumber) else { continue }
            if ch.isNumber {
                out.append(ch)
                isFirstLetter = false
                continue
            }
            if vowels.contains(ch) {
                if includeLeadingVowel && isFirstLetter {
                    out.append(ch)
                }
            } else {
                out.append(ch)
            }
            isFirstLetter = false
        }
        return out
    }

    /// Splits a trailing single uppercase tag letter (e.g. `WhrNrmA` -> `("WhrNrm", "A")`).
    private static func splitTrailingUpperTag(_ text: String) -> (stem: String, tag: String)? {
        guard text.count >= 3, let last = text.last, last.isASCII, last.isUppercase else {
            return nil
        }
        let stem = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
        guard !stem.isEmpty else { return nil }
        return (stem, String(last))
    }

    public static func suggestCleanForms(
        for token: String,
        knownEntries: [(token: String, canonical: String)] = [],
        extraLexicon: [String] = []
    ) -> [SkipVowelsSuggestion] {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [SkipVowelsSuggestion] = []
        var seenNormalized: Set<String> = []

        func appendUnique(_ normalized: String, source: String, isExact: Bool) {
            let clean = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, !seenNormalized.contains(clean) else { return }
            seenNormalized.insert(clean)
            results.append(
                SkipVowelsSuggestion(
                    token: trimmed,
                    normalized: clean,
                    source: source,
                    isExactMatch: isExact
                )
            )
        }

        // 1. Exact built-in mapping
        if let exact = builtInMappings[trimmed] {
            appendUnique(exact, source: "exact", isExact: true)
        } else if let ciMatch = builtInMappings.first(where: { $0.key.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            appendUnique(ciMatch.value, source: "exact", isExact: true)
        }

        // 2. Exact match from A3odex or custom rules
        for entry in knownEntries where entry.token == trimmed {
            appendUnique(entry.canonical, source: "a3odex", isExact: true)
        }
        for entry in knownEntries where entry.token.caseInsensitiveCompare(trimmed) == .orderedSame {
            appendUnique(entry.canonical, source: "a3odex", isExact: false)
        }

        // 3. Consonant-skeleton matching against A3odex canonicals + custom lexicon + built-in lexicon
        var lexicon: [String] = []
        var seenLex: Set<String> = []
        for phrase in extraLexicon + knownEntries.map(\.canonical) + builtInLexicon {
            if !phrase.isEmpty, !seenLex.contains(phrase) {
                seenLex.insert(phrase)
                lexicon.append(phrase)
            }
        }

        let targetSkel = consonantSkeleton(trimmed)
        let targetLeadSkel = consonantSkeleton(trimmed, includeLeadingVowel: true)
        let splitToken = splitTrailingUpperTag(trimmed)

        if !targetSkel.isEmpty || splitToken != nil {
            for candidate in lexicon {
                let candSkel = consonantSkeleton(candidate)
                let candLeadSkel = consonantSkeleton(candidate, includeLeadingVowel: true)
                if !targetSkel.isEmpty && (candSkel == targetSkel || candLeadSkel == targetLeadSkel) {
                    appendUnique(candidate, source: "skeleton", isExact: false)
                    continue
                }
                if let (tokStem, tokTag) = splitToken {
                    let tokStemSkel = consonantSkeleton(tokStem)
                    if let (candStem, candTag) = splitTrailingUpperTag(candidate),
                       candTag == tokTag,
                       !tokStemSkel.isEmpty,
                       consonantSkeleton(candStem) == tokStemSkel {
                        appendUnique(candidate, source: "skeleton", isExact: false)
                    } else if !tokStemSkel.isEmpty && candSkel == tokStemSkel && !candidate.hasSuffix(" \(tokTag)") {
                        appendUnique("\(candidate) \(tokTag)", source: "skeleton", isExact: false)
                    }
                }
            }
        }

        if results.isEmpty {
            appendUnique(trimmed, source: "fallback", isExact: false)
        }

        return results
    }

    public static func bestSuggestion(
        for token: String,
        knownEntries: [(token: String, canonical: String)] = [],
        extraLexicon: [String] = []
    ) -> SkipVowelsSuggestion? {
        suggestCleanForms(for: token, knownEntries: knownEntries, extraLexicon: extraLexicon).first
    }

    public static func makeVerifiedRule(token: String, normalized: String) -> MUNSCRule {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNorm = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = cleanToken.map { ($0.isLetter || $0.isNumber) ? String($0) : "_" }.joined()
        return MUNSCRule(
            name: "skip_vowels_\(slug)",
            pattern: cleanToken,
            replacement: cleanNorm,
            isRegex: false,
            description: "Skip vowels verified"
        )
    }
}

public enum VerificationTagHelper: Sendable {
    public static func appendII(to token: String) -> String {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }
        if clean.hasSuffix("ii") {
            return clean
        }
        return "\(clean)ii"
    }

    public static func appendIS5(to token: String) -> String {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }
        if clean.lowercased() == "is" {
            return "is5"
        }
        if clean.hasSuffix("is5") {
            return clean
        }
        return "\(clean)is5"
    }

    public static func isHierarchyOrVerifiedTag(_ token: String) -> Bool {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean == "i9or1" { return true }
        if clean.hasSuffix("is5") { return true }
        if clean.count >= 3 && clean.hasSuffix("ii") { return true }
        return false
    }
}

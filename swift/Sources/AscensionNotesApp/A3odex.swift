import Foundation

public enum A3odexTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case funs = "FUNs"
    case funcs = "FUNCs"
    case sxuncs = "SxUNCs"
    case svnuncs = "SvnUNCs"

    public var id: String { rawValue }

    public var charBadge: String {
        switch self {
        case .funs: return "4c"
        case .funcs: return "5c"
        case .sxuncs: return "6c"
        case .svnuncs: return "7c"
        }
    }

    public var displayTitle: String {
        "\(rawValue) (\(charBadge))"
    }

    public static func inferred(for token: String) -> A3odexTier {
        switch token.count {
        case ...4: return .funs
        case 5: return .funcs
        case 6: return .sxuncs
        default: return .svnuncs
        }
    }

    public static func parse(_ raw: String) -> A3odexTier? {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "funs", "fun", "4c": return .funs
        case "funcs", "func", "5c": return .funcs
        case "sxuncs", "sxunc", "6c": return .sxuncs
        case "svnuncs", "svnunc", "7c": return .svnuncs
        default: return nil
        }
    }
}

public struct A3odexEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(tier.rawValue):\(token)" }
    public let token: String
    public let canonical: String
    public let tier: A3odexTier
    public let meaning: String

    enum CodingKeys: String, CodingKey {
        case token, term, word
        case canonical, normalized, clean
        case tier
        case meaning, description, note
    }

    public init(
        token: String,
        canonical: String,
        tier: A3odexTier? = nil,
        meaning: String = ""
    ) {
        self.token = token
        self.canonical = canonical
        self.tier = tier ?? A3odexTier.inferred(for: token)
        self.meaning = meaning
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let plainToken = try? single.decode(String.self) {
            self.init(token: plainToken, canonical: plainToken, tier: A3odexTier.inferred(for: plainToken), meaning: "")
            return
        }

        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tok = try c.decodeIfPresent(String.self, forKey: .token)
            ?? c.decodeIfPresent(String.self, forKey: .term)
            ?? c.decode(String.self, forKey: .word)
        let canon = try c.decodeIfPresent(String.self, forKey: .canonical)
            ?? c.decodeIfPresent(String.self, forKey: .normalized)
            ?? c.decodeIfPresent(String.self, forKey: .clean)
            ?? tok
        let decodedTier: A3odexTier
        if let tierStr = try c.decodeIfPresent(String.self, forKey: .tier),
           let parsed = A3odexTier.parse(tierStr) {
            decodedTier = parsed
        } else {
            decodedTier = A3odexTier.inferred(for: tok)
        }
        let desc = try c.decodeIfPresent(String.self, forKey: .meaning)
            ?? c.decodeIfPresent(String.self, forKey: .description)
            ?? c.decodeIfPresent(String.self, forKey: .note)
            ?? ""
        self.init(token: tok, canonical: canon, tier: decodedTier, meaning: desc)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(token, forKey: .token)
        try c.encode(canonical, forKey: .canonical)
        try c.encode(tier.rawValue, forKey: .tier)
        try c.encode(meaning, forKey: .meaning)
    }
}

public enum A3odexError: Error, LocalizedError, Sendable {
    case invalidFormat

    public var errorDescription: String? {
        "Unrecognized a3odex.json structure. Expected an array of entries, {\"entries\": [...]}, or tier-grouped FUNs/FUNCs/SxUNCs/SvnUNCs."
    }
}

public enum A3odexCatalog: Sendable {
    public static let starterEntries: [A3odexEntry] = [
        // 4c FUNs
        A3odexEntry(token: "AXIF", canonical: "AXIF", tier: .funs, meaning: "Ascension eXchangeable Identifier Format metadata sidecar."),
        A3odexEntry(token: "AX1F", canonical: "AXIF", tier: .funs, meaning: "Leet-1 AXIF variant normalizing cleanly back to AXIF via custom/leet rules."),
        A3odexEntry(token: "T0UX", canonical: "Time0", tier: .funs, meaning: "Base-38 Jesus Clock Unix epoch anchor (1584540571 / 2020-03-18T14:09:31Z)."),
        A3odexEntry(token: "B00K", canonical: "Book", tier: .funs, meaning: "Double-zero leet MUNSC token for Reading & Book checklists."),
        A3odexEntry(token: "NrmA", canonical: "Norma A", tier: .funs, meaning: "Skip-vowels 4-char FUN for Norma A (Where's Norma? Book A)."),
        A3odexEntry(token: "NrmB", canonical: "Norma B", tier: .funs, meaning: "Skip-vowels 4-char FUN for Norma B (Where's Norma? Book B)."),
        A3odexEntry(token: "GSii", canonical: "GSii", tier: .funs, meaning: "Verified double-i (ii) 4-char FUN used by certified ILS ATSS."),
        A3odexEntry(token: "qst2", canonical: "qst2", tier: .funs, meaning: "Question-to dispatch prefix (paired with ftrq2) across AntTeam channels."),

        // 5c FUNCs
        A3odexEntry(token: "N0rma", canonical: "Norma", tier: .funcs, meaning: "Internal-zero leet MUNSC for Norma in Chamber Luncheon logs."),
        A3odexEntry(token: "NormA", canonical: "Norma", tier: .funcs, meaning: "Trailing uppercase MUNSC distinguishing NormA from Norm4 and Norma4."),
        A3odexEntry(token: "Norm4", canonical: "Norma", tier: .funcs, meaning: "Leet-4 MUNSC variant normalizing to Norma in Clean View."),
        A3odexEntry(token: "MUNSC", canonical: "MUNSC", tier: .funcs, meaning: "Multiple Unique Non-Special Characters embedded inside clean prose."),
        A3odexEntry(token: "Time0", canonical: "Time0", tier: .funcs, meaning: "March 8 Miracle / Base-38 zero-point clock reference."),
        A3odexEntry(token: "i9or1", canonical: "i9or1", tier: .funcs, meaning: "Search hierarchy 5-char FUNC (immediate, incredibly important, information) paired with is5."),
        A3odexEntry(token: "siri1", canonical: "Siri", tier: .funcs, meaning: "Bog-character lowercase self-handle for Siri (lowercases itself like spy on SlogBog)."),
        A3odexEntry(token: "sp4ce", canonical: "sp4ce", tier: .funcs, meaning: "Telescope tool case built by spy for X-ray tube testing at Varian Associates XRTP; AnecdotaL1 Story5 Data1a brain-bucket."),

        // 6c SxUNCs
        A3odexEntry(token: "Acode9", canonical: "Acode9", tier: .sxuncs, meaning: "9-char Jesus Clock stamped identifier (e.g. Ab2p^a40z)."),
        A3odexEntry(token: "Base38", canonical: "Base38", tier: .sxuncs, meaning: "38-symbol twst23 alphabet: 0-9, a-z, |, ^."),
        A3odexEntry(token: "Norma4", canonical: "Norma", tier: .sxuncs, meaning: "Trailing numeric disambiguator MUNSC normalizing to Norma."),
        A3odexEntry(token: "7Aunts", canonical: "7 Aunts", tier: .sxuncs, meaning: "Seven Aunts reference token from Formicary Castle logs."),
        A3odexEntry(token: "good1a", canonical: "good1a", tier: .sxuncs, meaning: "Strict letter-bounded 4-char Acode9 tail mode [a-z][0-9a-z]{2}[a-z]."),
        A3odexEntry(token: "Anotes", canonical: "Ascension Notes", tier: .sxuncs, meaning: "Skip-vowels 6-char SxUNC referring to the Ascension Notes app."),
        A3odexEntry(token: "Data1a", canonical: "Data1a", tier: .sxuncs, meaning: "Anecdotal Story Data layer 1a bucket for retelling short-stories and Strange Things."),
        A3odexEntry(token: "Story5", canonical: "Story5", tier: .sxuncs, meaning: "Short-story storytelling unit in AnecdotaL1 brain-bucket."),

        // 7c SvnUNCs
        A3odexEntry(token: "First1a", canonical: "First1a", tier: .svnuncs, meaning: "Defining First1a milestone marker across Ascender1a logs."),
        A3odexEntry(token: "S1tsUW8", canonical: "SitsUW8", tier: .svnuncs, meaning: "Sits-You-Weigh-Station MUNSC token (7-char SvnUNC)."),
        A3odexEntry(token: "WhrNrmA", canonical: "Where's Norma A", tier: .svnuncs, meaning: "Skip-vowels 7-char SvnUNC for Where's Norma? Book A."),
        A3odexEntry(token: "WhrNrmB", canonical: "Where's Norma B", tier: .svnuncs, meaning: "Skip-vowels 7-char SvnUNC for Where's Norma? Book B."),
        A3odexEntry(token: "Things5", canonical: "Things5", tier: .svnuncs, meaning: "Anecdotal collection token (ST57range Things5) in L1 story store."),
        A3odexEntry(token: "hv2p2gn", canonical: "hv2p2gn", tier: .svnuncs, meaning: "32GB Green microSD card archive brain-bucket (renamed from 2p2fnv; HV2p2red for Mr. MacBook).")
    ]

    public static func decodeJSON(_ data: Data) throws -> [A3odexEntry] {
        let decoder = JSONDecoder()

        if let directArray = try? decoder.decode([A3odexEntry].self, from: data) {
            return directArray
        }

        struct Wrapper: Decodable {
            let entries: [A3odexEntry]?
            let FUNs: [A3odexEntry]?
            let FUNCs: [A3odexEntry]?
            let SxUNCs: [A3odexEntry]?
            let SvnUNCs: [A3odexEntry]?
        }

        if let wrapper = try? decoder.decode(Wrapper.self, from: data) {
            var collected: [A3odexEntry] = []
            if let entries = wrapper.entries {
                collected.append(contentsOf: entries)
            }
            if let funs = wrapper.FUNs {
                collected.append(contentsOf: funs.map { A3odexEntry(token: $0.token, canonical: $0.canonical, tier: .funs, meaning: $0.meaning) })
            }
            if let funcs = wrapper.FUNCs {
                collected.append(contentsOf: funcs.map { A3odexEntry(token: $0.token, canonical: $0.canonical, tier: .funcs, meaning: $0.meaning) })
            }
            if let sxuncs = wrapper.SxUNCs {
                collected.append(contentsOf: sxuncs.map { A3odexEntry(token: $0.token, canonical: $0.canonical, tier: .sxuncs, meaning: $0.meaning) })
            }
            if let svnuncs = wrapper.SvnUNCs {
                collected.append(contentsOf: svnuncs.map { A3odexEntry(token: $0.token, canonical: $0.canonical, tier: .svnuncs, meaning: $0.meaning) })
            }
            if !collected.isEmpty {
                return collected
            }
        }

        throw A3odexError.invalidFormat
    }
}

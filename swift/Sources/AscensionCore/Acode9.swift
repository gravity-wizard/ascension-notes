import Foundation

public enum Acode9Mode: String, Codable, Sendable, CaseIterable {
    case standard
    case good1a
    case second1a

    public var isStrict: Bool {
        self == .good1a || self == .second1a
    }
}

public enum Acode9Error: Error, LocalizedError, Sendable, Equatable {
    case invalidLength(Int)
    case invalidBigA(Character)
    case invalidCenter(Character)
    case invalidClockCharacter(Character)
    case invalidLeadLetter(actual: Character, expected: Character, clockChar: Character)
    case invalidTailCharacter(Character)
    case strictValidationFailed([String])
    case generationExhausted(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLength(let len):
            return "Acode9 must be exactly 9 characters, got \(len)."
        case .invalidBigA(let ch):
            return "Acode9[0] must be 'A', got '\(ch)'."
        case .invalidCenter(let ch):
            return "Acode9[4] center must be '^' or '-', got '\(ch)'."
        case .invalidClockCharacter(let ch):
            return "Invalid B38 clock character '\(ch)'."
        case .invalidLeadLetter(let actual, let expected, let clockChar):
            return "Acode9[1] leadLetter '\(actual)' does not match clock[0]='\(clockChar)' (expected '\(expected)')."
        case .invalidTailCharacter(let ch):
            return "Invalid B38 tail character '\(ch)'."
        case .strictValidationFailed(let reasons):
            return "Acode9 failed validation: \(reasons.joined(separator: ", "))."
        case .generationExhausted(let attempts):
            return "Failed to generate clean Acode9 after \(attempts) attempts."
        }
    }
}

public struct Acode9Parts: Codable, Hashable, Sendable {
    public let raw: String
    public let canonical: String
    public let urlSafe: String
    public let bigA: Character
    public let leadLetter: Character
    public let clock2: String
    public let center: Character
    public let tail4: String
    public let isGood1a: Bool

    public func toDash() -> String { urlSafe }
    public func toCaret() -> String { canonical }

    enum CodingKeys: String, CodingKey {
        case raw, canonical, urlSafe, clock2, tail4, isGood1a
    }

    public init(
        raw: String,
        canonical: String,
        urlSafe: String,
        bigA: Character,
        leadLetter: Character,
        clock2: String,
        center: Character,
        tail4: String,
        isGood1a: Bool
    ) {
        self.raw = raw
        self.canonical = canonical
        self.urlSafe = urlSafe
        self.bigA = bigA
        self.leadLetter = leadLetter
        self.clock2 = clock2
        self.center = center
        self.tail4 = tail4
        self.isGood1a = isGood1a
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(String.self, forKey: .raw)
        let parsed = try Acode9.parse(rawValue, allowDash: true)
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(raw, forKey: .raw)
        try container.encode(canonical, forKey: .canonical)
        try container.encode(urlSafe, forKey: .urlSafe)
        try container.encode(clock2, forKey: .clock2)
        try container.encode(tail4, forKey: .tail4)
        try container.encode(isGood1a, forKey: .isGood1a)
    }
}

public struct Acode9ValidationResult: Sendable, Equatable {
    public let valid: Bool
    public let reasons: [String]
    public let parts: Acode9Parts?
    public let isGood1a: Bool
}

public struct Acode9PoolEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String { acode9 }
    public let acode9: String
    public let timestamp: Int64
    public let jesusClock: String
    public let mode: Acode9Mode

    public init(acode9: String, timestamp: Int64, jesusClock: String, mode: Acode9Mode) {
        self.acode9 = acode9
        self.timestamp = timestamp
        self.jesusClock = jesusClock
        self.mode = mode
    }
}

public enum Acode9: Sendable {
    public static let bigA: Character = "A"
    public static let centerCaret: Character = "^"
    public static let centerDash: Character = "-"

    private static let lowerChars: [Character] = Array("abcdefghijklmnopqrstuvwxyz")
    private static let alnumChars: [Character] = Array("0123456789abcdefghijklmnopqrstuvwxyz")
    private static let b38Chars: [Character] = Array(Base38Clock.alphabet)
    private static let lowerSet: Set<Character> = Set(lowerChars)
    private static let alnumSet: Set<Character> = Set(alnumChars)

    public static let defaultBlockedSubstrings: [String] = [
        "666",
        "anal", "anus", "arse", "bitch", "btch", "cock", "c0ck", "cunt",
        "damn", "dick", "d1ck", "dyke", "fag", "fck", "fuk", "fuck",
        "hell", "jizz", "kike", "klan", "nazi", "nig", "n1g", "porn",
        "p0rn", "puss", "rape", "shit", "sh1t", "slut", "spic", "twat",
        "wank", "whor", "xxx"
    ]

    private static let leetMap: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b"
    ]

    public static func leadLetter(for clockChar: Character) throws -> Character {
        let canonicalChar: Character = (clockChar == "_") ? "|" : ((clockChar == "-") ? "^" : clockChar)
        guard Base38Clock.contains(canonicalChar) else {
            throw Acode9Error.invalidClockCharacter(clockChar)
        }
        if canonicalChar >= "1" && canonicalChar <= "9", let ascii = canonicalChar.asciiValue {
            let offset = ascii - Character("1").asciiValue!
            return Character(UnicodeScalar(Character("a").asciiValue! + offset))
        }
        if canonicalChar == "0" {
            return "z"
        }
        if canonicalChar >= "a" && canonicalChar <= "z" {
            return canonicalChar
        }
        if canonicalChar == "|" {
            return "x"
        }
        if canonicalChar == "^" {
            return "y"
        }
        throw Acode9Error.invalidClockCharacter(clockChar)
    }

    public static func toDash(_ code: String) throws -> String {
        let chars = Array(code)
        guard chars.count == 9 else { throw Acode9Error.invalidLength(chars.count) }
        guard chars[4] == centerCaret || chars[4] == centerDash else {
            throw Acode9Error.invalidCenter(chars[4])
        }
        let left = Base38Clock.toURLSafe(String(chars[0..<4]))
        let right = Base38Clock.toURLSafe(String(chars[5..<9]))
        return left + String(centerDash) + right
    }

    public static func toCaret(_ code: String) throws -> String {
        let chars = Array(code)
        guard chars.count == 9 else { throw Acode9Error.invalidLength(chars.count) }
        guard chars[4] == centerCaret || chars[4] == centerDash else {
            throw Acode9Error.invalidCenter(chars[4])
        }
        let left = Base38Clock.fromURLSafe(String(chars[0..<4]))
        let right = Base38Clock.fromURLSafe(String(chars[5..<9]))
        return left + String(centerCaret) + right
    }

    public static func isGood1aTail(_ tail4: String) -> Bool {
        let chars = Array(tail4)
        guard chars.count == 4 else { return false }
        return lowerSet.contains(chars[0])
            && alnumSet.contains(chars[1])
            && alnumSet.contains(chars[2])
            && lowerSet.contains(chars[3])
    }

    public static func parse(_ code: String, allowDash: Bool = true) throws -> Acode9Parts {
        let rawChars = Array(code)
        guard rawChars.count == 9 else {
            throw Acode9Error.invalidLength(rawChars.count)
        }
        guard rawChars[0] == bigA else {
            throw Acode9Error.invalidBigA(rawChars[0])
        }
        let center = rawChars[4]
        let validCenter = allowDash ? (center == centerCaret || center == centerDash) : (center == centerCaret)
        guard validCenter else {
            throw Acode9Error.invalidCenter(center)
        }

        let normalized = allowDash ? try toCaret(code) : code
        let chars = Array(normalized)

        let clock2Chars = [chars[2], chars[3]]
        for ch in clock2Chars {
            guard Base38Clock.contains(ch) else {
                throw Acode9Error.invalidClockCharacter(ch)
            }
        }

        let expectedLead = try leadLetter(for: clock2Chars[0])
        guard chars[1] == expectedLead else {
            throw Acode9Error.invalidLeadLetter(
                actual: chars[1],
                expected: expectedLead,
                clockChar: clock2Chars[0]
            )
        }

        let tailChars = Array(chars[5..<9])
        for ch in tailChars {
            guard Base38Clock.contains(ch) else {
                throw Acode9Error.invalidTailCharacter(ch)
            }
        }

        let clock2 = String(clock2Chars)
        let tail4 = String(tailChars)
        let canonical = "\(bigA)\(chars[1])\(clock2)\(centerCaret)\(tail4)"
        let urlSafe = try toDash(canonical)

        return Acode9Parts(
            raw: code,
            canonical: canonical,
            urlSafe: urlSafe,
            bigA: bigA,
            leadLetter: chars[1],
            clock2: clock2,
            center: center,
            tail4: tail4,
            isGood1a: isGood1aTail(tail4)
        )
    }

    public static func isCleanID(
        _ candidate: String,
        blockedSubstrings: [String]? = nil,
        existingPool: Set<String> = [],
        blockAllSameTail: Bool = true,
        blockRepeatedPairs: Bool = false,
        ambiguousChars: String = ""
    ) -> (clean: Bool, reasons: [String]) {
        var reasons: [String] = []

        if candidate.isEmpty {
            reasons.append("empty_candidate")
        } else if candidate.count > 11 {
            reasons.append("exceeds_11_char_filter_window")
        }

        if !existingPool.isEmpty {
            var variants: Set<String> = [candidate]
            if let caret = try? toCaret(candidate), let dash = try? toDash(candidate) {
                variants.insert(caret)
                variants.insert(dash)
            }
            if !variants.isDisjoint(with: existingPool) {
                reasons.append("pool_collision")
            }
        }

        let chars = Array(candidate)
        let tail4: String
        let core: String
        if chars.count == 9 && (chars[4] == centerCaret || chars[4] == centerDash) {
            tail4 = String(chars[5..<9])
            core = String(chars[1..<4]) + tail4
        } else {
            tail4 = chars.count >= 4 ? String(chars.suffix(4)) : candidate
            core = String(chars.filter { $0 != "^" && $0 != "-" && $0 != "_" && $0 != "|" })
        }

        let blocked = (blockedSubstrings ?? defaultBlockedSubstrings).map { $0.lowercased() }.filter { !$0.isEmpty }
        let tailLower = tail4.lowercased()
        let coreLower = core.lowercased()
        if tailLower.contains("666") || coreLower.contains("666") {
            reasons.append("blocked_substring:666")
        }
        let tailLeet = String(tailLower.map { leetMap[$0] ?? $0 })
        let coreLeet = String(coreLower.map { leetMap[$0] ?? $0 })

        for bad in blocked where bad != "666" {
            if tailLower.contains(bad) || coreLower.contains(bad) || tailLeet.contains(bad) || coreLeet.contains(bad) {
                reasons.append("blocked_substring:\(bad)")
                break
            }
        }

        let tailArray = Array(tail4)
        if tailArray.count == 4 {
            if blockAllSameTail && Set(tailArray).count == 1 {
                reasons.append("all_same_tail_pattern")
            }
            if blockRepeatedPairs && tailArray[0] == tailArray[2] && tailArray[1] == tailArray[3] {
                reasons.append("repeated_pair_tail_pattern")
            }
        }

        if !ambiguousChars.isEmpty {
            let ambSet = Set(ambiguousChars)
            let target = chars.count == 9 ? tail4 : candidate
            if target.contains(where: { ambSet.contains($0) }) {
                reasons.append("ambiguous_character")
            }
        }

        return (reasons.isEmpty, reasons)
    }

    public static func validate(
        _ code: String,
        strict: Bool = false,
        mode: Acode9Mode? = nil,
        allowDash: Bool = true,
        filterProfanity: Bool = true,
        blockedSubstrings: [String]? = nil,
        existingPool: Set<String> = [],
        blockAllSameTail: Bool = true,
        blockRepeatedPairs: Bool = false,
        ambiguousChars: String = ""
    ) -> Acode9ValidationResult {
        let enforceStrict = strict || (mode?.isStrict ?? false)
        let parts: Acode9Parts
        do {
            parts = try parse(code, allowDash: allowDash)
        } catch {
            return Acode9ValidationResult(
                valid: false,
                reasons: [error.localizedDescription],
                parts: nil,
                isGood1a: false
            )
        }

        var reasons: [String] = []
        if enforceStrict && !parts.isGood1a {
            reasons.append("tail4 '\(parts.tail4)' does not satisfy good1a/second1a strict rules")
        }

        if filterProfanity || !existingPool.isEmpty || blockRepeatedPairs || !ambiguousChars.isEmpty {
            let filterRes = isCleanID(
                parts.canonical,
                blockedSubstrings: filterProfanity ? blockedSubstrings : [],
                existingPool: existingPool,
                blockAllSameTail: blockAllSameTail,
                blockRepeatedPairs: blockRepeatedPairs,
                ambiguousChars: ambiguousChars
            )
            if !filterRes.clean {
                reasons.append(contentsOf: filterRes.reasons)
            }
        }

        return Acode9ValidationResult(
            valid: reasons.isEmpty,
            reasons: reasons,
            parts: parts,
            isGood1a: parts.isGood1a
        )
    }

    private static func randomTail4(mode: Acode9Mode) -> String {
        if mode.isStrict {
            let c0 = lowerChars.randomElement()!
            let c1 = alnumChars.randomElement()!
            let c2 = alnumChars.randomElement()!
            let c3 = lowerChars.randomElement()!
            return String([c0, c1, c2, c3])
        }
        return String((0..<4).map { _ in b38Chars.randomElement()! })
    }

    public static func generate(
        unixSeconds: Int64 = Int64(Date().timeIntervalSince1970),
        mode: Acode9Mode = .good1a,
        urlSafe: Bool = false,
        tail4: String? = nil,
        existingPool: Set<String> = [],
        blockedSubstrings: [String]? = nil,
        blockAllSameTail: Bool = true,
        blockRepeatedPairs: Bool = false,
        ambiguousChars: String = "",
        maxAttempts: Int = 1000
    ) throws -> String {
        let c2 = Base38Clock.clock2(unixSeconds: unixSeconds)
        let lead = try leadLetter(for: c2.first!)

        if let fixedTail = tail4 {
            let rawCandidate = "\(bigA)\(lead)\(c2)\(centerCaret)\(fixedTail)"
            let candidate = urlSafe ? try toDash(rawCandidate) : rawCandidate
            let res = validate(
                candidate,
                strict: mode.isStrict,
                allowDash: true,
                filterProfanity: true,
                blockedSubstrings: blockedSubstrings,
                existingPool: existingPool,
                blockAllSameTail: blockAllSameTail,
                blockRepeatedPairs: blockRepeatedPairs,
                ambiguousChars: ambiguousChars
            )
            guard res.valid else {
                throw Acode9Error.strictValidationFailed(res.reasons)
            }
            return candidate
        }

        for _ in 0..<maxAttempts {
            let sampled = randomTail4(mode: mode)
            let rawCandidate = "\(bigA)\(lead)\(c2)\(centerCaret)\(sampled)"
            let candidate = urlSafe ? try toDash(rawCandidate) : rawCandidate
            let res = validate(
                candidate,
                strict: mode.isStrict,
                allowDash: true,
                filterProfanity: true,
                blockedSubstrings: blockedSubstrings,
                existingPool: existingPool,
                blockAllSameTail: blockAllSameTail,
                blockRepeatedPairs: blockRepeatedPairs,
                ambiguousChars: ambiguousChars
            )
            if res.valid {
                return candidate
            }
        }

        throw Acode9Error.generationExhausted(maxAttempts)
    }

    public static func generateRollingPool(
        count: Int = 60,
        startUnixSeconds: Int64 = Int64(Date().timeIntervalSince1970),
        cadenceSeconds: Int64 = 1,
        mode: Acode9Mode = .good1a,
        urlSafe: Bool = false,
        existingPool: Set<String> = [],
        blockedSubstrings: [String]? = nil,
        blockAllSameTail: Bool = true,
        blockRepeatedPairs: Bool = false,
        ambiguousChars: String = ""
    ) throws -> [Acode9PoolEntry] {
        var seen = existingPool
        for existing in existingPool {
            if let caret = try? toCaret(existing), let dash = try? toDash(existing) {
                seen.insert(caret)
                seen.insert(dash)
            }
        }

        var entries: [Acode9PoolEntry] = []
        entries.reserveCapacity(max(0, count))

        for i in 0..<max(0, count) {
            let ts = startUnixSeconds + Int64(i) * max(1, cadenceSeconds)
            let code = try generate(
                unixSeconds: ts,
                mode: mode,
                urlSafe: urlSafe,
                existingPool: seen,
                blockedSubstrings: blockedSubstrings,
                blockAllSameTail: blockAllSameTail,
                blockRepeatedPairs: blockRepeatedPairs,
                ambiguousChars: ambiguousChars
            )
            if let caret = try? toCaret(code), let dash = try? toDash(code) {
                seen.insert(caret)
                seen.insert(dash)
            }
            let clockReading = Base38Clock.safeJesusClock(unixSeconds: ts, minWidth: 2, urlSafe: urlSafe)
            entries.append(
                Acode9PoolEntry(
                    acode9: code,
                    timestamp: ts,
                    jesusClock: clockReading.clock,
                    mode: mode
                )
            )
        }

        return entries
    }
}

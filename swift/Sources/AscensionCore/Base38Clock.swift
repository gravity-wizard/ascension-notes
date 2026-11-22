import Foundation

public enum Base38Error: Error, LocalizedError, Sendable, Equatable {
    case negativeValue(Int64)
    case emptyString
    case invalidCharacter(Character)

    public var errorDescription: String? {
        switch self {
        case .negativeValue(let value):
            return "Base-38 encoding requires a non-negative integer, got \(value)."
        case .emptyString:
            return "Base-38 string must not be empty."
        case .invalidCharacter(let ch):
            return "Invalid Base-38 character '\(ch)'."
        }
    }
}

public struct SafeClockReading: Codable, Hashable, Sendable {
    public let clock: String
    public let rawClock: String
    public let isPaused: Bool
    public let effectiveUnix: Int64
    public let rawUnix: Int64
}

/// Base-38 (`twst23`) encoding and safe Jesus Clock (`Time0`) anchored at 2020-03-18T14:09:31Z.
public enum Base38Clock: Sendable {
    public static let alphabet = "0123456789abcdefghijklmnopqrstuvwxyz|^"
    public static let base: Int64 = 38
    public static let t0Unix: Int64 = 1_584_540_571

    private static let chars: [Character] = Array(alphabet)
    private static let indexMap: [Character: Int64] = {
        var map: [Character: Int64] = [:]
        map.reserveCapacity(chars.count)
        for (idx, ch) in chars.enumerated() {
            map[ch] = Int64(idx)
        }
        return map
    }()

    private static let leetMap: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b"
    ]

    public static func toURLSafe(_ value: String) -> String {
        value.replacingOccurrences(of: "^", with: "-").replacingOccurrences(of: "|", with: "_")
    }

    public static func fromURLSafe(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: "^").replacingOccurrences(of: "_", with: "|")
    }

    public static func contains(_ ch: Character) -> Bool {
        if ch == "-" || ch == "_" { return true }
        return indexMap[ch] != nil
    }

    public static func encode(_ value: Int64) throws -> String {
        guard value >= 0 else {
            throw Base38Error.negativeValue(value)
        }
        if value == 0 {
            return "0"
        }
        var n = value
        var output: [Character] = []
        while n > 0 {
            let rem = Int(n % base)
            n /= base
            output.append(chars[rem])
        }
        return String(output.reversed())
    }

    public static func decode(_ encoded: String) throws -> Int64 {
        guard !encoded.isEmpty else {
            throw Base38Error.emptyString
        }
        let canonical = fromURLSafe(encoded)
        var total: Int64 = 0
        for ch in canonical {
            guard let idx = indexMap[ch] else {
                throw Base38Error.invalidCharacter(ch)
            }
            total = total * base + idx
        }
        return total
    }

    public static func jesusClock(unixSeconds: Int64, minWidth: Int = 1, urlSafe: Bool = false) -> String {
        let elapsed = max(Int64(0), unixSeconds - t0Unix)
        var encoded = (try? encode(elapsed)) ?? "0"
        if minWidth > 1 && encoded.count < minWidth {
            encoded = String(repeating: "0", count: minWidth - encoded.count) + encoded
        }
        return urlSafe ? toURLSafe(encoded) : encoded
    }

    public static func jesusClock(for date: Date = Date(), minWidth: Int = 1, urlSafe: Bool = false) -> String {
        jesusClock(unixSeconds: Int64(date.timeIntervalSince1970), minWidth: minWidth, urlSafe: urlSafe)
    }

    public static func findBlockReason(
        in clockStr: String,
        blockedSubstrings: [String]? = nil
    ) -> (token: String, endIndex: Int)? {
        let canonical = fromURLSafe(clockStr).lowercased()
        if let range = canonical.range(of: "666") {
            let endIdx = canonical.distance(from: canonical.startIndex, to: range.upperBound)
            return ("666", endIdx)
        }

        let core = canonical.filter { $0 != "|" && $0 != "^" }
        let leet = String(core.map { leetMap[$0] ?? $0 })
        let blocked = (blockedSubstrings ?? Acode9.defaultBlockedSubstrings)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty && $0 != "666" }

        for bad in blocked {
            if let range = core.range(of: bad) {
                let endIdx = min(canonical.count, core.distance(from: core.startIndex, to: range.upperBound))
                return (bad, endIdx)
            }
            if let range = leet.range(of: bad) {
                let endIdx = min(canonical.count, leet.distance(from: leet.startIndex, to: range.upperBound))
                return (bad, endIdx)
            }
        }
        return nil
    }

    public static func isCleanClock(_ clockStr: String, blockedSubstrings: [String]? = nil) -> Bool {
        findBlockReason(in: clockStr, blockedSubstrings: blockedSubstrings) == nil
    }

    /// Computes Base-38 Jesus Clock while pausing cleanly over triple-6 ("666") and blocked substrings.
    public static func safeJesusClock(
        unixSeconds: Int64 = Int64(Date().timeIntervalSince1970),
        minWidth: Int = 1,
        urlSafe: Bool = false,
        blockedSubstrings: [String]? = nil
    ) -> SafeClockReading {
        let rawElapsed = max(Int64(0), unixSeconds - t0Unix)
        var rawClock = (try? encode(rawElapsed)) ?? "0"
        if minWidth > 1 && rawClock.count < minWidth {
            rawClock = String(repeating: "0", count: minWidth - rawClock.count) + rawClock
        }

        var elapsed = rawElapsed
        var isPaused = false

        while elapsed > 0 {
            var candidate = (try? encode(elapsed)) ?? "0"
            if minWidth > 1 && candidate.count < minWidth {
                candidate = String(repeating: "0", count: minWidth - candidate.count) + candidate
            }
            guard let hit = findBlockReason(in: candidate, blockedSubstrings: blockedSubstrings) else {
                return SafeClockReading(
                    clock: urlSafe ? toURLSafe(candidate) : candidate,
                    rawClock: urlSafe ? toURLSafe(rawClock) : rawClock,
                    isPaused: isPaused,
                    effectiveUnix: t0Unix + elapsed,
                    rawUnix: unixSeconds
                )
            }
            isPaused = true
            let trailingDigits = max(0, candidate.count - hit.endIndex)
            let jump = powInt64(base, trailingDigits)
            let step = trailingDigits > 0 ? ((elapsed % jump) + 1) : 1
            elapsed = max(Int64(0), elapsed - max(Int64(1), step))
        }

        let zero = minWidth > 1 ? String(repeating: "0", count: minWidth) : "0"
        return SafeClockReading(
            clock: zero,
            rawClock: urlSafe ? toURLSafe(rawClock) : rawClock,
            isPaused: isPaused,
            effectiveUnix: t0Unix,
            rawUnix: unixSeconds
        )
    }

    private static func powInt64(_ baseVal: Int64, _ exp: Int) -> Int64 {
        guard exp > 0 else { return 1 }
        var result: Int64 = 1
        for _ in 0..<min(exp, 10) {
            result &*= baseVal
        }
        return result
    }

    public static func decodeJesusClock(_ clock: String) throws -> Int64 {
        let elapsed = try decode(clock)
        return t0Unix + elapsed
    }

    public static func date(fromJesusClock clock: String) throws -> Date {
        let ts = try decodeJesusClock(clock)
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    public static func clock2(unixSeconds: Int64, urlSafe: Bool = false) -> String {
        let reading = safeJesusClock(unixSeconds: unixSeconds, minWidth: 2, urlSafe: urlSafe)
        return String(reading.clock.prefix(2))
    }

    public static func clock2(for date: Date = Date(), urlSafe: Bool = false) -> String {
        clock2(unixSeconds: Int64(date.timeIntervalSince1970), urlSafe: urlSafe)
    }

    // MARK: - Exact-Time Base-38 Arithmetic Workaround (Preserves MSDs & Uses Clean Lowercase)

    public struct ExactClockExpression: Codable, Hashable, Sendable {
        public let expression: String
        public let rawClock: String
        public let usedArithmeticWorkaround: Bool
        public let preservedMSDPrefix: String
        public let contextWordUsed: String?
        public let unixSeconds: Int64

        public init(
            expression: String,
            rawClock: String,
            usedArithmeticWorkaround: Bool,
            preservedMSDPrefix: String,
            contextWordUsed: String?,
            unixSeconds: Int64
        ) {
            self.expression = expression
            self.rawClock = rawClock
            self.usedArithmeticWorkaround = usedArithmeticWorkaround
            self.preservedMSDPrefix = preservedMSDPrefix
            self.contextWordUsed = contextWordUsed
            self.unixSeconds = unixSeconds
        }
    }

    private static let fallbackExactWords: [String] = [
        "sun", "sky", "joy", "art", "oak", "dew", "zen", "ace", "ray", "gem",
        "arc", "way", "key", "orb", "day", "era", "leaf", "peak", "pine", "wave",
        "moon", "glow", "hope", "love", "wind", "rain", "song", "book", "seed", "star",
        "calm", "home", "tree", "bird", "gold", "pure", "true", "wise", "good", "life",
        "angel", "bloom", "cloud", "dream", "earth", "faith", "grace", "heart", "light", "peace",
        "beacon", "nature", "wonder"
    ]

    public static func isLowerAlnumBase38(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.allSatisfy { ($0 >= "0" && $0 <= "9") || ($0 >= "a" && $0 <= "z") }
    }

    public static func isCleanLowerAlnumClock(_ value: String, blockedSubstrings: [String]? = nil) -> Bool {
        isLowerAlnumBase38(value) && isCleanClock(value, blockedSubstrings: blockedSubstrings)
    }

    public static func sanitizeFavorite3LetterOffset(_ raw: String?, blockedSubstrings: [String]? = nil) -> String? {
        guard let raw else { return nil }
        let letters = String(raw.lowercased().filter { $0 >= "a" && $0 <= "z" }.prefix(3))
        guard letters.count == 3,
              isCleanLowerAlnumClock(letters, blockedSubstrings: blockedSubstrings) else {
            return nil
        }
        return letters
    }

    /// Formats an exact Unix timestamp as a clean lowercase Base-38 tag (<= maxLength chars).
    /// When the raw Base-38 string hits "666", a blocked word, or non-alnum symbols (^/|),
    /// keeps the leading MSDs intact (e.g. `2p` or `2p7`) and emits a pretty lossless
    /// 9-digit + minus-sign formula (`2p7abc-xyz`, 6 digits minus 3 digits).
    /// When `favoriteOffset` is provided (e.g. "joy", "sun", or initials), it is prioritized first.
    public static func cleanExactClockExpression(
        unixSeconds: Int64 = Int64(Date().timeIntervalSince1970),
        contextWords: [String] = [],
        maxLength: Int = 17,
        alwaysUseDifferenceFormula: Bool = false,
        favoriteOffset: String? = nil,
        blockedSubstrings: [String]? = nil
    ) -> ExactClockExpression {
        let clampedUnix = max(t0Unix, unixSeconds)
        let elapsed = clampedUnix - t0Unix
        let rawClock = (try? encode(elapsed)) ?? "0"

        if !alwaysUseDifferenceFormula,
           rawClock.count <= maxLength,
           isCleanLowerAlnumClock(rawClock, blockedSubstrings: blockedSubstrings) {
            return ExactClockExpression(
                expression: rawClock,
                rawClock: rawClock,
                usedArithmeticWorkaround: false,
                preservedMSDPrefix: rawClock,
                contextWordUsed: nil,
                unixSeconds: clampedUnix
            )
        }

        // Extract clean 3-char lowercase [a-z] picture words first (for 6-3 = 9 digits + '-'),
        // prioritizing the Ascender's chosen favorite 3-letter offset if set,
        // then 2..6 char words as secondary fallback.
        var threeCharContext: [String] = []
        var otherContext: [String] = []
        var seenWords: Set<String> = []
        if let favorite = sanitizeFavorite3LetterOffset(favoriteOffset, blockedSubstrings: blockedSubstrings) {
            seenWords.insert(favorite)
            threeCharContext.append(favorite)
        }
        for rawWord in contextWords {
            let parts = rawWord
                .lowercased()
                .split { !($0 >= "a" && $0 <= "z") }
                .map(String.init)
            for part in parts where part.count >= 2 && part.count <= 6 {
                guard !seenWords.contains(part),
                      isCleanLowerAlnumClock(part, blockedSubstrings: blockedSubstrings) else {
                    continue
                }
                seenWords.insert(part)
                if part.count == 3 {
                    threeCharContext.append(part)
                } else {
                    otherContext.append(part)
                }
            }
        }

        var threeCharFallback: [String] = []
        var otherFallback: [String] = []
        for fallback in fallbackExactWords where !seenWords.contains(fallback) {
            guard isCleanLowerAlnumClock(fallback, blockedSubstrings: blockedSubstrings) else { continue }
            seenWords.insert(fallback)
            if fallback.count == 3 {
                threeCharFallback.append(fallback)
            } else {
                otherFallback.append(fallback)
            }
        }

        let preferred3WordPool = threeCharContext + threeCharFallback
        let fullWordPool = preferred3WordPool + otherContext + otherFallback

        // Candidate MSD prefixes from longest clean prefix (3 -> 2 -> 1 -> "")
        let rawChars = Array(rawClock)
        let maxMSD = max(0, min(3, rawChars.count - 2))
        var msdCandidates: [String] = []
        if maxMSD >= 1 {
            for len in stride(from: maxMSD, through: 1, by: -1) {
                let prefix = String(rawChars.prefix(len))
                if isCleanLowerAlnumClock(prefix, blockedSubstrings: blockedSubstrings) {
                    msdCandidates.append(prefix)
                }
            }
        }
        msdCandidates.append("")

        let targetAnchorDigits = rawClock.count

        // First pass across MSD tiers (3 -> 2 -> 1 -> ""): strictly prefer 9 Base-38 digits + '-' (<anchor>-<3-char>)
        let min3Digit = Int64(base * base)          // 1444 ("100")
        let max3Digit = min3Digit + 1200            // plenty to find a clean anchor quickly
        for msdPrefix in msdCandidates {
            // 1. Prefer strict 9-digit + '-' form: <targetAnchorDigits>-<3-char word> (e.g. 2p7n2s-gym)
            for word in preferred3WordPool {
                guard let rhsVal = try? decode(word), rhsVal > 0 else { continue }
                let plusAnchorVal = elapsed + rhsVal
                if let plusAnchor = try? encode(plusAnchorVal),
                   plusAnchor.count == targetAnchorDigits,
                   plusAnchor.hasPrefix(msdPrefix),
                   isCleanLowerAlnumClock(plusAnchor, blockedSubstrings: blockedSubstrings) {
                    let expr = "\(plusAnchor)-\(word)"
                    if expr.count <= maxLength {
                        return ExactClockExpression(
                            expression: expr,
                            rawClock: rawClock,
                            usedArithmeticWorkaround: true,
                            preservedMSDPrefix: msdPrefix,
                            contextWordUsed: word,
                            unixSeconds: clampedUnix
                        )
                    }
                }
            }

            // 2. Prefer strict 9-digit + '-' numeric 3-digit offset: 100_38 .. zzz_38 (e.g. 2p7abc-101)
            for step in min3Digit...max3Digit {
                guard let delta = try? encode(step),
                      delta.count == 3,
                      isCleanLowerAlnumClock(delta, blockedSubstrings: blockedSubstrings) else {
                    continue
                }
                if let plusAnchor = try? encode(elapsed + step),
                   plusAnchor.count == targetAnchorDigits,
                   plusAnchor.hasPrefix(msdPrefix),
                   isCleanLowerAlnumClock(plusAnchor, blockedSubstrings: blockedSubstrings) {
                    let expr = "\(plusAnchor)-\(delta)"
                    if expr.count <= maxLength {
                        return ExactClockExpression(
                            expression: expr,
                            rawClock: rawClock,
                            usedArithmeticWorkaround: true,
                            preservedMSDPrefix: msdPrefix,
                            contextWordUsed: nil,
                            unixSeconds: clampedUnix
                        )
                    }
                }
            }
        }

        // Secondary fallback across MSD tiers if strict 6-3 subtraction is not possible
        for msdPrefix in msdCandidates {
            // 3. Other clean word lengths (2 or 4..5 char) subtraction
            for word in fullWordPool where word.count != 3 {
                guard let rhsVal = try? decode(word), rhsVal > 0 else { continue }
                if let plusAnchor = try? encode(elapsed + rhsVal),
                   plusAnchor.hasPrefix(msdPrefix),
                   isCleanLowerAlnumClock(plusAnchor, blockedSubstrings: blockedSubstrings) {
                    let expr = "\(plusAnchor)-\(word)"
                    if expr.count <= maxLength {
                        return ExactClockExpression(
                            expression: expr,
                            rawClock: rawClock,
                            usedArithmeticWorkaround: true,
                            preservedMSDPrefix: msdPrefix,
                            contextWordUsed: word,
                            unixSeconds: clampedUnix
                        )
                    }
                }
            }

            // 4. Tiny offset subtraction (1..400) or addition fallback preserving MSDs
            for step in Int64(1)...Int64(400) {
                guard let delta = try? encode(step),
                      isCleanLowerAlnumClock(delta, blockedSubstrings: blockedSubstrings) else {
                    continue
                }
                if let plusAnchor = try? encode(elapsed + step),
                   plusAnchor.hasPrefix(msdPrefix),
                   isCleanLowerAlnumClock(plusAnchor, blockedSubstrings: blockedSubstrings) {
                    let expr = "\(plusAnchor)-\(delta)"
                    if expr.count <= maxLength {
                        return ExactClockExpression(
                            expression: expr,
                            rawClock: rawClock,
                            usedArithmeticWorkaround: true,
                            preservedMSDPrefix: msdPrefix,
                            contextWordUsed: nil,
                            unixSeconds: clampedUnix
                        )
                    }
                }
            }

            for word in fullWordPool {
                guard let rhsVal = try? decode(word), rhsVal > 0, elapsed >= rhsVal else { continue }
                if let minusAnchor = try? encode(elapsed - rhsVal),
                   minusAnchor.hasPrefix(msdPrefix),
                   isCleanLowerAlnumClock(minusAnchor, blockedSubstrings: blockedSubstrings) {
                    let expr = "\(minusAnchor)+\(word)"
                    if expr.count <= maxLength {
                        return ExactClockExpression(
                            expression: expr,
                            rawClock: rawClock,
                            usedArithmeticWorkaround: true,
                            preservedMSDPrefix: msdPrefix,
                            contextWordUsed: word,
                            unixSeconds: clampedUnix
                        )
                    }
                }
            }
        }

        // Last-resort safe fallback (never drops exact time)
        let safe = safeJesusClock(unixSeconds: clampedUnix, minWidth: 1, urlSafe: false, blockedSubstrings: blockedSubstrings)
        let delta = elapsed - (safe.effectiveUnix - t0Unix)
        if delta > 0,
           let deltaStr = try? encode(delta),
           isLowerAlnumBase38(safe.clock),
           isLowerAlnumBase38(deltaStr) {
            let expr = "\(safe.clock)+\(deltaStr)"
            return ExactClockExpression(
                expression: expr,
                rawClock: rawClock,
                usedArithmeticWorkaround: true,
                preservedMSDPrefix: "",
                contextWordUsed: nil,
                unixSeconds: clampedUnix
            )
        }

        return ExactClockExpression(
            expression: safe.clock,
            rawClock: rawClock,
            usedArithmeticWorkaround: safe.isPaused,
            preservedMSDPrefix: "",
            contextWordUsed: nil,
            unixSeconds: safe.effectiveUnix
        )
    }

    /// Evaluates either a plain Base-38 clock (`2p15ek`) or an arithmetic expression (`2p7n2s-gym`, `2p7k0a+joy`)
    /// back into exact integer UTC Unix seconds.
    public static func decodeClockExpression(_ expr: String) throws -> Int64 {
        let trimmed = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Base38Error.emptyString
        }
        if let plusIdx = trimmed.firstIndex(of: "+") {
            let lhs = String(trimmed[..<plusIdx])
            let rhs = String(trimmed[trimmed.index(after: plusIdx)...])
            let lhsVal = try decode(lhs)
            let rhsVal = try decode(rhs)
            return t0Unix + lhsVal + rhsVal
        }
        if let minusIdx = trimmed.firstIndex(of: "-") {
            let lhs = String(trimmed[..<minusIdx])
            let rhs = String(trimmed[trimmed.index(after: minusIdx)...])
            if !lhs.isEmpty, !rhs.isEmpty,
               isLowerAlnumBase38(lhs), isLowerAlnumBase38(rhs) {
                let lhsVal = try decode(lhs)
                let rhsVal = try decode(rhs)
                if lhsVal >= rhsVal {
                    return t0Unix + (lhsVal - rhsVal)
                }
            }
        }
        return try decodeJesusClock(trimmed)
    }

    public static func date(fromJesusClockExpression expr: String) throws -> Date {
        let ts = try decodeClockExpression(expr)
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }
}

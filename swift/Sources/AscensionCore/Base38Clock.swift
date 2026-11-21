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
}

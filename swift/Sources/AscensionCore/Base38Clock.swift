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

/// Base-38 (`twst23`) encoding and Jesus Clock (`Time0`) anchored at 2020-03-18T14:09:31Z.
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

    public static func contains(_ ch: Character) -> Bool {
        indexMap[ch] != nil
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
        var total: Int64 = 0
        for ch in encoded {
            guard let idx = indexMap[ch] else {
                throw Base38Error.invalidCharacter(ch)
            }
            total = total * base + idx
        }
        return total
    }

    public static func jesusClock(unixSeconds: Int64, minWidth: Int = 1) -> String {
        let elapsed = max(Int64(0), unixSeconds - t0Unix)
        let encoded = (try? encode(elapsed)) ?? "0"
        if minWidth > 1 && encoded.count < minWidth {
            return String(repeating: "0", count: minWidth - encoded.count) + encoded
        }
        return encoded
    }

    public static func jesusClock(for date: Date = Date(), minWidth: Int = 1) -> String {
        jesusClock(unixSeconds: Int64(date.timeIntervalSince1970), minWidth: minWidth)
    }

    public static func decodeJesusClock(_ clock: String) throws -> Int64 {
        let elapsed = try decode(clock)
        return t0Unix + elapsed
    }

    public static func date(fromJesusClock clock: String) throws -> Date {
        let ts = try decodeJesusClock(clock)
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    public static func clock2(unixSeconds: Int64) -> String {
        String(jesusClock(unixSeconds: unixSeconds, minWidth: 2).prefix(2))
    }

    public static func clock2(for date: Date = Date()) -> String {
        clock2(unixSeconds: Int64(date.timeIntervalSince1970))
    }
}

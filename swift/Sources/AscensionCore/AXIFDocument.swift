import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct MUNSCRule: Codable, Hashable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let pattern: String
    public let replacement: String
    public let isRegex: Bool
    public let description: String

    public init(
        name: String,
        pattern: String,
        replacement: String,
        isRegex: Bool = false,
        description: String = ""
    ) {
        self.name = name
        self.pattern = pattern
        self.replacement = replacement
        self.isRegex = isRegex
        self.description = description
    }

    public func apply(to token: String) -> String? {
        if isRegex {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return nil
            }
            let nsRange = NSRange(token.startIndex..<token.endIndex, in: token)
            let replaced = regex.stringByReplacingMatches(
                in: token,
                range: nsRange,
                withTemplate: replacement
            )
            return replaced != token ? replaced : nil
        }
        return (token == pattern && replacement != token) ? replacement : nil
    }
}

public struct AXIFEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(offset):\(token):\(acode9)" }
    public let token: String
    public let normalizedForm: String
    public let offset: Int
    public let length: Int
    public let normalizedOffset: Int
    public let normalizedLength: Int
    public let acode9: String
    public let munscRule: String

    public var rawEnd: Int { offset + length }
    public var normalizedEnd: Int { normalizedOffset + normalizedLength }

    public init(
        token: String,
        normalizedForm: String,
        offset: Int,
        acode9: String,
        munscRule: String,
        length: Int? = nil,
        normalizedOffset: Int? = nil,
        normalizedLength: Int? = nil
    ) {
        self.token = token
        self.normalizedForm = normalizedForm
        self.offset = offset
        self.length = length ?? token.count
        self.normalizedOffset = normalizedOffset ?? offset
        self.normalizedLength = normalizedLength ?? normalizedForm.count
        self.acode9 = acode9
        self.munscRule = munscRule
    }
}

public struct TextSegment: Hashable, Sendable {
    public let rawStart: Int
    public let rawEnd: Int
    public let normStart: Int
    public let normEnd: Int
    public let axifEntry: AXIFEntry?

    public init(
        rawStart: Int,
        rawEnd: Int,
        normStart: Int,
        normEnd: Int,
        axifEntry: AXIFEntry? = nil
    ) {
        self.rawStart = rawStart
        self.rawEnd = rawEnd
        self.normStart = normStart
        self.normEnd = normEnd
        self.axifEntry = axifEntry
    }
}

public struct AXIFMetadata: Codable, Hashable, Sendable {
    public static let currentVersion = "AXIF/1.0"

    public let version: String
    public let acode9: String
    public let jesusClock: String
    public let rawSHA256: String
    public let normalizedSHA256: String
    public let entries: [AXIFEntry]
    public let rules: [MUNSCRule]

    public var munscCount: Int { entries.count }

    public init(
        version: String = AXIFMetadata.currentVersion,
        acode9: String,
        jesusClock: String,
        rawSHA256: String,
        normalizedSHA256: String,
        entries: [AXIFEntry],
        rules: [MUNSCRule] = []
    ) {
        self.version = version
        self.acode9 = acode9
        self.jesusClock = jesusClock
        self.rawSHA256 = rawSHA256
        self.normalizedSHA256 = normalizedSHA256
        self.entries = entries
        self.rules = rules
    }

    public func toJSON(prettyPrinted: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    public static func fromJSON(_ json: String) throws -> AXIFMetadata {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(AXIFMetadata.self, from: data)
    }
}

public enum MUNSCNormalizer: Sendable {
    public static let defaultProtectedTokens: Set<String> = [
        "Acode9", "Acodes1a", "Base38", "First1a", "good1a", "second1a",
        "Hydrogen4", "AXIF", "MUNSC", "MUNSCs", "SwiftUI", "macOS", "iOS",
        "Xcode", "Time0", "T0UX"
    ]

    public static let defaultCanonicalForms: Set<String> = ["Norma"]

    public static let defaultRules: [MUNSCRule] = [
        MUNSCRule(
            name: "munsc_trailing_cap_norma",
            pattern: "NormA",
            replacement: "Norma",
            description: "Normalize trailing uppercase MUNSC 'NormA' -> 'Norma'"
        ),
        MUNSCRule(
            name: "munsc_leet_4_to_a",
            pattern: "Norm4",
            replacement: "Norma",
            description: "Normalize leet-digit MUNSC 'Norm4' -> 'Norma'"
        ),
        MUNSCRule(
            name: "munsc_trailing_disambiguator",
            pattern: "Norma4",
            replacement: "Norma",
            description: "Normalize trailing disambiguator MUNSC 'Norma4' -> 'Norma'"
        )
    ]

    private static let leetMap: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t"
    ]

    private static let trailingCapRegex = try! NSRegularExpression(pattern: "^[A-Z][a-z]{2,}[A-Z]$")
    private static let internalLeetRegex = try! NSRegularExpression(pattern: "^[A-Za-z]+[013457][A-Za-z]+$")
    private static let trailingLeetConsonantRegex = try! NSRegularExpression(
        pattern: "^[A-Z][a-z]+[bcdfghjklmnpqrstvwxyz][013457]$"
    )
    private static let trailingDigitRegex = try! NSRegularExpression(pattern: "^[A-Za-z]{2,}[0-9]$")

    private static func matches(_ regex: NSRegularExpression, _ value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    public static func normalizeToken(
        _ token: String,
        rules: [MUNSCRule] = [],
        canonicalForms: Set<String> = defaultCanonicalForms,
        protectedTokens: Set<String> = defaultProtectedTokens,
        autoDetect: Bool = true
    ) -> (normalized: String, ruleName: String)? {
        guard !token.isEmpty else { return nil }
        if protectedTokens.contains(token) { return nil }
        if token.count == 9 && Acode9.validate(token, filterProfanity: false).valid {
            return nil
        }

        for rule in rules {
            if let replaced = rule.apply(to: token) {
                return (replaced, rule.name)
            }
        }

        for rule in defaultRules {
            if let replaced = rule.apply(to: token) {
                return (replaced, rule.name)
            }
        }

        guard autoDetect else { return nil }

        if matches(trailingCapRegex, token), let last = token.last {
            return (String(token.dropLast()) + String(last).lowercased(), "munsc_trailing_cap")
        }

        if matches(internalLeetRegex, token) {
            let normalized = String(token.map { leetMap[$0] ?? $0 })
            if normalized != token {
                return (normalized, "munsc_internal_leet")
            }
        }

        if matches(trailingLeetConsonantRegex, token), let last = token.last {
            let mapped = leetMap[last] ?? last
            return (String(token.dropLast()) + String(mapped), "munsc_trailing_leet")
        }

        if matches(trailingDigitRegex, token) {
            let stem = String(token.dropLast())
            if canonicalForms.contains(stem) {
                return (stem, "munsc_trailing_disambiguator")
            }
        }

        return nil
    }
}

public struct AXIFDocument: Sendable, Identifiable {
    public var id: String { ownerAcode9 }
    public let title: String
    public let ownerAcode9: String
    public let rawText: String
    public let normalizedText: String
    public let axif: AXIFMetadata
    public let segments: [TextSegment]
    public let rules: [MUNSCRule]
    public let canonicalForms: Set<String>
    public let protectedTokens: Set<String>
    public let autoDetect: Bool

    private static let tokenScanRegex = try! NSRegularExpression(
        pattern: "A[a-z][0-9a-z|\\^]{2}[\\^\\-][0-9a-z|\\^]{4}|[A-Za-z0-9]+"
    )

    public init(
        title: String = "Untitled",
        rawText: String,
        ownerAcode9: String,
        rules: [MUNSCRule] = [],
        canonicalForms: Set<String> = MUNSCNormalizer.defaultCanonicalForms,
        protectedTokens: Set<String> = MUNSCNormalizer.defaultProtectedTokens,
        autoDetect: Bool = true,
        timestampUnix: Int64 = Int64(Date().timeIntervalSince1970)
    ) throws {
        let validation = Acode9.validate(ownerAcode9, allowDash: true, filterProfanity: false)
        guard validation.valid else {
            throw Acode9Error.strictValidationFailed(validation.reasons)
        }

        var normParts: [String] = []
        var entries: [AXIFEntry] = []
        var builtSegments: [TextSegment] = []

        var rawCursorIdx = rawText.startIndex
        var rawCharOffset = 0
        var normCharOffset = 0

        let fullRange = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
        let matches = Self.tokenScanRegex.matches(in: rawText, range: fullRange)

        for match in matches {
            guard let range = Range(match.range, in: rawText) else { continue }
            if range.lowerBound > rawCursorIdx {
                let plain = String(rawText[rawCursorIdx..<range.lowerBound])
                let plainLen = plain.count
                normParts.append(plain)
                builtSegments.append(
                    TextSegment(
                        rawStart: rawCharOffset,
                        rawEnd: rawCharOffset + plainLen,
                        normStart: normCharOffset,
                        normEnd: normCharOffset + plainLen,
                        axifEntry: nil
                    )
                )
                rawCharOffset += plainLen
                normCharOffset += plainLen
            }

            let token = String(rawText[range])
            let tokenLen = token.count

            if let normalized = MUNSCNormalizer.normalizeToken(
                token,
                rules: rules,
                canonicalForms: canonicalForms,
                protectedTokens: protectedTokens,
                autoDetect: autoDetect
            ) {
                let normLen = normalized.normalized.count
                let entry = AXIFEntry(
                    token: token,
                    normalizedForm: normalized.normalized,
                    offset: rawCharOffset,
                    acode9: ownerAcode9,
                    munscRule: normalized.ruleName,
                    length: tokenLen,
                    normalizedOffset: normCharOffset,
                    normalizedLength: normLen
                )
                entries.append(entry)
                normParts.append(normalized.normalized)
                builtSegments.append(
                    TextSegment(
                        rawStart: rawCharOffset,
                        rawEnd: rawCharOffset + tokenLen,
                        normStart: normCharOffset,
                        normEnd: normCharOffset + normLen,
                        axifEntry: entry
                    )
                )
                rawCharOffset += tokenLen
                normCharOffset += normLen
            } else {
                normParts.append(token)
                builtSegments.append(
                    TextSegment(
                        rawStart: rawCharOffset,
                        rawEnd: rawCharOffset + tokenLen,
                        normStart: normCharOffset,
                        normEnd: normCharOffset + tokenLen,
                        axifEntry: nil
                    )
                )
                rawCharOffset += tokenLen
                normCharOffset += tokenLen
            }

            rawCursorIdx = range.upperBound
        }

        if rawCursorIdx < rawText.endIndex {
            let tail = String(rawText[rawCursorIdx..<rawText.endIndex])
            let tailLen = tail.count
            normParts.append(tail)
            builtSegments.append(
                TextSegment(
                    rawStart: rawCharOffset,
                    rawEnd: rawCharOffset + tailLen,
                    normStart: normCharOffset,
                    normEnd: normCharOffset + tailLen,
                    axifEntry: nil
                )
            )
        }

        let compiledNormalized = normParts.joined()
        self.title = title
        self.ownerAcode9 = ownerAcode9
        self.rawText = rawText
        self.normalizedText = compiledNormalized
        self.segments = builtSegments
        self.rules = rules
        self.canonicalForms = canonicalForms
        self.protectedTokens = protectedTokens
        self.autoDetect = autoDetect
        self.axif = AXIFMetadata(
            acode9: ownerAcode9,
            jesusClock: Base38Clock.jesusClock(unixSeconds: timestampUnix, minWidth: 2),
            rawSHA256: Self.sha256Hex(rawText),
            normalizedSHA256: Self.sha256Hex(compiledNormalized),
            entries: entries,
            rules: rules
        )
    }

    public func render(normalized: Bool) -> String {
        normalized ? normalizedText : rawText
    }

    public func mapRawSpanToNormalized(start: Int, end: Int) -> (start: Int, end: Int, entry: AXIFEntry?) {
        var normStarts: [Int] = []
        var normEnds: [Int] = []
        var matchedEntry: AXIFEntry?

        for seg in segments {
            if seg.rawEnd <= start || seg.rawStart >= end { continue }
            if let entry = seg.axifEntry {
                matchedEntry = entry
                normStarts.append(seg.normStart)
                normEnds.append(seg.normEnd)
            } else {
                let deltaStart = max(0, start - seg.rawStart)
                let deltaEnd = min(seg.rawEnd, end) - seg.rawStart
                normStarts.append(seg.normStart + deltaStart)
                normEnds.append(seg.normStart + deltaEnd)
            }
        }

        guard let minS = normStarts.min(), let maxE = normEnds.max() else {
            return (start, end, nil)
        }
        return (minS, maxE, matchedEntry)
    }

    public func mapNormalizedSpanToRaw(start: Int, end: Int) -> (start: Int, end: Int, entry: AXIFEntry?) {
        var rawStarts: [Int] = []
        var rawEnds: [Int] = []
        var matchedEntry: AXIFEntry?

        for seg in segments {
            if seg.normEnd <= start || seg.normStart >= end { continue }
            if let entry = seg.axifEntry {
                matchedEntry = entry
                rawStarts.append(seg.rawStart)
                rawEnds.append(seg.rawEnd)
            } else {
                let deltaStart = max(0, start - seg.normStart)
                let deltaEnd = min(seg.normEnd, end) - seg.normStart
                rawStarts.append(seg.rawStart + deltaStart)
                rawEnds.append(seg.rawStart + deltaEnd)
            }
        }

        guard let minS = rawStarts.min(), let maxE = rawEnds.max() else {
            return (start, end, nil)
        }
        return (minS, maxE, matchedEntry)
    }

    private static func sha256Hex(_ text: String) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        // Deterministic FNV-1a 64-bit fallback only when CryptoKit is unavailable
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
        #endif
    }
}

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

    enum CodingKeys: String, CodingKey {
        case name, pattern, replacement, isRegex, is_regex, description
    }

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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        pattern = try c.decode(String.self, forKey: .pattern)
        replacement = try c.decode(String.self, forKey: .replacement)
        if let camel = try c.decodeIfPresent(Bool.self, forKey: .isRegex) {
            isRegex = camel
        } else {
            isRegex = try c.decodeIfPresent(Bool.self, forKey: .is_regex) ?? false
        }
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(pattern, forKey: .pattern)
        try c.encode(replacement, forKey: .replacement)
        try c.encode(isRegex, forKey: .isRegex)
        try c.encode(description, forKey: .description)
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

    enum CodingKeys: String, CodingKey {
        case token, normalizedForm, normalized_form, offset, length
        case normalizedOffset, normalized_offset, normalizedLength, normalized_length
        case acode9, munscRule, munsc_rule
    }

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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tok = try c.decode(String.self, forKey: .token)
        let norm: String
        if let camel = try c.decodeIfPresent(String.self, forKey: .normalizedForm) {
            norm = camel
        } else {
            norm = try c.decode(String.self, forKey: .normalized_form)
        }
        let off = try c.decode(Int.self, forKey: .offset)
        let len = try c.decodeIfPresent(Int.self, forKey: .length) ?? tok.count
        let normOff = try c.decodeIfPresent(Int.self, forKey: .normalizedOffset)
            ?? c.decodeIfPresent(Int.self, forKey: .normalized_offset)
            ?? off
        let normLen = try c.decodeIfPresent(Int.self, forKey: .normalizedLength)
            ?? c.decodeIfPresent(Int.self, forKey: .normalized_length)
            ?? norm.count
        let code = try c.decode(String.self, forKey: .acode9)
        let rule: String
        if let camelRule = try c.decodeIfPresent(String.self, forKey: .munscRule) {
            rule = camelRule
        } else {
            rule = try c.decode(String.self, forKey: .munsc_rule)
        }
        self.init(
            token: tok,
            normalizedForm: norm,
            offset: off,
            acode9: code,
            munscRule: rule,
            length: len,
            normalizedOffset: normOff,
            normalizedLength: normLen
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(token, forKey: .token)
        try c.encode(normalizedForm, forKey: .normalizedForm)
        try c.encode(offset, forKey: .offset)
        try c.encode(length, forKey: .length)
        try c.encode(normalizedOffset, forKey: .normalizedOffset)
        try c.encode(normalizedLength, forKey: .normalizedLength)
        try c.encode(acode9, forKey: .acode9)
        try c.encode(munscRule, forKey: .munscRule)
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

    enum CodingKeys: String, CodingKey {
        case version, acode9
        case jesusClock, jesus_clock
        case rawSHA256, raw_sha256
        case normalizedSHA256, normalized_sha256
        case entries, rules
    }

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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? AXIFMetadata.currentVersion
        acode9 = try c.decode(String.self, forKey: .acode9)
        if let camelClock = try c.decodeIfPresent(String.self, forKey: .jesusClock) {
            jesusClock = camelClock
        } else {
            jesusClock = try c.decode(String.self, forKey: .jesus_clock)
        }
        if let camelRaw = try c.decodeIfPresent(String.self, forKey: .rawSHA256) {
            rawSHA256 = camelRaw
        } else {
            rawSHA256 = try c.decode(String.self, forKey: .raw_sha256)
        }
        if let camelNorm = try c.decodeIfPresent(String.self, forKey: .normalizedSHA256) {
            normalizedSHA256 = camelNorm
        } else {
            normalizedSHA256 = try c.decode(String.self, forKey: .normalized_sha256)
        }
        entries = try c.decodeIfPresent([AXIFEntry].self, forKey: .entries) ?? []
        rules = try c.decodeIfPresent([MUNSCRule].self, forKey: .rules) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(acode9, forKey: .acode9)
        try c.encode(jesusClock, forKey: .jesusClock)
        try c.encode(rawSHA256, forKey: .rawSHA256)
        try c.encode(normalizedSHA256, forKey: .normalizedSHA256)
        try c.encode(entries, forKey: .entries)
        try c.encode(rules, forKey: .rules)
    }

    public func toJSON(prettyPrinted: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
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
        if token.hasPrefix("▸[") { return nil }
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
        pattern: #"▸\[(?:Image|Folded)[^\n\]]*\]|A[a-z][0-9a-z|\^]{2}[\^\-][0-9a-z|\^]{4}|[A-Za-z0-9]+"#
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

    public static func sha256Hex(_ text: String) -> String {
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

    public func exportCleanWithAXIFFooter(useBase64: Bool = true) throws -> String {
        let compactJSON = try axif.toJSON(prettyPrinted: false)
        let payload = useBase64 ? Data(compactJSON.utf8).base64EncodedString() : compactJSON
        return "\(normalizedText)\n\n[AXIF: \(ownerAcode9) | \(payload)]"
    }

    public func exportSlogBogBBCode() throws -> String {
        let json = try axif.toJSON(prettyPrinted: true)
        return """
        [quote="Acode9: \(ownerAcode9) | Clock: \(axif.jesusClock)"]
        \(normalizedText)
        [/quote]
        [b]Acode9:[/b] [code]\(ownerAcode9)[/code] | [b]Jesus Clock:[/b] [code]\(axif.jesusClock)[/code] | [b]MUNSCs:[/b] \(axif.munscCount)
        [spoiler=AXIF][code]
        \(json)
        [/code][/spoiler]
        """
    }

    public func exportMarkdown(
        title: String? = nil,
        includeFrontmatter: Bool = true,
        includeAXIFFooter: Bool = true,
        useRawText: Bool = false
    ) throws -> String {
        let body = useRawText ? rawText : normalizedText
        var parts: [String] = []

        if includeFrontmatter {
            let noteTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let safeTitle = noteTitle.isEmpty ? "Ascension Note" : noteTitle
            let escapedTitle = safeTitle.replacingOccurrences(of: "\"", with: "\\\"")
            parts.append("""
            ---
            title: "\(escapedTitle)"
            acode9: "\(ownerAcode9)"
            jesus_clock: "\(axif.jesusClock)"
            munsc_count: \(axif.munscCount)
            axif_version: "\(axif.version)"
            ---
            """)
        }

        parts.append(body)

        if includeAXIFFooter {
            let compactJSON = try axif.toJSON(prettyPrinted: false)
            let payload = Data(compactJSON.utf8).base64EncodedString()
            parts.append("<!-- AXIF: \(ownerAcode9) | Clock: \(axif.jesusClock) | Payload: \(payload) -->")
        }

        return parts.joined(separator: "\n\n")
    }

    public static func reconstructRawText(fromNormalized normalizedText: String, entries: [AXIFEntry]) -> String {
        guard !entries.isEmpty else { return normalizedText }
        var result = normalizedText
        let sorted = entries.sorted { $0.normalizedOffset > $1.normalizedOffset }
        for entry in sorted {
            let count = result.count
            guard entry.normalizedOffset >= 0,
                  entry.normalizedLength >= 0,
                  entry.normalizedOffset + entry.normalizedLength <= count else {
                continue
            }
            let sIdx = result.index(result.startIndex, offsetBy: entry.normalizedOffset)
            let eIdx = result.index(sIdx, offsetBy: entry.normalizedLength)
            if String(result[sIdx..<eIdx]) == entry.normalizedForm {
                result.replaceSubrange(sIdx..<eIdx, with: entry.token)
            }
        }
        return result
    }

    public static func parseSharedBundle(_ input: String) throws -> AXIFDecodedBundle {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AXIFShareError.emptyInput
        }

        // 1. Try [AXIF: <Acode9> | <base64-or-json>] footer format
        if let footerParsed = try parseAXIFFooterFormat(trimmed) {
            return footerParsed
        }

        // 2. Try SlogBog phpBBog [spoiler=AXIF] format
        if let bbParsed = try parseSlogBogBBCodeFormat(trimmed) {
            return bbParsed
        }

        // 3. Try JSON envelope or raw AXIFMetadata JSON
        if trimmed.first == "{" {
            if let envelopeData = trimmed.data(using: .utf8),
               let envelope = try? JSONDecoder().decode(AXIFShareEnvelope.self, from: envelopeData) {
                let norm = envelope.normalizedText ?? envelope.normalized_text
                let rawFromEnvelope = envelope.rawText ?? envelope.raw_text
                let reconstructed = rawFromEnvelope ?? norm.map { reconstructRawText(fromNormalized: $0, entries: envelope.axif.entries) }
                return buildDecodedBundle(
                    metadata: envelope.axif,
                    title: envelope.title,
                    normalizedText: norm,
                    reconstructedRawText: reconstructed,
                    sourceFormat: "AXIF Bundle JSON"
                )
            }
            if let metadata = try? AXIFMetadata.fromJSON(trimmed) {
                let validation = Acode9.validate(metadata.acode9, allowDash: true, filterProfanity: false)
                guard validation.valid else {
                    throw AXIFShareError.invalidAcode9(validation.reasons.joined(separator: ", "))
                }
                return buildDecodedBundle(
                    metadata: metadata,
                    title: nil,
                    normalizedText: nil,
                    reconstructedRawText: nil,
                    sourceFormat: "AXIF JSON"
                )
            }
        }

        throw AXIFShareError.unrecognizedFormat
    }

    private static func buildDecodedBundle(
        metadata: AXIFMetadata,
        title: String?,
        normalizedText: String?,
        reconstructedRawText: String?,
        sourceFormat: String
    ) -> AXIFDecodedBundle {
        let normMatches = normalizedText.map { sha256Hex($0) == metadata.normalizedSHA256 }
        let rawMatches = reconstructedRawText.map { sha256Hex($0) == metadata.rawSHA256 }
        return AXIFDecodedBundle(
            metadata: metadata,
            title: title,
            normalizedText: normalizedText,
            reconstructedRawText: reconstructedRawText,
            sourceFormat: sourceFormat,
            rawSHA256Matches: rawMatches,
            normalizedSHA256Matches: normMatches
        )
    }

    private static func parseAXIFFooterFormat(_ text: String) throws -> AXIFDecodedBundle? {
        guard let markerRange = text.range(of: "[AXIF:", options: .backwards) else {
            return nil
        }
        let bodyBeforeFooter = String(text[..<markerRange.lowerBound])
            .replacingOccurrences(of: #"\n+$"#, with: "", options: .regularExpression)
        let afterMarker = text[markerRange.upperBound...]
        guard let pipeIdx = afterMarker.firstIndex(of: "|") else {
            throw AXIFShareError.malformedFooter
        }
        let payloadArea = String(afterMarker[afterMarker.index(after: pipeIdx)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let jsonString: String
        if payloadArea.first == "{" {
            guard let extracted = extractBalancedJSONObject(from: payloadArea) else {
                throw AXIFShareError.malformedFooter
            }
            jsonString = extracted
        } else {
            let endBracket = payloadArea.firstIndex(of: "]") ?? payloadArea.endIndex
            let b64 = String(payloadArea[..<endBracket])
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
            guard let decoded = Data(base64Encoded: b64) else {
                throw AXIFShareError.invalidBase64Payload
            }
            jsonString = String(decoding: decoded, as: UTF8.self)
        }

        let metadata = try AXIFMetadata.fromJSON(jsonString)
        let validation = Acode9.validate(metadata.acode9, allowDash: true, filterProfanity: false)
        guard validation.valid else {
            throw AXIFShareError.invalidAcode9(validation.reasons.joined(separator: ", "))
        }
        let reconstructed = reconstructRawText(fromNormalized: bodyBeforeFooter, entries: metadata.entries)
        return buildDecodedBundle(
            metadata: metadata,
            title: nil,
            normalizedText: bodyBeforeFooter,
            reconstructedRawText: reconstructed,
            sourceFormat: "Clean + AXIF Footer"
        )
    }

    private static func parseSlogBogBBCodeFormat(_ text: String) throws -> AXIFDecodedBundle? {
        guard let spoilerRegex = try? NSRegularExpression(
            pattern: #"\[spoiler=AXIF\](.*?)\[/spoiler\]"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let spoilerMatch = spoilerRegex.firstMatch(in: text, range: fullRange),
              let innerRange = Range(spoilerMatch.range(at: 1), in: text) else {
            return nil
        }

        var rawPayload = String(text[innerRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let codeRegex = try? NSRegularExpression(
            pattern: #"\[code\](.*?)\[/code\]"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let innerNSRange = NSRange(rawPayload.startIndex..<rawPayload.endIndex, in: rawPayload)
            if let codeMatch = codeRegex.firstMatch(in: rawPayload, range: innerNSRange),
               let codeRange = Range(codeMatch.range(at: 1), in: rawPayload) {
                rawPayload = String(rawPayload[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let metadata: AXIFMetadata
        if rawPayload.first == "{" {
            metadata = try AXIFMetadata.fromJSON(rawPayload)
        } else if let data = Data(base64Encoded: rawPayload) {
            metadata = try AXIFMetadata.fromJSON(String(decoding: data, as: UTF8.self))
        } else {
            throw AXIFShareError.malformedBBCode
        }

        let validation = Acode9.validate(metadata.acode9, allowDash: true, filterProfanity: false)
        guard validation.valid else {
            throw AXIFShareError.invalidAcode9(validation.reasons.joined(separator: ", "))
        }

        var quotedNorm: String?
        if let quoteRegex = try? NSRegularExpression(
            pattern: #"\[quote(?:=[^\]]*)?\](.*?)\[/quote\]"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ), let quoteMatch = quoteRegex.firstMatch(in: text, range: fullRange),
           let qRange = Range(quoteMatch.range(at: 1), in: text) {
            var q = String(text[qRange])
            if q.hasPrefix("\r\n") { q.removeFirst(2) }
            else if q.hasPrefix("\n") { q.removeFirst() }
            if q.hasSuffix("\r\n") { q.removeLast(2) }
            else if q.hasSuffix("\n") { q.removeLast() }
            quotedNorm = q
        }

        let reconstructed = quotedNorm.map { reconstructRawText(fromNormalized: $0, entries: metadata.entries) }
        return buildDecodedBundle(
            metadata: metadata,
            title: nil,
            normalizedText: quotedNorm,
            reconstructedRawText: reconstructed,
            sourceFormat: "SlogBog phpBBog"
        )
    }

    private static func extractBalancedJSONObject(from text: String) -> String? {
        var depth = 0
        var inString = false
        var escaped = false
        var startIdx: String.Index?

        for idx in text.indices {
            let ch = text[idx]
            if escaped {
                escaped = false
                continue
            }
            if inString {
                if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                continue
            }
            if ch == "\"" {
                inString = true
            } else if ch == "{" {
                if depth == 0 { startIdx = idx }
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0, let start = startIdx {
                    return String(text[start...idx])
                }
            }
        }
        return nil
    }
}

public enum AXIFShareError: Error, LocalizedError, Sendable, Equatable {
    case emptyInput
    case unrecognizedFormat
    case malformedFooter
    case invalidBase64Payload
    case malformedBBCode
    case invalidAcode9(String)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Paste an AXIF JSON, Clean + AXIF footer, or SlogBog BBCode snippet."
        case .unrecognizedFormat:
            return "Could not recognize AXIF JSON, [AXIF: ...] footer, or [spoiler=AXIF] BBCode."
        case .malformedFooter:
            return "Malformed [AXIF: Acode9 | payload] footer."
        case .invalidBase64Payload:
            return "Could not decode base64 AXIF payload."
        case .malformedBBCode:
            return "Malformed [spoiler=AXIF] BBCode payload."
        case .invalidAcode9(let reason):
            return "Invalid Acode9 in AXIF bundle: \(reason)"
        }
    }
}

private struct AXIFShareEnvelope: Decodable {
    let title: String?
    let normalizedText: String?
    let normalized_text: String?
    let rawText: String?
    let raw_text: String?
    let axif: AXIFMetadata
}

public struct AXIFDecodedBundle: Sendable, Equatable {
    public let metadata: AXIFMetadata
    public let title: String?
    public let normalizedText: String?
    public let reconstructedRawText: String?
    public let sourceFormat: String
    public let rawSHA256Matches: Bool?
    public let normalizedSHA256Matches: Bool?

    public init(
        metadata: AXIFMetadata,
        title: String? = nil,
        normalizedText: String? = nil,
        reconstructedRawText: String? = nil,
        sourceFormat: String,
        rawSHA256Matches: Bool? = nil,
        normalizedSHA256Matches: Bool? = nil
    ) {
        self.metadata = metadata
        self.title = title
        self.normalizedText = normalizedText
        self.reconstructedRawText = reconstructedRawText
        self.sourceFormat = sourceFormat
        self.rawSHA256Matches = rawSHA256Matches
        self.normalizedSHA256Matches = normalizedSHA256Matches
    }
}

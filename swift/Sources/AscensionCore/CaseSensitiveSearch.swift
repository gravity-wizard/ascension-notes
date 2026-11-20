import Foundation

public enum SearchLayer: String, Codable, Sendable, CaseIterable {
    case dual
    case raw
    case normalized
}

public struct SearchOptions: Hashable, Sendable {
    public var caseSensitive: Bool
    public var wholeWord: Bool
    public var regex: Bool
    public var layer: SearchLayer

    public init(
        caseSensitive: Bool = true,
        wholeWord: Bool = false,
        regex: Bool = false,
        layer: SearchLayer = .dual
    ) {
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
        self.regex = regex
        self.layer = layer
    }
}

public struct SearchMatch: Hashable, Sendable, Identifiable {
    public var id: String {
        "\(acode9):\(layer.rawValue):\(rawOffset):\(rawEnd):\(normalizedOffset):\(normalizedEnd)"
    }
    public let query: String
    public let matchedText: String
    public let layer: SearchLayer
    public let rawOffset: Int
    public let rawEnd: Int
    public let normalizedOffset: Int
    public let normalizedEnd: Int
    public let lineNumber: Int
    public let column: Int
    public let snippet: String
    public let rawSnippet: String
    public let axifEntry: AXIFEntry?
    public let acode9: String
}

private struct SpanKey: Hashable {
    let start: Int
    let end: Int
}

public enum CaseSensitiveSearch: Sendable {
    public static func search(
        document: AXIFDocument,
        query: String,
        options: SearchOptions = SearchOptions()
    ) throws -> [SearchMatch] {
        guard !query.isEmpty else { return [] }

        let regex = try compileRegex(
            query: query,
            caseSensitive: options.caseSensitive,
            wholeWord: options.wholeWord,
            isRegex: options.regex
        )

        var matches: [SearchMatch] = []
        var seenNormSpans: Set<SpanKey> = []

        if options.layer == .dual || options.layer == .raw {
            let rawText = document.rawText
            let fullRange = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
            for hit in regex.matches(in: rawText, range: fullRange) {
                guard let range = Range(hit.range, in: rawText) else { continue }
                let rawStart = rawText.distance(from: rawText.startIndex, to: range.lowerBound)
                let rawEnd = rawText.distance(from: rawText.startIndex, to: range.upperBound)
                let mapped = document.mapRawSpanToNormalized(start: rawStart, end: rawEnd)
                seenNormSpans.insert(SpanKey(start: mapped.start, end: mapped.end))

                let (line, col) = lineAndColumn(in: document.normalizedText, charOffset: mapped.start)
                matches.append(
                    SearchMatch(
                        query: query,
                        matchedText: String(rawText[range]),
                        layer: .raw,
                        rawOffset: rawStart,
                        rawEnd: rawEnd,
                        normalizedOffset: mapped.start,
                        normalizedEnd: mapped.end,
                        lineNumber: line,
                        column: col,
                        snippet: snippet(in: document.normalizedText, start: mapped.start, end: mapped.end),
                        rawSnippet: snippet(in: rawText, start: rawStart, end: rawEnd),
                        axifEntry: mapped.entry,
                        acode9: document.ownerAcode9
                    )
                )
            }
        }

        if options.layer == .dual || options.layer == .normalized {
            let normText = document.normalizedText
            let fullRange = NSRange(normText.startIndex..<normText.endIndex, in: normText)
            for hit in regex.matches(in: normText, range: fullRange) {
                guard let range = Range(hit.range, in: normText) else { continue }
                let normStart = normText.distance(from: normText.startIndex, to: range.lowerBound)
                let normEnd = normText.distance(from: normText.startIndex, to: range.upperBound)

                if options.layer == .dual && seenNormSpans.contains(SpanKey(start: normStart, end: normEnd)) {
                    continue
                }

                let mapped = document.mapNormalizedSpanToRaw(start: normStart, end: normEnd)
                let (line, col) = lineAndColumn(in: normText, charOffset: normStart)
                matches.append(
                    SearchMatch(
                        query: query,
                        matchedText: String(normText[range]),
                        layer: .normalized,
                        rawOffset: mapped.start,
                        rawEnd: mapped.end,
                        normalizedOffset: normStart,
                        normalizedEnd: normEnd,
                        lineNumber: line,
                        column: col,
                        snippet: snippet(in: normText, start: normStart, end: normEnd),
                        rawSnippet: snippet(in: document.rawText, start: mapped.start, end: mapped.end),
                        axifEntry: mapped.entry,
                        acode9: document.ownerAcode9
                    )
                )
            }
        }

        matches.sort { lhs, rhs in
            if lhs.normalizedOffset != rhs.normalizedOffset {
                return lhs.normalizedOffset < rhs.normalizedOffset
            }
            return lhs.rawOffset < rhs.rawOffset
        }
        return matches
    }

    private static func compileRegex(
        query: String,
        caseSensitive: Bool,
        wholeWord: Bool,
        isRegex: Bool
    ) throws -> NSRegularExpression {
        var pattern = isRegex ? query : NSRegularExpression.escapedPattern(for: query)
        if wholeWord {
            pattern = "(?<!\\w)(?:\(pattern))(?!\\w)"
        }
        let opts: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        return try NSRegularExpression(pattern: pattern, options: opts)
    }

    private static func lineAndColumn(in text: String, charOffset: Int) -> (line: Int, column: Int) {
        let clamped = max(0, min(charOffset, text.count))
        let idx = text.index(text.startIndex, offsetBy: clamped)
        let prefix = text[..<idx]
        var line = 1
        var col = 1
        for ch in prefix {
            if ch == "\n" {
                line += 1
                col = 1
            } else {
                col += 1
            }
        }
        return (line, col)
    }

    private static func snippet(in text: String, start: Int, end: Int, radius: Int = 24) -> String {
        let count = text.count
        let left = max(0, start - radius)
        let right = min(count, end + radius)
        let sIdx = text.index(text.startIndex, offsetBy: left)
        let eIdx = text.index(text.startIndex, offsetBy: right)
        let prefix = left > 0 ? "..." : ""
        let suffix = right < count ? "..." : ""
        return "\(prefix)\(text[sIdx..<eIdx])\(suffix)"
    }
}

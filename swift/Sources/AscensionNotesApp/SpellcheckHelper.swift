import Foundation
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import AscensionCore

public struct SpellcheckIssue: Identifiable, Hashable, Sendable {
    public var id: String { "\(charOffset):\(charEnd):\(word)" }
    public let word: String
    public let charOffset: Int
    public let charEnd: Int
    public let guesses: [String]
}

public struct EditWordInspection: Equatable, Sendable {
    public let word: String
    public let rangeLocation: Int
    public let rangeLength: Int
    public let isMisspelled: Bool
    public let isGrammarIs: Bool
    public let guesses: [String]
}

@MainActor
enum SpellcheckHelper {
    private static let markerRegex = try? NSRegularExpression(
        pattern: #"▸\[(?:Image|Folded)[^\n\]]*\]"#
    )

    private static func markerRanges(in text: String) -> [NSRange] {
        guard let regex = markerRegex, !text.isEmpty else { return [] }
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: full).map(\.range)
    }

    private static func intersectsMarker(_ range: NSRange, markers: [NSRange]) -> Bool {
        for marker in markers {
            if NSIntersectionRange(range, marker).length > 0 {
                return true
            }
        }
        return false
    }

    /// Checks natural-language spelling in Clean View while skipping valid Acode9 identifiers
    /// and inline fold/image markers.
    static func findIssues(in text: String) -> [SpellcheckIssue] {
        guard !text.isEmpty else { return [] }
        var issues: [SpellcheckIssue] = []
        let markers = markerRanges(in: text)

        #if os(macOS)
        let checker = NSSpellChecker.shared
        let nsText = text as NSString
        var cursor = 0
        while cursor < nsText.length {
            let range = checker.checkSpelling(
                of: text,
                startingAt: cursor,
                language: nil,
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            )
            if range.location == NSNotFound || range.length == 0 {
                break
            }
            let word = nsText.substring(with: range)
            if !intersectsMarker(range, markers: markers),
               !shouldSkipToken(word),
               let swiftRange = Range(range, in: text) {
                let charOffset = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
                let charEnd = text.distance(from: text.startIndex, to: swiftRange.upperBound)
                let guesses = checker.guesses(
                    forWordRange: range,
                    in: text,
                    language: nil,
                    inSpellDocumentWithTag: 0
                ) ?? []
                issues.append(
                    SpellcheckIssue(
                        word: word,
                        charOffset: charOffset,
                        charEnd: charEnd,
                        guesses: Array(guesses.prefix(4))
                    )
                )
            }
            let next = range.location + range.length
            if next <= cursor { break }
            cursor = next
        }
        #elseif canImport(UIKit)
        let checker = UITextChecker()
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let lang = Locale.current.identifier
        var cursor = 0
        while cursor < nsText.length {
            let range = checker.rangeOfMisspelledWord(
                in: text,
                range: fullRange,
                startingAt: cursor,
                wrap: false,
                language: lang
            )
            if range.location == NSNotFound || range.length == 0 {
                break
            }
            let word = nsText.substring(with: range)
            if !intersectsMarker(range, markers: markers),
               !shouldSkipToken(word),
               let swiftRange = Range(range, in: text) {
                let charOffset = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
                let charEnd = text.distance(from: text.startIndex, to: swiftRange.upperBound)
                let guesses = checker.guesses(forWordRange: range, in: text, language: lang) ?? []
                issues.append(
                    SpellcheckIssue(
                        word: word,
                        charOffset: charOffset,
                        charEnd: charEnd,
                        guesses: Array(guesses.prefix(4))
                    )
                )
            }
            let next = range.location + range.length
            if next <= cursor { break }
            cursor = next
        }
        #endif

        return issues
    }

    static func learnWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        #if os(macOS)
        NSSpellChecker.shared.learnWord(trimmed)
        #elseif canImport(UIKit)
        UITextChecker.learnWord(trimmed)
        #endif
    }

    #if os(macOS)
    /// Inspects the token at or adjacent to `charIndex` in Edit View for red spelling underlines
    /// or the standalone word `"is"` (blue grammar underline candidate).
    static func inspectWord(at charIndex: Int, in text: String, spellDocumentTag: Int = 0) -> EditWordInspection? {
        let nsText = text as NSString
        let totalLen = nsText.length
        guard totalLen > 0 else { return nil }

        let clampedIndex = max(0, min(charIndex, totalLen))
        let markers = markerRanges(in: text)
        for marker in markers {
            if clampedIndex > marker.location && clampedIndex < NSMaxRange(marker) {
                return nil
            }
        }

        let probeLoc = min(clampedIndex, totalLen - 1)
        let lineRange = nsText.lineRange(for: NSRange(location: probeLoc, length: 0))
        let lineEnd = NSMaxRange(lineRange)
        let checker = NSSpellChecker.shared

        // 1. Scan only the current line using NSSpellChecker so boundaries match red underlines exactly.
        var cursor = lineRange.location
        while cursor < lineEnd {
            let spellRange = checker.checkSpelling(
                of: text,
                startingAt: cursor,
                language: nil,
                wrap: false,
                inSpellDocumentWithTag: spellDocumentTag,
                wordCount: nil
            )
            if spellRange.location == NSNotFound || spellRange.length == 0 || spellRange.location >= lineEnd {
                break
            }
            if clampedIndex >= spellRange.location && clampedIndex <= NSMaxRange(spellRange) {
                let word = nsText.substring(with: spellRange)
                if !intersectsMarker(spellRange, markers: markers) && !shouldSkipToken(word) {
                    let guesses = checker.guesses(
                        forWordRange: spellRange,
                        in: text,
                        language: nil,
                        inSpellDocumentWithTag: spellDocumentTag
                    ) ?? []
                    return EditWordInspection(
                        word: word,
                        rangeLocation: spellRange.location,
                        rangeLength: spellRange.length,
                        isMisspelled: true,
                        isGrammarIs: false,
                        guesses: Array(guesses.prefix(4))
                    )
                }
            }
            let next = NSMaxRange(spellRange)
            if next <= cursor { break }
            cursor = next
        }

        // 2. Check if cursor/click is on standalone "is" (blue grammar underline candidate).
        if let tokenRange = alphanumericWordRange(at: clampedIndex, in: nsText),
           !intersectsMarker(tokenRange, markers: markers) {
            let token = nsText.substring(with: tokenRange)
            if token.lowercased() == "is" {
                return EditWordInspection(
                    word: token,
                    rangeLocation: tokenRange.location,
                    rangeLength: tokenRange.length,
                    isMisspelled: false,
                    isGrammarIs: true,
                    guesses: ["is5", "isii"]
                )
            }
        }

        return nil
    }

    private static func alphanumericWordRange(at charIndex: Int, in nsText: NSString) -> NSRange? {
        let totalLen = nsText.length
        guard totalLen > 0 else { return nil }

        func isWordUnit(_ unit: unichar) -> Bool {
            guard let scalar = UnicodeScalar(unit) else { return false }
            return CharacterSet.alphanumerics.contains(scalar)
        }

        var anchor: Int?
        if charIndex < totalLen && isWordUnit(nsText.character(at: charIndex)) {
            anchor = charIndex
        } else if charIndex > 0 && isWordUnit(nsText.character(at: charIndex - 1)) {
            anchor = charIndex - 1
        }
        guard let center = anchor else { return nil }

        var start = center
        while start > 0 && isWordUnit(nsText.character(at: start - 1)) {
            start -= 1
        }
        var end = center + 1
        while end < totalLen && isWordUnit(nsText.character(at: end)) {
            end += 1
        }
        return NSRange(location: start, length: end - start)
    }
    #endif

    static func shouldSkipToken(_ word: String) -> Bool {
        if word.count == 9 && Acode9.validate(word, filterProfanity: false).valid {
            return true
        }
        return false
    }
}

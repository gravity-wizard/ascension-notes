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

@MainActor
enum SpellcheckHelper {
    /// Checks natural-language spelling in Clean View while skipping valid Acode9 identifiers.
    static func findIssues(in text: String) -> [SpellcheckIssue] {
        guard !text.isEmpty else { return [] }
        var issues: [SpellcheckIssue] = []

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
            if !shouldSkipToken(word), let swiftRange = Range(range, in: text) {
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
            if !shouldSkipToken(word), let swiftRange = Range(range, in: text) {
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
        #if os(macOS)
        NSSpellChecker.shared.learnWord(word)
        #elseif canImport(UIKit)
        UITextChecker.learnWord(word)
        #endif
    }

    private static func shouldSkipToken(_ word: String) -> Bool {
        if word.count == 9 && Acode9.validate(word, filterProfanity: false).valid {
            return true
        }
        return false
    }
}

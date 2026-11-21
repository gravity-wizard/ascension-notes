import XCTest
@testable import AscensionCore

final class AscensionCoreTests: XCTestCase {
    func testBase38AlphabetAndJesusClock2p15ek() throws {
        XCTAssertEqual(Base38Clock.alphabet, "0123456789abcdefghijklmnopqrstuvwxyz|^")
        XCTAssertEqual(Base38Clock.alphabet.count, 38)
        XCTAssertEqual(Base38Clock.t0Unix, 1_584_540_571)

        let ts = try Base38Clock.decodeJesusClock("2p15ek")
        XCTAssertEqual(Base38Clock.jesusClock(unixSeconds: ts), "2p15ek")
        XCTAssertEqual(Base38Clock.clock2(unixSeconds: ts), "2p")
        XCTAssertEqual(Base38Clock.jesusClock(unixSeconds: Base38Clock.t0Unix - 42), "0")
    }

    func testCanonicalAcode9ExamplesParseAndValidate() throws {
        for code in ["Ab2p^0oyu", "Ab2p^a40z", "Ac3x^chch"] {
            let parts = try Acode9.parse(code)
            XCTAssertEqual(parts.bigA, "A")
            XCTAssertEqual(parts.center, "^")
            XCTAssertEqual(parts.canonical, code)
            XCTAssertTrue(Acode9.validate(code).valid, "Expected \(code) to validate")
        }

        XCTAssertFalse(Acode9.validate("Ab2p^0oyu", strict: true).valid)
        XCTAssertTrue(Acode9.validate("Ab2p^a40z", strict: true).valid)
        XCTAssertTrue(Acode9.validate("Ac3x^chch", strict: true).valid)

        XCTAssertEqual(try Acode9.toDash("Ab2p^a40z"), "Ab2p-a40z")
        XCTAssertEqual(try Acode9.toCaret("Ab2p-a40z"), "Ab2p^a40z")
        XCTAssertEqual(Base38Clock.toURLSafe("2p|^6a"), "2p_-6a")
        XCTAssertEqual(Base38Clock.fromURLSafe("2p_-6a"), "2p|^6a")
        XCTAssertEqual(try Acode9.toDash("Ab2p^|a^z"), "Ab2p-_a-z")
        XCTAssertEqual(try Acode9.toCaret("Ab2p-_a-z"), "Ab2p^|a^z")
    }

    func testSafeJesusClockPausesOnTriple6AndBadWords() throws {
        let ts666 = try Base38Clock.decodeJesusClock("2666ab")
        let reading666 = Base38Clock.safeJesusClock(unixSeconds: ts666)
        XCTAssertTrue(reading666.isPaused)
        XCTAssertEqual(reading666.rawClock, "2666ab")
        XCTAssertEqual(reading666.clock, "2665^^")
        XCTAssertTrue(Base38Clock.isCleanClock(reading666.clock))

        let tsBad = try Base38Clock.decodeJesusClock("2shit1")
        let readingBad = Base38Clock.safeJesusClock(unixSeconds: tsBad)
        XCTAssertTrue(readingBad.isPaused)
        XCTAssertTrue(Base38Clock.isCleanClock(readingBad.clock))
    }

    func testYouTubeStyleIDFilterAndRollingPool() throws {
        XCTAssertFalse(Acode9.isCleanID("Ab2p^shit").clean)
        XCTAssertFalse(Acode9.isCleanID("Ab2p^sh1t").clean)
        XCTAssertFalse(Acode9.isCleanID("Ab2p^666z").clean)
        XCTAssertFalse(Acode9.isCleanID("Ab2p^aaaa").clean)
        XCTAssertFalse(Acode9.isCleanID("Ac3x^chch", blockRepeatedPairs: true).clean)
        XCTAssertFalse(Acode9.isCleanID("Ab2p-a40z", existingPool: ["Ab2p^a40z"]).clean)

        let startTs = try Base38Clock.decodeJesusClock("2p15ek")
        let pool = try Acode9.generateRollingPool(count: 15, startUnixSeconds: startTs, cadenceSeconds: 1, mode: .good1a)
        XCTAssertEqual(pool.count, 15)
        XCTAssertEqual(Set(pool.map(\.acode9)).count, 15)
        for (idx, item) in pool.enumerated() {
            XCTAssertEqual(item.timestamp, startTs + Int64(idx))
            XCTAssertTrue(Acode9.validate(item.acode9, mode: .second1a).valid)
        }
    }

    func testAXIFNormalizationAndCaseSensitiveDualLayerSearch() throws {
        let raw = "Log: NormA met Norm4 and Norma4 under Ab2p^a40z."
        let ts = try Base38Clock.decodeJesusClock("2p15ek")
        let doc = try AXIFDocument(
            title: "Test Log",
            rawText: raw,
            ownerAcode9: "Ab2p^a40z",
            timestampUnix: ts
        )

        XCTAssertEqual(doc.render(normalized: true), "Log: Norma met Norma and Norma under Ab2p^a40z.")
        XCTAssertEqual(doc.axif.munscCount, 3)
        XCTAssertEqual(doc.axif.jesusClock, "2p15ek")

        let hitA = try CaseSensitiveSearch.search(
            document: doc,
            query: "NormA",
            options: SearchOptions(caseSensitive: true)
        )
        XCTAssertEqual(hitA.count, 1)
        XCTAssertEqual(hitA.first?.matchedText, "NormA")
        XCTAssertEqual(hitA.first?.axifEntry?.normalizedForm, "Norma")

        let hit4 = try CaseSensitiveSearch.search(
            document: doc,
            query: "Norm4",
            options: SearchOptions(caseSensitive: true)
        )
        XCTAssertEqual(hit4.count, 1)
        XCTAssertEqual(hit4.first?.matchedText, "Norm4")

        let hitA4 = try CaseSensitiveSearch.search(
            document: doc,
            query: "Norma4",
            options: SearchOptions(caseSensitive: true)
        )
        XCTAssertEqual(hitA4.count, 1)
        XCTAssertEqual(hitA4.first?.matchedText, "Norma4")

        let hitLower = try CaseSensitiveSearch.search(
            document: doc,
            query: "norma",
            options: SearchOptions(caseSensitive: true)
        )
        XCTAssertTrue(hitLower.isEmpty)

        let hitInsensitive = try CaseSensitiveSearch.search(
            document: doc,
            query: "norma",
            options: SearchOptions(caseSensitive: false, wholeWord: true)
        )
        XCTAssertEqual(hitInsensitive.count, 3)
    }

    func testShareableAXIFFooterSlogBogAndRoundtripImport() throws {
        let customRule = MUNSCRule(
            name: "custom_z1on",
            pattern: "Z1on",
            replacement: "Zion",
            description: "Custom Zion MUNSC"
        )
        let raw = "Heading toward Z1on with NormA and Norm4."
        let ts = try Base38Clock.decodeJesusClock("2p15ek")
        let doc = try AXIFDocument(
            title: "Route",
            rawText: raw,
            ownerAcode9: "Ab2p^a40z",
            rules: [customRule],
            timestampUnix: ts
        )
        XCTAssertEqual(doc.normalizedText, "Heading toward Zion with Norma and Norma.")

        // 1. Clean + AXIF Footer roundtrip
        let footer = try doc.exportCleanWithAXIFFooter()
        let decodedFooter = try AXIFDocument.parseSharedBundle(footer)
        XCTAssertEqual(decodedFooter.metadata.acode9, "Ab2p^a40z")
        XCTAssertEqual(decodedFooter.reconstructedRawText, raw)
        XCTAssertEqual(decodedFooter.rawSHA256Matches, true)
        XCTAssertEqual(decodedFooter.normalizedSHA256Matches, true)
        XCTAssertEqual(decodedFooter.metadata.rules.first?.pattern, "Z1on")

        // 2. SlogBog phpBBog roundtrip
        let bbcode = try doc.exportSlogBogBBCode()
        XCTAssertTrue(bbcode.contains("[quote="))
        XCTAssertTrue(bbcode.contains("[spoiler=AXIF]"))
        let decodedBB = try AXIFDocument.parseSharedBundle(bbcode)
        XCTAssertEqual(decodedBB.reconstructedRawText, raw)
        XCTAssertEqual(decodedBB.rawSHA256Matches, true)
        XCTAssertEqual(decodedBB.normalizedSHA256Matches, true)

        // 3. Python-style snake_case MUNSCRule JSON compatibility
        let snakeRuleJSON = #"{"name":"py_rule","pattern":"C4stle","replacement":"Castle","is_regex":false,"description":"py"}"#
        let decodedRule = try JSONDecoder().decode(MUNSCRule.self, from: Data(snakeRuleJSON.utf8))
        XCTAssertEqual(decodedRule.pattern, "C4stle")
        XCTAssertEqual(decodedRule.replacement, "Castle")
        XCTAssertFalse(decodedRule.isRegex)
    }

    func testSkipVowelsSuggestionsAndVerificationTags() throws {
        XCTAssertEqual(SkipVowelsHelper.consonantSkeleton("Where's Norma"), "whrnrm")
        XCTAssertEqual(SkipVowelsHelper.consonantSkeleton("WhrNrm"), "whrnrm")

        XCTAssertEqual(SkipVowelsHelper.bestSuggestion(for: "WhrNrmA")?.normalized, "Where's Norma A")
        XCTAssertEqual(SkipVowelsHelper.bestSuggestion(for: "WhrNrmB")?.normalized, "Where's Norma B")
        XCTAssertEqual(SkipVowelsHelper.bestSuggestion(for: "NrmA")?.normalized, "Norma A")
        XCTAssertEqual(SkipVowelsHelper.bestSuggestion(for: "NrmB")?.normalized, "Norma B")
        XCTAssertEqual(SkipVowelsHelper.bestSuggestion(for: "Anotes")?.normalized, "Ascension Notes")
        XCTAssertEqual(SkipVowelsHelper.bestSuggestion(for: "GSii")?.normalized, "GSii")

        // Dynamic consonant-skeleton matching against custom lexicon
        let customSug = SkipVowelsHelper.bestSuggestion(
            for: "JssClck",
            extraLexicon: ["Jesus Clock"]
        )
        XCTAssertEqual(customSug?.normalized, "Jesus Clock")

        let ruleA = SkipVowelsHelper.makeVerifiedRule(token: "WhrNrmA", normalized: "Where's Norma A")
        XCTAssertEqual(ruleA.description, "Skip vowels verified")

        let ts = try Base38Clock.decodeJesusClock("2p15ek")
        let doc = try AXIFDocument(
            title: "Where's Norma?",
            rawText: "Comparing WhrNrmA and WhrNrmB with GSii and i9or1.",
            ownerAcode9: "Ab2p^a40z",
            rules: [
                ruleA,
                SkipVowelsHelper.makeVerifiedRule(token: "WhrNrmB", normalized: "Where's Norma B")
            ],
            timestampUnix: ts
        )
        XCTAssertEqual(doc.normalizedText, "Comparing Where's Norma A and Where's Norma B with GSii and i9or1.")

        XCTAssertEqual(VerificationTagHelper.appendII(to: "GS"), "GSii")
        XCTAssertEqual(VerificationTagHelper.appendII(to: "GSii"), "GSii")
        XCTAssertEqual(VerificationTagHelper.appendIS5(to: "is"), "is5")
        XCTAssertEqual(VerificationTagHelper.appendIS5(to: "Is"), "is5")
        XCTAssertEqual(VerificationTagHelper.appendIS5(to: "Appending"), "Appendingis5")
        XCTAssertEqual(VerificationTagHelper.appendIS5(to: "Appendingis5"), "Appendingis5")

        XCTAssertTrue(VerificationTagHelper.isHierarchyOrVerifiedTag("i9or1"))
        XCTAssertTrue(VerificationTagHelper.isHierarchyOrVerifiedTag("GSii"))
        XCTAssertTrue(VerificationTagHelper.isHierarchyOrVerifiedTag("is5"))
        XCTAssertFalse(VerificationTagHelper.isHierarchyOrVerifiedTag("is"))
        XCTAssertFalse(VerificationTagHelper.isHierarchyOrVerifiedTag("ii"))

        let docWithImage = try AXIFDocument(
            title: "Retina",
            rawText: "NormA screenshot:\n▸[Image: NormA.png #a1b2]",
            ownerAcode9: "Ab2p^a40z",
            timestampUnix: ts
        )
        XCTAssertEqual(docWithImage.normalizedText, "Norma screenshot:\n▸[Image: NormA.png #a1b2]")
        XCTAssertEqual(docWithImage.axif.munscCount, 1)
    }
}

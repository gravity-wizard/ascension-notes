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
    }

    func testYouTubeStyleIDFilterAndRollingPool() throws {
        XCTAssertFalse(Acode9.isCleanID("Ab2p^shit").clean)
        XCTAssertFalse(Acode9.isCleanID("Ab2p^sh1t").clean)
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
}

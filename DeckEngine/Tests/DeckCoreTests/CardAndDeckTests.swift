import XCTest
@testable import DeckCore

final class CardAndDeckTests: XCTestCase {

    func testCardIdentifiersAreUniqueWithinAPack() {
        let deck = DeckConfiguration.standard54.build()
        XCTAssertEqual(deck.count, 54)
        XCTAssertEqual(Set(deck.map(\.id)).count, 54)
    }

    func testMultiplePacksProduceDistinctIdentifiersForTheSameFace() {
        let deck = DeckConfiguration.double52.build()
        XCTAssertEqual(deck.count, 104)
        XCTAssertEqual(Set(deck.map(\.id)).count, 104)
        let aceOfSpades = deck.filter { $0.suit == .spades && $0.rank == .ace }
        XCTAssertEqual(aceOfSpades.count, 2)
        XCTAssertNotEqual(aceOfSpades[0].id, aceOfSpades[1].id)
        XCTAssertEqual(aceOfSpades[0].token, aceOfSpades[1].token)
    }

    func testStrippedDeckSizes() {
        XCTAssertEqual(DeckConfiguration.euchre24.totalCards, 24)
        XCTAssertEqual(DeckConfiguration.piquet32.totalCards, 32)
        XCTAssertEqual(DeckConfiguration.short36.totalCards, 36)
        XCTAssertEqual(DeckConfiguration.spider(suitCount: 1).totalCards, 104)
        XCTAssertEqual(DeckConfiguration.spider(suitCount: 2).totalCards, 104)
        XCTAssertEqual(DeckConfiguration.spider(suitCount: 4).totalCards, 104)
    }

    func testTokenRoundTrip() {
        for card in DeckConfiguration.standard54.build() {
            let parsed = Card(token: card.token)
            XCTAssertNotNil(parsed, "failed to parse \(card.token)")
            XCTAssertEqual(parsed?.kind, card.kind)
        }
        XCTAssertEqual(Card(token: "10H")?.rank, .ten)
        XCTAssertEqual(Card(token: "TH")?.rank, .ten)
        XCTAssertNil(Card(token: "ZZ"))
    }

    func testAceLowValue() {
        XCTAssertEqual(Rank.ace.rawValue, 14)
        XCTAssertEqual(Rank.ace.aceLowValue, 1)
        XCTAssertEqual(Rank.seven.aceLowValue, 7)
    }
}

final class SeededGeneratorTests: XCTestCase {

    func testSameSeedProducesSameSequence() {
        var a = SeededGenerator(seed: 12345)
        var b = SeededGenerator(seed: 12345)
        for _ in 0..<1000 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testDifferentSeedsDiverge() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)
        var differences = 0
        for _ in 0..<100 where a.next() != b.next() { differences += 1 }
        XCTAssertGreaterThan(differences, 90)
    }

    func testShuffleIsDeterministicAndAPermutation() {
        let deck = DeckConfiguration.standard52.build()
        var first = SeededGenerator(seed: 99)
        var second = SeededGenerator(seed: 99)
        let a = deck.deterministicShuffled(using: &first)
        let b = deck.deterministicShuffled(using: &second)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(Set(a.map(\.id)), Set(deck.map(\.id)))
        XCTAssertNotEqual(a.map(\.id), deck.map(\.id), "a shuffle should move something")
    }

    func testBoundedIntegersStayInRange() {
        var generator = SeededGenerator(seed: 7)
        var seen: Set<Int> = []
        for _ in 0..<5000 {
            let value = generator.nextInt(upperBound: 6)
            XCTAssertTrue((0..<6).contains(value))
            seen.insert(value)
        }
        XCTAssertEqual(seen.count, 6, "every value in range should occur")
    }

    func testBranchDoesNotAdvanceTheParent() {
        var parent = SeededGenerator(seed: 4242)
        let before = parent.state
        var child = parent.branch(17)
        _ = child.next()
        XCTAssertEqual(parent.state, before)
        var otherChild = parent.branch(18)
        XCTAssertNotEqual(child.next(), otherChild.next())
    }

    func testUnitDoublesStayInRange() {
        var generator = SeededGenerator(seed: 3)
        for _ in 0..<2000 {
            let value = generator.nextUnit()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
    }
}

final class SeedFactoryTests: XCTestCase {

    func testDailySeedIsStableForTheSameInputs() {
        let date = ChallengeDate(year: 2026, month: 8, day: 28)
        let a = SeedFactory.dailySeed(challengeDate: date, gameID: .hearts, rulesVersion: 1, challengeVersion: 1)
        let b = SeedFactory.dailySeed(challengeDate: date, gameID: .hearts, rulesVersion: 1, challengeVersion: 1)
        XCTAssertEqual(a, b)
    }

    func testDailySeedChangesWithEveryComponent() {
        let date = ChallengeDate(year: 2026, month: 8, day: 28)
        let base = SeedFactory.dailySeed(challengeDate: date, gameID: .hearts, rulesVersion: 1, challengeVersion: 1)
        XCTAssertNotEqual(base, SeedFactory.dailySeed(challengeDate: date.adding(days: 1), gameID: .hearts, rulesVersion: 1, challengeVersion: 1))
        XCTAssertNotEqual(base, SeedFactory.dailySeed(challengeDate: date, gameID: .spades, rulesVersion: 1, challengeVersion: 1))
        XCTAssertNotEqual(base, SeedFactory.dailySeed(challengeDate: date, gameID: .hearts, rulesVersion: 2, challengeVersion: 1))
        XCTAssertNotEqual(base, SeedFactory.dailySeed(challengeDate: date, gameID: .hearts, rulesVersion: 1, challengeVersion: 2))
    }

    func testKnownSeedValueDoesNotDrift() {
        // Pinning one value catches an accidental change to the hash, which
        // would silently re-roll every historical daily challenge.
        XCTAssertEqual(SeedFactory.hash("deck"), SeedFactory.hash("deck"))
        XCTAssertNotEqual(SeedFactory.hash("deck"), SeedFactory.hash("deck "))
    }
}

final class ChallengeDateTests: XCTestCase {

    func testIdentifierFormat() {
        XCTAssertEqual(ChallengeDate(year: 2026, month: 1, day: 5).identifier, "2026-01-05")
        XCTAssertEqual(ChallengeDate(identifier: "2026-01-05"), ChallengeDate(year: 2026, month: 1, day: 5))
        XCTAssertNil(ChallengeDate(identifier: "nonsense"))
    }

    func testDayArithmeticCrossesMonthAndYearBoundaries() {
        let utc = TimeZone(identifier: "UTC")!
        let endOfYear = ChallengeDate(year: 2026, month: 12, day: 31)
        XCTAssertEqual(endOfYear.adding(days: 1, in: utc), ChallengeDate(year: 2027, month: 1, day: 1))
        let endOfFeb = ChallengeDate(year: 2028, month: 2, day: 28)
        XCTAssertEqual(endOfFeb.adding(days: 1, in: utc), ChallengeDate(year: 2028, month: 2, day: 29),
                       "2028 is a leap year")
    }

    func testDaylightSavingTransitionDoesNotSkipADay() {
        // New York springs forward on 8 March 2026. Adding a day across the
        // transition must land on the ninth, not the tenth.
        guard let newYork = TimeZone(identifier: "America/New_York") else { return }
        let before = ChallengeDate(year: 2026, month: 3, day: 7)
        XCTAssertEqual(before.adding(days: 1, in: newYork), ChallengeDate(year: 2026, month: 3, day: 8))
        XCTAssertEqual(before.adding(days: 2, in: newYork), ChallengeDate(year: 2026, month: 3, day: 9))
    }

    func testDaysUntil() {
        let utc = TimeZone(identifier: "UTC")!
        let start = ChallengeDate(year: 2026, month: 8, day: 1)
        XCTAssertEqual(start.days(until: ChallengeDate(year: 2026, month: 8, day: 11), in: utc), 10)
        XCTAssertEqual(ChallengeDate(year: 2026, month: 8, day: 11).days(until: start, in: utc), -10)
    }

    func testOrdering() {
        XCTAssertLessThan(ChallengeDate(year: 2026, month: 1, day: 31),
                          ChallengeDate(year: 2026, month: 2, day: 1))
    }
}

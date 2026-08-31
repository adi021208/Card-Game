import XCTest
import DeckCore
@testable import DeckGames

/// `hand("4C", "5C", "6C")` — the tokens read the way a card reads.
private func hand(_ tokens: String...) -> [Card] {
    tokens.map { Card(token: $0)! }
}

private func names(_ melds: [[Card]]) -> Set<Set<String>> {
    Set(melds.map { Set($0.map(\.token)) })
}

final class MeldSolverTests: XCTestCase {

    // MARK: - Enumeration

    func testThreeOfAKindIsASet() {
        let cards = hand("7C", "7H", "7S")
        let melds = MeldSolver.enumerateMelds(cards)
        XCTAssertEqual(melds.count, 1)
        XCTAssertEqual(melds[0].count, 3)
    }

    func testFourOfAKindAlsoOffersItsThreeCardSubsets() {
        let cards = hand("9C", "9D", "9H", "9S")
        let melds = MeldSolver.enumerateMelds(cards)
        XCTAssertEqual(melds.count, 5, "the full set plus each of its four triples")
        XCTAssertEqual(melds.filter { $0.count == 4 }.count, 1)
        XCTAssertEqual(melds.filter { $0.count == 3 }.count, 4)
    }

    func testTwoOfAKindIsNotAMeld() {
        XCTAssertTrue(MeldSolver.enumerateMelds(hand("4C", "4H")).isEmpty)
    }

    func testARunNeedsThreeInOneSuit() {
        XCTAssertTrue(MeldSolver.enumerateMelds(hand("4C", "5C")).isEmpty)
        XCTAssertFalse(MeldSolver.enumerateMelds(hand("4C", "5C", "6C")).isEmpty)
        XCTAssertTrue(MeldSolver.enumerateMelds(hand("4C", "5H", "6C")).isEmpty,
                      "a run does not jump suits")
    }

    func testALongRunOffersEveryContiguousSubRun() {
        let cards = hand("4S", "5S", "6S", "7S")
        let melds = MeldSolver.enumerateMelds(cards)
        // 4-5-6, 5-6-7, and 4-5-6-7.
        XCTAssertEqual(melds.count, 3)
        XCTAssertTrue(names(melds).contains(["4S", "5S", "6S"]))
        XCTAssertTrue(names(melds).contains(["5S", "6S", "7S"]))
        XCTAssertTrue(names(melds).contains(["4S", "5S", "6S", "7S"]))
    }

    func testAcesAreLowInARun() {
        let low = hand("AH", "2H", "3H")
        XCTAssertEqual(MeldSolver.enumerateMelds(low).count, 1, "A-2-3 is a run")

        let high = hand("QH", "KH", "AH")
        XCTAssertTrue(MeldSolver.enumerateMelds(high).isEmpty, "Q-K-A does not wrap in rummy")
    }

    func testARunDoesNotWrapAroundThroughTheAce() {
        let cards = hand("KC", "AC", "2C")
        XCTAssertTrue(MeldSolver.enumerateMelds(cards).isEmpty)
    }

    // MARK: - The exact solve

    func testAHandOfNothingHasAllOfItAsDeadwood() {
        let cards = hand("2C", "5H", "9S", "KD")
        let solution = MeldSolver.best(cards)
        XCTAssertTrue(solution.melds.isEmpty)
        XCTAssertEqual(solution.deadwood.count, 4)
        XCTAssertEqual(solution.deadwoodPoints, 2 + 5 + 9 + 10)
        XCTAssertFalse(solution.isGin)
    }

    func testAFullyMeldedHandIsGin() {
        let cards = hand("4C", "5C", "6C", "9H", "9D", "9S", "JS", "QS", "KS", "2H")
        // Nine of the ten melt into melds; the stray two is the discard.
        let withoutStray = cards.filter { $0.token != "2H" }
        let solution = MeldSolver.best(withoutStray)
        XCTAssertTrue(solution.isGin)
        XCTAssertEqual(solution.deadwoodPoints, 0)
        XCTAssertEqual(solution.melds.count, 3)
    }

    /// The case a greedy solver gets wrong: the longest meld is not the best one.
    func testTheSolverBeatsGreedyLongestFirst() {
        // 5-6-7-8 of hearts, plus the other fives and the other eights.
        // Greedy takes the four-card run and is left holding two pairs — 26
        // points. The right answer keeps 5-6-7 of hearts and sets the eights,
        // leaving only the two black fives: 10.
        let cards = hand("5H", "6H", "7H", "8H", "5C", "5S", "8C", "8S")
        let solution = MeldSolver.best(cards)
        XCTAssertEqual(solution.deadwoodPoints, 10)
        XCTAssertEqual(solution.melds.count, 2)
        XCTAssertEqual(Set(solution.deadwood.map(\.token)), ["5C", "5S"])

        // Prove the greedy answer really is worse, so the test is not vacuous.
        let greedy = MeldSolver.enumerateMelds(cards).max(by: { $0.count < $1.count })!
        let greedyRest = cards.filter { card in !greedy.contains { $0.id == card.id } }
        XCTAssertEqual(greedy.count, 4)
        XCTAssertEqual(greedyRest.reduce(0) { $0 + CardScoring.deadwoodPoints($1) }, 26)
    }

    func testACardIsNeverCountedInTwoMelds() {
        let cards = hand("3D", "4D", "5D", "5C", "5H")
        let solution = MeldSolver.best(cards)
        let used = solution.melds.flatMap { $0.map(\.id) }
        XCTAssertEqual(used.count, Set(used).count, "no card appears in two melds")
        XCTAssertEqual(used.count + solution.deadwood.count, cards.count,
                       "every card is either melded or deadwood, exactly once")
    }

    func testDeadwoodIsSortedHighestFirstSoTheDiscardIsObvious() {
        let cards = hand("3C", "KH", "7S")
        let solution = MeldSolver.best(cards)
        XCTAssertEqual(solution.deadwood.map(\.token), ["KH", "7S", "3C"])
    }

    func testAnEmptyHandSolvesToNothing() {
        let solution = MeldSolver.best([])
        XCTAssertTrue(solution.melds.isEmpty)
        XCTAssertTrue(solution.deadwood.isEmpty)
        XCTAssertEqual(solution.deadwoodPoints, 0)
        XCTAssertTrue(solution.isGin, "a hand with no deadwood is gin, even an empty one")
    }

    func testMeldKindsAreLabelledCorrectly() {
        let cards = hand("4C", "5C", "6C", "9H", "9D", "9S")
        let kinds = Set(MeldSolver.best(cards).meldIDs().map(\.kind))
        XCTAssertEqual(kinds, [.run, .set])
    }

    func testAFullTenCardHandSolvesQuickly() {
        // Ten cards is the real gin hand size; the search must not blow up.
        let cards = hand("2C", "3C", "4C", "2D", "3D", "4D", "2H", "3H", "4H", "KS")
        let started = Date()
        let solution = MeldSolver.best(cards)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0,
                          "the exact solve is fast at hand size")
        XCTAssertEqual(solution.deadwoodPoints, 10, "only the king is left over")
    }

    // MARK: - Laying off

    func testACardExtendsARunAtEitherEnd() {
        let run = hand("5S", "6S", "7S")
        XCTAssertTrue(MeldSolver.canLayOff(Card(token: "4S")!, on: run))
        XCTAssertTrue(MeldSolver.canLayOff(Card(token: "8S")!, on: run))
        XCTAssertFalse(MeldSolver.canLayOff(Card(token: "4H")!, on: run), "wrong suit")
        XCTAssertFalse(MeldSolver.canLayOff(Card(token: "TS")!, on: run), "not adjacent")
    }

    func testASetTakesTheFourthCardAndNoMore() {
        let three = hand("QC", "QH", "QS")
        XCTAssertTrue(MeldSolver.canLayOff(Card(token: "QD")!, on: three))
        let four = three + [Card(token: "QD")!]
        XCTAssertFalse(MeldSolver.canLayOff(Card(.diamonds, .queen, deckIndex: 1), on: four),
                       "a set is full at four")
    }

    func testLayingOffCascadesWhenOneCardOpensTheNext() {
        let run = hand("5H", "6H", "7H")
        let deadwood = hand("9H", "8H", "2C")
        let outcome = MeldSolver.layOff(deadwood: deadwood, onto: [run])
        XCTAssertEqual(Set(outcome.laidOff.map(\.token)), ["8H", "9H"],
                       "the eight extends the run, which then takes the nine")
        XCTAssertEqual(outcome.remaining.map(\.token), ["2C"])
    }

    func testNothingLaysOffOntoAnEmptyTable() {
        let deadwood = hand("9H", "2C")
        let outcome = MeldSolver.layOff(deadwood: deadwood, onto: [])
        XCTAssertTrue(outcome.laidOff.isEmpty)
        XCTAssertEqual(outcome.remaining.count, 2)
    }

    func testTooShortAMeldTakesNothing() {
        let pair = hand("QC", "QH")
        XCTAssertFalse(MeldSolver.canLayOff(Card(token: "QS")!, on: pair),
                       "two cards are not a meld to lay off onto")
    }
}

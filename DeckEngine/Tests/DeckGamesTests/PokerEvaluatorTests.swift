import XCTest
import DeckCore
@testable import DeckGames

private func hand(_ tokens: String) -> [Card] {
    tokens.split(separator: " ").compactMap { Card(token: String($0)) }
}

private func rank(_ tokens: String) -> PokerHandRank {
    PokerEvaluator.best(from: hand(tokens))
}

final class PokerEvaluatorTests: XCTestCase {

    // MARK: - Every category is recognised

    func testCategoryRecognition() {
        XCTAssertEqual(rank("AS KD 9H 6C 2S").category, .highCard)
        XCTAssertEqual(rank("AS AD 9H 6C 2S").category, .pair)
        XCTAssertEqual(rank("AS AD 9H 9C 2S").category, .twoPair)
        XCTAssertEqual(rank("AS AD AH 9C 2S").category, .threeOfAKind)
        XCTAssertEqual(rank("5S 6D 7H 8C 9S").category, .straight)
        XCTAssertEqual(rank("2S 5S 7S TS KS").category, .flush)
        XCTAssertEqual(rank("AS AD AH 9C 9S").category, .fullHouse)
        XCTAssertEqual(rank("AS AD AH AC 9S").category, .fourOfAKind)
        XCTAssertEqual(rank("5S 6S 7S 8S 9S").category, .straightFlush)
    }

    func testRoyalFlushIsTheTopStraightFlush() {
        let royal = rank("TS JS QS KS AS")
        XCTAssertEqual(royal.category, .straightFlush)
        XCTAssertTrue(royal.isRoyalFlush)
        XCTAssertEqual(royal.tiebreakers.first, Rank.ace.rawValue)

        let lower = rank("9S TS JS QS KS")
        XCTAssertFalse(lower.isRoyalFlush)
        XCTAssertGreaterThan(royal, lower)
    }

    // MARK: - The wheel

    func testAceLowStraight() {
        let wheel = rank("AS 2D 3H 4C 5S")
        XCTAssertEqual(wheel.category, .straight)
        XCTAssertEqual(wheel.tiebreakers, [5], "the wheel's high card is the five")
    }

    func testWheelLosesToSixHighStraight() {
        XCTAssertLessThan(rank("AS 2D 3H 4C 5S"), rank("2S 3D 4H 5C 6S"))
    }

    func testSteelWheelIsAStraightFlush() {
        let steel = rank("AS 2S 3S 4S 5S")
        XCTAssertEqual(steel.category, .straightFlush)
        XCTAssertEqual(steel.tiebreakers, [5])
        XCTAssertLessThan(steel, rank("2S 3S 4S 5S 6S"))
    }

    func testAceHighStraightIsNotAWraparound() {
        // Q-K-A-2-3 is not a straight.
        let notAStraight = rank("QS KD AH 2C 3S")
        XCTAssertEqual(notAStraight.category, .highCard)
    }

    // MARK: - Kickers

    func testPairKickersDecideTheHand() {
        let better = rank("AS AD KH 7C 3S")
        let worse = rank("AC AH QD 7S 3C")
        XCTAssertGreaterThan(better, worse)
    }

    func testFourthKickerMatters() {
        let better = rank("AS AD KH 7C 4S")
        let worse = rank("AC AH KD 7S 3C")
        XCTAssertGreaterThan(better, worse)
    }

    func testTwoPairComparesHighPairFirst() {
        XCTAssertGreaterThan(rank("KS KD 2H 2C 9S"), rank("QS QD JH JC AS"))
    }

    func testTwoPairKickerBreaksATie() {
        XCTAssertGreaterThan(rank("KS KD QH QC AS"), rank("KH KC QS QD JS"))
    }

    func testTripsKickers() {
        XCTAssertGreaterThan(rank("7S 7D 7H AC 2S"), rank("7C 7H 7S KD 2C"))
    }

    func testQuadsKicker() {
        XCTAssertGreaterThan(rank("9S 9D 9H 9C AS"), rank("9S 9D 9H 9C KS"))
    }

    func testFullHouseComparesTripsFirst() {
        XCTAssertGreaterThan(rank("KS KD KH 2C 2S"), rank("QS QD QH AC AS"))
    }

    func testFlushComparesCardByCard() {
        XCTAssertGreaterThan(rank("AS QS 9S 5S 3S"), rank("AH QH 9H 5H 2H"))
        XCTAssertEqual(rank("AS QS 9S 5S 3S"), rank("AH QH 9H 5H 3H"), "identical flushes tie")
    }

    // MARK: - Ties

    func testIdenticalHandsTie() {
        XCTAssertEqual(rank("AS KD QH JC TS"), rank("AH KS QD JH TC"))
        XCTAssertFalse(rank("AS KD QH JC TS") < rank("AH KS QD JH TC"))
        XCTAssertFalse(rank("AS KD QH JC TS") > rank("AH KS QD JH TC"))
    }

    // MARK: - Category ordering

    func testCategoryOrderingIsComplete() {
        let ordered = [
            rank("AS KD 9H 6C 2S"),      // high card
            rank("2S 2D 9H 6C 3S"),      // pair
            rank("2S 2D 3H 3C 9S"),      // two pair
            rank("2S 2D 2H 6C 9S"),      // trips
            rank("2S 3D 4H 5C 6S"),      // straight
            rank("2S 5S 7S TS KS"),      // flush
            rank("2S 2D 2H 3C 3S"),      // full house
            rank("2S 2D 2H 2C 9S"),      // quads
            rank("2S 3S 4S 5S 6S")       // straight flush
        ]
        for index in 1..<ordered.count {
            XCTAssertGreaterThan(ordered[index], ordered[index - 1],
                                 "category \(ordered[index].category) should beat \(ordered[index - 1].category)")
        }
    }

    // MARK: - Best five from seven

    func testSevenCardsPicksTheBestFive() {
        // Board makes a flush; the two hole cards are irrelevant.
        let result = PokerEvaluator.best(from: hand("2C 7D AS KS QS JS TS"))
        XCTAssertEqual(result.category, .straightFlush)
        XCTAssertTrue(result.isRoyalFlush)
    }

    func testFullHouseFromTwoSetsOfTrips() {
        let result = PokerEvaluator.best(from: hand("9S 9D 9H 4C 4D 4S 2C"))
        XCTAssertEqual(result.category, .fullHouse)
        XCTAssertEqual(result.tiebreakers, [9, 4], "the higher trips play, the lower pair fills")
    }

    func testFlushBeatsStraightOnTheSameSevenCards() {
        let result = PokerEvaluator.best(from: hand("5H 6H 7H 8H 9C 2H TD"))
        XCTAssertEqual(result.category, .flush)
    }

    func testStraightFlushOutranksTheTripsInTheSameSevenCards() {
        // Quads and a straight flush cannot coexist in seven cards, but trips
        // and a straight flush can — and the straight flush has to win.
        let result = PokerEvaluator.best(from: hand("5H 6H 7H 8H 9H 9C 9D"))
        XCTAssertEqual(result.category, .straightFlush)
        XCTAssertEqual(result.tiebreakers, [9])
    }

    func testThreePairsPlayAsTheBestTwo() {
        let result = PokerEvaluator.best(from: hand("AS AD KH KC QS QD 2C"))
        XCTAssertEqual(result.category, .twoPair)
        XCTAssertEqual(result.tiebreakers, [14, 13, 12])
    }

    func testSixCardStraightUsesTheTopFive() {
        let result = PokerEvaluator.best(from: hand("4S 5D 6H 7C 8S 9D 2C"))
        XCTAssertEqual(result.category, .straight)
        XCTAssertEqual(result.tiebreakers, [9])
    }

    func testPlayingTheBoard() {
        let board = hand("AS KS QS JS TS")
        let alice = PokerEvaluator.bestHoldem(hole: hand("2C 3D"), board: board)
        let bob = PokerEvaluator.bestHoldem(hole: hand("4H 5H"), board: board)
        XCTAssertEqual(alice, bob, "when the board is the best hand, everyone ties")
        XCTAssertTrue(alice.isRoyalFlush)
    }

    func testBestFiveAlwaysReturnsFiveCards() {
        var generator = SeededGenerator(seed: 2026)
        let deck = DeckConfiguration.standard52.build()
        for _ in 0..<500 {
            let shuffled = deck.deterministicShuffled(using: &generator)
            let result = PokerEvaluator.best(from: Array(shuffled.prefix(7)))
            XCTAssertEqual(result.cards.count, 5)
            XCTAssertEqual(Set(result.cards.map(\.id)).count, 5)
        }
    }

    func testEvaluationIsConsistentUnderCardOrder() {
        var generator = SeededGenerator(seed: 77)
        let deck = DeckConfiguration.standard52.build()
        for _ in 0..<300 {
            let shuffled = deck.deterministicShuffled(using: &generator)
            let seven = Array(shuffled.prefix(7))
            let a = PokerEvaluator.best(from: seven)
            let b = PokerEvaluator.best(from: seven.reversed())
            XCTAssertEqual(a, b, "the order cards arrive in must not change the hand")
        }
    }

    func testRandomSevenCardHandsNeverMisrank() {
        // Cross-check the fast path against brute force over all 21 five-card
        // subsets, which is the definition of "best five".
        var generator = SeededGenerator(seed: 31337)
        let deck = DeckConfiguration.standard52.build()
        for _ in 0..<400 {
            let seven = Array(deck.deterministicShuffled(using: &generator).prefix(7))
            let fast = PokerEvaluator.best(from: seven)
            var brute: PokerHandRank?
            for a in 0..<3 {
                for b in (a + 1)..<4 {
                    for c in (b + 1)..<5 {
                        for d in (c + 1)..<6 {
                            for e in (d + 1)..<7 {
                                let five = [seven[a], seven[b], seven[c], seven[d], seven[e]]
                                let candidate = PokerEvaluator.best(from: five)
                                if brute == nil || candidate > brute! { brute = candidate }
                            }
                        }
                    }
                }
            }
            XCTAssertEqual(fast, brute, "best-of-seven disagreed with brute force on \(seven.map(\.token))")
        }
    }
}

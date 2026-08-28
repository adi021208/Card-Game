import XCTest
import DeckCore
@testable import DeckGames

private let a = SeatID(0)
private let b = SeatID(1)
private let c = SeatID(2)
private let d = SeatID(3)

private func rank(_ tokens: String) -> PokerHandRank {
    PokerEvaluator.best(from: tokens.split(separator: " ").compactMap { Card(token: String($0)) })
}

final class PotSolverTests: XCTestCase {

    func testSinglePotWithEqualContributions() {
        let pots = PotSolver.pots(contributions: [a: 100, b: 100, c: 100], contenders: [a, b, c])
        XCTAssertEqual(pots.count, 1)
        XCTAssertEqual(pots[0].amount, 300)
        XCTAssertEqual(Set(pots[0].contenders), [a, b, c])
        XCTAssertFalse(pots[0].isSidePot)
    }

    func testFoldedChipsStayInThePot() {
        let pots = PotSolver.pots(contributions: [a: 100, b: 100, c: 40], contenders: [a, b])
        XCTAssertEqual(PotSolver.total([a: 100, b: 100, c: 40]), 240)
        XCTAssertEqual(pots.reduce(0) { $0 + $1.amount }, 240,
                       "a folded player's chips are still won by someone")
    }

    func testShortStackAllInCreatesASidePot() {
        // A is all-in for 50; B and C keep betting to 300.
        let contributions: [SeatID: Int] = [a: 50, b: 300, c: 300]
        let pots = PotSolver.pots(contributions: contributions, contenders: [a, b, c])
        XCTAssertEqual(pots.count, 2)
        XCTAssertEqual(pots[0].amount, 150)
        XCTAssertEqual(Set(pots[0].contenders), [a, b, c])
        XCTAssertEqual(pots[1].amount, 500)
        XCTAssertEqual(Set(pots[1].contenders), [b, c])
        XCTAssertEqual(pots.reduce(0) { $0 + $1.amount }, 650)
    }

    func testThreeLayeredSidePots() {
        let contributions: [SeatID: Int] = [a: 25, b: 60, c: 150, d: 150]
        let pots = PotSolver.pots(contributions: contributions, contenders: [a, b, c, d])
        XCTAssertEqual(pots.count, 3)
        XCTAssertEqual(pots[0].amount, 100)                 // 25 x 4
        XCTAssertEqual(Set(pots[0].contenders), [a, b, c, d])
        XCTAssertEqual(pots[1].amount, 105)                 // 35 x 3
        XCTAssertEqual(Set(pots[1].contenders), [b, c, d])
        XCTAssertEqual(pots[2].amount, 180)                 // 90 x 2
        XCTAssertEqual(Set(pots[2].contenders), [c, d])
        XCTAssertEqual(pots.reduce(0) { $0 + $1.amount }, 385)
    }

    func testShortStackWinsOnlyTheMainPot() {
        let contributions: [SeatID: Int] = [a: 50, b: 300, c: 300]
        let pots = PotSolver.pots(contributions: contributions, contenders: [a, b, c])
        let ranks: [SeatID: PokerHandRank] = [
            a: rank("AS AD AH AC KS"),   // quads, the best hand
            b: rank("KS KD KH KC QS"),   // second best
            c: rank("2S 3D 7H 9C JS")    // nothing
        ]
        let payouts = PotSolver.award(pots: pots, ranks: ranks, oddChipOrder: [a, b, c])
        XCTAssertEqual(payouts[a], 150, "the short stack can only win what everyone matched")
        XCTAssertEqual(payouts[b], 500, "the side pot goes to the best hand that paid for it")
        XCTAssertNil(payouts[c])
        XCTAssertEqual((payouts[a] ?? 0) + (payouts[b] ?? 0), 650, "every chip is paid out")
    }

    func testSplitPotDividesEvenly() {
        let pots = PotSolver.pots(contributions: [a: 100, b: 100], contenders: [a, b])
        let ranks: [SeatID: PokerHandRank] = [a: rank("AS KD QH JC TS"), b: rank("AH KS QD JH TC")]
        let payouts = PotSolver.award(pots: pots, ranks: ranks, oddChipOrder: [a, b])
        XCTAssertEqual(payouts[a], 100)
        XCTAssertEqual(payouts[b], 100)
    }

    func testUncalledChipsComeBackToTheirOwner() {
        // A bet one more than B could call, so that chip is never contested.
        let pots = PotSolver.pots(contributions: [a: 51, b: 50], contenders: [a, b])
        XCTAssertEqual(pots.count, 2)
        XCTAssertEqual(pots[1].amount, 1)
        XCTAssertEqual(pots[1].contenders, [a])
        let ranks: [SeatID: PokerHandRank] = [a: rank("AS KD QH JC TS"), b: rank("AH KS QD JH TC")]
        let payouts = PotSolver.award(pots: pots, ranks: ranks, oddChipOrder: [b, a])
        XCTAssertEqual(payouts[a], 51)
        XCTAssertEqual(payouts[b], 50)
    }

    func testOddChipFollowsTheButtonOrder() {
        // C folded a single chip in, so the split pot is odd.
        let pots = PotSolver.pots(contributions: [a: 50, b: 50, c: 1], contenders: [a, b])
        XCTAssertEqual(pots.reduce(0) { $0 + $1.amount }, 101, "no chip is lost")
        let ranks: [SeatID: PokerHandRank] = [a: rank("AS KD QH JC TS"), b: rank("AH KS QD JH TC")]
        let payouts = PotSolver.award(pots: pots, ranks: ranks, oddChipOrder: [b, a, c])
        XCTAssertEqual((payouts[a] ?? 0) + (payouts[b] ?? 0), 101)
        XCTAssertEqual(payouts[b], 51, "the odd chip goes to the first winner left of the button")
        XCTAssertEqual(payouts[a], 50)
    }

    func testThreeWaySplitWithRemainder() {
        let pots = PotSolver.pots(contributions: [a: 34, b: 33, c: 33], contenders: [a, b, c])
        let tie = rank("AS KD QH JC TS")
        let payouts = PotSolver.award(pots: pots,
                                      ranks: [a: tie, b: tie, c: tie],
                                      oddChipOrder: [a, b, c])
        XCTAssertEqual((payouts[a] ?? 0) + (payouts[b] ?? 0) + (payouts[c] ?? 0), 100)
    }

    func testUncontestedPotGoesToTheLastPlayerStanding() {
        let pots = PotSolver.pots(contributions: [a: 100, b: 40, c: 20], contenders: [a])
        let payouts = PotSolver.award(pots: pots, ranks: [:], oddChipOrder: [a, b, c])
        XCTAssertEqual(payouts[a], 160)
    }

    func testMoneyNobodyCanWinIsNotLost() {
        // B and C both fold after putting money in; A is all-in for less.
        let contributions: [SeatID: Int] = [a: 20, b: 100, c: 100]
        let pots = PotSolver.pots(contributions: contributions, contenders: [a])
        XCTAssertEqual(pots.reduce(0) { $0 + $1.amount }, 220)
        let payouts = PotSolver.award(pots: pots, ranks: [:], oddChipOrder: [a, b, c])
        XCTAssertEqual(payouts[a], 220)
    }

    func testEmptyContributionsProduceNoPots() {
        XCTAssertTrue(PotSolver.pots(contributions: [:], contenders: []).isEmpty)
        XCTAssertTrue(PotSolver.pots(contributions: [a: 0, b: 0], contenders: [a, b]).isEmpty)
    }
}

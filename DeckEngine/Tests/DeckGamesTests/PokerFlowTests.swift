import XCTest
import DeckCore
@testable import DeckGames

final class TexasHoldemFlowTests: XCTestCase {
    private let rules = TexasHoldemRules()

    private func start(players: Int = 4,
                       seed: UInt64 = 909,
                       options: [String: Int] = [:]) -> (TexasHoldemRules.State, SeededGenerator, GameConfiguration) {
        var merged = ["startingChips": 1000, "smallBlind": 10, "bigBlind": 20]
        for (key, value) in options { merged[key] = value }
        let configuration = TestTable.configuration(.texasHoldem, humans: 1, ai: players - 1,
                                                    options: merged, seed: seed)
        var generator = SeededGenerator(seed: seed)
        let state = rules.setup(configuration: configuration, generator: &generator)
        return (state, generator, configuration)
    }

    func testDealGivesEveryoneTwoCards() {
        let (state, _, _) = start()
        for seat in state.seatOrder {
            XCTAssertEqual(state.board.count(in: .hand(seat)), 2)
        }
        XCTAssertEqual(state.community.count, 0)
        XCTAssertEqual(state.street, .preflop)
    }

    func testBlindsArePosted() {
        let (state, _, _) = start()
        XCTAssertEqual(state.pot, 30, "small blind plus big blind")
        XCTAssertEqual(state.currentBet, 20)
        let posted = state.committed.values.sorted()
        XCTAssertEqual(posted, [10, 20])
    }

    func testHeadsUpButtonPostsTheSmallBlindAndActsFirst() {
        let (state, _, _) = start(players: 2)
        XCTAssertEqual(state.committed[state.dealerSeat], 10,
                       "heads-up, the button is the small blind")
        XCTAssertEqual(state.activeSeat, state.dealerSeat,
                       "heads-up, the button acts first pre-flop")
    }

    func testActionStartsLeftOfTheBigBlindWithThreeOrMore() {
        let (state, _, _) = start(players: 4)
        let order = state.seatOrder
        guard let buttonIndex = order.firstIndex(of: state.dealerSeat) else { return XCTFail("no button") }
        let underTheGun = order[(buttonIndex + 3) % order.count]
        XCTAssertEqual(state.activeSeat, underTheGun)
    }

    func testBigBlindGetsTheOptionWhenEveryoneLimps() {
        var (state, generator, _) = start(players: 3)
        let order = state.seatOrder
        guard let buttonIndex = order.firstIndex(of: state.dealerSeat) else { return XCTFail("no button") }
        let bigBlindSeat = order[(buttonIndex + 2) % order.count]

        // Everyone calls round to the big blind.
        var safety = 0
        while state.activeSeat != bigBlindSeat && safety < 10 {
            safety += 1
            guard let seat = state.activeSeat else { break }
            let legal = rules.legalActions(in: state, for: seat)
            XCTAssertTrue(legal.contains(.call))
            _ = rules.apply(.call, to: &state, generator: &generator)
        }
        XCTAssertEqual(state.activeSeat, bigBlindSeat, "the big blind still has an option")
        XCTAssertEqual(state.toCall(bigBlindSeat), 0)
        XCTAssertTrue(rules.legalActions(in: state, for: bigBlindSeat).contains(.check))
    }

    func testCheckingRoundDealsTheFlop() {
        var (state, generator, _) = start(players: 3)
        var safety = 0
        while state.street == .preflop && safety < 12 {
            safety += 1
            guard let seat = state.activeSeat else { break }
            let legal = rules.legalActions(in: state, for: seat)
            if legal.contains(.check) {
                _ = rules.apply(.check, to: &state, generator: &generator)
            } else if legal.contains(.call) {
                _ = rules.apply(.call, to: &state, generator: &generator)
            } else {
                break
            }
        }
        XCTAssertEqual(state.street, .flop)
        XCTAssertEqual(state.community.count, 3)
        XCTAssertEqual(state.currentBet, 0, "a new street starts with nothing to call")
    }

    func testFoldingEveryoneElseEndsTheHandWithoutAShowdown() {
        var (state, generator, _) = start(players: 3)
        var safety = 0
        while !state.handComplete && safety < 12 {
            safety += 1
            guard let seat = state.activeSeat else { break }
            let legal = rules.legalActions(in: state, for: seat)
            if legal.contains(.fold) {
                _ = rules.apply(.fold, to: &state, generator: &generator)
            } else if legal.contains(.check) {
                _ = rules.apply(.check, to: &state, generator: &generator)
            } else {
                break
            }
        }
        XCTAssertTrue(state.handComplete)
        XCTAssertEqual(state.contenders.count, 1)
        XCTAssertTrue(state.revealedHands.isEmpty, "nobody has to show when everyone folds")
    }

    func testMinimumRaiseSizing() {
        var (state, generator, _) = start(players: 4)
        XCTAssertEqual(rules.minimumRaiseTotal(in: state), 40, "one big blind on top of the big blind")
        guard let seat = state.activeSeat else { return XCTFail("no seat") }
        XCTAssertNotNil(rules.rejection(for: .raise(to: 30), in: state), "30 is not a full raise")
        XCTAssertNil(rules.rejection(for: .raise(to: 40), in: state))
        _ = rules.apply(.raise(to: 60), to: &state, generator: &generator)
        XCTAssertEqual(state.currentBet, 60)
        XCTAssertEqual(state.lastRaiseSize, 40)
        XCTAssertEqual(rules.minimumRaiseTotal(in: state), 100, "the next raise must add another 40")
        XCTAssertNotEqual(state.activeSeat, seat)
    }

    func testARaiseReopensTheActionForPlayersWhoAlreadyCalled() {
        var (state, generator, _) = start(players: 3)
        guard let first = state.activeSeat else { return XCTFail("no seat") }
        _ = rules.apply(.call, to: &state, generator: &generator)
        guard let second = state.activeSeat else { return XCTFail("no seat") }
        _ = rules.apply(.raise(to: 100), to: &state, generator: &generator)
        // The first caller owes another action.
        XCTAssertTrue(state.actionQueue.contains(first), "a raise puts the caller back in")
        XCTAssertFalse(state.actionQueue.contains(second), "the raiser does not act again")
    }

    func testAllInForLessThanAFullRaiseDoesNotResetTheMinimum() {
        var (state, generator, _) = start(players: 3, options: ["startingChips": 1000])
        guard let seat = state.activeSeat else { return XCTFail("no seat") }
        _ = rules.apply(.raise(to: 200), to: &state, generator: &generator)
        XCTAssertEqual(state.lastRaiseSize, 180)
        // Shorten a stack so its all-in is a partial raise.
        guard let short = state.activeSeat else { return XCTFail("no seat") }
        state.stacks[short] = 260 - (state.committed[short] ?? 0)
        _ = rules.apply(.allIn, to: &state, generator: &generator)
        XCTAssertEqual(state.currentBet, 260)
        XCTAssertEqual(state.lastRaiseSize, 180, "a short all-in does not become the new minimum")
        XCTAssertFalse(state.actionQueue.contains(seat) && (state.committed[seat] ?? 0) >= 260)
    }

    func testShowdownRevealsHandsAndAwardsThePot() {
        var (state, generator, _) = start(players: 2, seed: 5150)
        var safety = 0
        while !state.handComplete && safety < 60 {
            safety += 1
            guard let seat = state.activeSeat else { break }
            let legal = rules.legalActions(in: state, for: seat)
            if legal.contains(.check) {
                _ = rules.apply(.check, to: &state, generator: &generator)
            } else if legal.contains(.call) {
                _ = rules.apply(.call, to: &state, generator: &generator)
            } else {
                break
            }
        }
        XCTAssertTrue(state.handComplete)
        XCTAssertEqual(state.street, .showdown)
        XCTAssertEqual(state.community.count, 5)
        XCTAssertEqual(state.revealedHands.count, 2, "both hands are shown at a showdown")
        XCTAssertEqual(state.lastPayouts.values.reduce(0, +), state.pot)
    }

    func testChipsAreConservedAcrossAWholeHand() {
        var (state, generator, configuration) = start(players: 4, seed: 3141)
        let startingTotal = state.stacks.values.reduce(0, +)
        var safety = 0
        while !state.handComplete && safety < 200 {
            safety += 1
            guard let seat = state.activeSeat else { break }
            let legal = rules.legalActions(in: state, for: seat)
            guard let action = legal.last else { break }   // last is usually all-in
            _ = rules.apply(action, to: &state, generator: &generator)
        }
        let endingTotal = state.stacks.values.reduce(0, +)
        XCTAssertEqual(endingTotal, startingTotal, "chips cannot be created or destroyed")
        XCTAssertEqual(configuration.seating.count, 4)
    }

    func testChipsAreConservedAcrossAWholeGame() {
        for seed in UInt64(1)...10 {
            let configuration = TestTable.configuration(.texasHoldem, humans: 1, ai: 3,
                                                        options: ["startingChips": 400,
                                                                  "smallBlind": 10,
                                                                  "bigBlind": 20,
                                                                  "handLimit": 40],
                                                        seed: seed)
            let outcome = TestTable.playOut(rules, configuration: configuration, maximumMoves: 4000)
            let total = outcome.state.stacks.values.reduce(0, +)
            XCTAssertEqual(total, 1600, "seed \(seed): chips leaked")
            XCTAssertNotNil(outcome.state.finalResult)
        }
    }

    func testGameEndsWhenOnePlayerHasEveryChip() {
        let configuration = TestTable.configuration(.texasHoldem, humans: 1, ai: 2,
                                                    options: ["startingChips": 100,
                                                              "smallBlind": 10,
                                                              "bigBlind": 20],
                                                    seed: 777)
        let outcome = TestTable.playOut(rules, configuration: configuration, maximumMoves: 4000)
        guard let result = outcome.state.finalResult else { return XCTFail("game never ended") }
        XCTAssertEqual(result.winners.count, 1)
        XCTAssertEqual(outcome.state.stacks.values.reduce(0, +), 300)
    }

    func testObservationNeverContainsAnotherPlayersCards() {
        let (state, _, _) = start(players: 4)
        for seat in state.seatOrder {
            let observation = rules.observation(of: state, for: seat)
            XCTAssertEqual(observation.hole.count, 2)
            let ownIDs = Set(state.board.contents(of: .hand(seat)))
            XCTAssertEqual(Set(observation.hole.map(\.id)), ownIDs)
            for other in state.seatOrder where other != seat {
                let otherIDs = Set(state.board.contents(of: .hand(other)))
                XCTAssertTrue(Set(observation.hole.map(\.id)).isDisjoint(with: otherIDs))
            }
            XCTAssertTrue(observation.community.isEmpty, "no board is dealt pre-flop")
        }
    }

    func testHoleCardsStayPrivateUntilShowdown() {
        let (state, _, _) = start(players: 4)
        let view = state.board.redacted(for: SeatID(0))
        for seat in state.seatOrder where seat != SeatID(0) {
            XCTAssertTrue(view.contents(of: .hand(seat)).allSatisfy { !$0.isKnown })
        }
        XCTAssertTrue(view.contents(of: .stock).allSatisfy { !$0.isKnown }, "the deck stays unknown")
    }

    func testBurnCardsAreNeverVisible() {
        var (state, generator, _) = start(players: 2)
        var safety = 0
        while state.street == .preflop && safety < 10 {
            safety += 1
            guard let seat = state.activeSeat else { break }
            let legal = rules.legalActions(in: state, for: seat)
            if legal.contains(.check) { _ = rules.apply(.check, to: &state, generator: &generator) }
            else if legal.contains(.call) { _ = rules.apply(.call, to: &state, generator: &generator) }
            else { break }
        }
        XCTAssertEqual(state.board.count(in: .reserve), 1, "one card is burned before the flop")
        let view = state.board.redacted(for: SeatID(0))
        XCTAssertTrue(view.contents(of: .reserve).allSatisfy { !$0.isKnown })
    }
}

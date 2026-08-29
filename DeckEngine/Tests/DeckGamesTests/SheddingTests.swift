import XCTest
import DeckCore
@testable import DeckGames

private func cardIDs(_ tokens: String...) -> [CardID] { tokens.map { Card(token: $0)!.id } }
private func deck(_ tokens: String...) -> [Card] { tokens.map { Card(token: $0)! } }

final class PresidentTests: XCTestCase {
    private let rules = PresidentRules()

    private func fresh(players: Int = 4, seed: UInt64 = 77) -> PresidentRules.State {
        let configuration = TestTable.configuration(.president, humans: 1, ai: players - 1, seed: seed)
        var generator = SeededGenerator(seed: seed)
        return rules.setup(configuration: configuration, generator: &generator)
    }

    func testTheWholeDeckIsDealtOut() {
        let state = fresh()
        let total = state.seatOrder.reduce(0) { $0 + state.board.count(in: .hand($1)) }
        XCTAssertEqual(total, 52)
        XCTAssertEqual(state.board.count(in: .stock), 0)
        // Four players get thirteen each; five would get an uneven split, which
        // is how the game is actually dealt.
        XCTAssertTrue(state.seatOrder.allSatisfy { state.board.count(in: .hand($0)) == 13 })
    }

    func testTheThreeOfClubsOpens() {
        for seed in UInt64(1)...20 {
            let state = fresh(seed: seed)
            let opener = state.activeSeat!
            XCTAssertTrue(state.hand(opener).contains { $0.token == "3C" },
                          "whoever holds the three of clubs leads, seed \(seed)")
        }
    }

    func testThreeIsLowAndTwoIsTheBomb() {
        XCTAssertLessThan(PresidentRules.power(.three, twosAreBombs: true),
                          PresidentRules.power(.four, twosAreBombs: true))
        XCTAssertLessThan(PresidentRules.power(.king, twosAreBombs: true),
                          PresidentRules.power(.ace, twosAreBombs: true))
        XCTAssertGreaterThan(PresidentRules.power(.two, twosAreBombs: true),
                             PresidentRules.power(.ace, twosAreBombs: true))
        // With the house rule off a two still outranks an ace — it just no
        // longer ignores the count or sweeps the pile.
        XCTAssertGreaterThan(PresidentRules.power(.two, twosAreBombs: false),
                             PresidentRules.power(.ace, twosAreBombs: false))
    }

    func testYouMustMatchTheCountAndBeatTheRank() {
        var state = fresh()
        let seat = state.seatOrder[0]
        state.activeSeat = seat
        TestTable.setHand(deck("7C", "7H", "7S", "5D", "5H", "2C"), for: seat, in: &state.board)
        state.leadRank = .six
        state.leadCount = 2
        state.lastPlayer = state.seatOrder[1]

        XCTAssertNil(rules.rejection(for: .play(cardIDs("7C", "7H")), in: state))
        XCTAssertEqual(rules.rejection(for: .play(cardIDs("7C")), in: state)?.reason, "matchTheCount")
        XCTAssertEqual(rules.rejection(for: .play(cardIDs("5D", "5H")), in: state)?.reason, "mustBeatRank")
        XCTAssertEqual(rules.rejection(for: .play(cardIDs("7C", "5D")), in: state)?.reason, "sameRankOnly")
    }

    func testABombIgnoresTheCount() {
        var state = fresh()
        let seat = state.seatOrder[0]
        state.activeSeat = seat
        TestTable.setHand(deck("2C", "4D", "4H"), for: seat, in: &state.board)
        state.leadRank = .ace
        state.leadCount = 3
        state.lastPlayer = state.seatOrder[1]
        XCTAssertNil(rules.rejection(for: .play(cardIDs("2C")), in: state),
                     "a single two beats three aces")
    }

    func testTheLeaderCannotPass() {
        var state = fresh()
        state.activeSeat = state.seatOrder[0]
        state.leadRank = nil
        XCTAssertEqual(rules.rejection(for: .pass, in: state)?.reason, "mustLead")
        state.leadRank = .seven
        state.leadCount = 1
        XCTAssertNil(rules.rejection(for: .pass, in: state))
    }

    func testPlayingABombSweepsThePileAndKeepsTheLead() {
        var state = fresh()
        let seat = state.seatOrder[0]
        state.activeSeat = seat
        TestTable.setHand(deck("2C", "9D", "9H"), for: seat, in: &state.board)
        state.leadRank = .king
        state.leadCount = 1
        state.lastPlayer = state.seatOrder[1]
        var generator = SeededGenerator(seed: 1)
        _ = rules.apply(.play(cardIDs("2C")), to: &state, generator: &generator)

        XCTAssertEqual(state.activeSeat, seat, "the bomber leads again")
        XCTAssertNil(state.leadRank, "the pile is gone, so anything can be led")
        XCTAssertEqual(state.leadCount, 0)
        XCTAssertEqual(state.bombsPlayed[seat], 1)
        XCTAssertEqual(state.board.count(in: .discard), 0, "the pile is swept away")
    }

    func testCompletingTheRankAlsoClearsThePile() {
        var state = fresh()
        let seat = state.seatOrder[0]
        state.activeSeat = seat
        TestTable.setHand(deck("6C", "6D", "6H", "6S", "9C"), for: seat, in: &state.board)
        state.leadRank = .five
        state.leadCount = 4
        state.lastPlayer = state.seatOrder[1]

        var generator = SeededGenerator(seed: 2)
        _ = rules.apply(.play(cardIDs("6C", "6D", "6H", "6S")), to: &state, generator: &generator)
        XCTAssertEqual(state.activeSeat, seat, "all four of a rank sweeps and holds the lead")
        XCTAssertNil(state.leadRank)
    }

    func testEmptyingYourHandRecordsYourPlace() {
        var state = fresh()
        let seat = state.seatOrder[0]
        state.activeSeat = seat
        TestTable.setHand(deck("9C", "9H"), for: seat, in: &state.board)
        state.leadRank = .eight
        state.leadCount = 2
        state.lastPlayer = state.seatOrder[1]

        var generator = SeededGenerator(seed: 3)
        _ = rules.apply(.play(cardIDs("9C", "9H")), to: &state, generator: &generator)
        XCTAssertEqual(state.finishOrder, [seat])
        XCTAssertNotEqual(state.activeSeat, seat, "play moves on without them")
        // Even if the turn somehow came back around, a finished player has no moves.
        state.activeSeat = seat
        XCTAssertTrue(rules.legalActions(in: state, for: seat).isEmpty,
                      "a player who is out has nothing left to do")
    }

    func testEverybodyPassingClearsThePileForTheLastPlayer() {
        var state = fresh(players: 3)
        let leader = state.seatOrder[0]
        let second = state.seatOrder[1]
        let third = state.seatOrder[2]
        state.leadRank = .king
        state.leadCount = 1
        state.lastPlayer = leader
        state.passedSeats = []
        state.activeSeat = second

        var generator = SeededGenerator(seed: 4)
        _ = rules.apply(.pass, to: &state, generator: &generator)
        XCTAssertEqual(state.activeSeat, third)
        _ = rules.apply(.pass, to: &state, generator: &generator)

        XCTAssertEqual(state.activeSeat, leader, "the pile comes back to whoever played last")
        XCTAssertNil(state.leadRank)
        XCTAssertTrue(state.passedSeats.isEmpty)
    }

    func testAFullGameFinishesWithEveryoneRanked() throws {
        let configuration = TestTable.configuration(.president, humans: 1, ai: 3)
        let outcome = TestTable.playOut(rules, configuration: configuration)
        let result = try XCTUnwrap(outcome.state.finalResult)
        XCTAssertEqual(Set(result.placements), Set(outcome.state.seatOrder),
                       "everybody gets a place, president to scum")
        XCTAssertEqual(result.winners.count, 1)
        XCTAssertGreaterThan(outcome.state.roundNumber, 1, "president is played over several deals")
    }

    func testObservationCountsOpponentCardsWithoutNamingThem() {
        let state = fresh()
        let seat = state.seatOrder[0]
        let observation = rules.observation(of: state, for: seat)
        XCTAssertEqual(observation.hand.count, 13)
        XCTAssertEqual(observation.opponentCardCounts.count, 3)
        XCTAssertTrue(observation.opponentCardCounts.values.allSatisfy { $0 == 13 })
        let mine = Set(observation.hand.map(\.id))
        var theirs: Set<CardID> = []
        for other in state.seatOrder where other != seat {
            theirs.formUnion(state.board.contents(of: .hand(other)))
        }
        XCTAssertTrue(mine.isDisjoint(with: theirs))
    }
}

final class CheatTests: XCTestCase {
    private let rules = CheatRules()

    private func fresh(players: Int = 4, seed: UInt64 = 64) -> CheatRules.State {
        let configuration = TestTable.configuration(.cheat, humans: 1, ai: players - 1, seed: seed)
        var generator = SeededGenerator(seed: seed)
        return rules.setup(configuration: configuration, generator: &generator)
    }

    func testTheWholeDeckIsDealtAndThePileStartsEmpty() {
        let state = fresh()
        let total = state.seatOrder.reduce(0) { $0 + state.board.count(in: .hand($1)) }
        XCTAssertEqual(total, 52)
        XCTAssertEqual(state.pileCount, 0)
        XCTAssertEqual(state.phase, .laying)
    }

    func testLaidCardsGoDownFaceDownAndStayThere() {
        var state = fresh()
        let seat = state.activeSeat!
        let card = state.hand(seat)[0]
        var generator = SeededGenerator(seed: 1)
        _ = rules.apply(.lay(cards: [card.id], claiming: state.requiredRank),
                        to: &state, generator: &generator)

        XCTAssertEqual(state.board.zone(of: card.id), Zone.discard)
        XCTAssertFalse(state.board.isFaceUp(card.id))
        for viewer in state.seatOrder {
            let redacted = state.board.redacted(for: viewer)
            XCTAssertFalse(redacted.knownCards.contains(card.id),
                           "not even the player who put it there gets to check")
        }
    }

    func testABluffIsAllowedAndCounted() {
        var state = fresh()
        let seat = state.seatOrder[0]
        state.activeSeat = seat
        state.requiredRank = .seven
        TestTable.setHand(deck("2C", "3D", "9H", "KS"), for: seat, in: &state.board)

        // Claiming sevens while holding none is the whole game.
        XCTAssertNil(rules.rejection(for: .lay(cards: cardIDs("2C"), claiming: .seven), in: state))
        var generator = SeededGenerator(seed: 2)
        _ = rules.apply(.lay(cards: cardIDs("2C"), claiming: .seven), to: &state, generator: &generator)
        XCTAssertEqual(state.bluffsMade[seat], 1)
        XCTAssertEqual(state.claimedRank, .seven)
        XCTAssertEqual(state.claimedCount, 1)
        XCTAssertEqual(state.phase, .challenging)
    }

    func testYouMustClaimTheRankThePileIsOn() {
        var state = fresh()
        state.activeSeat = state.seatOrder[0]
        state.requiredRank = .nine
        TestTable.setHand(deck("2C", "3D"), for: state.seatOrder[0], in: &state.board)
        XCTAssertEqual(rules.rejection(for: .lay(cards: cardIDs("2C"), claiming: .four), in: state)?.reason,
                       "mustClaimNextRank")
        XCTAssertNil(rules.rejection(for: .lay(cards: cardIDs("2C"), claiming: .nine), in: state))
    }

    func testTooManyCardsAndDuplicatesAreRefused() {
        var state = fresh()
        state.activeSeat = state.seatOrder[0]
        state.requiredRank = .five
        TestTable.setHand(deck("2C", "3D", "4H", "5S", "6C"), for: state.seatOrder[0], in: &state.board)
        let tooMany = cardIDs("2C", "3D", "4H", "5S", "6C")
        XCTAssertEqual(rules.rejection(for: .lay(cards: tooMany, claiming: .five), in: state)?.reason,
                       "layOneToFour")
        let twice = cardIDs("2C", "2C")
        XCTAssertEqual(rules.rejection(for: .lay(cards: twice, claiming: .five), in: state)?.reason,
                       "duplicateCards")
    }

    func testCatchingABluffGivesThePileToTheLiar() throws {
        var state = fresh(players: 3)
        let liar = state.seatOrder[0]
        let caller = state.seatOrder[1]
        state.activeSeat = liar
        state.requiredRank = .eight
        TestTable.setHand(deck("2C", "3D", "9H"), for: liar, in: &state.board)
        let liarHandBefore = state.board.count(in: .hand(liar))

        var generator = SeededGenerator(seed: 3)
        _ = rules.apply(.lay(cards: cardIDs("2C"), claiming: .eight), to: &state, generator: &generator)
        state.activeSeat = caller
        _ = rules.apply(.challenge, to: &state, generator: &generator)

        let outcome = try XCTUnwrap(state.lastChallenge)
        XCTAssertFalse(outcome.claimWasTrue)
        XCTAssertEqual(outcome.loser, liar)
        XCTAssertEqual(state.bluffsCaught[caller], 1)

        _ = rules.advanceAutomatically(&state, generator: &generator)
        XCTAssertEqual(state.pileCount, 0, "the pile is swept up")
        XCTAssertEqual(state.board.count(in: .hand(liar)), liarHandBefore,
                       "the liar takes their own card back, and the rest of the pile with it")
    }

    func testCallingAnHonestPlayerCostsYouThePile() throws {
        var state = fresh(players: 3)
        let honest = state.seatOrder[0]
        let caller = state.seatOrder[1]
        state.activeSeat = honest
        state.requiredRank = .eight
        TestTable.setHand(deck("8C", "3D", "9H"), for: honest, in: &state.board)
        let callerHandBefore = state.board.count(in: .hand(caller))

        var generator = SeededGenerator(seed: 4)
        _ = rules.apply(.lay(cards: cardIDs("8C"), claiming: .eight), to: &state, generator: &generator)
        state.activeSeat = caller
        _ = rules.apply(.challenge, to: &state, generator: &generator)

        let outcome = try XCTUnwrap(state.lastChallenge)
        XCTAssertTrue(outcome.claimWasTrue)
        XCTAssertEqual(outcome.loser, caller)
        XCTAssertEqual(state.badCalls[caller], 1)

        _ = rules.advanceAutomatically(&state, generator: &generator)
        XCTAssertEqual(state.board.count(in: .hand(caller)), callerHandBefore + 1,
                       "a bad call picks the whole pile up")
        XCTAssertEqual(state.pileCount, 0)
    }

    func testAChallengeOnlyRevealsTheCardsThatWereJustLaid() {
        var state = fresh(players: 3)
        let layer = state.seatOrder[0]
        let caller = state.seatOrder[1]
        var generator = SeededGenerator(seed: 5)

        // One card goes down and is believed, so it stays face down.
        state.activeSeat = layer
        state.requiredRank = .four
        TestTable.setHand(deck("4C", "4D", "9H"), for: layer, in: &state.board)
        _ = rules.apply(.lay(cards: cardIDs("4C"), claiming: .four), to: &state, generator: &generator)
        for seat in state.challengeQueue {
            state.activeSeat = seat
            _ = rules.apply(.believe, to: &state, generator: &generator)
        }

        // A second card goes down and is challenged.
        state.activeSeat = layer
        _ = rules.apply(.lay(cards: cardIDs("4D"), claiming: state.requiredRank),
                        to: &state, generator: &generator)
        state.activeSeat = caller
        _ = rules.apply(.challenge, to: &state, generator: &generator)

        let redacted = state.board.redacted(for: caller)
        XCTAssertTrue(redacted.knownCards.contains(Card(token: "4D")!.id),
                      "the cards under dispute are turned over")
        XCTAssertFalse(redacted.knownCards.contains(Card(token: "4C")!.id),
                       "nobody gets to sift back through the rest of the pile")
    }

    func testAFullGameFinishes() throws {
        let configuration = TestTable.configuration(.cheat, humans: 1, ai: 3)
        let outcome = TestTable.playOut(rules, configuration: configuration)
        let result = try XCTUnwrap(outcome.state.finalResult)
        XCTAssertEqual(result.winners.count, 1)
        let winner = result.winners[0]
        let held = outcome.state.board.count(in: Zone.hand(winner))
        let limit = outcome.state.settings.turnLimit
        if limit > 0 && outcome.state.turnsTaken >= limit {
            // The round was called. Cheat between players who count well is a
            // treadmill, so most games end this way rather than with somebody
            // going out, and the winner is whoever is holding fewest.
            for seat in outcome.state.seatOrder {
                XCTAssertLessThanOrEqual(held, outcome.state.board.count(in: Zone.hand(seat)),
                                         "a called round is won on the fewest cards")
            }
        } else {
            XCTAssertEqual(held, 0, "you win by getting rid of every card")
        }
    }

    func testObservationNeverNamesThePileOrAnotherHand() {
        var state = fresh()
        var generator = SeededGenerator(seed: 6)
        let layer = state.activeSeat!
        let laid = state.hand(layer)[0]
        _ = rules.apply(.lay(cards: [laid.id], claiming: state.requiredRank),
                        to: &state, generator: &generator)

        let watcher = state.seatOrder.first { $0 != layer }!
        let observation = rules.observation(of: state, for: watcher)
        let mine = Set(observation.hand.map(\.id))
        XCTAssertFalse(mine.contains(laid.id))
        XCTAssertEqual(observation.pileCount, 1, "you know how big the pile is, not what is in it")
        XCTAssertEqual(observation.claimedCount, 1)
        XCTAssertEqual(observation.lastLayer, layer)
        // Your own rank counts are exactly what you can see in your own hand.
        let expected = Dictionary(grouping: observation.hand.compactMap(\.rank), by: { $0 })
            .mapValues(\.count)
        XCTAssertEqual(observation.ownRankCounts, expected)
    }
}

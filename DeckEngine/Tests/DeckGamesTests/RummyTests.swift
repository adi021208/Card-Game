import XCTest
import DeckCore
@testable import DeckGames

private func cards(_ tokens: String...) -> [Card] { tokens.map { Card(token: $0)! } }

final class GinRummyTests: XCTestCase {
    private let rules = GinRummyRules()

    private func fresh(seed: UInt64 = 91) -> GinRummyRules.State {
        let configuration = TestTable.configuration(.ginRummy, humans: 1, ai: 1, seed: seed)
        var generator = SeededGenerator(seed: seed)
        return rules.setup(configuration: configuration, generator: &generator)
    }

    func testDealIsTenEachWithAnUpcard() {
        let state = fresh()
        for seat in state.seatOrder {
            XCTAssertEqual(state.board.count(in: .hand(seat)), 10)
        }
        XCTAssertEqual(state.board.count(in: .discard), 1)
        XCTAssertEqual(state.board.count(in: .stock), 52 - 21)
        XCTAssertTrue(state.openingUpcard)
    }

    func testTheNonDealerGetsFirstRefusalOfTheUpcard() {
        let state = fresh()
        XCTAssertNotEqual(state.activeSeat, state.dealerSeat)
        let actions = rules.legalActions(in: state, for: state.activeSeat!)
        XCTAssertTrue(actions.contains(.takeDiscard))
        XCTAssertTrue(actions.contains(.passUpcard), "the opening upcard may be declined")
        XCTAssertFalse(actions.contains(.drawFromStock),
                       "the stock is not open until the upcard has been refused twice")
    }

    func testTwoRefusalsOpenTheStock() {
        var state = fresh()
        var generator = SeededGenerator(seed: 2)
        _ = rules.apply(.passUpcard, to: &state, generator: &generator)
        _ = rules.apply(.passUpcard, to: &state, generator: &generator)
        XCTAssertFalse(state.openingUpcard, "the opening formality is over")
        let actions = rules.legalActions(in: state, for: state.activeSeat!)
        XCTAssertTrue(actions.contains(.drawFromStock))
        XCTAssertFalse(actions.contains(.passUpcard))
    }

    func testDrawingThenDiscardingKeepsTheHandAtTen() {
        var state = fresh()
        var generator = SeededGenerator(seed: 3)
        _ = rules.apply(.takeDiscard, to: &state, generator: &generator)
        let seat = state.activeSeat!
        XCTAssertEqual(state.phase, .discard)
        XCTAssertEqual(state.board.count(in: .hand(seat)), 11, "eleven in hand while choosing")
        let discard = rules.legalActions(in: state, for: seat).compactMap { action -> CardID? in
            if case let .discard(id) = action { return id }
            return nil
        }.first!
        _ = rules.apply(.discard(discard), to: &state, generator: &generator)
        XCTAssertEqual(state.board.count(in: .hand(seat)), 10)
        XCTAssertNotEqual(state.activeSeat, seat, "the turn passes on the discard")
        XCTAssertEqual(state.phase, .draw)
    }

    func testYouCannotDiscardTheCardYouJustTookFromTheDiscardPile() {
        var state = fresh()
        var generator = SeededGenerator(seed: 4)
        let upcard = state.board.top(of: .discard)!
        _ = rules.apply(.takeDiscard, to: &state, generator: &generator)
        XCTAssertEqual(rules.rejection(for: .discard(upcard.id), in: state)?.reason,
                       "cannotReturnUpcard")
        XCTAssertEqual(rules.rejection(for: .knock(upcard.id), in: state)?.reason,
                       "cannotReturnUpcard",
                       "knocking with it is the same move by another name")
        let offered = rules.legalActions(in: state, for: state.activeSeat!)
        XCTAssertFalse(offered.contains(.discard(upcard.id)),
                       "and it is never offered in the first place")
        let discards = offered.filter { if case .discard = $0 { return true }; return false }
        XCTAssertEqual(discards.count, 10, "the other ten cards are all fair game")
    }

    func testKnockingIsOnlyOfferedWhenTheHandIsLowEnough() {
        var state = fresh()
        // A hand of ten unrelated high cards can never knock.
        TestTable.setHand(cards("KC", "KH", "QS", "QD", "JC", "JH", "TS", "TD", "9C", "9H", "8S"),
                          for: state.seatOrder[0], in: &state.board)
        state.activeSeat = state.seatOrder[0]
        state.phase = .discard
        let actions = rules.legalActions(in: state, for: state.seatOrder[0])
        XCTAssertFalse(actions.contains { if case .knock = $0 { return true }; return false },
                       "ninety-odd points of deadwood cannot knock")
        XCTAssertEqual(actions.count, 11, "every card is still a legal discard")
    }

    func testAKnockableHandOffersTheKnock() {
        var state = fresh()
        // Three melds, one loose ace, plus the card to throw.
        TestTable.setHand(cards("4C", "5C", "6C", "9H", "9D", "9S", "JS", "QS", "KS", "AH", "8D"),
                          for: state.seatOrder[0], in: &state.board)
        state.activeSeat = state.seatOrder[0]
        state.phase = .discard
        let actions = rules.legalActions(in: state, for: state.seatOrder[0])
        let knocks = actions.compactMap { action -> CardID? in
            if case let .knock(id) = action { return id }
            return nil
        }
        XCTAssertTrue(knocks.contains(Card(token: "8D")!.id),
                      "throwing the eight leaves one point of deadwood")
    }

    func testGinScoresTheBonusAndTheOpponentsWholeHand() throws {
        var state = fresh()
        let knocker = state.seatOrder[0]
        let defender = state.seatOrder[1]
        // Knocker: three melds plus the card being thrown away.
        TestTable.setHand(cards("4C", "5C", "6C", "9H", "9D", "9S", "JS", "QS", "KS", "2H"),
                          for: knocker, in: &state.board)
        // Defender: nothing that melds and nothing that lays off.
        TestTable.setHand(cards("2C", "3D", "5H", "7S", "8H", "TC", "JD", "QH", "KD", "AS"),
                          for: defender, in: &state.board)
        state.activeSeat = knocker
        state.phase = .discard
        state.scores = [knocker: 0, defender: 0]

        var generator = SeededGenerator(seed: 5)
        _ = rules.apply(.knock(Card(token: "2H")!.id), to: &state, generator: &generator)

        let summary = try XCTUnwrap(state.lastKnock)
        XCTAssertTrue(summary.wasGin)
        XCTAssertEqual(summary.knockerDeadwood, 0)
        let defenderPoints = 2 + 3 + 5 + 7 + 8 + 10 + 10 + 10 + 10 + 1
        XCTAssertEqual(summary.defenderDeadwood, defenderPoints,
                       "after gin the defender lays nothing off")
        XCTAssertEqual(state.scores[knocker], defenderPoints + state.settings.ginBonus)
        XCTAssertEqual(state.scores[defender], 0)
        XCTAssertEqual(state.ginsScored[knocker], 1)
        XCTAssertEqual(state.phase, .roundOver)
    }

    func testAnUndercutScoresForTheDefender() throws {
        var state = fresh()
        let knocker = state.seatOrder[0]
        let defender = state.seatOrder[1]
        // Knocker: three melds, a stranded nine, and the card to throw.
        TestTable.setHand(cards("4H", "5H", "6H", "KD", "KS", "KH", "2S", "3S", "4S", "9C", "2H"),
                          for: knocker, in: &state.board)
        // Defender: three melds and a lone deuce — two points.
        TestTable.setHand(cards("3D", "4D", "5D", "7H", "7C", "7S", "TC", "JC", "QC", "2C"),
                          for: defender, in: &state.board)
        state.activeSeat = knocker
        state.phase = .discard
        state.scores = [knocker: 0, defender: 0]

        var generator = SeededGenerator(seed: 6)
        _ = rules.apply(.knock(Card(token: "2H")!.id), to: &state, generator: &generator)

        let summary = try XCTUnwrap(state.lastKnock)
        XCTAssertFalse(summary.wasGin)
        XCTAssertTrue(summary.wasUndercut, "two beats nine, so the knocker is undercut")
        XCTAssertEqual(summary.knockerDeadwood, 9)
        XCTAssertEqual(summary.defenderDeadwood, 2)
        XCTAssertEqual(state.scores[defender], 7 + state.settings.undercutBonus)
        XCTAssertEqual(state.scores[knocker], 0)
        XCTAssertEqual(state.undercuts[defender], 1)
    }

    func testTheDefenderLaysOffOntoTheKnockersMelds() throws {
        var state = fresh()
        let knocker = state.seatOrder[0]
        let defender = state.seatOrder[1]
        // Knocker melds ace-to-six of clubs and the nines, with a seven loose.
        TestTable.setHand(cards("AC", "2C", "3C", "4C", "5C", "6C", "9H", "9D", "9S", "7D", "KH"),
                          for: knocker, in: &state.board)
        // Defender holds the seven of clubs, which extends the knocker's run to
        // seven cards, plus a meld of kings and a spread of odds and ends.
        TestTable.setHand(cards("KC", "KD", "KS", "2D", "3H", "4H", "5S", "6H", "8S", "7C"),
                          for: defender, in: &state.board)
        state.activeSeat = knocker
        state.phase = .discard
        state.scores = [knocker: 0, defender: 0]

        var generator = SeededGenerator(seed: 7)
        _ = rules.apply(.knock(Card(token: "KH")!.id), to: &state, generator: &generator)

        let summary = try XCTUnwrap(state.lastKnock)
        XCTAssertFalse(summary.wasGin)
        XCTAssertEqual(summary.knockerDeadwood, 7, "only the seven of diamonds is loose")
        XCTAssertEqual(summary.defenderDeadwood, 2 + 3 + 4 + 5 + 6 + 8,
                       "the seven of clubs goes onto the knocker's run and stops counting")
        XCTAssertEqual(state.scores[knocker], 28 - 7, "the knocker still wins the difference")
        XCTAssertEqual(state.scores[defender], 0)
    }

    func testAFullGameReachesATargetScore() throws {
        let configuration = TestTable.configuration(.ginRummy, humans: 1, ai: 1)
        // Knocking is a judgement call, not the obvious move, so legalActions
        // offers every discard alongside the knock that discard would allow —
        // and the discard comes first. Take the head of the list every turn and
        // nobody ever knocks: every deal runs the stock out, washes out at
        // nil-nil, redeals, and the target score is never approached. Knock at
        // the first opportunity instead. It is impatient, but it is a real way
        // to play, and it is the only driver here that can end a Gin game.
        // Knock the moment it is legal, and otherwise play arbitrarily rather
        // than always taking the head of the list — which means taking the
        // discard every turn whatever it is, so the hand never improves and the
        // knock never becomes legal at all.
        let otherwise: (GinRummyRules.State, [GinRummyRules.Action]) -> GinRummyRules.Action
            = TestTable.anyLegal(seed: 31337)
        let outcome = TestTable.playOut(rules, configuration: configuration) { state, legal in
            for action in legal { if case .knock = action { return action } }
            return otherwise(state, legal)
        }
        let result = try XCTUnwrap(outcome.state.finalResult, "stopped because it \(outcome.stop)")
        XCTAssertEqual(result.winners.count, 1)
        let best = outcome.state.scores.values.max() ?? 0
        XCTAssertGreaterThanOrEqual(best, outcome.state.settings.targetScore)
    }

    func testObservationShowsCountsNotCards() {
        let state = fresh()
        let seat = state.seatOrder[0]
        let observation = rules.observation(of: state, for: seat)
        XCTAssertEqual(observation.hand.count, 10)
        XCTAssertEqual(observation.opponentCardCount, 10,
                       "you learn how many they hold, never which")
        XCTAssertEqual(observation.stockCount, 31)
        XCTAssertNotNil(observation.discardTop, "the upcard is face up and fair game")
        let mine = Set(observation.hand.map(\.id))
        let theirs = Set(state.board.contents(of: .hand(state.seatOrder[1])))
        XCTAssertTrue(mine.isDisjoint(with: theirs))
    }

    func testTakingFromTheDiscardIsPublicKnowledge() {
        var state = fresh()
        var generator = SeededGenerator(seed: 8)
        let taken = state.board.top(of: .discard)!
        let taker = state.activeSeat!
        _ = rules.apply(.takeDiscard, to: &state, generator: &generator)
        let watcher = state.seatOrder.first { $0 != taker }!
        let observation = rules.observation(of: state, for: watcher)
        XCTAssertTrue(observation.opponentTookFromDiscard.contains { $0.id == taken.id },
                      "everyone saw them take it, so everyone remembers")
    }
}

final class RummyTests: XCTestCase {
    private let rules = RummyRules()

    private func fresh(players: Int = 3, seed: UInt64 = 55) -> RummyRules.State {
        let configuration = TestTable.configuration(.rummy, humans: 1, ai: players - 1, seed: seed)
        var generator = SeededGenerator(seed: seed)
        return rules.setup(configuration: configuration, generator: &generator)
    }

    func testDealSizeFollowsTheTableSize() {
        let three = fresh(players: 3)
        for seat in three.seatOrder {
            XCTAssertEqual(three.board.count(in: .hand(seat)), three.settings.handSize)
        }
        XCTAssertEqual(three.board.count(in: .discard), 1)
    }

    func testATurnIsDrawThenBuildThenDiscard() {
        var state = fresh()
        var generator = SeededGenerator(seed: 9)
        XCTAssertEqual(state.phase, .draw)
        let seat = state.activeSeat!
        let before = state.board.count(in: .hand(seat))
        _ = rules.apply(.drawFromStock, to: &state, generator: &generator)
        XCTAssertEqual(state.phase, .build)
        XCTAssertEqual(state.board.count(in: .hand(seat)), before + 1)

        let discard = rules.legalActions(in: state, for: seat).compactMap { action -> CardID? in
            if case let .discard(id) = action { return id }
            return nil
        }.first!
        _ = rules.apply(.discard(discard), to: &state, generator: &generator)
        XCTAssertEqual(state.board.count(in: .hand(seat)), before)
        XCTAssertEqual(state.phase, .draw)
        XCTAssertNotEqual(state.activeSeat, seat)
    }

    func testARealMeldGoesToTheTableAndAFakeOneIsRefused() {
        var state = fresh()
        let seat = state.seatOrder[0]
        TestTable.setHand(cards("7C", "7H", "7S", "2D", "9C", "KH", "4S"), for: seat, in: &state.board)
        state.activeSeat = seat
        state.phase = .build

        let good: [CardID] = cards("7C", "7H", "7S").map(\.id)
        XCTAssertNil(rules.rejection(for: .meld(good), in: state))

        let bad: [CardID] = cards("2D", "9C", "KH").map(\.id)
        XCTAssertNotNil(rules.rejection(for: .meld(bad), in: state),
                        "three unrelated cards are not a meld")

        var generator = SeededGenerator(seed: 10)
        _ = rules.apply(.meld(good), to: &state, generator: &generator)
        XCTAssertEqual(state.melds.count, 1)
        XCTAssertEqual(state.melds[0].owner, seat)
        XCTAssertEqual(state.board.count(in: .hand(seat)), 4)
        XCTAssertTrue(state.hasMelded.contains(seat))
    }

    func testACardCanBeLaidOffOntoSomebodyElsesMeld() {
        var state = fresh()
        let owner = state.seatOrder[0]
        let player = state.seatOrder[1]
        TestTable.setHand(cards("5S", "6S", "7S", "2D"), for: owner, in: &state.board)
        TestTable.setHand(cards("8S", "KH", "3C"), for: player, in: &state.board)

        var generator = SeededGenerator(seed: 11)
        state.activeSeat = owner
        state.phase = .build
        _ = rules.apply(.meld(cards("5S", "6S", "7S").map(\.id)), to: &state, generator: &generator)

        state.activeSeat = player
        state.phase = .build
        XCTAssertNil(rules.rejection(for: .layOff(card: Card(token: "8S")!.id, meldIndex: 0), in: state))
        XCTAssertNotNil(rules.rejection(for: .layOff(card: Card(token: "KH")!.id, meldIndex: 0), in: state),
                        "a king does not extend a five-six-seven")

        _ = rules.apply(.layOff(card: Card(token: "8S")!.id, meldIndex: 0), to: &state, generator: &generator)
        XCTAssertEqual(state.meldCards(state.melds[0]).count, 4)
        XCTAssertEqual(state.board.count(in: .hand(player)), 2)
    }

    func testGoingOutEndsTheRoundAndScoresWhatIsLeftInHands() {
        var state = fresh(players: 2)
        let goer = state.seatOrder[0]
        let other = state.seatOrder[1]
        TestTable.setHand(cards("9C", "9H", "9S", "4D"), for: goer, in: &state.board)
        TestTable.setHand(cards("KH", "QD", "3C"), for: other, in: &state.board)
        state.activeSeat = goer
        state.phase = .build
        state.scores = [goer: 0, other: 0]
        // Well past the opening, so this is an ordinary go-out and not a rummy.
        state.turnsTaken = 20

        var generator = SeededGenerator(seed: 12)
        _ = rules.apply(.meld(cards("9C", "9H", "9S").map(\.id)), to: &state, generator: &generator)
        _ = rules.apply(.discard(Card(token: "4D")!.id), to: &state, generator: &generator)

        XCTAssertTrue(state.board.isEmpty(Zone.hand(goer)), "the last card went to the discard")
        XCTAssertEqual(state.phase, .roundOver)
        XCTAssertEqual(state.lastRoundWinner, goer)
        XCTAssertEqual(state.scores[goer], 10 + 10 + 3, "the loser's hand pays the winner")
        XCTAssertEqual(state.scores[other], 0)
        XCTAssertEqual(state.goneOutCount[goer], 1)
    }

    func testGoingOutInOneTurnDoublesTheScore() {
        var state = fresh(players: 2)
        let goer = state.seatOrder[0]
        let other = state.seatOrder[1]
        TestTable.setHand(cards("9C", "9H", "9S", "4D"), for: goer, in: &state.board)
        TestTable.setHand(cards("KH", "QD", "3C"), for: other, in: &state.board)
        state.activeSeat = goer
        state.phase = .build
        state.scores = [goer: 0, other: 0]
        state.turnsTaken = 0

        var generator = SeededGenerator(seed: 14)
        _ = rules.apply(.meld(cards("9C", "9H", "9S").map(\.id)), to: &state, generator: &generator)
        _ = rules.apply(.discard(Card(token: "4D")!.id), to: &state, generator: &generator)

        XCTAssertEqual(state.scores[goer], (10 + 10 + 3) * 2, "a rummy is worth double")
    }

    func testAFullGameFinishes() throws {
        let configuration = TestTable.configuration(.rummy, humans: 1, ai: 2)
        let outcome = TestTable.playOut(rules, configuration: configuration)
        let result = try XCTUnwrap(outcome.state.finalResult, "stopped because it \(outcome.stop)")
        XCTAssertEqual(result.winners.count, 1)
        XCTAssertGreaterThan(outcome.moves, 0)
    }

    func testObservationShowsTableMeldsButNotOpponentHands() {
        var state = fresh()
        let owner = state.seatOrder[0]
        TestTable.setHand(cards("7C", "7H", "7S", "2D"), for: owner, in: &state.board)
        state.activeSeat = owner
        state.phase = .build
        var generator = SeededGenerator(seed: 13)
        _ = rules.apply(.meld(cards("7C", "7H", "7S").map(\.id)), to: &state, generator: &generator)

        let watcher = state.seatOrder[1]
        let observation = rules.observation(of: state, for: watcher)
        XCTAssertEqual(observation.tableMelds.count, 1, "melds on the table are public")
        XCTAssertEqual(observation.tableMelds[0].count, 3)
        let mine = Set(observation.hand.map(\.id))
        let theirs = Set(state.board.contents(of: .hand(owner)))
        XCTAssertTrue(mine.isDisjoint(with: theirs))
        XCTAssertEqual(observation.opponentCardCounts[owner], 1,
                       "you know they are down to one card, not which one")
    }
}

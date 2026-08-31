import XCTest
import DeckCore
@testable import DeckGames

private func deck(_ tokens: String...) -> [Card] { tokens.map { Card(token: $0)! } }

final class GoFishTests: XCTestCase {
    private let rules = GoFishRules()

    private func fresh(players: Int = 3, seed: UInt64 = 33) -> GoFishRules.State {
        let configuration = TestTable.configuration(.goFish, humans: 1, ai: players - 1, seed: seed)
        var generator = SeededGenerator(seed: seed)
        return rules.setup(configuration: configuration, generator: &generator)
    }

    func testDealAndStock() {
        let state = fresh()
        let inHands = state.seatOrder.reduce(0) { $0 + state.board.count(in: .hand($1)) }
        let booked = state.totalBooks * 4
        XCTAssertEqual(inHands + booked + state.board.count(in: .stock), 52,
                       "every card is in a hand, a book or the pond")
    }

    func testFourOfAKindBooksAsSoonAsItIsHeld() {
        // This used to search eighty seeds for a deal that happened to contain
        // four of a kind. A seven-card hand holds one about once in six
        // hundred, so eighty deals across three players found one well under
        // half the time: the search was the thing that was wrong. Build the
        // hand instead and let the turn resolve.
        var state = fresh()
        let asker = state.seatOrder[0]
        let target = state.seatOrder[1]
        TestTable.setHand(deck("7C", "7D", "7H", "7S", "9C"), for: asker, in: &state.board)
        TestTable.setHand(deck("9D", "3S"), for: target, in: &state.board)
        state.activeSeat = asker

        var generator = SeededGenerator(seed: 5)
        _ = rules.apply(.ask(target: target, rank: .nine), to: &state, generator: &generator)

        XCTAssertEqual(state.books[asker] ?? [], [.seven], "four of a kind is a book")
        XCTAssertEqual(state.board.cardList(in: .captured(asker)).filter { $0.rank == .seven }.count, 4,
                       "all four cards go to the book")
        XCTAssertFalse(state.hand(asker).contains { $0.rank == .seven },
                       "a booked rank leaves the hand")
    }

    func testYouCanOnlyAskForARankYouHold() {
        var state = fresh()
        let asker = state.seatOrder[0]
        let target = state.seatOrder[1]
        state.activeSeat = asker
        TestTable.setHand(deck("5C", "9H"), for: asker, in: &state.board)
        TestTable.setHand(deck("5D", "5S", "KH"), for: target, in: &state.board)

        XCTAssertNil(rules.rejection(for: .ask(target: target, rank: .five), in: state))
        XCTAssertEqual(rules.rejection(for: .ask(target: target, rank: .king), in: state)?.reason,
                       "mustHoldRank")
        XCTAssertEqual(rules.rejection(for: .ask(target: asker, rank: .five), in: state)?.reason,
                       "cannotAskYourself")
    }

    func testEveryOfferedAskIsARankYouHold() {
        let state = fresh()
        let seat = state.activeSeat!
        let held = Set(state.hand(seat).compactMap(\.rank))
        for action in rules.legalActions(in: state, for: seat) {
            guard case let .ask(target, rank) = action else { return XCTFail("unexpected action") }
            XCTAssertTrue(held.contains(rank))
            XCTAssertNotEqual(target, seat)
            XCTAssertGreaterThan(state.board.count(in: .hand(target)), 0)
        }
    }

    func testAHitTakesEveryMatchingCardAndKeepsTheTurn() {
        var state = fresh()
        let asker = state.seatOrder[0]
        let target = state.seatOrder[1]
        state.activeSeat = asker
        TestTable.setHand(deck("5C", "9H"), for: asker, in: &state.board)
        TestTable.setHand(deck("5D", "5S", "KH"), for: target, in: &state.board)

        var generator = SeededGenerator(seed: 1)
        _ = rules.apply(.ask(target: target, rank: .five), to: &state, generator: &generator)

        XCTAssertEqual(state.hand(asker).filter { $0.rank == .five }.count, 3,
                       "both fives come across")
        XCTAssertEqual(state.board.count(in: .hand(target)), 1)
        XCTAssertEqual(state.activeSeat, asker, "a hit means another go")
        XCTAssertEqual(state.askHistory.last?.succeeded, true)
    }

    func testAMissDrawsFromThePondAndPassesTheTurn() {
        var state = fresh()
        let asker = state.seatOrder[0]
        let target = state.seatOrder[1]
        state.activeSeat = asker
        TestTable.setHand(deck("5C", "9H"), for: asker, in: &state.board)
        TestTable.setHand(deck("KH", "QD"), for: target, in: &state.board)
        // Park the other fives out of reach so the draw cannot be a lucky one,
        // which would keep the turn and make the test flap.
        TestTable.setHand(deck("5D", "5H", "5S", "2C"), for: state.seatOrder[2], in: &state.board)
        let pondBefore = state.board.count(in: .stock)

        var generator = SeededGenerator(seed: 2)
        _ = rules.apply(.ask(target: target, rank: .five), to: &state, generator: &generator)

        XCTAssertEqual(state.askHistory.last?.succeeded, false)
        XCTAssertEqual(state.board.count(in: .stock), pondBefore - 1, "go fish")
        XCTAssertNotEqual(state.activeSeat, asker)
    }

    func testCompletingASetBooksIt() {
        var state = fresh()
        let asker = state.seatOrder[0]
        let target = state.seatOrder[1]
        state.activeSeat = asker
        TestTable.setHand(deck("5C", "5D", "9H"), for: asker, in: &state.board)
        TestTable.setHand(deck("5H", "5S", "KH"), for: target, in: &state.board)
        let booksBefore = state.books[asker]?.count ?? 0

        var generator = SeededGenerator(seed: 3)
        _ = rules.apply(.ask(target: target, rank: .five), to: &state, generator: &generator)

        XCTAssertEqual(state.books[asker]?.count, booksBefore + 1)
        XCTAssertTrue(state.books[asker]?.contains(.five) ?? false)
        XCTAssertFalse(state.hand(asker).contains { $0.rank == .five }, "the book leaves the hand")
        XCTAssertEqual(state.board.cardList(in: .captured(asker)).filter { $0.rank == .five }.count, 4)
    }

    func testTheAskIsPublicButTheHandIsNot() {
        var state = fresh()
        let asker = state.seatOrder[0]
        let target = state.seatOrder[1]
        state.activeSeat = asker
        TestTable.setHand(deck("5C", "9H"), for: asker, in: &state.board)
        TestTable.setHand(deck("KH", "QD"), for: target, in: &state.board)

        var generator = SeededGenerator(seed: 4)
        _ = rules.apply(.ask(target: target, rank: .five), to: &state, generator: &generator)

        let watcher = state.seatOrder[2]
        let observation = rules.observation(of: state, for: watcher)
        XCTAssertEqual(observation.askHistory.last?.rank, .five,
                       "everyone hears the question and the answer")
        XCTAssertEqual(observation.askHistory.last?.succeeded, false)
        let mine = Set(observation.hand.map(\.id))
        var theirs: Set<CardID> = []
        for other in state.seatOrder where other != watcher {
            theirs.formUnion(state.board.contents(of: .hand(other)))
        }
        XCTAssertTrue(mine.isDisjoint(with: theirs))
        XCTAssertEqual(observation.opponentCardCounts[asker], state.board.count(in: .hand(asker)))
    }

    func testAFullGameBooksAllThirteenRanks() throws {
        let configuration = TestTable.configuration(.goFish, humans: 1, ai: 2)
        let outcome = TestTable.playOut(rules, configuration: configuration,
                                        chooser: TestTable.anyLegal(rules, seed: 909))
        let result = try XCTUnwrap(outcome.state.finalResult, "stopped because it \(outcome.stop)")
        XCTAssertEqual(outcome.state.totalBooks, 13, "all fifty-two cards end up in books")
        XCTAssertFalse(result.winners.isEmpty)
    }
}

final class WarTests: XCTestCase {
    private let rules = WarRules()

    private func fresh(seed: UInt64 = 44) -> WarRules.State {
        let configuration = TestTable.configuration(.war, humans: 1, ai: 1, seed: seed)
        var generator = SeededGenerator(seed: seed)
        return rules.setup(configuration: configuration, generator: &generator)
    }

    func testTheDeckSplitsEvenlyAndFaceDown() {
        let state = fresh()
        for seat in state.seatOrder {
            XCTAssertEqual(state.board.count(in: state.deckZone(seat)), 26)
            XCTAssertEqual(state.totalCards(seat), 26)
            for id in state.board.contents(of: state.deckZone(seat)) {
                XCTAssertFalse(state.board.isFaceUp(id), "your own deck is face down to you too")
                XCTAssertFalse(state.board.redacted(for: seat).knownCards.contains(id))
            }
        }
    }

    func testOneFlipTurnsACardForEverybody() {
        var state = fresh()
        var generator = SeededGenerator(seed: 1)
        _ = rules.apply(.flip, to: &state, generator: &generator)
        XCTAssertEqual(state.board.count(in: .trick), 2)
        XCTAssertTrue(state.pendingResolution, "the cards are down; resolving is the next beat")
        XCTAssertTrue(rules.legalActions(in: state, for: state.seatOrder[0]).isEmpty,
                      "no second flip until the battle is settled")
    }

    func testTheHigherCardTakesThePile() {
        var state = fresh()
        var generator = SeededGenerator(seed: 2)
        _ = rules.apply(.flip, to: &state, generator: &generator)
        let played = state.seatOrder.map { seat in
            (seat, state.board.card(state.battle[seat]!.last!)!.rank!.rawValue)
        }
        _ = rules.advanceAutomatically(&state, generator: &generator)

        if played[0].1 == played[1].1 {
            XCTAssertTrue(state.atWar, "equal cards mean war")
            return
        }
        let expected = played[0].1 > played[1].1 ? played[0].0 : played[1].0
        XCTAssertEqual(state.lastBattleWinner, expected)
        XCTAssertEqual(state.board.count(in: state.wonZone(expected)), 2)
        XCTAssertEqual(state.board.count(in: .trick), 0)
        XCTAssertFalse(state.atWar)
    }

    func testTheTotalNumberOfCardsIsConservedThroughout() {
        var state = fresh()
        var generator = SeededGenerator(seed: 3)
        for _ in 0..<40 {
            guard state.finalResult == nil else { break }
            if state.pendingResolution {
                _ = rules.advanceAutomatically(&state, generator: &generator)
            } else {
                _ = rules.apply(.flip, to: &state, generator: &generator)
            }
            let total = state.seatOrder.reduce(0) { $0 + state.totalCards($1) }
                + state.board.count(in: .trick)
            XCTAssertEqual(total, 52, "no card is ever created or lost")
        }
    }

    func testATieStakesMoreCardsAndFlipsAgain() {
        var found = false
        seeds: for seed in UInt64(1)...12 {
            var state = fresh(seed: seed)
            var generator = SeededGenerator(seed: seed)
            for _ in 0..<400 where state.finalResult == nil {
                guard state.pendingResolution else {
                    _ = rules.apply(.flip, to: &state, generator: &generator)
                    continue
                }
                _ = rules.advanceAutomatically(&state, generator: &generator)
                guard state.atWar else { continue }

                XCTAssertEqual(state.warDepth, 1)
                XCTAssertGreaterThan(state.board.count(in: .trick), 0,
                                     "the stake stays on the table")
                // The next flip buries the stake and turns one more card each.
                let trickBefore = state.board.count(in: .trick)
                _ = rules.apply(.flip, to: &state, generator: &generator)
                XCTAssertEqual(state.board.count(in: .trick),
                               trickBefore + 2 * (state.settings.warStake + 1))
                found = true
                break seeds
            }
        }
        XCTAssertTrue(found, "no war in twelve games, which is not credible")
    }

    func testAGameAlwaysEnds() throws {
        let configuration = TestTable.configuration(.war, humans: 1, ai: 1)
        let outcome = TestTable.playOut(rules, configuration: configuration)
        let result = try XCTUnwrap(outcome.state.finalResult, "stopped because it \(outcome.stop)")
        XCTAssertFalse(result.winners.isEmpty)
        XCTAssertLessThanOrEqual(outcome.state.flips, outcome.state.settings.flipLimit,
                                 "the flip limit stops war from running forever")
    }

    func testObservationIsCountsOnly() {
        var state = fresh()
        var generator = SeededGenerator(seed: 5)
        _ = rules.apply(.flip, to: &state, generator: &generator)
        let seat = state.seatOrder[0]
        let observation = rules.observation(of: state, for: seat)
        XCTAssertEqual(observation.ownDeckCount, state.board.count(in: state.deckZone(seat)))
        XCTAssertEqual(observation.opponentTotals[state.seatOrder[1]],
                       state.totalCards(state.seatOrder[1]))
        // There is nothing in a War observation that could name a face-down card.
        XCTAssertEqual(observation.seat, seat)
    }
}

final class SpeedTests: XCTestCase {
    private let rules = SpeedRules()

    private func fresh(seed: UInt64 = 66) -> SpeedRules.State {
        let configuration = TestTable.configuration(.speed, humans: 1, ai: 1, seed: seed)
        var generator = SeededGenerator(seed: seed)
        return rules.setup(configuration: configuration, generator: &generator)
    }

    func testTheTableIsSetWithTwoCentrePilesAndNoTurnOrder() {
        let state = fresh()
        XCTAssertNil(state.activeSeat, "speed is simultaneous — nobody is 'to move'")
        XCTAssertEqual(state.seatOrder.count, 2)
        XCTAssertNotNil(state.board.top(of: SpeedRules.State.centreZone(0)))
        XCTAssertNotNil(state.board.top(of: SpeedRules.State.centreZone(1)))
        for seat in state.seatOrder {
            XCTAssertEqual(state.board.count(in: .hand(seat)), state.settings.handSize)
            XCTAssertEqual(state.board.count(in: state.replacementZone(seat)),
                           state.settings.replacementSize - 1, "one of each went to the middle")
        }
        let total = state.seatOrder.reduce(0) { $0 + state.remaining($1)
            + state.board.count(in: state.replacementZone($1)) }
            + state.board.count(in: SpeedRules.State.centreZone(0))
            + state.board.count(in: SpeedRules.State.centreZone(1))
        XCTAssertEqual(total, 52)
    }

    func testAdjacencyWrapsAtTheAceButNowhereElse() {
        XCTAssertTrue(SpeedRules.isPlayable(Card(token: "8H")!, on: Card(token: "7C")!))
        XCTAssertTrue(SpeedRules.isPlayable(Card(token: "6H")!, on: Card(token: "7C")!))
        XCTAssertFalse(SpeedRules.isPlayable(Card(token: "9H")!, on: Card(token: "7C")!))
        XCTAssertTrue(SpeedRules.isPlayable(Card(token: "AH")!, on: Card(token: "KC")!),
                      "the ace sits above the king")
        XCTAssertTrue(SpeedRules.isPlayable(Card(token: "AH")!, on: Card(token: "2C")!),
                      "and below the two")
        XCTAssertFalse(SpeedRules.isPlayable(Card(token: "KH")!, on: Card(token: "2C")!),
                       "but the wrap does not go king to two")
        XCTAssertFalse(SpeedRules.isPlayable(Card(token: "7H")!, on: Card(token: "7C")!),
                       "same rank is not adjacent")
    }

    func testEitherPlayerMayMoveAtAnyTime() {
        let state = fresh()
        // Both seats are offered moves from the same position — there is no turn.
        let zero = rules.legalActions(in: state, for: state.seatOrder[0])
        let one = rules.legalActions(in: state, for: state.seatOrder[1])
        for action in zero + one {
            XCTAssertNil(rules.rejection(for: action, in: state))
        }
        XCTAssertFalse(zero.isEmpty && one.isEmpty && !rules.isDeadlocked(state),
                       "if neither can move, the position is deadlocked by definition")
    }

    func testPlayingACardDrawsStraightBackUp() {
        var state = fresh()
        let seat = state.seatOrder[0]
        guard let action = rules.legalActions(in: state, for: seat).first,
              case let .play(_, cardID, pile) = action else {
            return XCTAssertTrue(rules.isDeadlocked(state), "no move and no deadlock is a bug")
        }
        var generator = SeededGenerator(seed: 1)
        _ = rules.apply(action, to: &state, generator: &generator)

        XCTAssertEqual(state.board.zone(of: cardID), SpeedRules.State.centreZone(pile))
        XCTAssertEqual(state.board.count(in: .hand(seat)), state.settings.handSize,
                       "the hand refills from the draw pile")
        XCTAssertEqual(state.cardsPlayed[seat], 1)
    }

    func testAnUnplayableCardIsRefusedWithAReason() {
        var state = fresh()
        let seat = state.seatOrder[0]
        SpeedTests.jam(&state, mine: "9H", theirs: "9S", centres: ("2C", "2D"))
        XCTAssertEqual(rules.rejection(for: .play(seat: seat, card: Card(token: "9H")!.id, pile: 0),
                                       in: state)?.reason,
                       "mustBeAdjacentRank")
        XCTAssertTrue(rules.isDeadlocked(state))
    }

    /// Forces a position: one named card in each hand, one on each centre pile.
    private static func jam(_ state: inout SpeedRules.State,
                            mine: String,
                            theirs: String,
                            centres: (String, String)) {
        for pile in 0..<2 {
            for id in state.board.contents(of: SpeedRules.State.centreZone(pile)) {
                state.board.move(id, to: .stock, facing: .faceDown)
            }
        }
        TestTable.setHand([Card(token: mine)!], for: state.seatOrder[0], in: &state.board)
        TestTable.setHand([Card(token: theirs)!], for: state.seatOrder[1], in: &state.board)
        state.board.move(Card(token: centres.0)!.id,
                         to: SpeedRules.State.centreZone(0), facing: .faceUp)
        state.board.move(Card(token: centres.1)!.id,
                         to: SpeedRules.State.centreZone(1), facing: .faceUp)
    }

    func testBreakingADeadlockTurnsANewPair() {
        var state = fresh()
        let seat = state.seatOrder[0]
        SpeedTests.jam(&state, mine: "9H", theirs: "9S", centres: ("2C", "2D"))
        let flipsBefore = state.flipsUsed
        let reservesBefore = state.seatOrder.map { state.board.count(in: state.replacementZone($0)) }

        XCTAssertEqual(rules.legalActions(in: state, for: seat), [.breakDeadlock(seat: seat)],
                       "the only thing left to do is turn a new pair")
        var generator = SeededGenerator(seed: 2)
        _ = rules.apply(.breakDeadlock(seat: seat), to: &state, generator: &generator)

        XCTAssertEqual(state.flipsUsed, flipsBefore + 1)
        for (index, seat) in state.seatOrder.enumerated() {
            XCTAssertEqual(state.board.count(in: state.replacementZone(seat)),
                           reservesBefore[index] - 1, "one card each comes off the reserve")
        }
        XCTAssertNotEqual(state.board.top(of: SpeedRules.State.centreZone(0))?.token, "2C")
        XCTAssertNotEqual(state.board.top(of: SpeedRules.State.centreZone(1))?.token, "2D")
    }

    func testTurningANewPairIsRefusedWhileSomebodyCanStillPlay() {
        var state = fresh()
        let seat = state.seatOrder[0]
        SpeedTests.jam(&state, mine: "4D", theirs: "9S", centres: ("3C", "JD"))
        XCTAssertFalse(rules.isDeadlocked(state))
        XCTAssertEqual(rules.rejection(for: .breakDeadlock(seat: seat), in: state)?.reason,
                       "someoneCanStillPlay")
    }

    func testAFullGameFinishes() throws {
        let configuration = TestTable.configuration(.speed, humans: 1, ai: 1)
        var generator = SeededGenerator(seed: configuration.seed)
        var state = rules.setup(configuration: configuration, generator: &generator)
        var moves = 0
        // Simultaneous play: whoever has a move takes one, alternating fairly.
        while state.finalResult == nil && moves < 4000 {
            let seat = state.seatOrder[moves % 2]
            let other = state.seatOrder[(moves + 1) % 2]
            let action = rules.legalActions(in: state, for: seat).first
                ?? rules.legalActions(in: state, for: other).first
            guard let action else { break }
            XCTAssertNil(rules.rejection(for: action, in: state))
            _ = rules.apply(action, to: &state, generator: &generator)
            moves += 1
        }
        let result = try XCTUnwrap(state.finalResult, "speed did not reach an end in \(moves) moves")
        XCTAssertEqual(result.winners.count, 1)
    }

    func testObservationShowsTheCentreAndYourOwnHandOnly() {
        let state = fresh()
        let seat = state.seatOrder[0]
        let other = state.seatOrder[1]
        let observation = rules.observation(of: state, for: seat)
        XCTAssertEqual(observation.hand.count, state.settings.handSize)
        XCTAssertEqual(observation.centreTops.count, 2)
        XCTAssertEqual(observation.opponentHandCount, state.board.count(in: .hand(other)))
        let mine = Set(observation.hand.map(\.id))
        XCTAssertTrue(mine.isDisjoint(with: Set(state.board.contents(of: .hand(other)))))
    }
}

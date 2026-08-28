import XCTest
import DeckCore
@testable import DeckGames

extension TestTable {
    /// Forces an exact hand for a seat. Whatever was there goes back to the
    /// stock; the named cards come in from wherever the deal put them.
    ///
    /// Card identifiers are a pure function of suit, rank and deck index, so a
    /// test can name the hand it wants and get it.
    static func setHand(_ cards: [Card], for seat: SeatID, in board: inout Board) {
        board.ensureZones([.stock, .hand(seat)])
        for id in board.contents(of: .hand(seat)) {
            board.move(id, to: .stock, facing: .faceDown)
        }
        for card in cards {
            board.move(card.id, to: .hand(seat), facing: .hand(seat))
        }
    }
}

final class SpadesTests: XCTestCase {
    private let rules = SpadesRules()

    private func fresh(seed: UInt64 = 7) -> SpadesRules.State {
        let configuration = TestTable.configuration(.spades, humans: 1, ai: 3, teams: true, seed: seed)
        var generator = SeededGenerator(seed: seed)
        return rules.setup(configuration: configuration, generator: &generator)
    }

    func testDealIsThirteenEachAndNothingIsLeftOver() {
        let state = fresh()
        XCTAssertEqual(state.seatOrder.count, 4)
        for seat in state.seatOrder {
            XCTAssertEqual(state.board.count(in: .hand(seat)), 13)
        }
        XCTAssertEqual(state.board.count(in: .stock), 0, "a spades deal uses the whole deck")
    }

    func testPartnersSitAcross() {
        let state = fresh()
        XCTAssertEqual(state.team(state.seatOrder[0]), state.team(state.seatOrder[2]))
        XCTAssertEqual(state.team(state.seatOrder[1]), state.team(state.seatOrder[3]))
        XCTAssertNotEqual(state.team(state.seatOrder[0]), state.team(state.seatOrder[1]))
    }

    func testBiddingComesBeforePlaying() {
        let state = fresh()
        XCTAssertEqual(state.phase, .bidding)
        let seat = try! XCTUnwrap(state.activeSeat)
        let actions = rules.legalActions(in: state, for: seat)
        XCTAssertEqual(actions.count, 14, "zero through thirteen")
        XCTAssertTrue(actions.contains(.bid(0)), "nil is always on the table")
        XCTAssertFalse(actions.contains(where: { if case .play = $0 { return true }; return false }),
                       "no cards can be played until every bid is in")
    }

    func testABidOutsideTheHandSizeIsRefusedWithAReason() {
        let state = fresh()
        let reason = rules.rejection(for: .bid(14), in: state)
        XCTAssertNotNil(reason)
        XCTAssertEqual(reason?.reason, "bidOutOfRange")
    }

    func testEveryoneBidsBeforeTheFirstCard() {
        var state = fresh()
        var generator = SeededGenerator(seed: 1)
        for _ in 0..<4 {
            XCTAssertEqual(state.phase, .bidding)
            XCTAssertNotNil(state.activeSeat)
            _ = rules.apply(.bid(3), to: &state, generator: &generator)
        }
        XCTAssertEqual(state.phase, .playing)
        XCTAssertEqual(state.bids.count, 4)
    }

    func testSpadesCannotBeLedUntilTheyAreBroken() {
        var state = fresh()
        state.phase = .playing
        state.spadesBroken = false
        state.trickPlays = []
        state.ledSuit = nil
        let seat = state.seatOrder[0]
        state.activeSeat = seat
        TestTable.setHand([Card(.spades, .ace), Card(.hearts, .three), Card(.clubs, .nine)],
                          for: seat, in: &state.board)

        let legal = rules.legalCards(in: state, for: seat)
        XCTAssertFalse(legal.contains(Card(.spades, .ace)),
                       "a spade cannot open a trick while spades are unbroken")
        XCTAssertEqual(rules.rejection(for: .play(Card(.spades, .ace).id), in: state)?.reason,
                       "spadesNotBroken")

        state.spadesBroken = true
        XCTAssertTrue(rules.legalCards(in: state, for: seat).contains(Card(.spades, .ace)))
    }

    func testAHandOfNothingButSpadesMayLeadOne() {
        var state = fresh()
        state.phase = .playing
        state.spadesBroken = false
        state.trickPlays = []
        let seat = state.seatOrder[0]
        state.activeSeat = seat
        TestTable.setHand([Card(.spades, .two), Card(.spades, .king)], for: seat, in: &state.board)
        XCTAssertEqual(rules.legalCards(in: state, for: seat).count, 2,
                       "a player holding only spades is not frozen out")
    }

    func testMustFollowSuitAndSaysSo() {
        var state = fresh()
        state.phase = .playing
        let leader = state.seatOrder[0]
        let follower = state.seatOrder[1]
        TestTable.setHand([Card(.hearts, .king), Card(.clubs, .four)], for: follower, in: &state.board)
        state.ledSuit = .hearts
        state.trickPlays = [TrickPlay(seat: leader, card: Card(.hearts, .five).id)]
        state.activeSeat = follower

        XCTAssertEqual(rules.legalCards(in: state, for: follower), [Card(.hearts, .king)])
        XCTAssertEqual(rules.rejection(for: .play(Card(.clubs, .four).id), in: state),
                       .mustFollowSuit(.hearts))
    }

    func testASpadeBeatsTheLedSuitHoweverHighItIs() {
        let table = [Card(.hearts, .ace), Card(.hearts, .king),
                     Card(.spades, .two), Card(.hearts, .queen)]
        let cards = Dictionary(uniqueKeysWithValues: table.map { ($0.id, $0) })
        let plays = table.enumerated().map { TrickPlay(seat: SeatID($0.offset), card: $0.element.id) }
        let winner = TrickEngine.winner(plays: plays, cards: cards, ledSuit: .hearts, trump: .spades)
        XCTAssertEqual(winner, SeatID(2), "the smallest trump beats the biggest heart")
    }

    func testMakingTheBidScoresTenAPlusOnePerBag() {
        var state = fresh()
        state.phase = .playing
        state.teamScores = [0: 0, 1: 0]
        state.teamBags = [0: 0, 1: 0]
        // Team 0 bid four and took six; team 1 bid nine and took seven.
        state.bids = [state.seatOrder[0]: 2, state.seatOrder[2]: 2,
                      state.seatOrder[1]: 5, state.seatOrder[3]: 4]
        state.tricksWon = [state.seatOrder[0]: 3, state.seatOrder[2]: 3,
                           state.seatOrder[1]: 4, state.seatOrder[3]: 3]
        state.dealComplete = true
        var generator = SeededGenerator(seed: 2)
        _ = rules.advanceAutomatically(&state, generator: &generator)

        XCTAssertEqual(state.teamScores[0], 42, "four bid made, plus two bags")
        XCTAssertEqual(state.teamScores[1], -90, "nine bid, seven taken, set")
        XCTAssertEqual(state.teamBags[0], 2)
    }

    func testTenBagsCostAHundred() {
        var state = fresh()
        state.phase = .playing
        state.teamScores = [0: 200, 1: 0]
        state.teamBags = [0: 8, 1: 0]
        state.bids = [state.seatOrder[0]: 1, state.seatOrder[2]: 1,
                      state.seatOrder[1]: 5, state.seatOrder[3]: 6]
        state.tricksWon = [state.seatOrder[0]: 2, state.seatOrder[2]: 3,
                           state.seatOrder[1]: 4, state.seatOrder[3]: 4]
        state.dealComplete = true
        var generator = SeededGenerator(seed: 3)
        _ = rules.advanceAutomatically(&state, generator: &generator)

        // Bid two, took five: 20 + 3 bags = 23, then 8 + 3 = 11 bags trips the penalty.
        XCTAssertEqual(state.teamBags[0], 1, "the bag count wraps rather than resetting")
        XCTAssertEqual(state.teamScores[0], 200 + 23 - 100)
    }

    func testNilIsScoredOnItsOwnAndItsTricksDoNotHelpThePartner() {
        var state = fresh()
        state.phase = .playing
        state.teamScores = [0: 0, 1: 0]
        state.teamBags = [0: 0, 1: 0]
        state.bids = [state.seatOrder[0]: 0, state.seatOrder[2]: 5,
                      state.seatOrder[1]: 4, state.seatOrder[3]: 4]
        state.tricksWon = [state.seatOrder[0]: 0, state.seatOrder[2]: 5,
                           state.seatOrder[1]: 4, state.seatOrder[3]: 4]
        state.dealComplete = true
        var generator = SeededGenerator(seed: 4)
        _ = rules.advanceAutomatically(&state, generator: &generator)

        XCTAssertEqual(state.teamScores[0], 100 + 50, "a made nil, plus the partner's five")
        XCTAssertEqual(state.nilsMade[state.seatOrder[0]], 1)
    }

    func testABrokenNilCostsThePoints() {
        var state = fresh()
        state.phase = .playing
        state.teamScores = [0: 0, 1: 0]
        state.teamBags = [0: 0, 1: 0]
        state.bids = [state.seatOrder[0]: 0, state.seatOrder[2]: 5,
                      state.seatOrder[1]: 4, state.seatOrder[3]: 4]
        state.tricksWon = [state.seatOrder[0]: 1, state.seatOrder[2]: 5,
                           state.seatOrder[1]: 4, state.seatOrder[3]: 3]
        state.dealComplete = true
        var generator = SeededGenerator(seed: 5)
        _ = rules.advanceAutomatically(&state, generator: &generator)

        // Nil goes down (-100); the partnership bid five and took five (+50);
        // the nil-bidder's stray trick lands as a bag.
        XCTAssertEqual(state.teamScores[0], -100 + 50 + 1)
        XCTAssertEqual(state.nilsMade[state.seatOrder[0]] ?? 0, 0)
    }

    func testAFullGameFinishes() {
        let configuration = TestTable.configuration(.spades, humans: 1, ai: 3, teams: true)
        let outcome = TestTable.playOut(rules, configuration: configuration)
        let result = try! XCTUnwrap(outcome.state.finalResult)
        XCTAssertFalse(result.winners.isEmpty)
        XCTAssertEqual(result.winners.count, 2, "spades is won by a partnership")
        XCTAssertGreaterThan(outcome.state.roundNumber, 1, "a game takes more than one deal")
    }

    func testEveryDealAwardsExactlyThirteenTricks() {
        var generator = SeededGenerator(seed: 11)
        let configuration = TestTable.configuration(.spades, humans: 1, ai: 3, teams: true, seed: 11)
        var state = rules.setup(configuration: configuration, generator: &generator)
        for _ in 0..<4 {
            let seat = state.activeSeat!
            _ = rules.apply(.bid(3), to: &state, generator: &generator)
            XCTAssertNotEqual(state.activeSeat, seat)
        }
        var moves = 0
        while state.phase == .playing && moves < 60 {
            guard let seat = state.activeSeat else { break }
            let action = rules.legalActions(in: state, for: seat).first!
            _ = rules.apply(action, to: &state, generator: &generator)
            moves += 1
        }
        XCTAssertEqual(moves, 52, "fifty-two cards, thirteen tricks")
        XCTAssertEqual(state.tricksWon.values.reduce(0, +), 13)
    }

    func testObservationCarriesOnlyTheViewersHand() {
        let state = fresh()
        let seat = state.seatOrder[0]
        let observation = rules.observation(of: state, for: seat)
        XCTAssertEqual(observation.hand.count, 13)
        XCTAssertEqual(observation.seat, seat)
        // The only cards named anywhere in the observation are the viewer's own
        // and cards already played to the table.
        let ownIDs = Set(observation.hand.map(\.id))
        let tableIDs = Set(observation.trickPlays.map(\.card.id))
        XCTAssertTrue(tableIDs.isDisjoint(with: ownIDs))
        XCTAssertEqual(observation.playedCards.count, 0, "nothing has been played yet")
    }
}

final class EuchreTests: XCTestCase {
    private let rules = EuchreRules()

    private func fresh(seed: UInt64 = 21) -> EuchreRules.State {
        let configuration = TestTable.configuration(.euchre, humans: 1, ai: 3, teams: true, seed: seed)
        var generator = SeededGenerator(seed: seed)
        return rules.setup(configuration: configuration, generator: &generator)
    }

    func testDealIsFiveEachWithAnUpcard() {
        let state = fresh()
        for seat in state.seatOrder {
            XCTAssertEqual(state.board.count(in: .hand(seat)), 5)
        }
        XCTAssertNotNil(state.upcard)
        XCTAssertEqual(state.phase, .bidRoundOne)
    }

    func testTheDeckIsTwentyFourCardsNineThroughAce() {
        let state = fresh()
        var all: [Card] = []
        for seat in state.seatOrder { all += state.board.cardList(in: .hand(seat)) }
        if let upcard = state.upcard, let card = state.board.card(upcard) { all.append(card) }
        all += state.board.cardList(in: .stock)
        XCTAssertEqual(all.count, 24)
        XCTAssertTrue(all.allSatisfy { ($0.rank?.rawValue ?? 0) >= Rank.nine.rawValue },
                      "euchre plays with nine to ace only")
    }

    func testTheLeftBowerCountsAsTrump() {
        XCTAssertEqual(EuchreRules.effectiveSuit(Card(.diamonds, .jack), trump: .hearts), .hearts)
        XCTAssertEqual(EuchreRules.effectiveSuit(Card(.hearts, .jack), trump: .hearts), .hearts)
        XCTAssertEqual(EuchreRules.effectiveSuit(Card(.diamonds, .ace), trump: .hearts), .diamonds,
                       "only the jack changes suit")
        XCTAssertEqual(EuchreRules.effectiveSuit(Card(.spades, .jack), trump: .hearts), .spades)
    }

    func testTrumpOrderPutsBowersOnTop() {
        let trump = Suit.spades
        let right = EuchreRules.trumpValue(Card(.spades, .jack), trump: trump)
        let left = EuchreRules.trumpValue(Card(.clubs, .jack), trump: trump)
        let ace = EuchreRules.trumpValue(Card(.spades, .ace), trump: trump)
        let offsuit = EuchreRules.trumpValue(Card(.hearts, .ace), trump: trump)
        XCTAssertGreaterThan(right, left)
        XCTAssertGreaterThan(left, ace)
        XCTAssertGreaterThan(ace, offsuit)
        XCTAssertEqual(offsuit, 0, "a card that is not trump has no trump value")
    }

    func testFollowingSuitUsesTheEffectiveSuit() {
        var state = fresh()
        state.phase = .playing
        state.trump = .hearts
        let seat = state.seatOrder[1]
        state.activeSeat = seat
        TestTable.setHand([Card(.diamonds, .jack), Card(.spades, .ace), Card(.clubs, .ten)],
                          for: seat, in: &state.board)
        state.ledSuit = .hearts
        state.trickPlays = [TrickPlay(seat: state.seatOrder[0], card: Card(.hearts, .nine).id)]

        XCTAssertEqual(rules.legalCards(in: state, for: seat), [Card(.diamonds, .jack)],
                       "holding the left bower means you can follow trump")

        state.ledSuit = .diamonds
        state.trickPlays = [TrickPlay(seat: state.seatOrder[0], card: Card(.diamonds, .ten).id)]
        XCTAssertEqual(rules.legalCards(in: state, for: seat).count, 3,
                       "the left bower is not a diamond, so nothing follows and anything goes")
    }

    func testTheDealerCannotPassInTheSecondRound() {
        var state = fresh()
        state.phase = .bidRoundTwo
        state.activeSeat = state.dealerSeat
        let actions = rules.legalActions(in: state, for: state.dealerSeat)
        XCTAssertFalse(actions.contains(.passBid), "the dealer is stuck and must name a suit")
        XCTAssertFalse(actions.isEmpty)

        let other = state.seatOrder.first { $0 != state.dealerSeat }!
        state.activeSeat = other
        XCTAssertTrue(rules.legalActions(in: state, for: other).contains(.passBid))
    }

    func testTheTurnedDownSuitCannotBeNamed() {
        var state = fresh()
        state.phase = .bidRoundTwo
        let seat = state.seatOrder.first { $0 != state.dealerSeat }!
        state.activeSeat = seat
        let turned = state.board.card(state.upcard!)!.suit!
        XCTAssertFalse(rules.legalActions(in: state, for: seat).contains(.callTrump(turned, alone: false)))
        XCTAssertEqual(rules.rejection(for: .callTrump(turned, alone: false), in: state)?.reason,
                       "cannotNameTurnedSuit")
    }

    func testOrderingUpMakesTrumpAndSendsTheDealerToDiscard() {
        var state = fresh()
        var generator = SeededGenerator(seed: 5)
        let upcardSuit = state.board.card(state.upcard!)!.suit!
        let bidder = state.activeSeat!
        _ = rules.apply(.orderUp(alone: false), to: &state, generator: &generator)

        XCTAssertEqual(state.trump, upcardSuit)
        XCTAssertEqual(state.makerSeat, bidder)
        XCTAssertEqual(state.phase, .dealerDiscard)
        XCTAssertEqual(state.activeSeat, state.dealerSeat)
        XCTAssertEqual(state.board.count(in: .hand(state.dealerSeat)), 6,
                       "the dealer picks the upcard up before pitching one")
    }

    func testGoingAloneSitsThePartnerOut() {
        var state = fresh()
        var generator = SeededGenerator(seed: 6)
        let bidder = state.activeSeat!
        _ = rules.apply(.orderUp(alone: true), to: &state, generator: &generator)
        let partner = state.seatOrder.first { $0 != bidder && state.team($0) == state.team(bidder) }
        XCTAssertEqual(state.sittingOut, partner)
        XCTAssertEqual(state.activePlayers.count, 3)
        XCTAssertFalse(state.activePlayers.contains(partner!))
    }

    func testAFullGameFinishes() {
        let configuration = TestTable.configuration(.euchre, humans: 1, ai: 3, teams: true)
        let outcome = TestTable.playOut(rules, configuration: configuration)
        let result = try! XCTUnwrap(outcome.state.finalResult)
        XCTAssertEqual(result.winners.count, 2)
        let winningScore = outcome.state.teamScores.values.max() ?? 0
        XCTAssertGreaterThanOrEqual(winningScore, outcome.state.settings.targetScore)
    }

    func testEveryDealAwardsExactlyFiveTricks() {
        for seed in UInt64(30)...36 {
            let configuration = TestTable.configuration(.euchre, humans: 1, ai: 3, teams: true, seed: seed)
            var generator = SeededGenerator(seed: seed)
            var state = rules.setup(configuration: configuration, generator: &generator)
            var moves = 0
            while !state.dealComplete && state.finalResult == nil && moves < 200 {
                guard let seat = state.activeSeat,
                      let action = rules.legalActions(in: state, for: seat).first else { break }
                _ = rules.apply(action, to: &state, generator: &generator)
                moves += 1
            }
            XCTAssertTrue(state.dealComplete, "seed \(seed) never finished its deal")
            XCTAssertEqual(state.tricksWon.values.reduce(0, +), 5,
                           "five cards each, five tricks, seed \(seed)")
            XCTAssertTrue(state.activePlayers.allSatisfy { state.board.isEmpty(Zone.hand($0)) },
                          "every active player is out of cards, seed \(seed)")
        }
    }

    func testScoringADealResetsTheTableForTheNext() {
        let configuration = TestTable.configuration(.euchre, humans: 1, ai: 3, teams: true, seed: 41)
        var generator = SeededGenerator(seed: 41)
        var state = rules.setup(configuration: configuration, generator: &generator)
        var moves = 0
        while !state.dealComplete && moves < 200 {
            guard let seat = state.activeSeat,
                  let action = rules.legalActions(in: state, for: seat).first else { break }
            _ = rules.apply(action, to: &state, generator: &generator)
            moves += 1
        }
        XCTAssertTrue(state.dealComplete)
        _ = rules.advanceAutomatically(&state, generator: &generator)

        XCTAssertEqual(state.roundNumber, 2)
        XCTAssertEqual(state.tricksWon.values.reduce(0, +), 0, "trick counters reset")
        XCTAssertNil(state.trump, "trump is named again every deal")
        XCTAssertNil(state.sittingOut)
        XCTAssertEqual(state.phase, .bidRoundOne)
        for seat in state.seatOrder {
            XCTAssertEqual(state.board.count(in: .hand(seat)), 5, "everyone gets a fresh five")
        }
        XCTAssertGreaterThan(state.teamScores.values.reduce(0, +), 0,
                             "somebody scored for that deal")
    }

    func testObservationNeverNamesAnotherHand() {
        let state = fresh()
        let seat = state.seatOrder[2]
        let observation = rules.observation(of: state, for: seat)
        let mine = Set(observation.hand.map(\.id))
        XCTAssertEqual(mine.count, 5)
        var others: Set<CardID> = []
        for other in state.seatOrder where other != seat {
            others.formUnion(state.board.contents(of: .hand(other)))
        }
        XCTAssertTrue(mine.isDisjoint(with: others))
        XCTAssertTrue(observation.playedCards.isEmpty)
        XCTAssertNotNil(observation.upcard, "the upcard is face up, so it is fair to see")
    }
}

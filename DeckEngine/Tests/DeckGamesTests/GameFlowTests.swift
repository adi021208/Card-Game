import XCTest
import DeckCore
@testable import DeckGames

/// Helpers shared by the per-game flow tests.
enum TestTable {
    static func seating(humans: Int, ai: Int = 0, teams: Bool = false) -> SeatingPlan {
        var seats: [Seat] = []
        let names = ["Maya", "Ike", "Rue", "Jo", "Bex", "Sam"]
        let cast: [AIPersonalityID] = [.hal, .pedro, .calvin, .rohan, .shayla, .honey, .scarlet]
        for index in 0..<humans {
            seats.append(Seat(id: SeatID(index),
                              displayName: names[index % names.count],
                              controller: .human(profileID: "p\(index)"),
                              team: teams ? index % 2 : nil))
        }
        for index in 0..<ai {
            let seatIndex = humans + index
            seats.append(Seat(id: SeatID(seatIndex),
                              displayName: "AI \(index)",
                              controller: .ai(personality: cast[index % cast.count], difficulty: .skilled),
                              team: teams ? seatIndex % 2 : nil))
        }
        return SeatingPlan(seats: seats)
    }

    static func configuration(_ gameID: GameID,
                              humans: Int,
                              ai: Int = 0,
                              teams: Bool = false,
                              options: [String: Int] = [:],
                              seed: UInt64 = 20260828) -> GameConfiguration {
        GameConfiguration(gameID: gameID,
                          seating: seating(humans: humans, ai: ai, teams: teams),
                          options: options,
                          seed: seed)
    }

    /// Plays a game to completion by always taking the first legal move.
    ///
    /// A blunt driver, but it proves the rules never deadlock, never offer an
    /// illegal move, and always reach a result.
    @discardableResult
    static func playOut<R: GameRules>(_ rules: R,
                                      configuration: GameConfiguration,
                                      maximumMoves: Int = 6000,
                                      chooser: ((R.State, [R.Action]) -> R.Action)? = nil) -> (state: R.State, moves: Int) {
        var generator = SeededGenerator(seed: configuration.seed)
        var state = rules.setup(configuration: configuration, generator: &generator)
        var moves = 0
        while state.finalResult == nil && moves < maximumMoves {
            var advanced = false
            for _ in 0..<512 {
                let events = rules.advanceAutomatically(&state, generator: &generator)
                if events.isEmpty { break }
                advanced = true
            }
            guard state.finalResult == nil else { break }
            guard let seat = state.activeSeat else {
                XCTAssertTrue(advanced, "no active seat and nothing left to do automatically")
                break
            }
            let legal = rules.legalActions(in: state, for: seat)
            // The chooser must return an action, so it is only consulted when
            // there is one to return.
            guard let action = (legal.isEmpty ? nil : chooser.map { $0(state, legal) }) ?? legal.first else {
                XCTFail("no legal move for \(seat) after \(moves) moves")
                break
            }
            XCTAssertNil(rules.rejection(for: action, in: state),
                         "a move returned by legalActions was rejected")
            _ = rules.apply(action, to: &state, generator: &generator)
            moves += 1
        }
        return (state, moves)
    }
}

final class CrazyEightsTests: XCTestCase {
    private let rules = CrazyEightsRules()

    func testDealSizes() {
        let configuration = TestTable.configuration(.crazyEights, humans: 1, ai: 3)
        var generator = SeededGenerator(seed: configuration.seed)
        let state = rules.setup(configuration: configuration, generator: &generator)
        for seat in state.seatOrder {
            XCTAssertEqual(state.board.count(in: .hand(seat)), 5)
        }
        XCTAssertEqual(state.board.count(in: .discard), 1)
        XCTAssertNotNil(state.board.top(of: .discard))
    }

    func testTwoPlayerDealIsSeven() {
        let configuration = TestTable.configuration(.crazyEights, humans: 2)
        var generator = SeededGenerator(seed: configuration.seed)
        let state = rules.setup(configuration: configuration, generator: &generator)
        for seat in state.seatOrder {
            XCTAssertEqual(state.board.count(in: .hand(seat)), 7)
        }
    }

    func testStarterIsNeverAnEight() {
        for seed in UInt64(1)...60 {
            let configuration = TestTable.configuration(.crazyEights, humans: 2, seed: seed)
            var generator = SeededGenerator(seed: seed)
            let state = rules.setup(configuration: configuration, generator: &generator)
            XCTAssertNotEqual(state.board.top(of: .discard)?.rank, .eight)
        }
    }

    func testMatchingRules() {
        let configuration = TestTable.configuration(.crazyEights, humans: 2)
        var generator = SeededGenerator(seed: configuration.seed)
        var state = rules.setup(configuration: configuration, generator: &generator)
        guard let top = state.board.top(of: .discard), let topSuit = top.suit, let topRank = top.rank else {
            return XCTFail("no starter")
        }
        state.currentSuit = topSuit

        let sameSuit = Card(topSuit, topRank == .king ? .queen : .king)
        XCTAssertTrue(rules.isPlayable(sameSuit, in: state), "matching the suit is always legal")

        let otherSuit: Suit = topSuit == .spades ? .hearts : .spades
        let sameRank = Card(otherSuit, topRank)
        XCTAssertTrue(rules.isPlayable(sameRank, in: state), "matching the rank is always legal")

        let mismatch = Card(otherSuit, topRank == .three ? .four : .three)
        XCTAssertFalse(rules.isPlayable(mismatch, in: state))

        XCTAssertTrue(rules.isPlayable(Card(otherSuit, .eight), in: state), "an eight always goes")
    }

    func testEightRequiresASuitNomination() {
        let configuration = TestTable.configuration(.crazyEights, humans: 2)
        var generator = SeededGenerator(seed: configuration.seed)
        var state = rules.setup(configuration: configuration, generator: &generator)
        guard let seat = state.activeSeat else { return XCTFail("no active seat") }
        // Force an eight into the hand.
        let eight = Card(.hearts, .eight)
        state.board.load([eight], into: .hand(seat))
        state.board.setVisibility(.onlySeat(seat), for: eight.id)

        XCTAssertNotNil(rules.rejection(for: .play(eight.id), in: state),
                        "an eight cannot be played without naming a suit")
        XCTAssertNil(rules.rejection(for: .playWild(eight.id, .clubs), in: state))

        let actions = rules.legalActions(in: state, for: seat)
        // Scoped to this eight: load appends, and the dealt hand may hold an
        // eight of its own, which would legitimately offer four more.
        let wildActions = actions.filter {
            if case let .playWild(id, _) = $0 { return id == eight.id }
            return false
        }
        XCTAssertEqual(wildActions.count, 4, "every suit is offered for the eight")
    }

    func testPlayingAnEightSetsTheSuit() {
        let configuration = TestTable.configuration(.crazyEights, humans: 2)
        var generator = SeededGenerator(seed: configuration.seed)
        var state = rules.setup(configuration: configuration, generator: &generator)
        guard let seat = state.activeSeat else { return XCTFail("no active seat") }
        let eight = Card(.hearts, .eight)
        state.board.load([eight], into: .hand(seat))
        _ = rules.apply(.playWild(eight.id, .clubs), to: &state, generator: &generator)
        XCTAssertEqual(state.currentSuit, .clubs)
        XCTAssertEqual(state.board.top(of: .discard)?.id, eight.id)
    }

    func testGameCompletes() {
        for seed in UInt64(1)...25 {
            let configuration = TestTable.configuration(.crazyEights,
                                                        humans: 1, ai: 3,
                                                        options: ["targetScore": 0],
                                                        seed: seed)
            let outcome = TestTable.playOut(rules, configuration: configuration)
            XCTAssertNotNil(outcome.state.finalResult, "seed \(seed) never finished")
            XCTAssertEqual(outcome.state.finalResult?.winners.count, 1)
        }
    }

    func testMatchPlaysMultipleDeals() {
        let configuration = TestTable.configuration(.crazyEights,
                                                    humans: 1, ai: 2,
                                                    options: ["targetScore": 100])
        let outcome = TestTable.playOut(rules, configuration: configuration)
        XCTAssertNotNil(outcome.state.finalResult)
        guard let winner = outcome.state.finalResult?.winners.first else { return XCTFail("no winner") }
        XCTAssertGreaterThanOrEqual(outcome.state.scores[winner] ?? 0, 100)
    }

    func testStockRecyclesRatherThanDeadlocking() {
        let configuration = TestTable.configuration(.crazyEights,
                                                    humans: 1, ai: 1,
                                                    options: ["targetScore": 0, "handSize": 20])
        let outcome = TestTable.playOut(rules, configuration: configuration)
        XCTAssertNotNil(outcome.state.finalResult)
    }

    func testHouseRuleTwoForcesADraw() {
        let configuration = TestTable.configuration(.crazyEights,
                                                    humans: 2,
                                                    options: ["houseSpecials": 1, "targetScore": 0])
        var generator = SeededGenerator(seed: configuration.seed)
        var state = rules.setup(configuration: configuration, generator: &generator)
        guard let seat = state.activeSeat, let topSuit = state.board.top(of: .discard)?.suit else {
            return XCTFail("no starter")
        }
        state.pendingDraw = 0
        let two = Card(topSuit, .two)
        state.board.load([two], into: .hand(seat))
        _ = rules.apply(.play(two.id), to: &state, generator: &generator)
        XCTAssertEqual(state.pendingDraw, 2)
        guard let next = state.activeSeat else { return XCTFail("no next seat") }
        let actions = rules.legalActions(in: state, for: next)
        XCTAssertEqual(actions, [.draw], "a penalty has to be served before anything else")
    }

    func testObservationHidesOpponentHands() {
        let configuration = TestTable.configuration(.crazyEights, humans: 1, ai: 3)
        var generator = SeededGenerator(seed: configuration.seed)
        let state = rules.setup(configuration: configuration, generator: &generator)
        let observation = rules.observation(of: state, for: SeatID(1))
        XCTAssertEqual(observation.hand.count, 5)
        XCTAssertEqual(observation.opponentCardCounts.count, 3)
        // The observation exposes counts, never cards.
        XCTAssertEqual(Set(observation.hand.map(\.id)),
                       Set(state.board.contents(of: .hand(SeatID(1)))))
    }
}

final class HeartsTests: XCTestCase {
    private let rules = HeartsRules()

    private func startedState(seed: UInt64 = 4242, options: [String: Int] = [:]) -> (HeartsRules.State, SeededGenerator) {
        let configuration = TestTable.configuration(.hearts, humans: 1, ai: 3, options: options, seed: seed)
        var generator = SeededGenerator(seed: seed)
        let state = rules.setup(configuration: configuration, generator: &generator)
        return (state, generator)
    }

    func testDealIsThirteenEach() {
        let (state, _) = startedState()
        for seat in state.seatOrder {
            XCTAssertEqual(state.board.count(in: .hand(seat)), 13)
        }
        XCTAssertEqual(state.board.count(in: .stock), 0)
    }

    func testPassDirectionCycle() {
        XCTAssertEqual(HeartsRules.PassDirection.forRound(1), .left)
        XCTAssertEqual(HeartsRules.PassDirection.forRound(2), .right)
        XCTAssertEqual(HeartsRules.PassDirection.forRound(3), .across)
        XCTAssertEqual(HeartsRules.PassDirection.forRound(4), .hold)
        XCTAssertEqual(HeartsRules.PassDirection.forRound(5), .left)
    }

    func testPassOffsets() {
        XCTAssertEqual(HeartsRules.PassDirection.left.offset(playerCount: 4), 1)
        XCTAssertEqual(HeartsRules.PassDirection.right.offset(playerCount: 4), 3)
        XCTAssertEqual(HeartsRules.PassDirection.across.offset(playerCount: 4), 2)
        XCTAssertEqual(HeartsRules.PassDirection.hold.offset(playerCount: 4), 0)
    }

    func testPassingMovesExactlyThreeCardsEachWay() {
        var (state, generator) = startedState()
        XCTAssertEqual(state.phase, .passing)
        for _ in 0..<4 {
            guard let seat = state.activeSeat else { return XCTFail("no active seat") }
            let chosen = Array(state.hand(seat).prefix(3)).map(\.id)
            _ = rules.apply(.passCards(chosen), to: &state, generator: &generator)
        }
        XCTAssertEqual(state.phase, .playing)
        for seat in state.seatOrder {
            XCTAssertEqual(state.board.count(in: .hand(seat)), 13, "everyone still holds thirteen")
            XCTAssertEqual(state.board.count(in: .exchange(seat)), 0)
        }
    }

    func testTwoOfClubsLeadsTheFirstTrick() {
        var (state, generator) = startedState(options: ["shootSubtracts": 0])
        for _ in 0..<4 {
            guard let seat = state.activeSeat else { break }
            _ = rules.apply(.passCards(Array(state.hand(seat).prefix(3)).map(\.id)),
                            to: &state, generator: &generator)
        }
        guard let leader = state.activeSeat else { return XCTFail("no leader") }
        let legal = rules.legalCards(in: state, for: leader)
        XCTAssertEqual(legal.count, 1)
        XCTAssertEqual(legal.first?.suit, .clubs)
        XCTAssertEqual(legal.first?.rank, .two)
    }

    func testMustFollowSuit() {
        var (state, generator) = startedState()
        for _ in 0..<4 {
            guard let seat = state.activeSeat else { break }
            _ = rules.apply(.passCards(Array(state.hand(seat).prefix(3)).map(\.id)),
                            to: &state, generator: &generator)
        }
        guard let leader = state.activeSeat,
              let two = rules.legalCards(in: state, for: leader).first else { return XCTFail("no lead") }
        _ = rules.apply(.play(two.id), to: &state, generator: &generator)

        guard let follower = state.activeSeat else { return XCTFail("no follower") }
        let hand = rules.legalCards(in: state, for: follower)
        if state.hand(follower).contains(where: { $0.suit == .clubs }) {
            XCTAssertTrue(hand.allSatisfy { $0.suit == .clubs }, "must follow clubs when holding them")
        }
    }

    func testNoPointsOnTheFirstTrick() {
        var (state, generator) = startedState()
        for _ in 0..<4 {
            guard let seat = state.activeSeat else { break }
            _ = rules.apply(.passCards(Array(state.hand(seat).prefix(3)).map(\.id)),
                            to: &state, generator: &generator)
        }
        guard let leader = state.activeSeat,
              let two = rules.legalCards(in: state, for: leader).first else { return XCTFail("no lead") }
        _ = rules.apply(.play(two.id), to: &state, generator: &generator)

        for _ in 0..<3 {
            guard let seat = state.activeSeat else { break }
            let legal = rules.legalCards(in: state, for: seat)
            let hasNonScoring = state.hand(seat).contains { card in
                card.suit != .hearts && !(card.suit == .spades && card.rank == .queen)
            }
            if hasNonScoring {
                for card in legal {
                    XCTAssertNotEqual(card.suit, .hearts, "hearts cannot be dropped on trick one")
                    XCTAssertFalse(card.suit == .spades && card.rank == .queen,
                                   "the queen cannot be dropped on trick one")
                }
            }
            guard let card = legal.first else { break }
            _ = rules.apply(.play(card.id), to: &state, generator: &generator)
        }
    }

    func testHeartsCannotBeLedUntilBroken() {
        var (state, _) = startedState()
        state.phase = .playing
        state.trickNumber = 2
        state.heartsBroken = false
        state.trickPlays = []
        guard let seat = state.seatOrder.first else { return XCTFail("no seat") }
        state.activeSeat = seat
        let legal = rules.legalCards(in: state, for: seat)
        let hasNonHeart = state.hand(seat).contains { $0.suit != .hearts }
        if hasNonHeart {
            XCTAssertTrue(legal.allSatisfy { $0.suit != .hearts })
        } else {
            XCTAssertFalse(legal.isEmpty, "a hand of only hearts may lead one")
        }
    }

    func testTrickWinnerIsHighestOfTheLedSuit() {
        let cards: [CardID: Card] = [
            Card(.clubs, .two).id: Card(.clubs, .two),
            Card(.clubs, .king).id: Card(.clubs, .king),
            Card(.hearts, .ace).id: Card(.hearts, .ace),
            Card(.clubs, .five).id: Card(.clubs, .five)
        ]
        let plays = [
            TrickPlay(seat: SeatID(0), card: Card(.clubs, .two).id),
            TrickPlay(seat: SeatID(1), card: Card(.clubs, .king).id),
            TrickPlay(seat: SeatID(2), card: Card(.hearts, .ace).id),
            TrickPlay(seat: SeatID(3), card: Card(.clubs, .five).id)
        ]
        let winner = TrickEngine.winner(plays: plays, cards: cards, ledSuit: .clubs, trump: nil)
        XCTAssertEqual(winner, SeatID(1), "the ace of hearts cannot win a club trick")
    }

    func testFullGameCompletes() {
        for seed in UInt64(1)...8 {
            let configuration = TestTable.configuration(.hearts, humans: 1, ai: 3,
                                                        options: ["targetScore": 50], seed: seed)
            let outcome = TestTable.playOut(rules, configuration: configuration, maximumMoves: 20000)
            XCTAssertNotNil(outcome.state.finalResult, "seed \(seed) never finished")
            guard let result = outcome.state.finalResult else { continue }
            XCTAssertFalse(result.winners.isEmpty)
            // Lowest score wins.
            let winningScore = result.scores[result.winners[0]] ?? 0
            for (_, score) in result.scores {
                XCTAssertGreaterThanOrEqual(score, winningScore)
            }
        }
    }

    func testPointsAlwaysTotalTwentySixPerDeal() {
        let configuration = TestTable.configuration(.hearts, humans: 1, ai: 3, options: ["targetScore": 26])
        var generator = SeededGenerator(seed: configuration.seed)
        var state = rules.setup(configuration: configuration, generator: &generator)
        var guardCount = 0
        while state.roundNumber == 1 && state.finalResult == nil && guardCount < 4000 {
            guardCount += 1
            _ = rules.advanceAutomatically(&state, generator: &generator)
            guard state.finalResult == nil, let seat = state.activeSeat else { break }
            guard let action = rules.legalActions(in: state, for: seat).first else { break }
            _ = rules.apply(action, to: &state, generator: &generator)
            if state.phase == .scoring { break }
        }
        if state.phase == .scoring {
            let total = state.roundPoints.values.reduce(0, +)
            XCTAssertEqual(total, 26, "thirteen hearts plus the queen is twenty-six")
        }
    }
}

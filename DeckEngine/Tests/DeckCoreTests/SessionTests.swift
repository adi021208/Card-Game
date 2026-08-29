import XCTest
@testable import DeckCore

/// A minimal game, written only for these tests.
///
/// Two players take turns playing any card from their hand onto a shared pile;
/// whoever empties their hand first wins. It exercises the whole session
/// contract — setup, legality, apply, tokens, observation, presentation,
/// checkpointing and replay — without any real game's rules getting in the way.
struct ToyRules: GameRules {
    static let gameID = GameID("toy")
    static let rulesVersion = 3

    struct State: GameStateProtocol {
        var board: Board
        var activeSeat: SeatID?
        var roundNumber: Int
        var finalResult: GameResult?
        var seatOrder: [SeatID]
        var moves: Int
    }

    enum Action: Hashable, Sendable {
        case play(CardID)
    }

    struct Observation: Sendable {
        var hand: [Card]
        var topOfPile: Card?
        var opponentCount: Int
    }

    func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State {
        var board = Board()
        var deck = DeckConfiguration.standard52.build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)
        let seats = configuration.seating.ids
        board.ensureZones(seats.map { Zone.hand($0) } + [.stock, .discard])
        for _ in 0..<5 {
            for seat in seats {
                board.draw(from: .stock, to: .hand(seat), facing: .hand(seat))
            }
        }
        return State(board: board,
                     activeSeat: seats.first,
                     roundNumber: 1,
                     finalResult: nil,
                     seatOrder: seats,
                     moves: 0)
    }

    func legalActions(in state: State, for seat: SeatID) -> [Action] {
        guard state.finalResult == nil, state.activeSeat == seat else { return [] }
        return state.board.contents(of: .hand(seat)).sorted().map { Action.play($0) }
    }

    func rejection(for action: Action, in state: State) -> IllegalMove? {
        guard let seat = state.activeSeat else { return .notYourTurn }
        guard case let .play(card) = action else { return .noSuchAction }
        guard state.board.zone(of: card) == Zone.hand(seat) else { return .cardNotInHand }
        return nil
    }

    func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard let seat = state.activeSeat, case let .play(card) = action else { return [] }
        state.board.move(card, to: .discard, facing: .faceUp)
        state.moves += 1
        if state.board.isEmpty(Zone.hand(seat)) {
            let result = GameResult(winners: [seat],
                                    scores: [seat: state.moves],
                                    placements: state.seatOrder,
                                    turnCount: state.moves,
                                    roundCount: 1)
            state.finalResult = result
            state.activeSeat = nil
            return [.cardPlayed(card: card, by: seat, to: .discard), .gameEnded(result)]
        }
        let index = state.seatOrder.firstIndex(of: seat) ?? 0
        let next = state.seatOrder[(index + 1) % state.seatOrder.count]
        state.activeSeat = next
        return [.cardPlayed(card: card, by: seat, to: .discard), .turnChanged(from: seat, to: next)]
    }

    func token(for action: Action, in state: State) -> ActionToken {
        guard case let .play(card) = action else {
            return ActionToken(id: "noop", kind: .passTurn, seat: SeatID(0), labelKey: "noop")
        }
        let seat = state.activeSeat ?? SeatID(0)
        return ActionToken(id: ToyToken.id(seat, card),
                           kind: .playCard,
                           seat: seat,
                           cards: [card],
                           labelKey: "action.play")
    }

    func decodeAction(id: String, in state: State) -> Action? {
        let parts = id.split(separator: "/")
        guard parts.count == 3, parts[1] == "play", let raw = Int(parts[2]) else { return nil }
        return .play(CardID(rawValue: raw))
    }

    func observation(of state: State, for seat: SeatID) -> Observation {
        Observation(hand: state.board.cardList(in: .hand(seat)),
                    topOfPile: state.board.top(of: .discard),
                    opponentCount: state.seatOrder.count - 1)
    }

    func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation {
        TablePresentation(gameID: Self.gameID,
                          viewer: viewer,
                          board: state.board.redacted(for: viewer),
                          slots: [],
                          seats: [],
                          actions: viewer.map { seat in
                              legalActions(in: state, for: seat).map { token(for: $0, in: state) }
                          } ?? [],
                          activeSeat: state.activeSeat,
                          result: state.finalResult)
    }
}

enum ToyToken {
    static func id(_ seat: SeatID, _ card: CardID) -> String {
        "\(seat.rawValue)/play/\(card.rawValue)"
    }
}

private func makeConfiguration(seed: UInt64 = 4242) -> GameConfiguration {
    let seats = [
        Seat(id: SeatID(0), displayName: "A", controller: .human(profileID: "a")),
        Seat(id: SeatID(1), displayName: "B", controller: .human(profileID: "b"))
    ]
    return GameConfiguration(gameID: ToyRules.gameID,
                             seating: SeatingPlan(seats: seats),
                             seed: seed)
}

final class GameSessionTests: XCTestCase {

    func testSessionDealsAndOffersMoves() {
        let session = GameSession(rules: ToyRules(), configuration: makeConfiguration())
        XCTAssertEqual(session.activeSeat, SeatID(0))
        XCTAssertEqual(session.availableActions(for: SeatID(0)).count, 5)
        XCTAssertTrue(session.availableActions(for: SeatID(1)).isEmpty,
                      "a seat that is not to move has no moves")
    }

    func testPerformingAMoveAdvancesTheTurn() throws {
        let session = GameSession(rules: ToyRules(), configuration: makeConfiguration())
        let token = try XCTUnwrap(session.availableActions(for: SeatID(0)).first)
        let events = try session.perform(token)
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(session.activeSeat, SeatID(1))
        XCTAssertEqual(session.turnCount, 1)
        XCTAssertEqual(session.replayLog, [token.id])
    }

    func testIllegalMoveThrowsWithAReason() throws {
        let session = GameSession(rules: ToyRules(), configuration: makeConfiguration())
        // A card from the other player's hand. A presentation board holds
        // VisibleCards, whose id is there whether the face is known or
        // concealed — that is the whole point of the seam. Unwrapping rather
        // than defaulting: an empty opponent hand should fail this test, not
        // quietly hand it a card that never existed.
        let opponentCard = try XCTUnwrap(session.presentation(for: SeatID(1))
            .board.contents(of: .hand(SeatID(1))).first)
        let bogus = ActionToken(id: ToyToken.id(SeatID(0), opponentCard.id),
                                kind: .playCard,
                                seat: SeatID(0),
                                labelKey: "action.play")
        XCTAssertThrowsError(try session.perform(bogus)) { error in
            guard case let GameSessionError.illegal(reason) = error else {
                return XCTFail("expected an illegal-move error, got \(error)")
            }
            XCTAssertEqual(reason, .cardNotInHand)
        }
    }

    func testGameReachesAResult() throws {
        let session = GameSession(rules: ToyRules(), configuration: makeConfiguration())
        var guardCount = 0
        while session.result == nil && guardCount < 40 {
            guardCount += 1
            guard let seat = session.activeSeat,
                  let token = session.availableActions(for: seat).first else { break }
            try session.perform(token)
        }
        let result = try XCTUnwrap(session.result)
        XCTAssertEqual(result.winners.count, 1)
        XCTAssertEqual(session.availableActions(for: SeatID(0)).count, 0,
                       "a finished game offers no moves")
    }

    func testCheckpointRoundTrip() throws {
        let session = GameSession(rules: ToyRules(), configuration: makeConfiguration())
        for _ in 0..<3 {
            guard let seat = session.activeSeat,
                  let token = session.availableActions(for: seat).first else { break }
            try session.perform(token)
        }
        let checkpoint = try session.checkpoint()
        XCTAssertEqual(checkpoint.gameID, ToyRules.gameID)
        XCTAssertEqual(checkpoint.rulesVersion, ToyRules.rulesVersion)
        XCTAssertEqual(checkpoint.replayLog.count, 3)

        let restored = try GameSession.restore(rules: ToyRules(), checkpoint: checkpoint)
        XCTAssertEqual(restored.state, session.state)
        XCTAssertEqual(restored.replayLog, session.replayLog)
        XCTAssertEqual(restored.activeSeat, session.activeSeat)
    }

    func testCheckpointFromDifferentRulesIsRefused() throws {
        let session = GameSession(rules: ToyRules(), configuration: makeConfiguration())
        var checkpoint = try session.checkpoint()
        checkpoint.rulesVersion = ToyRules.rulesVersion + 1
        XCTAssertThrowsError(try GameSession.restore(rules: ToyRules(), checkpoint: checkpoint)) { error in
            guard case GameSessionError.checkpointRulesMismatch = error else {
                return XCTFail("expected a rules mismatch, got \(error)")
            }
        }
    }

    func testCheckpointFromAnotherGameIsRefused() throws {
        let session = GameSession(rules: ToyRules(), configuration: makeConfiguration())
        var checkpoint = try session.checkpoint()
        checkpoint.gameID = GameID("something-else")
        XCTAssertThrowsError(try GameSession.restore(rules: ToyRules(), checkpoint: checkpoint))
    }

    func testCorruptCheckpointIsRefused() throws {
        let session = GameSession(rules: ToyRules(), configuration: makeConfiguration())
        var checkpoint = try session.checkpoint()
        checkpoint.stateData = Data("not a game".utf8)
        XCTAssertThrowsError(try GameSession.restore(rules: ToyRules(), checkpoint: checkpoint)) { error in
            guard case GameSessionError.checkpointCorrupt = error else {
                return XCTFail("expected corruption, got \(error)")
            }
        }
    }

    func testReplayReproducesTheGame() throws {
        let session = GameSession(rules: ToyRules(), configuration: makeConfiguration(seed: 99))
        for _ in 0..<5 {
            guard let seat = session.activeSeat,
                  let token = session.availableActions(for: seat).last else { break }
            try session.perform(token)
        }
        XCTAssertNoThrow(try session.verifyReplay())
    }

    func testTheSameSeedDealsTheSameGame() {
        let first = GameSession(rules: ToyRules(), configuration: makeConfiguration(seed: 7))
        let second = GameSession(rules: ToyRules(), configuration: makeConfiguration(seed: 7))
        XCTAssertEqual(first.state, second.state)

        let different = GameSession(rules: ToyRules(), configuration: makeConfiguration(seed: 8))
        XCTAssertNotEqual(first.state, different.state)
    }

    func testAgentReceivesAnObservationAndNotTheState() throws {
        var seenHandCounts: [Int] = []
        let seats = [
            Seat(id: SeatID(0), displayName: "You", controller: .human(profileID: "you")),
            Seat(id: SeatID(1), displayName: "Hal", controller: .ai(personality: .hal, difficulty: .casual))
        ]
        let configuration = GameConfiguration(gameID: ToyRules.gameID,
                                              seating: SeatingPlan(seats: seats),
                                              seed: 5150)
        let session = GameSession(rules: ToyRules(), configuration: configuration) { observation, legal, _, _ in
            // The observation contains exactly one hand: the agent's own.
            seenHandCounts.append(observation.hand.count)
            return legal.first
        }
        // Move to the AI's turn.
        let token = try XCTUnwrap(session.availableActions(for: SeatID(0)).first)
        try session.perform(token)
        let aiToken = try XCTUnwrap(session.aiMove(for: SeatID(1)))
        try session.perform(aiToken)
        XCTAssertEqual(seenHandCounts, [5])
    }

    func testAIDeliberationDoesNotChangeTheDeal() throws {
        let seats = [
            Seat(id: SeatID(0), displayName: "You", controller: .human(profileID: "you")),
            Seat(id: SeatID(1), displayName: "Hal", controller: .ai(personality: .hal, difficulty: .expert))
        ]
        let configuration = GameConfiguration(gameID: ToyRules.gameID,
                                              seating: SeatingPlan(seats: seats),
                                              seed: 31337)
        // One session where the agent burns a lot of randomness, one where it
        // burns none. The deal must be identical either way.
        let greedy = GameSession(rules: ToyRules(), configuration: configuration) { _, legal, _, generator in
            for _ in 0..<500 { _ = generator.next() }
            return legal.first
        }
        let frugal = GameSession(rules: ToyRules(), configuration: configuration) { _, legal, _, _ in
            legal.first
        }
        for session in [greedy, frugal] {
            let token = try XCTUnwrap(session.availableActions(for: SeatID(0)).first)
            try session.perform(token)
            let aiToken = try XCTUnwrap(session.aiMove(for: SeatID(1)))
            try session.perform(aiToken)
        }
        XCTAssertEqual(greedy.state, frugal.state,
                       "how hard the AI thinks must not change what was dealt")
    }

    func testUndoIsRefusedWhenTheGameDoesNotSupportIt() throws {
        let session = GameSession(rules: ToyRules(), configuration: makeConfiguration())
        let token = try XCTUnwrap(session.availableActions(for: SeatID(0)).first)
        try session.perform(token)
        XCTAssertFalse(session.canUndo)
        XCTAssertFalse(session.undo())
    }

    func testResultCarriesTheEngineMeasuredMetrics() throws {
        let session = GameSession(rules: ToyRules(), configuration: makeConfiguration())
        var guardCount = 0
        while session.result == nil && guardCount < 40 {
            guardCount += 1
            guard let seat = session.activeSeat,
                  let token = session.availableActions(for: seat).first else { break }
            try session.perform(token)
        }
        let result = try XCTUnwrap(session.result)
        XCTAssertNotNil(result.metrics[GlobalMetrics.turns])
        XCTAssertEqual(result.metrics[GlobalMetrics.undoCount], 0)
        XCTAssertEqual(result.metrics[GlobalMetrics.hintsUsed], 0)
    }
}

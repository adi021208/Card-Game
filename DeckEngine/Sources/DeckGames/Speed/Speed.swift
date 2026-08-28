import Foundation
import DeckCore

/// Speed.
///
/// The only game in the library where nobody waits their turn: both players
/// reach for the same two piles at once. The engine models that honestly —
/// `activeSeat` is nil and a move from either seat is legal at any moment — and
/// the interface paces the opponent with its reaction time rather than pretending
/// it takes turns.
public struct SpeedRules: GameRules {
    public static let gameID = GameID.speed
    public static let rulesVersion = 1

    public init() {}

    public struct Settings: Hashable, Codable, Sendable {
        /// Cards held at once.
        public var handSize: Int
        /// Cards set aside for each player's replacement pile.
        public var replacementSize: Int

        public init(handSize: Int = 5, replacementSize: Int = 5) {
            self.handSize = max(3, min(7, handSize))
            self.replacementSize = max(1, min(10, replacementSize))
        }

        public static func from(_ configuration: GameConfiguration) -> Settings {
            Settings(handSize: configuration.option("handSize", default: 5),
                     replacementSize: configuration.option("replacementSize", default: 5))
        }
    }

    public struct State: GameStateProtocol {
        public var board: Board
        /// Always nil: anybody may move at any time. This is what tells the rest
        /// of the app that the game is simultaneous.
        public var activeSeat: SeatID?
        public var roundNumber: Int
        public var finalResult: GameResult?

        public var settings: Settings
        public var seatOrder: [SeatID]
        public var cardsPlayed: [SeatID: Int]
        public var flipsUsed: Int
        public var moveCount: Int
        /// Set when neither player can move, so a new pair of centre cards is due.
        public var deadlocked: Bool

        /// A player's face-down draw pile.
        public func drawZone(_ seat: SeatID) -> Zone { Zone(.stock, owner: seat) }
        /// A player's face-down replacement pile, turned over when nobody can move.
        public func replacementZone(_ seat: SeatID) -> Zone { Zone(.reserve, owner: seat) }
        /// The two piles in the middle.
        public static func centreZone(_ index: Int) -> Zone { Zone(.discard, index: index) }

        public func hand(_ seat: SeatID) -> [Card] { board.cardList(in: .hand(seat)) }
        public func remaining(_ seat: SeatID) -> Int {
            board.count(in: .hand(seat)) + board.count(in: drawZone(seat))
        }
    }

    public enum Action: Hashable, Sendable {
        /// Slap a card onto one of the two centre piles.
        case play(seat: SeatID, card: CardID, pile: Int)
        /// Both players are stuck: turn a new card onto each centre pile.
        case breakDeadlock(seat: SeatID)
    }

    public struct Observation: Sendable {
        public var seat: SeatID
        public var hand: [Card]
        public var centreTops: [Card?]
        public var ownDrawCount: Int
        public var opponentHandCount: Int
        public var opponentDrawCount: Int
        public var deadlocked: Bool
    }

    // MARK: - Setup

    public func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State {
        let settings = Settings.from(configuration)
        let seats = Array(configuration.seating.ids.prefix(2))
        var board = Board()
        var deck = DeckConfiguration.standard52.build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)

        var zones: [Zone] = [.stock, State.centreZone(0), State.centreZone(1)]
        for seat in seats {
            zones.append(Zone.hand(seat))
            zones.append(Zone(.stock, owner: seat))
            zones.append(Zone(.reserve, owner: seat))
        }
        board.ensureZones(zones)

        // Each player gets a replacement pile, a hand and a draw pile; the split
        // is even, so a 52-card pack divides cleanly in two.
        for seat in seats {
            for _ in 0..<settings.replacementSize {
                board.draw(from: .stock, to: Zone(.reserve, owner: seat), facing: .faceDown)
            }
        }
        for seat in seats {
            for _ in 0..<settings.handSize {
                board.draw(from: .stock, to: .hand(seat), facing: .hand(seat))
            }
        }
        var index = 0
        while board.count(in: .stock) > 0 {
            let seat = seats[index % seats.count]
            board.draw(from: .stock, to: Zone(.stock, owner: seat), facing: .faceDown)
            index += 1
        }
        for seat in seats { board.sort(.hand(seat), by: HandSort.byRankThenSuit) }

        var state = State(board: board,
                          activeSeat: nil,
                          roundNumber: 1,
                          finalResult: nil,
                          settings: settings,
                          seatOrder: seats,
                          cardsPlayed: [:],
                          flipsUsed: 0,
                          moveCount: 0,
                          deadlocked: false)
        // Turn the two starting cards.
        for (index, seat) in seats.enumerated() {
            if let card = state.board.contents(of: state.replacementZone(seat)).last {
                state.board.move(card, to: State.centreZone(index), facing: .faceUp)
            }
        }
        state.flipsUsed = 1
        return state
    }

    // MARK: - Rules

    /// A card goes onto a centre pile when it is one rank above or below the top
    /// card, with ace wrapping between king and two.
    public static func isPlayable(_ card: Card, on top: Card) -> Bool {
        guard let cardRank = card.rank, let topRank = top.rank else { return false }
        let a = cardRank.rawValue
        let b = topRank.rawValue
        if abs(a - b) == 1 { return true }
        // Ace joins both ends: A-2 and K-A.
        let aceLowA = cardRank.aceLowValue
        let aceLowB = topRank.aceLowValue
        return abs(aceLowA - aceLowB) == 1
    }

    public func legalActions(in state: State, for seat: SeatID) -> [Action] {
        guard state.finalResult == nil else { return [] }
        guard state.seatOrder.contains(seat) else { return [] }
        var actions: [Action] = []
        for card in state.hand(seat) {
            for pile in 0..<2 {
                guard let top = state.board.top(of: State.centreZone(pile)) else { continue }
                if Self.isPlayable(card, on: top) {
                    actions.append(.play(seat: seat, card: card.id, pile: pile))
                }
            }
        }
        if actions.isEmpty && isDeadlocked(state) && canFlip(state) {
            actions.append(.breakDeadlock(seat: seat))
        }
        return actions
    }

    /// True when neither player holds a card that will go.
    public func isDeadlocked(_ state: State) -> Bool {
        for seat in state.seatOrder {
            for card in state.hand(seat) {
                for pile in 0..<2 {
                    guard let top = state.board.top(of: State.centreZone(pile)) else { continue }
                    if Self.isPlayable(card, on: top) { return false }
                }
            }
        }
        return true
    }

    private func canFlip(_ state: State) -> Bool {
        state.seatOrder.allSatisfy { state.board.count(in: state.replacementZone($0)) > 0 }
    }

    public func rejection(for action: Action, in state: State) -> IllegalMove? {
        guard state.finalResult == nil else { return .gameOver }
        switch action {
        case let .play(seat, cardID, pile):
            guard state.board.zone(of: cardID) == Zone.hand(seat) else { return .cardNotInHand }
            guard let card = state.board.card(cardID) else { return .cardNotInHand }
            guard pile >= 0, pile < 2, let top = state.board.top(of: State.centreZone(pile)) else {
                return .emptyPile
            }
            guard Self.isPlayable(card, on: top) else {
                return IllegalMove("mustBeAdjacentRank",
                                   english: "A card only goes on one exactly a rank above or below.")
            }
            return nil
        case .breakDeadlock:
            guard isDeadlocked(state) else {
                return IllegalMove("someoneCanStillPlay",
                                   english: "Somebody can still play — keep going.")
            }
            guard canFlip(state) else {
                return IllegalMove("noReplacementsLeft", english: "There are no cards left to turn.")
            }
            return nil
        }
    }

    public func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        var events: [GameEvent] = []
        switch action {
        case let .play(seat, cardID, pile):
            state.board.move(cardID, to: State.centreZone(pile), facing: .faceUp)
            state.cardsPlayed[seat, default: 0] += 1
            state.moveCount += 1
            events.append(.cardPlayed(card: cardID, by: seat, to: State.centreZone(pile)))
            // Draw straight back up to a full hand, which is what makes it fast.
            while state.board.count(in: .hand(seat)) < state.settings.handSize,
                  state.board.count(in: state.drawZone(seat)) > 0 {
                if let drawn = state.board.draw(from: state.drawZone(seat),
                                                to: .hand(seat),
                                                facing: .hand(seat)) {
                    events.append(.cardDrawn(card: drawn.id, by: seat, from: state.drawZone(seat)))
                }
            }
            state.board.sort(.hand(seat), by: HandSort.byRankThenSuit)
            if state.remaining(seat) == 0 {
                events += finish(state: &state, winner: seat)
                return events
            }

        case .breakDeadlock:
            state.flipsUsed += 1
            state.deadlocked = false
            for (index, seat) in state.seatOrder.enumerated() {
                if let card = state.board.contents(of: state.replacementZone(seat)).last {
                    state.board.move(card, to: State.centreZone(index % 2), facing: .faceUp)
                    events.append(.cardFlipped(card: card, faceUp: true))
                }
            }
        }

        state.deadlocked = isDeadlocked(state)
        if state.deadlocked && !canFlip(state) {
            // Nobody can move and there is nothing to turn: whoever has fewer
            // cards left has won.
            let ranked = state.seatOrder.sorted { state.remaining($0) < state.remaining($1) }
            events += finish(state: &state, winner: ranked[0])
        }
        return events
    }

    private func finish(state: inout State, winner: SeatID) -> [GameEvent] {
        let ranked = state.seatOrder.sorted { state.remaining($0) < state.remaining($1) }
        var scores: [SeatID: Int] = [:]
        for seat in state.seatOrder { scores[seat] = 52 - state.remaining(seat) }
        var metrics: [String: Int] = [:]
        metrics[SpeedStatistics.cardsPlayed] = state.cardsPlayed[winner] ?? 0
        metrics[SpeedStatistics.flips] = state.flipsUsed
        var highlights = ["speed.win"]
        if state.flipsUsed <= 2 { highlights.append("speed.clean") }
        let result = GameResult(winners: [winner],
                                scores: scores,
                                placements: ranked,
                                duration: 0,
                                turnCount: state.moveCount,
                                roundCount: 1,
                                metrics: metrics,
                                highlights: highlights)
        state.finalResult = result
        state.activeSeat = nil
        return [.gameEnded(result)]
    }

    // MARK: - Tokens

    public func token(for action: Action, in state: State) -> ActionToken {
        switch action {
        case let .play(seat, cardID, pile):
            return ActionToken(id: TokenID.make(seat, "play", [String(cardID.rawValue), String(pile)]),
                               kind: .playCard,
                               seat: seat,
                               cards: [cardID],
                               destination: State.centreZone(pile),
                               source: .hand(seat),
                               labelKey: "action.play")
        case let .breakDeadlock(seat):
            return ActionToken(id: TokenID.make(seat, "flip"),
                               kind: .dealNext,
                               seat: seat,
                               labelKey: "action.turnCentre")
        }
    }

    public func decodeAction(id: String, in state: State) -> Action? {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count >= 2, let rawSeat = Int(parts[0]) else { return nil }
        let seat = SeatID(rawSeat)
        switch parts[1] {
        case "flip": return .breakDeadlock(seat: seat)
        case "play":
            guard parts.count >= 4, let raw = Int(parts[2]), let pile = Int(parts[3]) else { return nil }
            return .play(seat: seat, card: CardID(rawValue: raw), pile: pile)
        default: return nil
        }
    }

    // MARK: - Observation

    public func observation(of state: State, for seat: SeatID) -> Observation {
        let other = state.seatOrder.first { $0 != seat } ?? seat
        return Observation(seat: seat,
                           hand: state.hand(seat),
                           centreTops: [state.board.top(of: State.centreZone(0)),
                                        state.board.top(of: State.centreZone(1))],
                           ownDrawCount: state.board.count(in: state.drawZone(seat)),
                           opponentHandCount: state.board.count(in: .hand(other)),
                           opponentDrawCount: state.board.count(in: state.drawZone(other)),
                           deadlocked: state.deadlocked)
    }

    // MARK: - Presentation

    public func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation {
        var slots: [TableSlot] = []
        if let own = TableBuilder.ownHandSlot(viewer: viewer, seating: seating, style: .row(overlap: 0.15)) {
            slots.append(own)
        }
        slots += TableBuilder.opponentSlots(seating: seating, viewer: viewer)
        for pile in 0..<2 {
            slots.append(TableSlot(zone: State.centreZone(pile),
                                   style: .stack,
                                   anchor: .centre(order: pile),
                                   acceptsDrop: true,
                                   prominence: 1.6))
        }
        for seat in seating.ids {
            slots.append(TableSlot(zone: Zone(.stock, owner: seat),
                                   style: .stack,
                                   anchor: seat == viewer ? .corner(.bottomTrailing) : .corner(.topTrailing),
                                   titleKey: "zone.yourDeck"))
        }

        var callouts: [TableCallout] = []
        if state.deadlocked {
            callouts.append(TableCallout(id: "stuck", labelKey: "callout.bothStuck", emphasis: .alert))
        }
        for seat in state.seatOrder {
            callouts.append(TableCallout(id: "left\(seat.rawValue)",
                                         labelKey: "callout.cardsLeft",
                                         arguments: [String(state.remaining(seat))],
                                         emphasis: seat == viewer ? .primary : .secondary))
        }

        var scores: [SeatID: Int] = [:]
        for seat in state.seatOrder { scores[seat] = state.remaining(seat) }

        let actions = viewer.map { seat in
            legalActions(in: state, for: seat).map { token(for: $0, in: state) }
        } ?? []

        return TablePresentation(gameID: Self.gameID,
                                 viewer: viewer,
                                 board: state.board.redacted(for: viewer),
                                 slots: slots,
                                 seats: TableBuilder.seatStatuses(seating: seating,
                                                                  board: state.board,
                                                                  activeSeat: nil,
                                                                  scores: scores,
                                                                  scoreLabelKey: "label.cardsLeft"),
                                 callouts: callouts,
                                 actions: actions,
                                 playableCards: Set(actions.flatMap(\.cards)),
                                 activeSeat: nil,
                                 roundNumber: 1,
                                 phaseKey: "phase.speed",
                                 result: state.finalResult)
    }

    public func hint(for state: State, seat: SeatID) -> Hint? {
        let actions = legalActions(in: state, for: seat)
        if actions.isEmpty {
            return Hint(messageKey: "hint.speed.stuck",
                        english: "Nothing in your hand fits either pile. Watch for the moment your opponent changes one — that is when your card becomes playable.")
        }
        let cards = actions.compactMap { action -> CardID? in
            guard case let .play(_, card, _) = action else { return nil }
            return card
        }
        return Hint(messageKey: "hint.speed.playable",
                    arguments: [String(cards.count)],
                    english: "You have \(cards.count) cards that fit. Playing the one that leaves you a follow-up on the same pile is worth more than playing the first one you see.",
                    cards: cards)
    }
}

public enum SpeedStatistics {
    public static let cardsPlayed = "speed.cardsPlayed"
    public static let flips = "speed.flips"
}

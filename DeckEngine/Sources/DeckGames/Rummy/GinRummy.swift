import Foundation
import DeckCore

/// Gin Rummy.
///
/// Two players, ten cards each, and one decision every turn: take the card you
/// can see or the one you cannot. Knocking early is safe and small; going for
/// gin is worth more and loses badly when the other player gets there first.
public struct GinRummyRules: GameRules {
    public static let gameID = GameID.ginRummy
    public static let rulesVersion = 1

    public init() {}

    public struct Settings: Hashable, Codable, Sendable {
        public var targetScore: Int
        /// Deadwood a player may knock with. Ten is standard.
        public var knockThreshold: Int
        /// Bonus for going out with no deadwood at all.
        public var ginBonus: Int
        /// Bonus for the defender when their deadwood is not more than the
        /// knocker's.
        public var undercutBonus: Int

        public init(targetScore: Int = 100,
                    knockThreshold: Int = 10,
                    ginBonus: Int = 25,
                    undercutBonus: Int = 25) {
            self.targetScore = targetScore
            self.knockThreshold = knockThreshold
            self.ginBonus = ginBonus
            self.undercutBonus = undercutBonus
        }

        public static func from(_ configuration: GameConfiguration) -> Settings {
            Settings(targetScore: configuration.option("targetScore", default: 100),
                     knockThreshold: configuration.option("knockThreshold", default: 10),
                     ginBonus: configuration.option("ginBonus", default: 25),
                     undercutBonus: configuration.option("undercutBonus", default: 25))
        }
    }

    public enum Phase: Hashable, Codable, Sendable {
        /// Take a card from the stock or the discard pile.
        case draw
        /// Throw one away, or knock.
        case discard
        case roundOver
    }

    public struct State: GameStateProtocol {
        public var board: Board
        public var activeSeat: SeatID?
        public var roundNumber: Int
        public var finalResult: GameResult?

        public var settings: Settings
        public var seatOrder: [SeatID]
        public var phase: Phase
        public var dealerSeat: SeatID
        public var scores: [SeatID: Int]
        public var turnsTaken: Int
        public var ginsScored: [SeatID: Int]
        public var undercuts: [SeatID: Int]
        public var knocks: [SeatID: Int]
        /// True on the very first turn, when the non-dealer may pass the upcard.
        public var openingUpcard: Bool
        /// Both players declined the upcard, so the first draw is from the stock.
        public var upcardRefusals: Int
        public var roundComplete: Bool
        /// Cards each player has taken from the discard pile this hand. Public
        /// information, and the strongest read either player gets.
        public var discardTakes: [SeatID: [CardID]]
        /// The upcard taken this turn, which may not be thrown straight back.
        public var takenUpcard: CardID?
        /// Result of the last knock, for the score screen.
        public var lastKnock: KnockSummary?

        public struct KnockSummary: Hashable, Codable, Sendable {
            public var knocker: SeatID
            public var knockerDeadwood: Int
            public var defenderDeadwood: Int
            public var wasGin: Bool
            public var wasUndercut: Bool
            public var points: Int
        }

        public func hand(_ seat: SeatID) -> [Card] { board.cardList(in: .hand(seat)) }
    }

    public enum Action: Hashable, Sendable {
        case drawFromStock
        case takeDiscard
        /// Decline the opening upcard.
        case passUpcard
        case discard(CardID)
        /// Discard and end the hand.
        case knock(CardID)
    }

    /// A Gin agent sees its hand, the discard pile everyone has watched, and how
    /// many cards are left. Never the opponent's hand, never the stock order.
    public struct Observation: Sendable {
        public var seat: SeatID
        public var hand: [Card]
        public var phase: Phase
        public var discardTop: Card?
        /// The whole discard pile is public: both players saw every card go in.
        public var discardPile: [Card]
        public var stockCount: Int
        public var opponentCardCount: Int
        /// Cards the opponent took from the discard pile, which says a lot.
        public var opponentTookFromDiscard: [Card]
        public var settings: Settings
        public var scores: [SeatID: Int]
    }

    // MARK: - Setup

    public func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State {
        let settings = Settings.from(configuration)
        let seats = configuration.seating.ids
        let dealer = seats[0]
        var scores: [SeatID: Int] = [:]
        for seat in seats { scores[seat] = 0 }
        let board = Self.deal(seats: seats, generator: &generator)
        return State(board: board,
                     activeSeat: seats.count > 1 ? seats[1] : seats[0],
                     roundNumber: 1,
                     finalResult: nil,
                     settings: settings,
                     seatOrder: seats,
                     phase: .draw,
                     dealerSeat: dealer,
                     scores: scores,
                     turnsTaken: 0,
                     ginsScored: [:],
                     undercuts: [:],
                     knocks: [:],
                     openingUpcard: true,
                     upcardRefusals: 0,
                     roundComplete: false,
                     discardTakes: [:],
                     takenUpcard: nil,
                     lastKnock: nil)
    }

    static func deal(seats: [SeatID], generator: inout SeededGenerator) -> Board {
        var board = Board()
        var deck = DeckConfiguration.standard52.build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)
        board.ensureZones(seats.flatMap { [Zone.hand($0), Zone.meld($0, 0)] } + [.stock, .discard])
        for _ in 0..<10 {
            for seat in seats {
                board.draw(from: .stock, to: .hand(seat), facing: .hand(seat))
            }
        }
        for seat in seats { board.sort(.hand(seat), by: HandSort.bySuitThenRank) }
        board.draw(from: .stock, to: .discard, facing: .faceUp)
        return board
    }

    private func opponent(of seat: SeatID, in state: State) -> SeatID {
        state.seatOrder.first { $0 != seat } ?? seat
    }

    // MARK: - Rules

    public func legalActions(in state: State, for seat: SeatID) -> [Action] {
        guard state.finalResult == nil, state.activeSeat == seat else { return [] }
        switch state.phase {
        case .draw:
            var actions: [Action] = []
            if state.board.count(in: .discard) > 0 { actions.append(.takeDiscard) }
            if state.openingUpcard {
                // On the opening turn a player may decline rather than draw.
                actions.append(.passUpcard)
            } else if state.board.count(in: .stock) > 0 {
                actions.append(.drawFromStock)
            }
            return actions
        case .discard:
            let hand = state.hand(seat)
            var actions: [Action] = []
            for card in hand where card.id != state.takenUpcard {
                actions.append(.discard(card.id))
                var remaining = hand
                remaining.removeAll { $0.id == card.id }
                let solution = MeldSolver.best(remaining)
                if solution.deadwoodPoints <= state.settings.knockThreshold {
                    actions.append(.knock(card.id))
                }
            }
            return actions
        case .roundOver:
            return []
        }
    }

    public func rejection(for action: Action, in state: State) -> IllegalMove? {
        guard state.finalResult == nil else { return .gameOver }
        guard let seat = state.activeSeat else { return .notYourTurn }
        switch action {
        case .drawFromStock:
            guard state.phase == .draw else { return .noSuchAction }
            guard !state.openingUpcard else {
                return IllegalMove("mustDecideUpcard",
                                   english: "Take the upcard or pass it first.")
            }
            guard state.board.count(in: .stock) > 0 else { return .emptyPile }
            return nil
        case .takeDiscard:
            guard state.phase == .draw, state.board.count(in: .discard) > 0 else { return .noSuchAction }
            return nil
        case .passUpcard:
            guard state.phase == .draw, state.openingUpcard else { return .noSuchAction }
            return nil
        case let .discard(cardID):
            guard state.phase == .discard else { return .noSuchAction }
            guard state.board.zone(of: cardID) == Zone.hand(seat) else { return .cardNotInHand }
            if let reason = upcardReturn(cardID, in: state) { return reason }
            return nil
        case let .knock(cardID):
            guard state.phase == .discard else { return .noSuchAction }
            guard state.board.zone(of: cardID) == Zone.hand(seat) else { return .cardNotInHand }
            if let reason = upcardReturn(cardID, in: state) { return reason }
            var remaining = state.hand(seat)
            remaining.removeAll { $0.id == cardID }
            let deadwood = MeldSolver.best(remaining).deadwoodPoints
            guard deadwood <= state.settings.knockThreshold else {
                return IllegalMove("deadwoodTooHigh",
                                   arguments: [String(deadwood), String(state.settings.knockThreshold)],
                                   english: "You would still be holding \(deadwood) in deadwood; you can only knock at \(state.settings.knockThreshold) or less.")
            }
            return nil
        }
    }

    /// Taking the upcard and throwing it straight back would pass the turn
    /// without changing anything, so the rules forbid it.
    private func upcardReturn(_ cardID: CardID, in state: State) -> IllegalMove? {
        guard state.takenUpcard == cardID else { return nil }
        return IllegalMove("cannotReturnUpcard",
                           english: "You cannot discard the card you just took from the discard pile.")
    }

    public func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard let seat = state.activeSeat else { return [] }
        var events: [GameEvent] = []
        state.turnsTaken += 1

        switch action {
        case .drawFromStock:
            guard let card = state.board.draw(from: .stock, to: .hand(seat), facing: .hand(seat)) else { break }
            state.board.sort(.hand(seat), by: HandSort.bySuitThenRank)
            state.takenUpcard = nil
            state.phase = .discard
            events.append(.cardDrawn(card: card.id, by: seat, from: .stock))

        case .takeDiscard:
            guard let card = state.board.draw(from: .discard, to: .hand(seat), facing: .hand(seat)) else { break }
            state.board.sort(.hand(seat), by: HandSort.bySuitThenRank)
            state.openingUpcard = false
            state.phase = .discard
            state.discardTakes[seat, default: []].append(card.id)
            state.takenUpcard = card.id
            events.append(.cardDrawn(card: card.id, by: seat, from: .discard))

        case .passUpcard:
            state.upcardRefusals += 1
            if state.upcardRefusals >= 2 {
                // Both declined: from here the game runs normally.
                state.openingUpcard = false
            }
            let next = opponent(of: seat, in: state)
            state.activeSeat = next
            events.append(.turnSkipped(seat: seat))
            events.append(.turnChanged(from: seat, to: next))
            return events

        case let .discard(cardID):
            state.board.move(cardID, to: .discard, facing: .faceUp)
            state.takenUpcard = nil
            state.phase = .draw
            events.append(.cardDiscarded(card: cardID, by: seat))
            // Running the stock down to two cards is a draw.
            if state.board.count(in: .stock) <= 2 {
                events += endRoundAsDraw(state: &state)
                return events
            }
            let next = opponent(of: seat, in: state)
            state.activeSeat = next
            events.append(.turnChanged(from: seat, to: next))
            return events

        case let .knock(cardID):
            state.board.move(cardID, to: .discard, facing: .faceUp)
            state.takenUpcard = nil
            events.append(.cardDiscarded(card: cardID, by: seat))
            events += resolveKnock(knocker: seat, state: &state)
            return events
        }
        return events
    }

    private func resolveKnock(knocker: SeatID, state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        let defender = opponent(of: knocker, in: state)
        let knockerSolution = MeldSolver.best(state.hand(knocker))
        var defenderSolution = MeldSolver.best(state.hand(defender))

        // Both hands go face up at a knock.
        for seat in state.seatOrder {
            for card in state.hand(seat) {
                state.board.setVisibility(.everyone, for: card.id)
            }
        }
        events.append(.showdown(revealed: [
            knocker: state.hand(knocker).map(\.id),
            defender: state.hand(defender).map(\.id)
        ]))

        let wasGin = knockerSolution.deadwoodPoints == 0
        var defenderDeadwood = defenderSolution.deadwoodPoints
        if !wasGin {
            // The defender lays off onto the knocker's melds — but not after gin.
            let layOff = MeldSolver.layOff(deadwood: defenderSolution.deadwood, onto: knockerSolution.melds)
            defenderDeadwood = layOff.remaining.reduce(0) { $0 + CardScoring.deadwoodPoints($1) }
            defenderSolution = MeldSolution(melds: defenderSolution.melds,
                                            deadwood: layOff.remaining,
                                            deadwoodPoints: defenderDeadwood)
            if !layOff.laidOff.isEmpty {
                events.append(.highlight(code: "gin.laidOff", seat: defender, value: layOff.laidOff.count))
            }
        }

        let difference = defenderDeadwood - knockerSolution.deadwoodPoints
        var winner = knocker
        var points = difference
        var undercut = false

        if wasGin {
            points = defenderDeadwood + state.settings.ginBonus
            state.ginsScored[knocker, default: 0] += 1
            events.append(.highlight(code: "gin.gin", seat: knocker, value: nil))
        } else if difference <= 0 {
            // Undercut: the defender was at least as low as the knocker.
            winner = defender
            points = abs(difference) + state.settings.undercutBonus
            undercut = true
            state.undercuts[defender, default: 0] += 1
            events.append(.highlight(code: "gin.undercut", seat: defender, value: nil))
        } else {
            state.knocks[knocker, default: 0] += 1
        }

        state.scores[winner, default: 0] += points
        state.lastKnock = State.KnockSummary(knocker: knocker,
                                             knockerDeadwood: knockerSolution.deadwoodPoints,
                                             defenderDeadwood: defenderDeadwood,
                                             wasGin: wasGin,
                                             wasUndercut: undercut,
                                             points: points)
        events.append(.scoreChanged(seat: winner, delta: points, total: state.scores[winner] ?? 0))
        events.append(.roundEnded(scores: state.scores))
        state.phase = .roundOver
        state.activeSeat = nil
        state.roundComplete = true
        return events
    }

    private func endRoundAsDraw(state: inout State) -> [GameEvent] {
        state.phase = .roundOver
        state.activeSeat = nil
        state.roundComplete = true
        state.lastKnock = nil
        return [.roundEnded(scores: state.scores), .highlight(code: "gin.washout", seat: nil, value: nil)]
    }

    public func advanceAutomatically(_ state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard state.finalResult == nil, state.roundComplete else { return [] }
        state.roundComplete = false

        if let reached = state.seatOrder.first(where: { (state.scores[$0] ?? 0) >= state.settings.targetScore }) {
            let result = buildResult(state: state, winner: reached)
            state.finalResult = result
            return [.gameEnded(result)]
        }

        state.roundNumber += 1
        state.board = Self.deal(seats: state.seatOrder, generator: &generator)
        state.dealerSeat = opponent(of: state.dealerSeat, in: state)
        state.activeSeat = opponent(of: state.dealerSeat, in: state)
        state.phase = .draw
        state.openingUpcard = true
        state.upcardRefusals = 0
        state.discardTakes = [:]
        state.takenUpcard = nil
        return [.roundStarted(number: state.roundNumber),
                .handsDealt(counts: Dictionary(uniqueKeysWithValues: state.seatOrder.map { ($0, 10) }))]
    }

    private func buildResult(state: State, winner: SeatID) -> GameResult {
        let ranked = state.seatOrder.sorted { (state.scores[$0] ?? 0) > (state.scores[$1] ?? 0) }
        var metrics: [String: Int] = [:]
        metrics[GinRummyStatistics.gins] = state.ginsScored[winner] ?? 0
        metrics[GinRummyStatistics.undercuts] = state.undercuts[winner] ?? 0
        metrics[GinRummyStatistics.knocks] = state.knocks[winner] ?? 0
        metrics[GinRummyStatistics.finalScore] = state.scores[winner] ?? 0
        var highlights: [String] = []
        if (state.ginsScored[winner] ?? 0) > 0 { highlights.append("gin.gin") }
        if (state.undercuts[winner] ?? 0) > 0 { highlights.append("gin.undercut") }
        let loserScore = state.seatOrder.filter { $0 != winner }.map { state.scores[$0] ?? 0 }.max() ?? 0
        if loserScore == 0 { highlights.append("gin.shutout") }
        return GameResult(winners: [winner],
                          scores: state.scores,
                          placements: ranked,
                          duration: 0,
                          turnCount: state.turnsTaken,
                          roundCount: state.roundNumber,
                          metrics: metrics,
                          highlights: highlights)
    }

    // MARK: - Tokens

    public func token(for action: Action, in state: State) -> ActionToken {
        let seat = state.activeSeat ?? state.seatOrder[0]
        switch action {
        case .drawFromStock:
            return ActionToken(id: TokenID.make(seat, "draw"), kind: .drawCard, seat: seat,
                               source: .stock, labelKey: "action.drawStock")
        case .takeDiscard:
            let card = state.board.top(of: .discard)
            return ActionToken(id: TokenID.make(seat, "take"), kind: .drawCard, seat: seat,
                               cards: card.map { [$0.id] } ?? [],
                               source: .discard,
                               labelKey: "action.takeDiscard")
        case .passUpcard:
            return ActionToken(id: TokenID.make(seat, "passup"), kind: .passTurn, seat: seat,
                               labelKey: "action.passUpcard")
        case let .discard(cardID):
            return ActionToken(id: TokenID.make(seat, "discard", card: cardID),
                               kind: .discardCard, seat: seat, cards: [cardID],
                               destination: .discard, source: .hand(seat),
                               labelKey: "action.discard")
        case let .knock(cardID):
            return ActionToken(id: TokenID.make(seat, "knock", card: cardID),
                               kind: .knock, seat: seat, cards: [cardID],
                               destination: .discard, source: .hand(seat),
                               labelKey: "action.knock")
        }
    }

    public func decodeAction(id: String, in state: State) -> Action? {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        switch parts[1] {
        case "draw": return .drawFromStock
        case "take": return .takeDiscard
        case "passup": return .passUpcard
        case "discard":
            guard parts.count >= 3, let raw = Int(parts[2]) else { return nil }
            return .discard(CardID(rawValue: raw))
        case "knock":
            guard parts.count >= 3, let raw = Int(parts[2]) else { return nil }
            return .knock(CardID(rawValue: raw))
        default: return nil
        }
    }

    // MARK: - Observation

    public func observation(of state: State, for seat: SeatID) -> Observation {
        let other = opponent(of: seat, in: state)
        return Observation(seat: seat,
                           hand: state.hand(seat),
                           phase: state.phase,
                           discardTop: state.board.top(of: .discard),
                           discardPile: state.board.cardList(in: .discard),
                           stockCount: state.board.count(in: .stock),
                           opponentCardCount: state.board.count(in: .hand(other)),
                           opponentTookFromDiscard: (state.discardTakes[other] ?? []).compactMap { state.board.card($0) },
                           settings: state.settings,
                           scores: state.scores)
    }

    // MARK: - Presentation

    public func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation {
        var slots: [TableSlot] = []
        if let own = TableBuilder.ownHandSlot(viewer: viewer, seating: seating) { slots.append(own) }
        slots += TableBuilder.opponentSlots(seating: seating, viewer: viewer)
        slots.append(TableSlot(zone: .stock, style: .stack, anchor: .centre(order: 0),
                               titleKey: "zone.stock", acceptsDrop: true))
        slots.append(TableSlot(zone: .discard, style: .stack, anchor: .centre(order: 1),
                               titleKey: "zone.discard", acceptsDrop: true, prominence: 1.3))

        var callouts: [TableCallout] = []
        if let viewer {
            let solution = MeldSolver.best(state.hand(viewer))
            callouts.append(TableCallout(id: "deadwood",
                                         labelKey: "callout.deadwood",
                                         arguments: [String(solution.deadwoodPoints)],
                                         emphasis: solution.deadwoodPoints <= state.settings.knockThreshold ? .alert : .primary))
        }
        callouts.append(TableCallout(id: "stock",
                                     labelKey: "callout.cardsInStock",
                                     arguments: [String(state.board.count(in: .stock))]))
        callouts.append(TableCallout(id: "target",
                                     labelKey: "callout.playingTo",
                                     arguments: [String(state.settings.targetScore)]))

        let actions = viewer.flatMap { seat -> [ActionToken]? in
            guard state.activeSeat == seat else { return nil }
            return legalActions(in: state, for: seat).map { token(for: $0, in: state) }
        } ?? []

        return TablePresentation(gameID: Self.gameID,
                                 viewer: viewer,
                                 board: state.board.redacted(for: viewer),
                                 slots: slots,
                                 seats: TableBuilder.seatStatuses(seating: seating,
                                                                  board: state.board,
                                                                  activeSeat: state.activeSeat,
                                                                  dealer: state.dealerSeat,
                                                                  scores: state.scores,
                                                                  scoreLabelKey: "label.points"),
                                 callouts: callouts,
                                 actions: actions,
                                 playableCards: Set(actions.flatMap(\.cards)),
                                 activeSeat: state.activeSeat,
                                 roundNumber: state.roundNumber,
                                 phaseKey: state.phase == .draw ? "phase.draw" : "phase.discard",
                                 result: state.finalResult)
    }

    // MARK: - Hints

    public func hint(for state: State, seat: SeatID) -> Hint? {
        guard state.activeSeat == seat else { return nil }
        let hand = state.hand(seat)
        let solution = MeldSolver.best(hand)

        if state.phase == .draw {
            guard let top = state.board.top(of: .discard) else { return nil }
            let withCard = MeldSolver.best(hand + [top])
            if withCard.deadwoodPoints < solution.deadwoodPoints {
                return Hint(messageKey: "hint.gin.takeDiscard",
                            arguments: [String(solution.deadwoodPoints - withCard.deadwoodPoints)],
                            english: "That card cuts your deadwood by \(solution.deadwoodPoints - withCard.deadwoodPoints). Taking it also tells your opponent what you are collecting — worth it here.",
                            cards: [top.id])
            }
            return Hint(messageKey: "hint.gin.drawStock",
                        english: "The upcard does not help, and taking it would tell your opponent what you are building. Draw blind.")
        }

        if solution.deadwoodPoints <= state.settings.knockThreshold {
            return Hint(messageKey: "hint.gin.canKnock",
                        arguments: [String(solution.deadwoodPoints)],
                        english: "You are down to \(solution.deadwoodPoints) deadwood, so you can knock. Knocking small wins small; holding on for gin wins more and loses badly to an undercut.",
                        cards: solution.deadwood.map(\.id))
        }
        return Hint(messageKey: "hint.gin.discardHigh",
                    arguments: [String(solution.deadwoodPoints)],
                    english: "Your deadwood is \(solution.deadwoodPoints). Throw the highest card that is not part of anything — and prefer one your opponent has shown no interest in.",
                    cards: solution.deadwood.prefix(3).map(\.id))
    }
}

public enum GinRummyStatistics {
    public static let gins = "gin.gins"
    public static let undercuts = "gin.undercuts"
    public static let knocks = "gin.knocks"
    public static let finalScore = "gin.finalScore"
}

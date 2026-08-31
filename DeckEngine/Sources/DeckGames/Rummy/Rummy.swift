import Foundation
import DeckCore

/// Rummy.
///
/// Draw, lay down sets and runs, add to what is already on the table, discard.
/// The tension is between melding early — which scores if the hand ends
/// suddenly — and holding on, which keeps your options open and your intentions
/// hidden.
public struct RummyRules: GameRules {
    public static let gameID = GameID.rummy
    public static let rulesVersion = 1

    public init() {}

    public struct Settings: Hashable, Codable, Sendable {
        public var handSize: Int
        public var targetScore: Int
        /// Cards may be added to melds already on the table, including other
        /// players' melds.
        public var allowLayOff: Bool
        /// Going out in one turn without having melded before doubles the score.
        public var rummyBonus: Bool

        public init(handSize: Int = 10,
                    targetScore: Int = 100,
                    allowLayOff: Bool = true,
                    rummyBonus: Bool = true) {
            self.handSize = max(6, min(13, handSize))
            self.targetScore = targetScore
            self.allowLayOff = allowLayOff
            self.rummyBonus = rummyBonus
        }

        public static func from(_ configuration: GameConfiguration) -> Settings {
            let players = configuration.seating.count
            let defaultHand = players <= 2 ? 10 : (players <= 4 ? 7 : 6)
            return Settings(handSize: configuration.option("handSize", default: defaultHand),
                            targetScore: configuration.option("targetScore", default: 100),
                            allowLayOff: configuration.flag("allowLayOff", default: true),
                            rummyBonus: configuration.flag("rummyBonus", default: true))
        }
    }

    public enum Phase: Hashable, Codable, Sendable {
        case draw
        /// Meld, lay off, then discard to finish.
        case build
        case roundOver
    }

    /// A meld on the table, and who put it there.
    public struct TableMeld: Hashable, Codable, Sendable {
        public var owner: SeatID
        public var index: Int
        public var kind: MeldKind
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
        public var melds: [TableMeld]
        /// Seats that have laid at least one meld this deal.
        public var hasMelded: Set<SeatID>
        public var turnsTaken: Int
        public var meldsLaid: [SeatID: Int]
        public var goneOutCount: [SeatID: Int]
        public var roundComplete: Bool
        public var lastRoundWinner: SeatID?

        public func hand(_ seat: SeatID) -> [Card] { board.cardList(in: .hand(seat)) }
        public func meldCards(_ meld: TableMeld) -> [Card] {
            board.cardList(in: .meld(meld.owner, meld.index))
        }
    }

    public enum Action: Hashable, Sendable {
        case drawFromStock
        case takeDiscard
        /// Lay a valid set or run on the table.
        case meld([CardID])
        /// Add a card to a meld already down.
        case layOff(card: CardID, meldIndex: Int)
        case discard(CardID)
    }

    public struct Observation: Sendable {
        public var seat: SeatID
        public var hand: [Card]
        public var phase: Phase
        public var discardTop: Card?
        public var discardPile: [Card]
        public var stockCount: Int
        public var tableMelds: [[Card]]
        public var opponentCardCounts: [SeatID: Int]
        public var settings: Settings
        public var scores: [SeatID: Int]
    }

    // MARK: - Setup

    public func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State {
        let settings = Settings.from(configuration)
        let seats = configuration.seating.ids
        var scores: [SeatID: Int] = [:]
        for seat in seats { scores[seat] = 0 }
        let board = Self.deal(seats: seats, handSize: settings.handSize, generator: &generator)
        return State(board: board,
                     activeSeat: seats.count > 1 ? seats[1] : seats[0],
                     roundNumber: 1,
                     finalResult: nil,
                     settings: settings,
                     seatOrder: seats,
                     phase: .draw,
                     dealerSeat: seats[0],
                     scores: scores,
                     melds: [],
                     hasMelded: [],
                     turnsTaken: 0,
                     meldsLaid: [:],
                     goneOutCount: [:],
                     roundComplete: false,
                     lastRoundWinner: nil)
    }

    static func deal(seats: [SeatID], handSize: Int, generator: inout SeededGenerator) -> Board {
        var board = Board()
        var deck = DeckConfiguration.standard52.build()
        if seats.count >= 5 { deck = DeckConfiguration.double52.build() }
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)
        var zones: [Zone] = [.stock, .discard]
        for seat in seats {
            zones.append(Zone.hand(seat))
            for index in 0..<12 { zones.append(Zone.meld(seat, index)) }
        }
        board.ensureZones(zones)
        for _ in 0..<handSize {
            for seat in seats { board.draw(from: .stock, to: .hand(seat), facing: .hand(seat)) }
        }
        for seat in seats { board.sort(.hand(seat), by: HandSort.bySuitThenRank) }
        board.draw(from: .stock, to: .discard, facing: .faceUp)
        return board
    }

    /// A valid meld: three or more of a rank, or three or more in sequence in one suit.
    public static func isValidMeld(_ cards: [Card]) -> MeldKind? {
        guard cards.count >= 3 else { return nil }
        let ranks = Set(cards.compactMap(\.rank))
        if ranks.count == 1 {
            // Every card in a set must be a different suit.
            let suits = Set(cards.compactMap(\.suit))
            return suits.count == cards.count ? .set : nil
        }
        let suits = Set(cards.compactMap(\.suit))
        guard suits.count == 1 else { return nil }
        let values = cards.compactMap { $0.rank?.aceLowValue }.sorted()
        guard values.count == cards.count, Set(values).count == values.count else { return nil }
        for index in 1..<values.count where values[index] != values[index - 1] + 1 { return nil }
        return .run
    }

    private func nextSeat(after seat: SeatID, in state: State) -> SeatID {
        guard let index = state.seatOrder.firstIndex(of: seat) else { return state.seatOrder[0] }
        return state.seatOrder[(index + 1) % state.seatOrder.count]
    }

    // MARK: - Rules

    public func legalActions(in state: State, for seat: SeatID) -> [Action] {
        guard state.finalResult == nil, state.activeSeat == seat else { return [] }
        switch state.phase {
        case .draw:
            var actions: [Action] = []
            if state.board.count(in: .stock) > 0 { actions.append(.drawFromStock) }
            if state.board.count(in: .discard) > 0 { actions.append(.takeDiscard) }
            return actions
        case .build:
            var actions: [Action] = []
            let hand = state.hand(seat)
            // Every valid meld the hand contains. The interface builds a
            // selection; this list is what the agent searches.
            for candidate in MeldSolver.enumerateMelds(hand) where Self.isValidMeld(candidate) != nil {
                actions.append(.meld(candidate.map(\.id).sorted()))
            }
            if state.settings.allowLayOff {
                for card in hand {
                    for (index, meld) in state.melds.enumerated()
                    where MeldSolver.canLayOff(card, on: state.meldCards(meld)) {
                        actions.append(.layOff(card: card.id, meldIndex: index))
                    }
                }
            }
            for card in hand { actions.append(.discard(card.id)) }
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
            guard state.board.count(in: .stock) > 0 else { return .emptyPile }
            return nil
        case .takeDiscard:
            guard state.phase == .draw else { return .noSuchAction }
            guard state.board.count(in: .discard) > 0 else { return .emptyPile }
            return nil
        case let .meld(ids):
            guard state.phase == .build else { return .noSuchAction }
            for id in ids where state.board.zone(of: id) != Zone.hand(seat) { return .cardNotInHand }
            let cards = ids.compactMap { state.board.card($0) }
            guard cards.count == ids.count, Self.isValidMeld(cards) != nil else {
                return IllegalMove("notAValidMeld",
                                   english: "A meld is three or more of a rank in different suits, or three or more in sequence in one suit.")
            }
            return nil
        case let .layOff(cardID, meldIndex):
            guard state.phase == .build, state.settings.allowLayOff else { return .noSuchAction }
            guard state.board.zone(of: cardID) == Zone.hand(seat) else { return .cardNotInHand }
            guard meldIndex >= 0, meldIndex < state.melds.count, let card = state.board.card(cardID) else {
                return .noSuchAction
            }
            guard MeldSolver.canLayOff(card, on: state.meldCards(state.melds[meldIndex])) else {
                return IllegalMove("cannotLayOff",
                                   english: "That card does not extend the meld you chose.")
            }
            return nil
        case let .discard(cardID):
            guard state.phase == .build else { return .noSuchAction }
            guard state.board.zone(of: cardID) == Zone.hand(seat) else { return .cardNotInHand }
            return nil
        }
    }

    public func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard let seat = state.activeSeat else { return [] }
        var events: [GameEvent] = []
        state.turnsTaken += 1

        switch action {
        case .drawFromStock:
            if let card = state.board.draw(from: .stock, to: .hand(seat), facing: .hand(seat)) {
                events.append(.cardDrawn(card: card.id, by: seat, from: .stock))
            }
            state.board.sort(.hand(seat), by: HandSort.bySuitThenRank)
            state.phase = .build

        case .takeDiscard:
            if let card = state.board.draw(from: .discard, to: .hand(seat), facing: .hand(seat)) {
                events.append(.cardDrawn(card: card.id, by: seat, from: .discard))
            }
            state.board.sort(.hand(seat), by: HandSort.bySuitThenRank)
            state.phase = .build

        case let .meld(ids):
            let cards = ids.compactMap { state.board.card($0) }
            let kind = Self.isValidMeld(cards) ?? .set
            let index = state.melds.filter { $0.owner == seat }.count
            let zone = Zone.meld(seat, index)
            for id in ids {
                // Melds are public the moment they hit the table.
                state.board.move(id, to: zone, facing: .faceUp)
            }
            state.melds.append(TableMeld(owner: seat, index: index, kind: kind))
            state.hasMelded.insert(seat)
            state.meldsLaid[seat, default: 0] += 1
            events.append(.cardsMoved(cards: ids, from: .hand(seat), to: zone))
            events.append(.highlight(code: "rummy.meld", seat: seat, value: ids.count))

        case let .layOff(cardID, meldIndex):
            let meld = state.melds[meldIndex]
            state.board.move(cardID, to: .meld(meld.owner, meld.index), facing: .faceUp)
            events.append(.cardsMoved(cards: [cardID], from: .hand(seat), to: .meld(meld.owner, meld.index)))

        case let .discard(cardID):
            state.board.move(cardID, to: .discard, facing: .faceUp)
            events.append(.cardDiscarded(card: cardID, by: seat))
            if state.board.isEmpty(Zone.hand(seat)) {
                events += endRound(winner: seat, state: &state)
                return events
            }
            state.phase = .draw
            let next = nextSeat(after: seat, in: state)
            state.activeSeat = next
            events.append(.turnChanged(from: seat, to: next))
            // Running out of stock ends the deal with nobody out.
            if state.board.count(in: .stock) == 0 {
                events += endRound(winner: nil, state: &state)
            }
            return events
        }

        // Going out by melding everything is legal in most house rules; the hand
        // still needs a discard, so nothing ends here.
        return events
    }

    private func endRound(winner: SeatID?, state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        var total = 0
        for seat in state.seatOrder where seat != winner {
            let value = state.hand(seat).reduce(0) { $0 + CardScoring.deadwoodPoints($1) }
            total += value
            events.append(.scoreChanged(seat: seat, delta: 0, total: state.scores[seat] ?? 0))
        }
        if let winner {
            var points = total
            // Going out in a single turn without having melded before is a rummy.
            if state.settings.rummyBonus, (state.meldsLaid[winner] ?? 0) <= 1, state.turnsTaken <= state.seatOrder.count * 2 {
                points *= 2
                events.append(.highlight(code: "rummy.rummy", seat: winner, value: nil))
            }
            state.scores[winner, default: 0] += points
            state.goneOutCount[winner, default: 0] += 1
            events.append(.scoreChanged(seat: winner, delta: points, total: state.scores[winner] ?? 0))
        }
        events.append(.roundEnded(scores: state.scores))
        state.phase = .roundOver
        state.activeSeat = nil
        state.roundComplete = true
        state.lastRoundWinner = winner
        return events
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
        state.board = Self.deal(seats: state.seatOrder, handSize: state.settings.handSize, generator: &generator)
        state.melds = []
        state.hasMelded = []
        state.phase = .draw
        state.dealerSeat = nextSeat(after: state.dealerSeat, in: state)
        state.activeSeat = nextSeat(after: state.dealerSeat, in: state)
        return [.roundStarted(number: state.roundNumber),
                .handsDealt(counts: Dictionary(uniqueKeysWithValues: state.seatOrder.map { ($0, state.settings.handSize) }))]
    }

    private func buildResult(state: State, winner: SeatID) -> GameResult {
        let ranked = state.seatOrder.sorted { (state.scores[$0] ?? 0) > (state.scores[$1] ?? 0) }
        var metrics: [String: Int] = [:]
        metrics[RummyStatistics.meldsLaid] = state.meldsLaid[winner] ?? 0
        metrics[RummyStatistics.timesOut] = state.goneOutCount[winner] ?? 0
        metrics[RummyStatistics.finalScore] = state.scores[winner] ?? 0
        var highlights: [String] = []
        if (state.goneOutCount[winner] ?? 0) >= 3 { highlights.append("rummy.streak") }
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
                               cards: card.map { [$0.id] } ?? [], source: .discard,
                               labelKey: "action.takeDiscard")
        case let .meld(ids):
            let sorted = ids.sorted()
            return ActionToken(id: TokenID.make(seat, "meld", cards: sorted),
                               kind: .meld, seat: seat, cards: sorted,
                               source: .hand(seat), amount: sorted.count,
                               labelKey: "action.meld")
        case let .layOff(cardID, meldIndex):
            return ActionToken(id: TokenID.make(seat, "layoff", [String(cardID.rawValue), String(meldIndex)]),
                               kind: .layOff, seat: seat, cards: [cardID],
                               source: .hand(seat), amount: meldIndex,
                               labelKey: "action.layOff")
        case let .discard(cardID):
            return ActionToken(id: TokenID.make(seat, "discard", card: cardID),
                               kind: .discardCard, seat: seat, cards: [cardID],
                               destination: .discard, source: .hand(seat),
                               labelKey: "action.discard")
        }
    }

    public func decodeAction(id: String, in state: State) -> Action? {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        switch parts[1] {
        case "draw": return .drawFromStock
        case "take": return .takeDiscard
        case "meld":
            let ids = parts.dropFirst(2).compactMap { Int($0) }.map { CardID(rawValue: $0) }
            return ids.isEmpty ? nil : .meld(ids)
        case "layoff":
            guard parts.count >= 4, let raw = Int(parts[2]), let index = Int(parts[3]) else { return nil }
            return .layOff(card: CardID(rawValue: raw), meldIndex: index)
        case "discard":
            guard parts.count >= 3, let raw = Int(parts[2]) else { return nil }
            return .discard(CardID(rawValue: raw))
        default: return nil
        }
    }

    // MARK: - Observation

    public func observation(of state: State, for seat: SeatID) -> Observation {
        var counts: [SeatID: Int] = [:]
        for other in state.seatOrder where other != seat {
            counts[other] = state.board.count(in: .hand(other))
        }
        return Observation(seat: seat,
                           hand: state.hand(seat),
                           phase: state.phase,
                           discardTop: state.board.top(of: .discard),
                           discardPile: state.board.cardList(in: .discard),
                           stockCount: state.board.count(in: .stock),
                           tableMelds: state.melds.map { state.meldCards($0) },
                           opponentCardCounts: counts,
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
        for (index, meld) in state.melds.enumerated() {
            slots.append(TableSlot(zone: .meld(meld.owner, meld.index),
                                   style: .row(overlap: 0.55),
                                   anchor: .grid(row: 2 + index / 3, column: index % 3),
                                   acceptsDrop: state.settings.allowLayOff))
        }

        var callouts: [TableCallout] = []
        if let viewer {
            let solution = MeldSolver.best(state.hand(viewer))
            callouts.append(TableCallout(id: "deadwood",
                                         labelKey: "callout.inHand",
                                         arguments: [String(solution.deadwoodPoints)],
                                         emphasis: .primary))
        }
        callouts.append(TableCallout(id: "stock", labelKey: "callout.cardsInStock",
                                     arguments: [String(state.board.count(in: .stock))]))
        callouts.append(TableCallout(id: "target", labelKey: "callout.playingTo",
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
                                 phaseKey: state.phase == .draw ? "phase.draw" : "phase.build",
                                 result: state.finalResult)
    }

    public func hint(for state: State, seat: SeatID) -> Hint? {
        guard state.activeSeat == seat else { return nil }
        let hand = state.hand(seat)
        let solution = MeldSolver.best(hand)
        if state.phase == .draw {
            guard let top = state.board.top(of: .discard) else { return nil }
            let withCard = MeldSolver.best(hand + [top])
            if withCard.melds.count > solution.melds.count {
                return Hint(messageKey: "hint.rummy.takeDiscard",
                            english: "That card completes a meld. Taking from the discard pile shows your hand though — think about whether it is worth the read.",
                            cards: [top.id])
            }
            return Hint(messageKey: "hint.rummy.drawStock",
                        english: "The discard does not finish anything. Draw blind and keep your intentions to yourself.")
        }
        if !solution.melds.isEmpty {
            return Hint(messageKey: "hint.rummy.canMeld",
                        arguments: [String(solution.melds.count)],
                        english: "You can lay \(solution.melds.count) meld(s) down. Melding banks the points but tells everybody what you are collecting, and lets them lay off on you.",
                        cards: solution.melds.flatMap { $0.map(\.id) })
        }
        return Hint(messageKey: "hint.rummy.discardHigh",
                    english: "Throw the high card that is doing the least work. Watch what your opponents pick up — anything near it is dangerous.",
                    cards: solution.deadwood.prefix(3).map(\.id))
    }
}

public enum RummyStatistics {
    public static let meldsLaid = "rummy.meldsLaid"
    public static let timesOut = "rummy.timesOut"
    public static let finalScore = "rummy.finalScore"
}

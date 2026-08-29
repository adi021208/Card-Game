import Foundation
import DeckCore

/// Klondike — the solitaire everybody means when they say solitaire.
///
/// Seven columns, four foundations, and a stock you turn one or three at a time.
/// Build down in alternating colours on the tableau and up in suit on the
/// foundations. Undo is unlimited; hints explain the move rather than making it.
public struct KlondikeRules: GameRules {
    public static let gameID = GameID.klondike
    public static let rulesVersion = 1
    public let supportsUndo = true

    public init() {}

    public static let tableauCount = 7
    public static let foundationCount = 4

    // MARK: - Settings

    public struct Settings: Hashable, Codable, Sendable {
        /// Cards turned from the stock at a time: one (easier) or three.
        public var drawCount: Int
        /// Times the waste may be turned back into the stock. Zero means
        /// unlimited, which is the usual "easy" setting.
        public var redealLimit: Int

        public init(drawCount: Int = 1, redealLimit: Int = 0) {
            self.drawCount = max(1, drawCount)
            self.redealLimit = max(0, redealLimit)
        }

        public static func from(_ configuration: GameConfiguration) -> Settings {
            Settings(drawCount: configuration.option("drawCount", default: 1),
                     redealLimit: configuration.option("redealLimit", default: 0))
        }
    }

    // MARK: - State

    public struct State: GameStateProtocol {
        public var board: Board
        public var activeSeat: SeatID?
        public var roundNumber: Int
        public var finalResult: GameResult?

        public var settings: Settings
        public var seat: SeatID
        public var moveCount: Int
        public var redealsUsed: Int
        /// Windows-style running score, shown alongside moves and time.
        public var score: Int
        public var wonAt: Int?

        public var foundationTotal: Int {
            (0..<KlondikeRules.foundationCount).reduce(0) { $0 + board.count(in: .foundation($1)) }
        }
    }

    public enum Action: Hashable, Sendable {
        /// Turn one (or three) from the stock onto the waste.
        case drawFromStock
        /// Turn the waste back over when the stock is empty.
        case recycleWaste
        /// Move a card, or a face-up run headed by it, to another pile.
        case move(card: CardID, to: Zone)
        /// Send every card that can go to a foundation, repeatedly. Offered only
        /// once the board is fully turned up and the game is a formality.
        case collect
    }

    /// Klondike has no opponent, so the observation is simply the position — but
    /// it still goes through the same channel so the auto-solver and the hint
    /// system read exactly what a player can see, never a face-down card.
    public struct Observation: Sendable {
        public var faceUpTableau: [[Card]]
        public var faceDownCounts: [Int]
        public var foundations: [[Card]]
        public var wasteTop: Card?
        public var wasteCount: Int
        public var stockCount: Int
        public var settings: Settings
    }

    // MARK: - Setup

    public func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State {
        let settings = Settings.from(configuration)
        let seat = configuration.seating.ids.first ?? SeatID(0)
        var board = Board()
        var deck = DeckConfiguration.standard52.build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)
        board.ensureZones((0..<Self.tableauCount).map { Zone.tableau($0) }
                          + (0..<Self.foundationCount).map { Zone.foundation($0) }
                          + [.stock, .waste])

        // Column n gets n+1 cards, the last of which is turned up.
        for column in 0..<Self.tableauCount {
            for row in 0...column {
                let faceUp = row == column
                board.draw(from: .stock,
                           to: .tableau(column),
                           facing: faceUp ? .faceUp : .faceDown)
            }
        }

        return State(board: board,
                     activeSeat: seat,
                     roundNumber: 1,
                     finalResult: nil,
                     settings: settings,
                     seat: seat,
                     moveCount: 0,
                     redealsUsed: 0,
                     score: 0,
                     wonAt: nil)
    }

    // MARK: - Rules

    /// Foundations build up in suit from the ace.
    public func canPlaceOnFoundation(_ card: Card, foundation: Zone, in state: State) -> Bool {
        guard let rank = card.rank, card.suit != nil else { return false }
        guard let top = state.board.top(of: foundation) else { return rank == .ace }
        guard top.suit == card.suit else { return false }
        return rank.rawValue == top.rank.map({ $0.rawValue + 1 })
    }

    /// Tableau piles build down in alternating colours; a King, or a run headed
    /// by one, is the only thing that starts an empty column.
    public func canPlaceOnTableau(_ card: Card, column: Zone, in state: State) -> Bool {
        guard let rank = card.rank else { return false }
        guard let top = state.board.top(of: column) else { return rank == .king }
        guard state.board.isFaceUp(top.id), let topRank = top.rank else { return false }
        guard top.isRed != card.isRed else { return false }
        return rank.rawValue == topRank.rawValue - 1
    }

    /// The face-up run starting at `card` and running to the bottom of its pile.
    /// Only a properly ordered run may be lifted as one.
    public func liftableRun(from card: CardID, in state: State) -> [CardID]? {
        guard let zone = state.board.zone(of: card) else { return nil }
        switch zone.kind {
        case .waste, .foundation:
            // Only the top card of the waste or a foundation is available.
            guard state.board.contents(of: zone).last == card else { return nil }
            return [card]
        case .tableau:
            let contents = state.board.contents(of: zone)
            guard let index = contents.firstIndex(of: card) else { return nil }
            guard state.board.isFaceUp(card) else { return nil }
            let run = Array(contents[index...])
            // Every card in the run must be face-up and correctly sequenced.
            var previous: Card?
            for id in run {
                guard state.board.isFaceUp(id), let current = state.board.card(id) else { return nil }
                if let previous {
                    guard let previousRank = previous.rank, let currentRank = current.rank else { return nil }
                    guard previous.isRed != current.isRed,
                          currentRank.rawValue == previousRank.rawValue - 1 else { return nil }
                }
                previous = current
            }
            return run
        default:
            return nil
        }
    }

    public func legalActions(in state: State, for seat: SeatID) -> [Action] {
        guard state.finalResult == nil else { return [] }
        var actions: [Action] = []

        if state.board.count(in: .stock) > 0 {
            actions.append(.drawFromStock)
        } else if state.board.count(in: .waste) > 0 {
            if state.settings.redealLimit == 0 || state.redealsUsed < state.settings.redealLimit {
                actions.append(.recycleWaste)
            }
        }

        let foundations = (0..<Self.foundationCount).map { Zone.foundation($0) }
        let columns = (0..<Self.tableauCount).map { Zone.tableau($0) }

        // Sources: the waste top, every face-up tableau card, and foundation tops.
        var sources: [CardID] = []
        if let wasteTop = state.board.top(of: .waste) { sources.append(wasteTop.id) }
        for column in columns {
            for id in state.board.contents(of: column) where state.board.isFaceUp(id) {
                sources.append(id)
            }
        }
        for foundation in foundations {
            if let top = state.board.top(of: foundation) { sources.append(top.id) }
        }

        for source in sources {
            guard let card = state.board.card(source),
                  let run = liftableRun(from: source, in: state) else { continue }
            let origin = state.board.zone(of: source)

            if run.count == 1 {
                for foundation in foundations where foundation != origin {
                    if canPlaceOnFoundation(card, foundation: foundation, in: state) {
                        actions.append(.move(card: source, to: foundation))
                        // Only ever offer the first matching foundation; the
                        // other three are the same move with a different slot.
                        break
                    }
                }
            }
            for column in columns where column != origin {
                // Shifting a whole column into an empty one is legal but changes
                // nothing, so it is not offered as a move.
                if state.board.isEmpty(column),
                   let origin, origin.kind == .tableau,
                   state.board.contents(of: origin).first == source {
                    continue
                }
                if canPlaceOnTableau(card, column: column, in: state) {
                    actions.append(.move(card: source, to: column))
                }
            }
        }

        if canCollect(state: state) {
            actions.append(.collect)
        }
        return actions
    }

    /// True once every card is face-up and the rest is mechanical.
    public func canCollect(state: State) -> Bool {
        guard state.foundationTotal < 52 else { return false }
        guard state.board.count(in: .stock) == 0, state.board.count(in: .waste) <= 1 else { return false }
        for column in 0..<Self.tableauCount {
            for id in state.board.contents(of: .tableau(column)) where !state.board.isFaceUp(id) {
                return false
            }
        }
        return true
    }

    public func rejection(for action: Action, in state: State) -> IllegalMove? {
        guard state.finalResult == nil else { return .gameOver }
        switch action {
        case .drawFromStock:
            guard state.board.count(in: .stock) > 0 else { return .emptyPile }
            return nil
        case .recycleWaste:
            guard state.board.count(in: .stock) == 0 else {
                return IllegalMove("stockNotEmpty", english: "Turn the rest of the stock first.")
            }
            guard state.board.count(in: .waste) > 0 else { return .emptyPile }
            guard state.settings.redealLimit == 0 || state.redealsUsed < state.settings.redealLimit else {
                return IllegalMove("noRedealsLeft", english: "No redeals left in this game.")
            }
            return nil
        case let .move(cardID, destination):
            guard let card = state.board.card(cardID) else { return .cardNotInHand }
            guard let run = liftableRun(from: cardID, in: state) else {
                return IllegalMove("cardNotAvailable",
                                   english: "That card is not free to move — turn the cards above it first.")
            }
            switch destination.kind {
            case .foundation:
                guard run.count == 1 else {
                    return IllegalMove("foundationOneCard",
                                       english: "Foundations take one card at a time.")
                }
                guard canPlaceOnFoundation(card, foundation: destination, in: state) else {
                    return IllegalMove("foundationOrder",
                                       english: "Foundations go up in suit, starting with the ace.")
                }
                return nil
            case .tableau:
                guard canPlaceOnTableau(card, column: destination, in: state) else {
                    if state.board.isEmpty(destination) {
                        return IllegalMove("kingsOnly", english: "Only a king can start an empty column.")
                    }
                    return IllegalMove("tableauOrder",
                                       english: "Tableau piles go down in alternating colours.")
                }
                return nil
            default:
                return .noSuchAction
            }
        case .collect:
            guard canCollect(state: state) else { return .noSuchAction }
            return nil
        }
    }

    // MARK: - Applying

    public func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        var events: [GameEvent] = []
        switch action {
        case .drawFromStock:
            let count = min(state.settings.drawCount, state.board.count(in: .stock))
            for _ in 0..<count {
                if let card = state.board.draw(from: .stock, to: .waste, facing: .faceUp) {
                    events.append(.cardDrawn(card: card.id, by: state.seat, from: .stock))
                }
            }
            state.moveCount += 1
        case .recycleWaste:
            let cards = state.board.contents(of: .waste).reversed()
            for id in cards {
                state.board.move(id, to: .stock, facing: .faceDown)
            }
            state.redealsUsed += 1
            state.moveCount += 1
            // Turning the pack costs points in the standard scoring, but never
            // below zero.
            if state.settings.drawCount == 1 { state.score = max(0, state.score - 100) }
            events.append(.deckRecycled(from: .waste, to: .stock))
        case let .move(cardID, destination):
            events += performMove(cardID, to: destination, state: &state)
        case .collect:
            events += collectAll(state: &state)
        }

        if state.foundationTotal == 52 && state.finalResult == nil {
            state.wonAt = state.moveCount
            let result = buildResult(state: state, won: true)
            state.finalResult = result
            state.activeSeat = nil
            events.append(.gameEnded(result))
        }
        return events
    }

    private func performMove(_ cardID: CardID, to destination: Zone, state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        guard let run = liftableRun(from: cardID, in: state),
              let origin = state.board.zone(of: cardID) else { return events }

        state.board.move(run, to: destination)
        for id in run { state.board.flip(id, faceUp: true) }
        state.moveCount += 1
        events.append(.cardsMoved(cards: run, from: origin, to: destination))

        // Scoring follows the familiar Windows rules: it gives the player a
        // number that goes up when they make progress.
        switch (origin.kind, destination.kind) {
        case (.waste, .tableau): state.score += 5
        case (.waste, .foundation): state.score += 10
        case (.tableau, .foundation): state.score += 10
        case (.foundation, .tableau): state.score = max(0, state.score - 15)
        default: break
        }

        if destination.kind == .foundation {
            events.append(.highlight(code: "klondike.toFoundation", seat: state.seat, value: nil))
            if state.board.count(in: destination) == 13 {
                events.append(.foundationCompleted(zone: destination))
            }
        }

        // Turning up the card left exposed underneath is automatic.
        if origin.kind == .tableau, let newTop = state.board.top(of: origin), !state.board.isFaceUp(newTop.id) {
            state.board.flip(newTop.id, faceUp: true)
            state.score += 5
            events.append(.cardFlipped(card: newTop.id, faceUp: true))
        }
        return events
    }

    /// Runs every available foundation move until nothing is left to send.
    private func collectAll(state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        var progressed = true
        var safety = 0
        while progressed && safety < 200 {
            progressed = false
            safety += 1
            var sources: [CardID] = []
            if let wasteTop = state.board.top(of: .waste) { sources.append(wasteTop.id) }
            for column in 0..<Self.tableauCount {
                if let top = state.board.top(of: .tableau(column)) { sources.append(top.id) }
            }
            for source in sources {
                guard let card = state.board.card(source) else { continue }
                for index in 0..<Self.foundationCount {
                    let foundation = Zone.foundation(index)
                    if canPlaceOnFoundation(card, foundation: foundation, in: state) {
                        events += performMove(source, to: foundation, state: &state)
                        progressed = true
                        break
                    }
                }
                if progressed { break }
            }
        }
        return events
    }

    private func buildResult(state: State, won: Bool) -> GameResult {
        var metrics: [String: Int] = [:]
        metrics[KlondikeStatistics.moves] = state.moveCount
        metrics[KlondikeStatistics.score] = state.score
        metrics[KlondikeStatistics.foundationCards] = state.foundationTotal
        var highlights: [String] = []
        if won {
            highlights.append("klondike.win")
            if state.settings.drawCount == 3 { highlights.append("klondike.drawThree") }
            if state.settings.redealLimit > 0 { highlights.append("klondike.limitedRedeals") }
        }
        return GameResult(winners: won ? [state.seat] : [],
                          scores: [state.seat: state.score],
                          placements: [state.seat],
                          duration: 0,
                          turnCount: state.moveCount,
                          roundCount: 1,
                          metrics: metrics,
                          highlights: highlights)
    }

    // MARK: - Tokens

    public func token(for action: Action, in state: State) -> ActionToken {
        let seat = state.seat
        switch action {
        case .drawFromStock:
            return ActionToken(id: TokenID.make(seat, "draw"),
                               kind: .drawCard,
                               seat: seat,
                               source: .stock,
                               labelKey: "action.turnStock")
        case .recycleWaste:
            return ActionToken(id: TokenID.make(seat, "recycle"),
                               kind: .drawCard,
                               seat: seat,
                               destination: .stock,
                               source: .waste,
                               labelKey: "action.recycle")
        case let .move(cardID, destination):
            let cards = liftableRun(from: cardID, in: state) ?? [cardID]
            return ActionToken(id: TokenID.make(seat, "move", [String(cardID.rawValue), Self.encode(destination)]),
                               kind: .moveCards,
                               seat: seat,
                               cards: cards,
                               destination: destination,
                               source: state.board.zone(of: cardID),
                               labelKey: "action.move")
        case .collect:
            return ActionToken(id: TokenID.make(seat, "collect"),
                               kind: .claim,
                               seat: seat,
                               labelKey: "action.collect")
        }
    }

    public func decodeAction(id: String, in state: State) -> Action? {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        switch parts[1] {
        case "draw": return .drawFromStock
        case "recycle": return .recycleWaste
        case "collect": return .collect
        case "move":
            guard parts.count >= 4, let raw = Int(parts[2]), let zone = Self.decode(parts[3]) else { return nil }
            return .move(card: CardID(rawValue: raw), to: zone)
        default: return nil
        }
    }

    /// Compact, stable zone encoding for token ids: `t3`, `f0`, `w`, `s`.
    static func encode(_ zone: Zone) -> String {
        switch zone.kind {
        case .tableau: return "t\(zone.index)"
        case .foundation: return "f\(zone.index)"
        case .freeCell: return "c\(zone.index)"
        case .waste: return "w"
        case .stock: return "s"
        default: return "\(zone.kind.rawValue)\(zone.index)"
        }
    }

    static func decode(_ text: String) -> Zone? {
        guard let first = text.first else { return nil }
        let indexText = String(text.dropFirst())
        let index = Int(indexText) ?? 0
        switch first {
        case "t": return .tableau(index)
        case "f": return .foundation(index)
        case "c": return .freeCell(index)
        case "w": return .waste
        case "s": return .stock
        default: return nil
        }
    }

    // MARK: - Observation

    public func observation(of state: State, for seat: SeatID) -> Observation {
        var faceUp: [[Card]] = []
        var faceDown: [Int] = []
        for column in 0..<Self.tableauCount {
            let contents = state.board.contents(of: .tableau(column))
            let up = contents.filter { state.board.isFaceUp($0) }.compactMap { state.board.card($0) }
            faceUp.append(up)
            faceDown.append(contents.count - up.count)
        }
        let foundations = (0..<Self.foundationCount).map { state.board.cardList(in: .foundation($0)) }
        return Observation(faceUpTableau: faceUp,
                           faceDownCounts: faceDown,
                           foundations: foundations,
                           wasteTop: state.board.top(of: .waste),
                           wasteCount: state.board.count(in: .waste),
                           stockCount: state.board.count(in: .stock),
                           settings: state.settings)
    }

    // MARK: - Presentation

    public func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation {
        var slots: [TableSlot] = []
        slots.append(TableSlot(zone: .stock,
                               style: .stack,
                               anchor: .grid(row: 0, column: 0),
                               titleKey: "zone.stock",
                               emptyHintKey: "zone.stock.turnOver",
                               acceptsDrop: true))
        slots.append(TableSlot(zone: .waste,
                               style: .row(overlap: 0.6),
                               anchor: .grid(row: 0, column: 1),
                               titleKey: "zone.waste"))
        for index in 0..<Self.foundationCount {
            slots.append(TableSlot(zone: .foundation(index),
                                   style: .single,
                                   anchor: .grid(row: 0, column: 3 + index),
                                   emptyHintKey: "zone.foundation.empty",
                                   acceptsDrop: true))
        }
        for index in 0..<Self.tableauCount {
            slots.append(TableSlot(zone: .tableau(index),
                                   style: .cascade,
                                   anchor: .grid(row: 1, column: index),
                                   emptyHintKey: "zone.tableau.kingsOnly",
                                   acceptsDrop: true,
                                   prominence: 1.2))
        }

        let actions = legalActions(in: state, for: state.seat).map { token(for: $0, in: state) }
        let callouts = [
            TableCallout(id: "moves", labelKey: "callout.moves", arguments: [String(state.moveCount)]),
            TableCallout(id: "score", labelKey: "callout.score",
                         arguments: [String(state.score)], emphasis: .primary),
            TableCallout(id: "foundation", labelKey: "callout.foundationProgress",
                         arguments: [String(state.foundationTotal), "52"])
        ]

        return TablePresentation(gameID: Self.gameID,
                                 viewer: viewer,
                                 board: state.board.redacted(for: viewer),
                                 slots: slots,
                                 seats: TableBuilder.seatStatuses(seating: seating,
                                                                  board: state.board,
                                                                  activeSeat: state.activeSeat,
                                                                  scores: [state.seat: state.score],
                                                                  scoreLabelKey: "label.score",
                                                                  handZone: { _ in Zone.waste }),
                                 callouts: callouts,
                                 actions: actions,
                                 playableCards: Set(actions.flatMap(\.cards)),
                                 activeSeat: state.activeSeat,
                                 roundNumber: 1,
                                 phaseKey: "phase.solitaire",
                                 result: state.finalResult)
    }

    // MARK: - Hints

    public func hint(for state: State, seat: SeatID) -> Hint? {
        let actions = legalActions(in: state, for: seat)
        guard !actions.isEmpty else {
            return Hint(messageKey: "hint.klondike.stuck",
                        english: "There is no legal move left. This deal cannot be finished — deal a new one.")
        }

        // Turning a face-down card is almost always the best move available,
        // because it is the only one that adds information to the board.
        for action in actions {
            guard case let .move(cardID, _) = action,
                  let origin = state.board.zone(of: cardID),
                  origin.kind == .tableau,
                  let run = liftableRun(from: cardID, in: state) else { continue }
            let contents = state.board.contents(of: origin)
            let remaining = contents.count - run.count
            guard remaining > 0 else { continue }
            let below = contents[remaining - 1]
            if !state.board.isFaceUp(below) {
                return Hint(messageKey: "hint.klondike.turnUp",
                            english: "Moving this run turns up the card underneath it. Uncovering cards is worth more than anything else on the board.",
                            cards: run,
                            suggestedAction: token(for: action, in: state))
            }
        }

        // Emptying a column is next best, but only when a king can fill it.
        let kingAvailable = state.board.top(of: .waste)?.rank == .king
            || (0..<Self.tableauCount).contains { column in
                guard let first = state.board.contents(of: .tableau(column)).first else { return false }
                return state.board.card(first)?.rank == .king && state.board.isFaceUp(first)
            }
        if kingAvailable {
            for action in actions {
                guard case let .move(cardID, _) = action,
                      let origin = state.board.zone(of: cardID),
                      origin.kind == .tableau,
                      let run = liftableRun(from: cardID, in: state),
                      run.count == state.board.contents(of: origin).count else { continue }
                return Hint(messageKey: "hint.klondike.emptyColumn",
                            english: "Clearing this column gives you somewhere to put a king. That is worth more right now than another card on a foundation.",
                            cards: run,
                            suggestedAction: token(for: action, in: state))
            }
        }

        let foundationMoves = actions.filter { action in
            guard case let .move(_, destination) = action else { return false }
            return destination.kind == .foundation
        }
        if !foundationMoves.isEmpty {
            let cards = foundationMoves.compactMap { action -> CardID? in
                guard case let .move(cardID, _) = action else { return nil }
                return cardID
            }
            return Hint(messageKey: "hint.klondike.foundation",
                        english: "These can go up to a foundation. Sending low cards early is safe; hold a card back only while a lower one of the opposite colour still needs somewhere to sit.",
                        cards: cards)
        }

        if actions.contains(.drawFromStock) {
            return Hint(messageKey: "hint.klondike.draw",
                        english: "Nothing on the tableau moves the game forward, so turn the stock and see what it gives you.")
        }
        return Hint(messageKey: "hint.klondike.shuffleAround",
                    english: "Only sideways moves are left. Prefer the one that exposes a face-down card, even if it looks like less progress.")
    }
}

public enum KlondikeStatistics {
    public static let moves = "klondike.moves"
    public static let score = "klondike.score"
    public static let foundationCards = "klondike.foundationCards"
}

import Foundation
import DeckCore

/// FreeCell.
///
/// Every card is face up from the first move, so nothing is hidden and almost
/// every deal can be won. The four cells are the whole game: each empty one
/// doubles how much of a column you can pick up at once.
public struct FreeCellRules: GameRules {
    public static let gameID = GameID.freeCell
    public static let rulesVersion = 1
    public let supportsUndo = true

    public init() {}

    public static let columnCount = 8
    public static let foundationCount = 4

    public struct Settings: Hashable, Codable, Sendable {
        /// Free cells available. Four is standard; fewer is much harder.
        public var cellCount: Int

        public init(cellCount: Int = 4) { self.cellCount = max(1, min(6, cellCount)) }

        public static func from(_ configuration: GameConfiguration) -> Settings {
            Settings(cellCount: configuration.option("cellCount", default: 4))
        }
    }

    public struct State: GameStateProtocol {
        public var board: Board
        public var activeSeat: SeatID?
        public var roundNumber: Int
        public var finalResult: GameResult?

        public var settings: Settings
        public var seat: SeatID
        public var moveCount: Int

        public var foundationTotal: Int {
            (0..<FreeCellRules.foundationCount).reduce(0) { $0 + board.count(in: .foundation($1)) }
        }
        public var freeCellCount: Int {
            (0..<settings.cellCount).reduce(0) { $0 + (board.isEmpty(.freeCell($1)) ? 1 : 0) }
        }
        public var emptyColumnCount: Int {
            (0..<FreeCellRules.columnCount).reduce(0) { $0 + (board.isEmpty(.tableau($1)) ? 1 : 0) }
        }
    }

    public enum Action: Hashable, Sendable {
        case move(card: CardID, to: Zone)
        /// Send everything that can safely go up, in one gesture.
        case collect
    }

    public struct Observation: Sendable {
        public var columns: [[Card]]
        public var cells: [Card?]
        public var foundations: [[Card]]
        public var freeCells: Int
        public var emptyColumns: Int
    }

    // MARK: - Setup

    public func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State {
        let settings = Settings.from(configuration)
        let seat = configuration.seating.ids.first ?? SeatID(0)
        var board = Board()
        var deck = DeckConfiguration.standard52.build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)
        board.ensureZones((0..<Self.columnCount).map { Zone.tableau($0) }
                          + (0..<Self.foundationCount).map { Zone.foundation($0) }
                          + (0..<settings.cellCount).map { Zone.freeCell($0) }
                          + [.stock])
        var column = 0
        while board.count(in: .stock) > 0 {
            board.draw(from: .stock, to: .tableau(column % Self.columnCount), facing: .faceUp)
            column += 1
        }
        return State(board: board,
                     activeSeat: seat,
                     roundNumber: 1,
                     finalResult: nil,
                     settings: settings,
                     seat: seat,
                     moveCount: 0)
    }

    // MARK: - Rules

    public func canPlaceOnFoundation(_ card: Card, foundation: Zone, in state: State) -> Bool {
        guard let rank = card.rank, card.suit != nil else { return false }
        guard let top = state.board.top(of: foundation) else { return rank == .ace }
        guard top.suit == card.suit, let topRank = top.rank else { return false }
        return rank.aceLowValue == topRank.aceLowValue + 1
    }

    public func canPlaceOnTableau(_ card: Card, column: Zone, in state: State) -> Bool {
        guard let rank = card.rank else { return false }
        guard let top = state.board.top(of: column) else { return true }
        guard let topRank = top.rank, top.isRed != card.isRed else { return false }
        return rank.aceLowValue == topRank.aceLowValue - 1
    }

    /// How many cards can be lifted at once.
    ///
    /// The classic formula: `(free cells + 1) x 2^(empty columns)`, halved when
    /// the destination is itself an empty column, because that column cannot be
    /// used as a staging area for its own move.
    public func maximumLift(in state: State, movingToEmptyColumn: Bool) -> Int {
        let base = (state.freeCellCount + 1)
        var multiplier = 1
        var empties = state.emptyColumnCount
        if movingToEmptyColumn { empties = max(0, empties - 1) }
        for _ in 0..<empties { multiplier *= 2 }
        return base * multiplier
    }

    /// The properly sequenced run starting at `card`.
    public func liftableRun(from card: CardID, in state: State) -> [CardID]? {
        guard let zone = state.board.zone(of: card) else { return nil }
        switch zone.kind {
        case .freeCell, .foundation:
            guard state.board.contents(of: zone).last == card else { return nil }
            return [card]
        case .tableau:
            let contents = state.board.contents(of: zone)
            guard let index = contents.firstIndex(of: card) else { return nil }
            let run = Array(contents[index...])
            var previous: Card?
            for id in run {
                guard let current = state.board.card(id) else { return nil }
                if let previous {
                    guard let previousRank = previous.rank, let currentRank = current.rank,
                          previous.isRed != current.isRed,
                          currentRank.aceLowValue == previousRank.aceLowValue - 1 else { return nil }
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
        let columns = (0..<Self.columnCount).map { Zone.tableau($0) }
        let foundations = (0..<Self.foundationCount).map { Zone.foundation($0) }
        let cells = (0..<state.settings.cellCount).map { Zone.freeCell($0) }

        var sources: [CardID] = []
        for column in columns {
            for id in state.board.contents(of: column) { sources.append(id) }
        }
        for cell in cells {
            if let top = state.board.top(of: cell) { sources.append(top.id) }
        }

        for source in sources {
            guard let card = state.board.card(source),
                  let run = liftableRun(from: source, in: state) else { continue }
            let origin = state.board.zone(of: source)

            if run.count == 1 {
                for foundation in foundations where foundation != origin {
                    if canPlaceOnFoundation(card, foundation: foundation, in: state) {
                        actions.append(.move(card: source, to: foundation))
                        break
                    }
                }
                if origin?.kind != .freeCell, let emptyCell = cells.first(where: { state.board.isEmpty($0) }) {
                    actions.append(.move(card: source, to: emptyCell))
                }
            }

            var offeredEmptyColumn = false
            for column in columns where column != origin {
                let isEmpty = state.board.isEmpty(column)
                if isEmpty {
                    // All empty columns are the same destination; offering seven
                    // identical moves is noise.
                    if offeredEmptyColumn { continue }
                    if let origin, origin.kind == .tableau,
                       state.board.contents(of: origin).first == source { continue }
                }
                guard canPlaceOnTableau(card, column: column, in: state) else { continue }
                guard run.count <= maximumLift(in: state, movingToEmptyColumn: isEmpty) else { continue }
                actions.append(.move(card: source, to: column))
                if isEmpty { offeredEmptyColumn = true }
            }
        }

        if canCollect(state: state) { actions.append(.collect) }
        return actions
    }

    /// True when at least one card can safely go up.
    public func canCollect(state: State) -> Bool {
        guard state.foundationTotal < 52 else { return false }
        var sources: [Card] = []
        for column in 0..<Self.columnCount {
            if let top = state.board.top(of: .tableau(column)) { sources.append(top) }
        }
        for cell in 0..<state.settings.cellCount {
            if let top = state.board.top(of: .freeCell(cell)) { sources.append(top) }
        }
        return sources.contains { card in
            (0..<Self.foundationCount).contains { canPlaceOnFoundation(card, foundation: .foundation($0), in: state) }
        }
    }

    public func rejection(for action: Action, in state: State) -> IllegalMove? {
        guard state.finalResult == nil else { return .gameOver }
        switch action {
        case let .move(cardID, destination):
            guard let card = state.board.card(cardID) else { return .cardNotInHand }
            guard let run = liftableRun(from: cardID, in: state) else {
                return IllegalMove("runNotOrdered",
                                   english: "Only a run going down in alternating colours can be moved together.")
            }
            switch destination.kind {
            case .foundation:
                guard run.count == 1, canPlaceOnFoundation(card, foundation: destination, in: state) else {
                    return IllegalMove("foundationOrder",
                                       english: "Foundations go up in suit, one card at a time, starting with the ace.")
                }
                return nil
            case .freeCell:
                guard run.count == 1 else {
                    return IllegalMove("cellOneCard", english: "A cell holds one card.")
                }
                guard state.board.isEmpty(destination) else {
                    return IllegalMove("cellOccupied", english: "That cell is taken.")
                }
                return nil
            case .tableau:
                guard canPlaceOnTableau(card, column: destination, in: state) else {
                    return IllegalMove("tableauOrder",
                                       english: "Columns go down in alternating colours.")
                }
                let limit = maximumLift(in: state, movingToEmptyColumn: state.board.isEmpty(destination))
                guard run.count <= limit else {
                    return IllegalMove("notEnoughSpace",
                                       arguments: [String(limit)],
                                       english: "You can only move \(limit) cards at once with the cells and columns you have free.")
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

    public func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        var events: [GameEvent] = []
        switch action {
        case let .move(cardID, destination):
            events += performMove(cardID, to: destination, state: &state)
        case .collect:
            events += collectAll(state: &state)
        }
        if state.foundationTotal == 52 && state.finalResult == nil {
            var metrics: [String: Int] = [:]
            metrics[FreeCellStatistics.moves] = state.moveCount
            metrics[FreeCellStatistics.cellsUsed] = state.settings.cellCount
            var highlights = ["freecell.win"]
            if state.settings.cellCount < 4 { highlights.append("freecell.fewCells") }
            let result = GameResult(winners: [state.seat],
                                    scores: [state.seat: max(0, 1000 - state.moveCount * 2)],
                                    placements: [state.seat],
                                    duration: 0,
                                    turnCount: state.moveCount,
                                    roundCount: 1,
                                    metrics: metrics,
                                    highlights: highlights)
            state.finalResult = result
            state.activeSeat = nil
            events.append(.gameEnded(result))
        } else if state.finalResult == nil,
                  legalActions(in: state, for: state.seat).isEmpty {
            // FreeCell has no stock to turn, so a position with no legal move
            // is the end of the deal: it is lost, and there is nothing to do
            // but start another. Klondike can always recycle its waste, which
            // is why this is the solitaire that needs a losing ending.
            let result = GameResult(winners: [],
                                    scores: [state.seat: 0],
                                    placements: [state.seat],
                                    duration: 0,
                                    turnCount: state.moveCount,
                                    roundCount: 1,
                                    metrics: [FreeCellStatistics.moves: state.moveCount],
                                    highlights: ["freecell.stuck"])
            state.finalResult = result
            state.activeSeat = nil
            events.append(.gameEnded(result))
        }
        return events
    }

    private func performMove(_ cardID: CardID, to destination: Zone, state: inout State) -> [GameEvent] {
        guard let run = liftableRun(from: cardID, in: state),
              let origin = state.board.zone(of: cardID) else { return [] }
        state.board.move(run, to: destination)
        for id in run { state.board.flip(id, faceUp: true) }
        state.moveCount += 1
        var events: [GameEvent] = [.cardsMoved(cards: run, from: origin, to: destination)]
        if destination.kind == .foundation, state.board.count(in: destination) == 13 {
            events.append(.foundationCompleted(zone: destination))
        }
        return events
    }

    private func collectAll(state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        var progressed = true
        var safety = 0
        while progressed && safety < 120 {
            progressed = false
            safety += 1
            var sources: [CardID] = []
            for column in 0..<Self.columnCount {
                if let top = state.board.top(of: .tableau(column)) { sources.append(top.id) }
            }
            for cell in 0..<state.settings.cellCount {
                if let top = state.board.top(of: .freeCell(cell)) { sources.append(top.id) }
            }
            for source in sources {
                guard let card = state.board.card(source) else { continue }
                // Only send a card up when no lower card of the opposite colour
                // could still need it, which is the standard safe-autoplay rule.
                guard isSafeToCollect(card, state: state) else { continue }
                for index in 0..<Self.foundationCount where canPlaceOnFoundation(card, foundation: .foundation(index), in: state) {
                    events += performMove(source, to: .foundation(index), state: &state)
                    progressed = true
                    break
                }
                if progressed { break }
            }
        }
        return events
    }

    private func isSafeToCollect(_ card: Card, state: State) -> Bool {
        guard let rank = card.rank, let suit = card.suit else { return false }
        if rank == .ace || rank == .two { return true }
        // Safe when both opposite-colour foundations are already at least one
        // rank below this card: nothing on the tableau still needs it.
        let opposites = Suit.allCases.filter { $0.isRed != suit.isRed }
        for opposite in opposites {
            let height = (0..<Self.foundationCount)
                .compactMap { state.board.top(of: .foundation($0)) }
                .first { $0.suit == opposite }?
                .rank?.aceLowValue ?? 0
            if height < rank.aceLowValue - 1 { return false }
        }
        return true
    }

    // MARK: - Tokens

    public func token(for action: Action, in state: State) -> ActionToken {
        let seat = state.seat
        switch action {
        case let .move(cardID, destination):
            let cards = liftableRun(from: cardID, in: state) ?? [cardID]
            return ActionToken(id: TokenID.make(seat, "move", [String(cardID.rawValue), KlondikeRules.encode(destination)]),
                               kind: .moveCards,
                               seat: seat,
                               cards: cards,
                               destination: destination,
                               source: state.board.zone(of: cardID),
                               labelKey: "action.move")
        case .collect:
            return ActionToken(id: TokenID.make(seat, "collect"), kind: .claim, seat: seat, labelKey: "action.collect")
        }
    }

    public func decodeAction(id: String, in state: State) -> Action? {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        switch parts[1] {
        case "collect": return .collect
        case "move":
            guard parts.count >= 4, let raw = Int(parts[2]),
                  let zone = KlondikeRules.decode(parts[3]) else { return nil }
            return .move(card: CardID(rawValue: raw), to: zone)
        default: return nil
        }
    }

    public func observation(of state: State, for seat: SeatID) -> Observation {
        Observation(columns: (0..<Self.columnCount).map { state.board.cardList(in: .tableau($0)) },
                    cells: (0..<state.settings.cellCount).map { state.board.top(of: .freeCell($0)) },
                    foundations: (0..<Self.foundationCount).map { state.board.cardList(in: .foundation($0)) },
                    freeCells: state.freeCellCount,
                    emptyColumns: state.emptyColumnCount)
    }

    public func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation {
        var slots: [TableSlot] = []
        for index in 0..<state.settings.cellCount {
            slots.append(TableSlot(zone: .freeCell(index),
                                   style: .single,
                                   anchor: .grid(row: 0, column: index),
                                   emptyHintKey: "zone.cell.empty",
                                   acceptsDrop: true))
        }
        for index in 0..<Self.foundationCount {
            slots.append(TableSlot(zone: .foundation(index),
                                   style: .single,
                                   anchor: .grid(row: 0, column: 4 + index),
                                   emptyHintKey: "zone.foundation.empty",
                                   acceptsDrop: true))
        }
        for index in 0..<Self.columnCount {
            slots.append(TableSlot(zone: .tableau(index),
                                   style: .cascade,
                                   anchor: .grid(row: 1, column: index),
                                   emptyHintKey: "zone.column.empty",
                                   acceptsDrop: true,
                                   prominence: 1.2))
        }
        let actions = legalActions(in: state, for: state.seat).map { token(for: $0, in: state) }
        let callouts = [
            TableCallout(id: "lift",
                         labelKey: "callout.canMove",
                         arguments: [String(maximumLift(in: state, movingToEmptyColumn: false))],
                         emphasis: .primary),
            TableCallout(id: "cells",
                         labelKey: "callout.cellsFree",
                         arguments: [String(state.freeCellCount), String(state.settings.cellCount)]),
            TableCallout(id: "foundation",
                         labelKey: "callout.foundationProgress",
                         arguments: [String(state.foundationTotal), "52"])
        ]
        return TablePresentation(gameID: Self.gameID,
                                 viewer: viewer,
                                 board: state.board.redacted(for: viewer),
                                 slots: slots,
                                 seats: TableBuilder.seatStatuses(seating: seating,
                                                                  board: state.board,
                                                                  activeSeat: state.activeSeat,
                                                                  scores: [state.seat: state.moveCount],
                                                                  scoreLabelKey: "label.moves",
                                                                  handZone: { _ in Zone.stock }),
                                 callouts: callouts,
                                 actions: actions,
                                 playableCards: Set(actions.flatMap(\.cards)),
                                 activeSeat: state.activeSeat,
                                 roundNumber: 1,
                                 phaseKey: "phase.solitaire",
                                 result: state.finalResult)
    }

    public func hint(for state: State, seat: SeatID) -> Hint? {
        let actions = legalActions(in: state, for: seat)
        guard !actions.isEmpty else {
            return Hint(messageKey: "hint.freecell.stuck",
                        english: "Nothing moves. Undo back to the last point where a cell was free — that is almost always where it went wrong.")
        }
        if state.freeCellCount == 0 {
            return Hint(messageKey: "hint.freecell.cellsFull",
                        english: "Every cell is full, so you can only move one card at a time. Emptying a cell is more urgent than anything else on the board.")
        }
        if state.emptyColumnCount > 0 {
            return Hint(messageKey: "hint.freecell.emptyColumn",
                        arguments: [String(maximumLift(in: state, movingToEmptyColumn: false))],
                        english: "An empty column doubles what you can lift — you can move \(maximumLift(in: state, movingToEmptyColumn: false)) cards. Filling it costs you that, so think before you park a king there.")
        }
        return Hint(messageKey: "hint.freecell.plan",
                    english: "Dig for the aces first. Every card you send up is one fewer thing the cells have to hold.")
    }
}

public enum FreeCellStatistics {
    public static let moves = "freecell.moves"
    public static let cellsUsed = "freecell.cellsUsed"
}

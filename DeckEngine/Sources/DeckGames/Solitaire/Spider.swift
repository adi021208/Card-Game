import Foundation
import DeckCore

/// Spider.
///
/// Two packs, ten columns, and the whole game is about untangling suits. A run
/// from king down to ace in one suit leaves the table; clear all eight and you
/// have won. The one-suit deal is a gentle introduction; four suits is one of
/// the hardest solitaires there is.
public struct SpiderRules: GameRules {
    public static let gameID = GameID.spider
    public static let rulesVersion = 1
    public let supportsUndo = true

    public init() {}

    public static let columnCount = 10
    public static let foundationCount = 8

    public struct Settings: Hashable, Codable, Sendable {
        /// One, two or four suits.
        public var suitCount: Int

        public init(suitCount: Int = 1) {
            self.suitCount = [1, 2, 4].contains(suitCount) ? suitCount : 1
        }

        public static func from(_ configuration: GameConfiguration) -> Settings {
            Settings(suitCount: configuration.option("suitCount", default: 1))
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
        public var completedRuns: Int

        public var faceDownCount: Int {
            (0..<SpiderRules.columnCount).reduce(0) { total, column in
                total + board.contents(of: .tableau(column)).filter { !board.isFaceUp($0) }.count
            }
        }
    }

    public enum Action: Hashable, Sendable {
        case move(card: CardID, to: Zone)
        /// Deal one more card onto every column.
        case dealRow
    }

    public struct Observation: Sendable {
        public var columns: [[Card]]
        public var faceDownCounts: [Int]
        public var stockRowsLeft: Int
        public var completedRuns: Int
        public var suitCount: Int
    }

    // MARK: - Setup

    public func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State {
        let settings = Settings.from(configuration)
        let seat = configuration.seating.ids.first ?? SeatID(0)
        var board = Board()
        var deck = DeckConfiguration.spider(suitCount: settings.suitCount).build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)
        board.ensureZones((0..<Self.columnCount).map { Zone.tableau($0) }
                          + (0..<Self.foundationCount).map { Zone.foundation($0) }
                          + [.stock])

        // The standard opening: four columns of six, six columns of five, with
        // the last card of each turned up. That is 54 cards; 50 stay in the stock
        // for five further deals of ten.
        for column in 0..<Self.columnCount {
            let depth = column < 4 ? 6 : 5
            for row in 0..<depth {
                board.draw(from: .stock,
                           to: .tableau(column),
                           facing: row == depth - 1 ? .faceUp : .faceDown)
            }
        }

        return State(board: board,
                     activeSeat: seat,
                     roundNumber: 1,
                     finalResult: nil,
                     settings: settings,
                     seat: seat,
                     moveCount: 0,
                     completedRuns: 0)
    }

    // MARK: - Rules

    /// Any card may sit on one exactly a rank higher, regardless of suit — but
    /// only a same-suit run can be picked up as a unit.
    public func canPlaceOnTableau(_ card: Card, column: Zone, in state: State) -> Bool {
        guard let rank = card.rank else { return false }
        guard let top = state.board.top(of: column) else { return true }
        guard state.board.isFaceUp(top.id), let topRank = top.rank else { return false }
        return rank.rawValue == topRank.rawValue - 1
    }

    public func liftableRun(from card: CardID, in state: State) -> [CardID]? {
        guard let zone = state.board.zone(of: card), zone.kind == .tableau else { return nil }
        let contents = state.board.contents(of: zone)
        guard let index = contents.firstIndex(of: card), state.board.isFaceUp(card) else { return nil }
        let run = Array(contents[index...])
        var previous: Card?
        for id in run {
            guard state.board.isFaceUp(id), let current = state.board.card(id) else { return nil }
            if let previous {
                guard let previousRank = previous.rank, let currentRank = current.rank,
                      previous.suit == current.suit,
                      currentRank.rawValue == previousRank.rawValue - 1 else { return nil }
            }
            previous = current
        }
        return run
    }

    public func legalActions(in state: State, for seat: SeatID) -> [Action] {
        guard state.finalResult == nil else { return [] }
        var actions: [Action] = []
        let columns = (0..<Self.columnCount).map { Zone.tableau($0) }

        for column in columns {
            for source in state.board.contents(of: column) where state.board.isFaceUp(source) {
                guard let card = state.board.card(source),
                      liftableRun(from: source, in: state) != nil else { continue }
                var offeredEmptyColumn = false
                for destination in columns where destination != column {
                    let isEmpty = state.board.isEmpty(destination)
                    if isEmpty {
                        if offeredEmptyColumn { continue }
                        // Shifting a whole column into an empty one achieves nothing.
                        if state.board.contents(of: column).first == source { continue }
                    }
                    guard canPlaceOnTableau(card, column: destination, in: state) else { continue }
                    actions.append(.move(card: source, to: destination))
                    if isEmpty { offeredEmptyColumn = true }
                }
            }
        }

        // A new row may only be dealt when every column has something in it.
        if state.board.count(in: .stock) >= Self.columnCount,
           columns.allSatisfy({ !state.board.isEmpty($0) }) {
            actions.append(.dealRow)
        }
        return actions
    }

    public func rejection(for action: Action, in state: State) -> IllegalMove? {
        guard state.finalResult == nil else { return .gameOver }
        switch action {
        case let .move(cardID, destination):
            guard let card = state.board.card(cardID) else { return .cardNotInHand }
            guard liftableRun(from: cardID, in: state) != nil else {
                return IllegalMove("runNotOneSuit",
                                   english: "Only a run in a single suit can be moved together.")
            }
            guard destination.kind == .tableau else { return .noSuchAction }
            guard canPlaceOnTableau(card, column: destination, in: state) else {
                return IllegalMove("spiderOrder",
                                   english: "A card can only go on one exactly a rank higher.")
            }
            return nil
        case .dealRow:
            guard state.board.count(in: .stock) >= Self.columnCount else { return .emptyPile }
            for column in 0..<Self.columnCount where state.board.isEmpty(.tableau(column)) {
                return IllegalMove("fillEmptyColumnsFirst",
                                   english: "Every column has to have a card before you can deal another row.")
            }
            return nil
        }
    }

    public func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        var events: [GameEvent] = []
        switch action {
        case let .move(cardID, destination):
            guard let run = liftableRun(from: cardID, in: state),
                  let origin = state.board.zone(of: cardID) else { return events }
            state.board.move(run, to: destination)
            state.moveCount += 1
            events.append(.cardsMoved(cards: run, from: origin, to: destination))
            if let newTop = state.board.top(of: origin), !state.board.isFaceUp(newTop.id) {
                state.board.flip(newTop.id, faceUp: true)
                events.append(.cardFlipped(card: newTop.id, faceUp: true))
            }
            events += harvestCompletedRuns(state: &state)

        case .dealRow:
            state.moveCount += 1
            for column in 0..<Self.columnCount {
                if let card = state.board.draw(from: .stock, to: .tableau(column), facing: .faceUp) {
                    events.append(.cardDealt(card: card.id, to: .tableau(column), faceUp: true))
                }
            }
            events += harvestCompletedRuns(state: &state)
        }

        if state.completedRuns == Self.foundationCount && state.finalResult == nil {
            var metrics: [String: Int] = [:]
            metrics[SpiderStatistics.moves] = state.moveCount
            metrics[SpiderStatistics.suits] = state.settings.suitCount
            var highlights = ["spider.win"]
            if state.settings.suitCount == 4 { highlights.append("spider.fourSuit") }
            else if state.settings.suitCount == 2 { highlights.append("spider.twoSuit") }
            let result = GameResult(winners: [state.seat],
                                    scores: [state.seat: max(0, 1200 - state.moveCount)],
                                    placements: [state.seat],
                                    duration: 0,
                                    turnCount: state.moveCount,
                                    roundCount: 1,
                                    metrics: metrics,
                                    highlights: highlights)
            state.finalResult = result
            state.activeSeat = nil
            events.append(.gameEnded(result))
        }
        return events
    }

    /// Removes any king-to-ace run in a single suit that has formed.
    private func harvestCompletedRuns(state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        var progressed = true
        while progressed {
            progressed = false
            for column in 0..<Self.columnCount {
                let contents = state.board.contents(of: .tableau(column))
                guard contents.count >= 13 else { continue }
                let tail = Array(contents.suffix(13))
                guard let topCard = state.board.card(tail[0]), topCard.rank == .king,
                      let run = liftableRun(from: tail[0], in: state), run.count == 13,
                      let last = state.board.card(tail[12]), last.rank == .ace else { continue }
                let foundation = Zone.foundation(state.completedRuns)
                state.board.move(tail, to: foundation)
                state.completedRuns += 1
                events.append(.foundationCompleted(zone: foundation))
                events.append(.highlight(code: "spider.runCleared", seat: state.seat, value: state.completedRuns))
                if let newTop = state.board.top(of: .tableau(column)), !state.board.isFaceUp(newTop.id) {
                    state.board.flip(newTop.id, faceUp: true)
                    events.append(.cardFlipped(card: newTop.id, faceUp: true))
                }
                progressed = true
                break
            }
        }
        return events
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
        case .dealRow:
            return ActionToken(id: TokenID.make(seat, "deal"),
                               kind: .dealNext,
                               seat: seat,
                               source: .stock,
                               labelKey: "action.dealRow")
        }
    }

    public func decodeAction(id: String, in state: State) -> Action? {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        switch parts[1] {
        case "deal": return .dealRow
        case "move":
            guard parts.count >= 4, let raw = Int(parts[2]),
                  let zone = KlondikeRules.decode(parts[3]) else { return nil }
            return .move(card: CardID(rawValue: raw), to: zone)
        default: return nil
        }
    }

    public func observation(of state: State, for seat: SeatID) -> Observation {
        var columns: [[Card]] = []
        var faceDown: [Int] = []
        for column in 0..<Self.columnCount {
            let contents = state.board.contents(of: .tableau(column))
            columns.append(contents.filter { state.board.isFaceUp($0) }.compactMap { state.board.card($0) })
            faceDown.append(contents.filter { !state.board.isFaceUp($0) }.count)
        }
        return Observation(columns: columns,
                           faceDownCounts: faceDown,
                           stockRowsLeft: state.board.count(in: .stock) / Self.columnCount,
                           completedRuns: state.completedRuns,
                           suitCount: state.settings.suitCount)
    }

    public func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation {
        var slots: [TableSlot] = [
            TableSlot(zone: .stock,
                      style: .stack,
                      anchor: .corner(.topTrailing),
                      titleKey: "zone.deals",
                      acceptsDrop: true)
        ]
        for index in 0..<Self.foundationCount {
            slots.append(TableSlot(zone: .foundation(index),
                                   style: .single,
                                   anchor: .grid(row: 0, column: index),
                                   emptyHintKey: nil))
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
            TableCallout(id: "runs",
                         labelKey: "callout.runsCleared",
                         arguments: [String(state.completedRuns), "8"],
                         emphasis: .primary),
            TableCallout(id: "deals",
                         labelKey: "callout.dealsLeft",
                         arguments: [String(state.board.count(in: .stock) / Self.columnCount)]),
            TableCallout(id: "hidden",
                         labelKey: "callout.faceDown",
                         arguments: [String(state.faceDownCount)])
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
            return Hint(messageKey: "hint.spider.stuck",
                        english: "Nothing moves and there is no row left to deal. Undo, or start a new deal.")
        }
        if state.settings.suitCount > 1 {
            return Hint(messageKey: "hint.spider.sameSuit",
                        english: "Building in the same suit is what actually wins Spider — a mixed pile looks tidy and cannot be moved. Prefer the move that keeps a suit together, even if it uncovers less.")
        }
        if state.faceDownCount > 0 {
            return Hint(messageKey: "hint.spider.uncover",
                        arguments: [String(state.faceDownCount)],
                        english: "There are \(state.faceDownCount) cards still face down. Uncovering them beats tidying the columns you can already see.")
        }
        return Hint(messageKey: "hint.spider.empty",
                    english: "An empty column is the most valuable thing on the board. Use it to unpick a mixed pile, not to park a king you cannot move again.")
    }
}

public enum SpiderStatistics {
    public static let moves = "spider.moves"
    public static let suits = "spider.suits"
}

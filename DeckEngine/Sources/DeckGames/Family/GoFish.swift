import Foundation
import DeckCore

/// Go Fish.
///
/// Ask a player for a rank you already hold. What makes the digital version
/// interesting is that everything you ask for is public: a good player is
/// listening to the questions as much as the answers.
public struct GoFishRules: GameRules {
    public static let gameID = GameID.goFish
    public static let rulesVersion = 1

    public init() {}

    public struct Settings: Hashable, Codable, Sendable {
        public var handSize: Int
        /// A successful ask lets you go again, which is the standard rule.
        public var askAgainOnHit: Bool
        /// Drawing the rank you asked for also lets you go again.
        public var luckyDrawContinues: Bool

        public init(handSize: Int = 7, askAgainOnHit: Bool = true, luckyDrawContinues: Bool = true) {
            self.handSize = handSize
            self.askAgainOnHit = askAgainOnHit
            self.luckyDrawContinues = luckyDrawContinues
        }

        public static func from(_ configuration: GameConfiguration) -> Settings {
            let players = configuration.seating.count
            return Settings(handSize: configuration.option("handSize", default: players >= 4 ? 5 : 7),
                            askAgainOnHit: configuration.flag("askAgainOnHit", default: true),
                            luckyDrawContinues: configuration.flag("luckyDrawContinues", default: true))
        }
    }

    /// One question asked at the table, which everybody heard.
    public struct AskRecord: Hashable, Codable, Sendable {
        public var asker: SeatID
        public var target: SeatID
        public var rank: Rank
        public var succeeded: Bool
    }

    public struct State: GameStateProtocol {
        public var board: Board
        public var activeSeat: SeatID?
        public var roundNumber: Int
        public var finalResult: GameResult?

        public var settings: Settings
        public var seatOrder: [SeatID]
        public var books: [SeatID: [Rank]]
        /// Every question asked this game, in order. Public information.
        public var askHistory: [AskRecord]
        public var turnsTaken: Int
        public var luckyDraws: [SeatID: Int]

        public func hand(_ seat: SeatID) -> [Card] { board.cardList(in: .hand(seat)) }
        public var totalBooks: Int { books.values.reduce(0) { $0 + $1.count } }
    }

    public enum Action: Hashable, Sendable {
        case ask(target: SeatID, rank: Rank)
    }

    /// What a Go Fish agent knows: its own hand, its books, and the public
    /// record of what everybody has asked for. Never another player's cards.
    public struct Observation: Sendable {
        public var seat: SeatID
        public var hand: [Card]
        public var opponentCardCounts: [SeatID: Int]
        public var books: [SeatID: [Rank]]
        public var askHistory: [AskRecord]
        public var stockCount: Int
        public var seatOrder: [SeatID]
    }

    // MARK: - Setup

    public func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State {
        let settings = Settings.from(configuration)
        let seats = configuration.seating.ids
        var board = Board()
        var deck = DeckConfiguration.standard52.build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)
        board.ensureZones(seats.flatMap { [Zone.hand($0), Zone.captured($0)] } + [.stock])
        for _ in 0..<settings.handSize {
            for seat in seats {
                board.draw(from: .stock, to: .hand(seat), facing: .hand(seat))
            }
        }
        for seat in seats { board.sort(.hand(seat), by: HandSort.byRankThenSuit) }

        var state = State(board: board,
                          activeSeat: seats.first,
                          roundNumber: 1,
                          finalResult: nil,
                          settings: settings,
                          seatOrder: seats,
                          books: [:],
                          askHistory: [],
                          turnsTaken: 0,
                          luckyDraws: [:])
        // A hand dealt with four of a kind books immediately.
        for seat in seats { _ = collectBooks(seat: seat, state: &state) }
        return state
    }

    // MARK: - Rules

    public func legalActions(in state: State, for seat: SeatID) -> [Action] {
        guard state.finalResult == nil, state.activeSeat == seat else { return [] }
        let ranks = Set(state.hand(seat).compactMap(\.rank)).sorted()
        // You may only ask for a rank you hold, and only from a player who still
        // has cards.
        let targets = state.seatOrder.filter { $0 != seat && state.board.count(in: .hand($0)) > 0 }
        var actions: [Action] = []
        for target in targets {
            for rank in ranks {
                actions.append(.ask(target: target, rank: rank))
            }
        }
        return actions
    }

    public func rejection(for action: Action, in state: State) -> IllegalMove? {
        guard state.finalResult == nil else { return .gameOver }
        guard let seat = state.activeSeat else { return .notYourTurn }
        guard case let .ask(target, rank) = action else { return .noSuchAction }
        guard target != seat else {
            return IllegalMove("cannotAskYourself", english: "Ask somebody else.")
        }
        guard state.hand(seat).contains(where: { $0.rank == rank }) else {
            return IllegalMove("mustHoldRank",
                               arguments: [rank.localizationKey],
                               english: "You can only ask for a rank you already hold.")
        }
        guard state.board.count(in: .hand(target)) > 0 else {
            return IllegalMove("targetHasNoCards", english: "That player has no cards left.")
        }
        return nil
    }

    public func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard let seat = state.activeSeat, case let .ask(target, rank) = action else { return [] }
        var events: [GameEvent] = []
        state.turnsTaken += 1

        let matching = state.board.contents(of: .hand(target)).filter { state.board.card($0)?.rank == rank }
        let succeeded = !matching.isEmpty
        state.askHistory.append(AskRecord(asker: seat, target: target, rank: rank, succeeded: succeeded))
        events.append(.claimMade(seat: seat, claim: "\(rank.token)@\(target.rawValue)"))

        var goAgain = false
        if succeeded {
            for id in matching {
                state.board.move(id, to: .hand(seat), facing: .hand(seat))
            }
            state.board.sort(.hand(seat), by: HandSort.byRankThenSuit)
            events.append(.cardsMoved(cards: matching, from: .hand(target), to: .hand(seat)))
            events.append(.highlight(code: "gofish.hit", seat: seat, value: matching.count))
            goAgain = state.settings.askAgainOnHit
        } else {
            events.append(.highlight(code: "gofish.goFish", seat: seat, value: nil))
            if let drawn = state.board.draw(from: .stock, to: .hand(seat), facing: .hand(seat)) {
                state.board.sort(.hand(seat), by: HandSort.byRankThenSuit)
                events.append(.cardDrawn(card: drawn.id, by: seat, from: .stock))
                if drawn.rank == rank {
                    state.luckyDraws[seat, default: 0] += 1
                    events.append(.highlight(code: "gofish.luckyDraw", seat: seat, value: nil))
                    goAgain = state.settings.luckyDrawContinues
                }
            }
        }

        events += collectBooks(seat: seat, state: &state)
        events += refillEmptyHands(state: &state)

        if let result = checkForEnd(state: &state) {
            events.append(.gameEnded(result))
            return events
        }

        if !goAgain || state.board.isEmpty(Zone.hand(seat)) {
            let next = nextPlayableSeat(after: seat, in: state)
            state.activeSeat = next
            events.append(.turnChanged(from: seat, to: next))
        }
        return events
    }

    /// Lays down any completed set of four.
    private func collectBooks(seat: SeatID, state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        var byRank: [Rank: [CardID]] = [:]
        for id in state.board.contents(of: .hand(seat)) {
            guard let rank = state.board.card(id)?.rank else { continue }
            byRank[rank, default: []].append(id)
        }
        for (rank, ids) in byRank.sorted(by: { $0.key < $1.key }) where ids.count == 4 {
            for id in ids {
                // A completed book is laid face up for everyone to see.
                state.board.move(id, to: .captured(seat), facing: .faceUp)
            }
            state.books[seat, default: []].append(rank)
            events.append(.cardsMoved(cards: ids, from: .hand(seat), to: .captured(seat)))
            events.append(.highlight(code: "gofish.book", seat: seat, value: rank.rawValue))
        }
        return events
    }

    /// A player who runs out draws back up while the stock lasts.
    private func refillEmptyHands(state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        for seat in state.seatOrder where state.board.isEmpty(Zone.hand(seat)) {
            guard state.board.count(in: .stock) > 0 else { continue }
            let wanted = min(state.settings.handSize, state.board.count(in: .stock))
            for _ in 0..<wanted {
                if let card = state.board.draw(from: .stock, to: .hand(seat), facing: .hand(seat)) {
                    events.append(.cardDrawn(card: card.id, by: seat, from: .stock))
                }
            }
            state.board.sort(.hand(seat), by: HandSort.byRankThenSuit)
            events += collectBooks(seat: seat, state: &state)
        }
        return events
    }

    private func nextPlayableSeat(after seat: SeatID, in state: State) -> SeatID {
        guard let index = state.seatOrder.firstIndex(of: seat) else { return state.seatOrder[0] }
        let count = state.seatOrder.count
        for offset in 1...count {
            let candidate = state.seatOrder[(index + offset) % count]
            if state.board.count(in: .hand(candidate)) > 0 { return candidate }
        }
        return seat
    }

    private func checkForEnd(state: inout State) -> GameResult? {
        guard state.totalBooks == 13 else {
            // The game also ends when nobody can ask any more.
            let anyoneHasCards = state.seatOrder.contains { state.board.count(in: .hand($0)) > 0 }
            guard !anyoneHasCards, state.board.count(in: .stock) == 0 else { return nil }
            return finish(state: &state)
        }
        return finish(state: &state)
    }

    private func finish(state: inout State) -> GameResult {
        let ranked = state.seatOrder.sorted { (state.books[$0]?.count ?? 0) > (state.books[$1]?.count ?? 0) }
        let best = state.seatOrder.map { state.books[$0]?.count ?? 0 }.max() ?? 0
        let winners = state.seatOrder.filter { (state.books[$0]?.count ?? 0) == best }
        var scores: [SeatID: Int] = [:]
        for seat in state.seatOrder { scores[seat] = state.books[seat]?.count ?? 0 }
        let leader = winners.first ?? ranked[0]
        var metrics: [String: Int] = [:]
        metrics[GoFishStatistics.books] = scores[leader] ?? 0
        metrics[GoFishStatistics.luckyDraws] = state.luckyDraws[leader] ?? 0
        var highlights: [String] = []
        if best >= 7 { highlights.append("gofish.landslide") }
        let result = GameResult(winners: winners,
                                scores: scores,
                                placements: ranked,
                                duration: 0,
                                turnCount: state.turnsTaken,
                                roundCount: 1,
                                metrics: metrics,
                                highlights: highlights)
        state.finalResult = result
        state.activeSeat = nil
        return result
    }

    // MARK: - Tokens

    public func token(for action: Action, in state: State) -> ActionToken {
        let seat = state.activeSeat ?? state.seatOrder[0]
        guard case let .ask(target, rank) = action else {
            return ActionToken(id: TokenID.make(seat, "noop"), kind: .passTurn, seat: seat, labelKey: "action.pass")
        }
        let name = state.seatOrder.firstIndex(of: target).map { String($0) } ?? "?"
        return ActionToken(id: TokenID.make(seat, "ask", [String(target.rawValue), rank.token]),
                           kind: .claim,
                           seat: seat,
                           amount: rank.rawValue,
                           labelKey: "action.askFor",
                           labelArguments: [rank.localizationKey, name])
    }

    public func decodeAction(id: String, in state: State) -> Action? {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count >= 4, parts[1] == "ask",
              let target = Int(parts[2]), let rank = Rank(token: parts[3]) else { return nil }
        return .ask(target: SeatID(target), rank: rank)
    }

    // MARK: - Observation

    public func observation(of state: State, for seat: SeatID) -> Observation {
        var counts: [SeatID: Int] = [:]
        for other in state.seatOrder where other != seat {
            counts[other] = state.board.count(in: .hand(other))
        }
        return Observation(seat: seat,
                           hand: state.hand(seat),
                           opponentCardCounts: counts,
                           books: state.books,
                           askHistory: state.askHistory,
                           stockCount: state.board.count(in: .stock),
                           seatOrder: state.seatOrder)
    }

    // MARK: - Presentation

    public func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation {
        var slots: [TableSlot] = []
        if let own = TableBuilder.ownHandSlot(viewer: viewer, seating: seating) { slots.append(own) }
        slots += TableBuilder.opponentSlots(seating: seating, viewer: viewer)
        slots.append(TableSlot(zone: .stock,
                               style: .stack,
                               anchor: .centre(order: 0),
                               titleKey: "zone.pond",
                               emptyHintKey: "zone.pond.empty"))
        for seat in seating.ids {
            slots.append(TableSlot(zone: .captured(seat),
                                   style: .row(overlap: 0.75),
                                   anchor: .centre(order: 1 + (seating.index(of: seat) ?? 0)),
                                   titleKey: "zone.books"))
        }

        var callouts: [TableCallout] = [
            TableCallout(id: "pond",
                         labelKey: "callout.cardsInPond",
                         arguments: [String(state.board.count(in: .stock))])
        ]
        if let last = state.askHistory.last {
            callouts.append(TableCallout(id: "lastAsk",
                                         labelKey: last.succeeded ? "callout.askHit" : "callout.askMiss",
                                         arguments: [last.rank.localizationKey],
                                         emphasis: .primary))
        }

        var scores: [SeatID: Int] = [:]
        for seat in state.seatOrder { scores[seat] = state.books[seat]?.count ?? 0 }

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
                                                                  scores: scores,
                                                                  scoreLabelKey: "label.books"),
                                 callouts: callouts,
                                 actions: actions,
                                 playableCards: Set(state.hand(viewer ?? SeatID(-1)).map(\.id)),
                                 activeSeat: state.activeSeat,
                                 roundNumber: 1,
                                 phaseKey: "phase.asking",
                                 result: state.finalResult)
    }

    public func hint(for state: State, seat: SeatID) -> Hint? {
        guard state.activeSeat == seat else { return nil }
        // The most useful thing to say is what the table has already told them.
        let recent = state.askHistory.suffix(6).filter { $0.asker != seat }
        if let useful = recent.last(where: { record in
            state.hand(seat).contains { $0.rank == record.rank }
        }) {
            return Hint(messageKey: "hint.gofish.listen",
                        arguments: [useful.rank.localizationKey],
                        english: "Somebody already asked for \(useful.rank.englishName.lowercased())s, so they hold at least one. You hold one too — ask them.",
                        cards: state.hand(seat).filter { $0.rank == useful.rank }.map(\.id))
        }
        let counts = Dictionary(grouping: state.hand(seat).compactMap(\.rank), by: { $0 })
        if let best = counts.max(by: { $0.value.count < $1.value.count })?.key {
            return Hint(messageKey: "hint.gofish.nearBook",
                        arguments: [best.localizationKey],
                        english: "You are closest to a book of \(best.englishName.lowercased())s. Asking for what you hold most of finishes books fastest.",
                        cards: state.hand(seat).filter { $0.rank == best }.map(\.id))
        }
        return nil
    }
}

public enum GoFishStatistics {
    public static let books = "gofish.books"
    public static let luckyDraws = "gofish.luckyDraws"
}

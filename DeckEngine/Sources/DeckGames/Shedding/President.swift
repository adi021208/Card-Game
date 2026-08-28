import Foundation
import DeckCore

/// President (also played as Scum, Daihinmin or Arsehole).
///
/// Get rid of your cards first and you are President next hand; go out last and
/// you hand your two best cards to the person who beat you. The card exchange is
/// the whole point — it makes winning harder and losing worse, which is exactly
/// why the game is still being played.
public struct PresidentRules: GameRules {
    public static let gameID = GameID.president
    public static let rulesVersion = 1

    public init() {}

    public struct Settings: Hashable, Codable, Sendable {
        /// Deals to play. Ranks and the exchange only matter across several.
        public var rounds: Int
        /// Twos beat everything and clear the pile.
        public var twosAreBombs: Bool
        /// Matching the rank on the pile ends the round and passes the lead.
        public var completionClears: Bool
        /// The President and Scum swap cards between deals.
        public var exchangeCards: Bool

        public init(rounds: Int = 3,
                    twosAreBombs: Bool = true,
                    completionClears: Bool = true,
                    exchangeCards: Bool = true) {
            self.rounds = max(1, rounds)
            self.twosAreBombs = twosAreBombs
            self.completionClears = completionClears
            self.exchangeCards = exchangeCards
        }

        public static func from(_ configuration: GameConfiguration) -> Settings {
            Settings(rounds: configuration.option("rounds", default: 3),
                     twosAreBombs: configuration.flag("twosAreBombs", default: true),
                     completionClears: configuration.flag("completionClears", default: true),
                     exchangeCards: configuration.flag("exchangeCards", default: true))
        }
    }

    public struct State: GameStateProtocol {
        public var board: Board
        public var activeSeat: SeatID?
        public var roundNumber: Int
        public var finalResult: GameResult?

        public var settings: Settings
        public var seatOrder: [SeatID]
        /// Cards in the current set on the pile, and how many there are.
        public var leadCount: Int
        public var leadRank: Rank?
        /// Who put the current set down.
        public var lastPlayer: SeatID?
        /// Seats that have passed since the last play.
        public var passedSeats: Set<SeatID>
        /// Order players went out this deal.
        public var finishOrder: [SeatID]
        /// Ranking carried from the previous deal, best first.
        public var standings: [SeatID]
        /// Cumulative match points.
        public var scores: [SeatID: Int]
        public var turnsTaken: Int
        public var presidencies: [SeatID: Int]
        public var bombsPlayed: [SeatID: Int]
        public var dealComplete: Bool

        public func hand(_ seat: SeatID) -> [Card] { board.cardList(in: .hand(seat)) }
        public var isOut: (SeatID) -> Bool { { self.finishOrder.contains($0) } }
    }

    public enum Action: Hashable, Sendable {
        /// Put down a set of equal-ranked cards.
        case play([CardID])
        case pass
    }

    public struct Observation: Sendable {
        public var seat: SeatID
        public var hand: [Card]
        public var leadCount: Int
        public var leadRank: Rank?
        public var lastPlayer: SeatID?
        public var opponentCardCounts: [SeatID: Int]
        public var pileCount: Int
        public var playedCards: [Card]
        public var finishOrder: [SeatID]
        public var settings: Settings
        public var seatOrder: [SeatID]
    }

    // MARK: - Setup

    public func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State {
        let settings = Settings.from(configuration)
        let seats = configuration.seating.ids
        let board = Self.deal(seats: seats, generator: &generator)
        var scores: [SeatID: Int] = [:]
        for seat in seats { scores[seat] = 0 }
        var state = State(board: board,
                          activeSeat: nil,
                          roundNumber: 1,
                          finalResult: nil,
                          settings: settings,
                          seatOrder: seats,
                          leadCount: 0,
                          leadRank: nil,
                          lastPlayer: nil,
                          passedSeats: [],
                          finishOrder: [],
                          standings: [],
                          scores: scores,
                          turnsTaken: 0,
                          presidencies: [:],
                          bombsPlayed: [:],
                          dealComplete: false)
        // The three of clubs opens the very first deal, as it does at a table.
        state.activeSeat = Self.holderOfLowestClub(in: state) ?? seats[0]
        return state
    }

    static func deal(seats: [SeatID], generator: inout SeededGenerator) -> Board {
        var board = Board()
        var deck = DeckConfiguration.standard52.build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)
        board.ensureZones(seats.flatMap { [Zone.hand($0), Zone.exchange($0)] } + [.stock, .discard])
        var index = 0
        while board.count(in: .stock) > 0 {
            let seat = seats[index % seats.count]
            board.draw(from: .stock, to: .hand(seat), facing: .hand(seat))
            index += 1
        }
        for seat in seats { board.sort(.hand(seat), by: HandSort.byRankThenSuit) }
        return board
    }

    static func holderOfLowestClub(in state: State) -> SeatID? {
        for seat in state.seatOrder {
            if state.hand(seat).contains(where: { $0.suit == .clubs && $0.rank == .three }) { return seat }
        }
        return state.seatOrder.first
    }

    /// Rank ordering: three is low, ace high, and a two beats everything.
    static func power(_ rank: Rank, twosAreBombs: Bool) -> Int {
        if rank == .two && twosAreBombs { return 100 }
        // Three is the lowest card, so shift the scale down past the two.
        return rank == .two ? 15 : rank.rawValue
    }

    // MARK: - Rules

    public func legalActions(in state: State, for seat: SeatID) -> [Action] {
        guard state.finalResult == nil, state.activeSeat == seat else { return [] }
        guard !state.finishOrder.contains(seat) else { return [] }
        let hand = state.hand(seat)
        guard !hand.isEmpty else { return [] }

        var byRank: [Rank: [Card]] = [:]
        for card in hand {
            guard let rank = card.rank else { continue }
            byRank[rank, default: []].append(card)
        }

        var actions: [Action] = []
        let leading = state.leadRank == nil
        for (rank, cards) in byRank.sorted(by: { $0.key < $1.key }) {
            let sorted = cards.sorted { $0.id < $1.id }
            if leading {
                // A new lead may be any size the player holds.
                for count in 1...sorted.count {
                    actions.append(.play(Array(sorted.prefix(count)).map(\.id)))
                }
            } else {
                guard let leadRank = state.leadRank else { continue }
                let required = state.leadCount
                let isBomb = state.settings.twosAreBombs && rank == .two
                guard sorted.count >= required || isBomb else { continue }
                guard Self.power(rank, twosAreBombs: state.settings.twosAreBombs)
                        > Self.power(leadRank, twosAreBombs: state.settings.twosAreBombs) else { continue }
                let count = isBomb ? min(sorted.count, max(1, required)) : required
                actions.append(.play(Array(sorted.prefix(count)).map(\.id)))
            }
        }
        if !leading { actions.append(.pass) }
        return actions
    }

    public func rejection(for action: Action, in state: State) -> IllegalMove? {
        guard state.finalResult == nil else { return .gameOver }
        guard let seat = state.activeSeat else { return .notYourTurn }
        switch action {
        case .pass:
            guard state.leadRank != nil else {
                return IllegalMove("mustLead", english: "You have the lead — you have to play something.")
            }
            return nil
        case let .play(ids):
            guard !ids.isEmpty else { return .noSuchAction }
            for id in ids where state.board.zone(of: id) != Zone.hand(seat) {
                return .cardNotInHand
            }
            let cards = ids.compactMap { state.board.card($0) }
            guard cards.count == ids.count else { return .cardNotInHand }
            let ranks = Set(cards.compactMap(\.rank))
            guard ranks.count == 1, let rank = ranks.first else {
                return IllegalMove("sameRankOnly", english: "Every card you put down has to be the same rank.")
            }
            guard let leadRank = state.leadRank else { return nil }
            let isBomb = state.settings.twosAreBombs && rank == .two
            if !isBomb && ids.count != state.leadCount {
                return IllegalMove("matchTheCount",
                                   arguments: [String(state.leadCount)],
                                   english: "The pile is on \(state.leadCount) cards, so you have to play \(state.leadCount).")
            }
            guard Self.power(rank, twosAreBombs: state.settings.twosAreBombs)
                    > Self.power(leadRank, twosAreBombs: state.settings.twosAreBombs) else {
                return IllegalMove("mustBeatRank",
                                   arguments: [leadRank.localizationKey],
                                   english: "You have to beat \(leadRank.englishName.lowercased())s or pass.")
            }
            return nil
        }
    }

    public func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard let seat = state.activeSeat else { return [] }
        var events: [GameEvent] = []
        state.turnsTaken += 1

        switch action {
        case .pass:
            state.passedSeats.insert(seat)
            events.append(.turnSkipped(seat: seat))

        case let .play(ids):
            for id in ids { state.board.move(id, to: .discard, facing: .faceUp) }
            let rank = state.board.card(ids[0])?.rank
            events.append(.cardsPlayed(cards: ids, by: seat, to: .discard))
            let isBomb = state.settings.twosAreBombs && rank == .two
            if isBomb {
                state.bombsPlayed[seat, default: 0] += 1
                events.append(.highlight(code: "president.bomb", seat: seat, value: nil))
            }
            state.leadRank = rank
            state.leadCount = ids.count
            state.lastPlayer = seat
            state.passedSeats = []

            if state.board.isEmpty(Zone.hand(seat)) {
                state.finishOrder.append(seat)
                let place = state.finishOrder.count
                events.append(.playerOut(seat: seat, place: place))
                if place == 1 {
                    events.append(.highlight(code: "president.president", seat: seat, value: nil))
                }
            }
            // A bomb, or completing the rank, sweeps the pile and keeps the lead.
            let completesRank = state.settings.completionClears && ids.count == 4
            if isBomb || completesRank {
                events += clearPile(state: &state, keepingLeadWith: seat)
                return events
            }
        }

        events += advanceTurn(from: seat, state: &state)
        return events
    }

    private func advanceTurn(from seat: SeatID, state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        let stillIn = state.seatOrder.filter { !state.finishOrder.contains($0) }

        if stillIn.count <= 1 {
            events += finishDeal(state: &state, stragglers: stillIn)
            return events
        }

        // Once everybody else has passed, the pile is cleared and whoever put
        // the last set down leads again.
        let waiting = stillIn.filter { !state.passedSeats.contains($0) }
        if let last = state.lastPlayer, waiting.count <= 1, waiting.first == last || waiting.isEmpty {
            let leader = state.finishOrder.contains(last) ? nextActive(after: last, in: state) : last
            events += clearPile(state: &state, keepingLeadWith: leader)
            return events
        }

        var next = nextActive(after: seat, in: state)
        var guardCount = 0
        while state.passedSeats.contains(next) && guardCount < state.seatOrder.count {
            next = nextActive(after: next, in: state)
            guardCount += 1
        }
        state.activeSeat = next
        events.append(.turnChanged(from: seat, to: next))
        return events
    }

    private func clearPile(state: inout State, keepingLeadWith seat: SeatID) -> [GameEvent] {
        var events: [GameEvent] = []
        let pile = state.board.contents(of: .discard)
        for id in pile { state.board.move(id, to: .reserve, facing: .faceDown) }
        state.leadRank = nil
        state.leadCount = 0
        state.lastPlayer = nil
        state.passedSeats = []
        if !pile.isEmpty {
            events.append(.cardsMoved(cards: pile, from: .discard, to: .reserve))
        }

        let stillIn = state.seatOrder.filter { !state.finishOrder.contains($0) }
        guard stillIn.count > 1 else {
            events += finishDeal(state: &state, stragglers: stillIn)
            return events
        }
        let leader = stillIn.contains(seat) ? seat : nextActive(after: seat, in: state)
        state.activeSeat = leader
        events.append(.turnChanged(from: nil, to: leader))
        return events
    }

    private func nextActive(after seat: SeatID, in state: State) -> SeatID {
        guard let index = state.seatOrder.firstIndex(of: seat) else { return state.seatOrder[0] }
        let count = state.seatOrder.count
        for offset in 1...count {
            let candidate = state.seatOrder[(index + offset) % count]
            if !state.finishOrder.contains(candidate) { return candidate }
        }
        return seat
    }

    private func finishDeal(state: inout State, stragglers: [SeatID]) -> [GameEvent] {
        var events: [GameEvent] = []
        for seat in stragglers where !state.finishOrder.contains(seat) {
            state.finishOrder.append(seat)
            events.append(.playerOut(seat: seat, place: state.finishOrder.count))
        }
        // Points: first place is worth the most, last is worth nothing.
        let count = state.finishOrder.count
        for (index, seat) in state.finishOrder.enumerated() {
            let points = count - index - 1
            state.scores[seat, default: 0] += points
            events.append(.scoreChanged(seat: seat, delta: points, total: state.scores[seat] ?? 0))
        }
        if let president = state.finishOrder.first {
            state.presidencies[president, default: 0] += 1
        }
        state.standings = state.finishOrder
        state.dealComplete = true
        state.activeSeat = nil
        events.append(.roundEnded(scores: state.scores))
        return events
    }

    // MARK: - Between deals

    public func advanceAutomatically(_ state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard state.finalResult == nil, state.dealComplete else { return [] }
        state.dealComplete = false

        if state.roundNumber >= state.settings.rounds {
            let result = buildResult(state: state)
            state.finalResult = result
            return [.gameEnded(result)]
        }

        state.roundNumber += 1
        state.board = Self.deal(seats: state.seatOrder, generator: &generator)
        var events: [GameEvent] = [.roundStarted(number: state.roundNumber)]

        if state.settings.exchangeCards, state.standings.count >= 2 {
            events += runExchange(state: &state)
        }

        state.leadRank = nil
        state.leadCount = 0
        state.lastPlayer = nil
        state.passedSeats = []
        state.finishOrder = []
        // The Scum leads the next deal, which is the small mercy they get.
        state.activeSeat = state.standings.last ?? state.seatOrder[0]
        return events
    }

    /// The Scum hands over their best cards; the President gives back whatever
    /// they least want. Two cards at the extremes, one for the pair inside.
    private func runExchange(state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        let standings = state.standings
        let pairs: [(taker: SeatID, giver: SeatID, count: Int)]
        if standings.count >= 4 {
            pairs = [(standings[0], standings[standings.count - 1], 2),
                     (standings[1], standings[standings.count - 2], 1)]
        } else {
            pairs = [(standings[0], standings[standings.count - 1], 2)]
        }

        for pair in pairs {
            let giverHand = state.hand(pair.giver).sorted {
                Self.power($0.rank ?? .three, twosAreBombs: state.settings.twosAreBombs)
                    > Self.power($1.rank ?? .three, twosAreBombs: state.settings.twosAreBombs)
            }
            let takerHand = state.hand(pair.taker).sorted {
                Self.power($0.rank ?? .three, twosAreBombs: state.settings.twosAreBombs)
                    < Self.power($1.rank ?? .three, twosAreBombs: state.settings.twosAreBombs)
            }
            let best = giverHand.prefix(pair.count).map(\.id)
            let worst = takerHand.prefix(pair.count).map(\.id)
            for id in best { state.board.move(id, to: .hand(pair.taker), facing: .hand(pair.taker)) }
            for id in worst { state.board.move(id, to: .hand(pair.giver), facing: .hand(pair.giver)) }
            events.append(.cardsMoved(cards: best, from: .hand(pair.giver), to: .hand(pair.taker)))
            events.append(.cardsMoved(cards: worst, from: .hand(pair.taker), to: .hand(pair.giver)))
        }
        for seat in state.seatOrder { state.board.sort(.hand(seat), by: HandSort.byRankThenSuit) }
        events.append(.highlight(code: "president.exchange", seat: standings.first, value: nil))
        return events
    }

    private func buildResult(state: State) -> GameResult {
        let ranked = state.seatOrder.sorted { (state.scores[$0] ?? 0) > (state.scores[$1] ?? 0) }
        let best = state.scores.values.max() ?? 0
        let winners = state.seatOrder.filter { (state.scores[$0] ?? 0) == best }
        let leader = winners.first ?? ranked[0]
        var metrics: [String: Int] = [:]
        metrics[PresidentStatistics.presidencies] = state.presidencies[leader] ?? 0
        metrics[PresidentStatistics.bombs] = state.bombsPlayed[leader] ?? 0
        metrics[PresidentStatistics.finalScore] = state.scores[leader] ?? 0
        var highlights: [String] = []
        if (state.presidencies[leader] ?? 0) == state.settings.rounds { highlights.append("president.dynasty") }
        return GameResult(winners: winners,
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
        case .pass:
            return ActionToken(id: TokenID.make(seat, "pass"), kind: .passTurn, seat: seat, labelKey: "action.pass")
        case let .play(ids):
            let sorted = ids.sorted()
            let rank = state.board.card(sorted[0])?.rank
            return ActionToken(id: TokenID.make(seat, "play", cards: sorted),
                               kind: .playCard,
                               seat: seat,
                               cards: sorted,
                               destination: .discard,
                               source: .hand(seat),
                               amount: sorted.count,
                               labelKey: "action.playSet",
                               labelArguments: [String(sorted.count), rank?.localizationKey ?? ""])
        }
    }

    public func decodeAction(id: String, in state: State) -> Action? {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        if parts[1] == "pass" { return .pass }
        guard parts[1] == "play" else { return nil }
        let ids = parts.dropFirst(2).compactMap { Int($0) }.map { CardID(rawValue: $0) }
        return ids.isEmpty ? nil : .play(ids)
    }

    // MARK: - Observation

    public func observation(of state: State, for seat: SeatID) -> Observation {
        var counts: [SeatID: Int] = [:]
        for other in state.seatOrder where other != seat {
            counts[other] = state.board.count(in: .hand(other))
        }
        return Observation(seat: seat,
                           hand: state.hand(seat),
                           leadCount: state.leadCount,
                           leadRank: state.leadRank,
                           lastPlayer: state.lastPlayer,
                           opponentCardCounts: counts,
                           pileCount: state.board.count(in: .discard),
                           playedCards: state.board.cardList(in: .discard) + state.board.cardList(in: .reserve),
                           finishOrder: state.finishOrder,
                           settings: state.settings,
                           seatOrder: state.seatOrder)
    }

    // MARK: - Presentation

    public func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation {
        var slots: [TableSlot] = []
        if let own = TableBuilder.ownHandSlot(viewer: viewer, seating: seating) { slots.append(own) }
        slots += TableBuilder.opponentSlots(seating: seating, viewer: viewer)
        slots.append(TableSlot(zone: .discard,
                               style: .row(overlap: 0.35),
                               anchor: .centre(order: 0),
                               titleKey: "zone.pile",
                               emptyHintKey: "zone.pile.leadAnything",
                               prominence: 1.5))

        var callouts: [TableCallout] = []
        if let rank = state.leadRank {
            callouts.append(TableCallout(id: "beat",
                                         labelKey: "callout.beatThis",
                                         arguments: [String(state.leadCount), rank.localizationKey],
                                         emphasis: .primary))
        } else {
            callouts.append(TableCallout(id: "lead", labelKey: "callout.yourLead", emphasis: .primary))
        }
        callouts.append(TableCallout(id: "round",
                                     labelKey: "callout.dealOf",
                                     arguments: [String(state.roundNumber), String(state.settings.rounds)]))

        var states: [SeatID: String] = [:]
        for (index, seat) in state.finishOrder.enumerated() {
            states[seat] = index == 0 ? "state.president" : (index == state.seatOrder.count - 1 ? "state.scum" : "state.out")
        }
        for seat in state.passedSeats where states[seat] == nil { states[seat] = "state.passed" }

        var scores: [SeatID: Int] = [:]
        for seat in state.seatOrder { scores[seat] = state.board.count(in: .hand(seat)) }

        var actions: [ActionToken] = []
        var playable: Set<CardID> = []
        if let viewer, state.activeSeat == viewer {
            let legal = legalActions(in: state, for: viewer)
            actions = legal.map { token(for: $0, in: state) }
            playable = Set(actions.flatMap(\.cards))
        }

        return TablePresentation(gameID: Self.gameID,
                                 viewer: viewer,
                                 board: state.board.redacted(for: viewer),
                                 slots: slots,
                                 seats: TableBuilder.seatStatuses(seating: seating,
                                                                  board: state.board,
                                                                  activeSeat: state.activeSeat,
                                                                  scores: scores,
                                                                  scoreLabelKey: "label.cards",
                                                                  states: states,
                                                                  wagers: state.scores),
                                 callouts: callouts,
                                 actions: actions,
                                 playableCards: playable,
                                 activeSeat: state.activeSeat,
                                 roundNumber: state.roundNumber,
                                 phaseKey: "phase.deal",
                                 phaseArguments: [String(state.roundNumber)],
                                 result: state.finalResult)
    }

    public func hint(for state: State, seat: SeatID) -> Hint? {
        guard state.activeSeat == seat else { return nil }
        let hand = state.hand(seat)
        if state.leadRank == nil {
            return Hint(messageKey: "hint.president.lead",
                        english: "You have the lead, so you choose the size. Leading a pair or a triple burns other players' matching cards while you still hold singles to finish with.",
                        cards: hand.prefix(4).map(\.id))
        }
        let legal = legalActions(in: state, for: seat)
        if legal.count == 1, case .pass = legal[0] {
            return Hint(messageKey: "hint.president.mustPass",
                        arguments: [String(state.leadCount), state.leadRank?.localizationKey ?? ""],
                        english: "Nothing you hold beats that, so you pass. Once everybody passes, whoever played last leads again.")
        }
        return Hint(messageKey: "hint.president.hold",
                    english: "Passing when you could play is often right: whoever plays last leads next, and leading is worth more than shedding one card.")
    }
}

public enum PresidentStatistics {
    public static let presidencies = "president.presidencies"
    public static let bombs = "president.bombs"
    public static let finalScore = "president.finalScore"
}

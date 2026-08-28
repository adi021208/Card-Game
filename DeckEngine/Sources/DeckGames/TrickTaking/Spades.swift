import Foundation
import DeckCore

/// Spades — partnership bidding, with spades permanently trump.
///
/// You say how many tricks you will take before a card is played, and then you
/// have to take exactly that many. Taking too few is a disaster; taking too many
/// piles up bags until they cost you a hundred points all at once.
public struct SpadesRules: GameRules {
    public static let gameID = GameID.spades
    public static let rulesVersion = 1

    public init() {}

    // MARK: - Settings

    public struct Settings: Hashable, Codable, Sendable {
        public var targetScore: Int
        /// Bags that trigger the penalty. Ten is standard.
        public var bagLimit: Int
        public var bagPenalty: Int
        /// Bidding nil is allowed and worth this much made, lost if broken.
        public var nilValue: Int
        /// Bidding nil before looking at your hand, worth double.
        public var allowBlindNil: Bool
        /// Spades may not be led until one has been played off-suit.
        public var mustBreakSpades: Bool

        public init(targetScore: Int = 500,
                    bagLimit: Int = 10,
                    bagPenalty: Int = 100,
                    nilValue: Int = 100,
                    allowBlindNil: Bool = false,
                    mustBreakSpades: Bool = true) {
            self.targetScore = targetScore
            self.bagLimit = bagLimit
            self.bagPenalty = bagPenalty
            self.nilValue = nilValue
            self.allowBlindNil = allowBlindNil
            self.mustBreakSpades = mustBreakSpades
        }

        public static func from(_ configuration: GameConfiguration) -> Settings {
            Settings(targetScore: configuration.option("targetScore", default: 500),
                     bagLimit: configuration.option("bagLimit", default: 10),
                     bagPenalty: configuration.option("bagPenalty", default: 100),
                     nilValue: configuration.option("nilValue", default: 100),
                     allowBlindNil: configuration.flag("allowBlindNil"),
                     mustBreakSpades: configuration.flag("mustBreakSpades", default: true))
        }
    }

    public enum Phase: Hashable, Codable, Sendable {
        case bidding
        case playing
        case scoring
    }

    // MARK: - State

    public struct State: GameStateProtocol {
        public var board: Board
        public var activeSeat: SeatID?
        public var roundNumber: Int
        public var finalResult: GameResult?

        public var settings: Settings
        public var seatOrder: [SeatID]
        /// Team index for each seat: 0 or 1.
        public var teams: [SeatID: Int]
        public var phase: Phase
        public var bids: [SeatID: Int]
        public var trickPlays: [TrickPlay]
        public var ledSuit: Suit?
        public var trickNumber: Int
        public var spadesBroken: Bool
        public var dealerSeat: SeatID
        public var tricksWon: [SeatID: Int]
        /// Match totals, keyed by team index.
        public var teamScores: [Int: Int]
        public var teamBags: [Int: Int]
        public var nilsMade: [SeatID: Int]
        public var turnsTaken: Int
        public var dealComplete: Bool

        public func hand(_ seat: SeatID) -> [Card] { board.cardList(in: .hand(seat)) }
        public func team(_ seat: SeatID) -> Int { teams[seat] ?? 0 }
    }

    public enum Action: Hashable, Sendable {
        /// Bid a number of tricks. Zero is nil.
        case bid(Int)
        case play(CardID)
    }

    public struct Observation: Sendable {
        public var seat: SeatID
        public var hand: [Card]
        public var phase: Phase
        public var bids: [SeatID: Int]
        public var partner: SeatID?
        public var trickPlays: [(seat: SeatID, card: Card)]
        public var ledSuit: Suit?
        public var trickNumber: Int
        public var spadesBroken: Bool
        public var tricksWon: [SeatID: Int]
        public var teamScores: [Int: Int]
        public var teamBags: [Int: Int]
        public var playedCards: [(seat: SeatID, card: Card)]
        public var seatOrder: [SeatID]
        public var settings: Settings
        public var legalCards: [Card]
    }

    // MARK: - Setup

    public func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State {
        let settings = Settings.from(configuration)
        let seats = configuration.seating.ids
        var teams: [SeatID: Int] = [:]
        for (index, seat) in seats.enumerated() {
            // Partners sit opposite: 0 with 2, 1 with 3.
            teams[seat] = configuration.seating[seat]?.team ?? (index % 2)
        }
        let board = Self.deal(seats: seats, generator: &generator)
        let dealer = seats[0]
        return State(board: board,
                     activeSeat: nextSeat(after: dealer, in: seats),
                     roundNumber: 1,
                     finalResult: nil,
                     settings: settings,
                     seatOrder: seats,
                     teams: teams,
                     phase: .bidding,
                     bids: [:],
                     trickPlays: [],
                     ledSuit: nil,
                     trickNumber: 1,
                     spadesBroken: false,
                     dealerSeat: dealer,
                     tricksWon: [:],
                     teamScores: [0: 0, 1: 0],
                     teamBags: [0: 0, 1: 0],
                     nilsMade: [:],
                     turnsTaken: 0,
                     dealComplete: false)
    }

    static func deal(seats: [SeatID], generator: inout SeededGenerator) -> Board {
        var board = Board()
        var deck = DeckConfiguration.standard52.build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)
        board.ensureZones(seats.flatMap { [Zone.hand($0), Zone.captured($0)] } + [.trick, .stock])
        let perPlayer = 52 / max(1, seats.count)
        for _ in 0..<perPlayer {
            for seat in seats {
                board.draw(from: .stock, to: .hand(seat), facing: .hand(seat))
            }
        }
        for seat in seats {
            board.sort(.hand(seat), by: HandSort.bySuitThenRank)
        }
        return board
    }

    private func nextSeat(after seat: SeatID, in seats: [SeatID]) -> SeatID {
        guard let index = seats.firstIndex(of: seat) else { return seats[0] }
        return seats[(index + 1) % seats.count]
    }

    // MARK: - Legality

    public func legalCards(in state: State, for seat: SeatID) -> [Card] {
        let hand = state.hand(seat)
        guard !hand.isEmpty else { return [] }
        if state.trickPlays.isEmpty {
            guard state.settings.mustBreakSpades, !state.spadesBroken else { return hand }
            let nonSpades = hand.filter { $0.suit != .spades }
            return nonSpades.isEmpty ? hand : nonSpades
        }
        guard let ledSuit = state.ledSuit else { return hand }
        return TrickEngine.followingCards(hand: hand, ledSuit: ledSuit)
    }

    public func legalActions(in state: State, for seat: SeatID) -> [Action] {
        guard state.finalResult == nil, state.activeSeat == seat else { return [] }
        switch state.phase {
        case .bidding:
            let handSize = state.hand(seat).count
            return (0...handSize).map { Action.bid($0) }
        case .playing:
            return legalCards(in: state, for: seat).map { Action.play($0.id) }
        case .scoring:
            return []
        }
    }

    public func rejection(for action: Action, in state: State) -> IllegalMove? {
        guard state.finalResult == nil else { return .gameOver }
        guard let seat = state.activeSeat else { return .notYourTurn }
        switch action {
        case let .bid(value):
            guard state.phase == .bidding else { return .noSuchAction }
            guard value >= 0, value <= state.hand(seat).count else {
                return IllegalMove("bidOutOfRange",
                                   arguments: [String(state.hand(seat).count)],
                                   english: "Bid between 0 and \(state.hand(seat).count).")
            }
            return nil
        case let .play(cardID):
            guard state.phase == .playing else { return .noSuchAction }
            guard state.board.zone(of: cardID) == Zone.hand(seat) else { return .cardNotInHand }
            guard let card = state.board.card(cardID) else { return .cardNotInHand }
            guard legalCards(in: state, for: seat).contains(where: { $0.id == cardID }) else {
                if let ledSuit = state.ledSuit,
                   TrickEngine.canFollow(hand: state.hand(seat), ledSuit: ledSuit) {
                    return .mustFollowSuit(ledSuit)
                }
                if card.suit == .spades && !state.spadesBroken {
                    return IllegalMove("spadesNotBroken",
                                       english: "Spades have not been broken, so you cannot lead one.")
                }
                return .noSuchAction
            }
            return nil
        }
    }

    // MARK: - Applying

    public func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard let seat = state.activeSeat else { return [] }
        var events: [GameEvent] = []

        switch action {
        case let .bid(value):
            state.bids[seat] = value
            events.append(.bidMade(seat: seat, value: value))
            if value == 0 {
                events.append(.highlight(code: "spades.nilBid", seat: seat, value: nil))
            }
            if state.bids.count == state.seatOrder.count {
                state.phase = .playing
                let leader = nextSeat(after: state.dealerSeat, in: state.seatOrder)
                state.activeSeat = leader
                events.append(.turnChanged(from: seat, to: leader))
            } else {
                let next = nextSeat(after: seat, in: state.seatOrder)
                state.activeSeat = next
                events.append(.turnChanged(from: seat, to: next))
            }

        case let .play(cardID):
            guard let card = state.board.card(cardID) else { return events }
            state.board.move(cardID, to: .trick, facing: .faceUp)
            state.trickPlays.append(TrickPlay(seat: seat, card: cardID))
            state.turnsTaken += 1
            events.append(.cardPlayed(card: cardID, by: seat, to: .trick))
            if state.trickPlays.count == 1 { state.ledSuit = card.suit }
            if card.suit == .spades && !state.spadesBroken {
                state.spadesBroken = true
                events.append(.highlight(code: "spades.broken", seat: seat, value: nil))
            }
            if state.trickPlays.count == state.seatOrder.count {
                events += completeTrick(state: &state)
            } else {
                let next = nextSeat(after: seat, in: state.seatOrder)
                state.activeSeat = next
                events.append(.turnChanged(from: seat, to: next))
            }
        }
        return events
    }

    private func completeTrick(state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        guard let ledSuit = state.ledSuit else { return events }
        let winner = TrickEngine.winner(plays: state.trickPlays,
                                        cards: state.board.cards,
                                        ledSuit: ledSuit,
                                        trump: .spades) ?? state.trickPlays[0].seat
        let cards = state.trickPlays.map(\.card)
        for id in cards {
            state.board.move(id, to: .captured(winner), facing: .faceUp)
        }
        state.tricksWon[winner, default: 0] += 1
        events.append(.trickCompleted(winner: winner, cards: cards))
        state.trickPlays = []
        state.ledSuit = nil
        state.trickNumber += 1

        if state.seatOrder.allSatisfy({ state.board.isEmpty(Zone.hand($0)) }) {
            state.phase = .scoring
            state.activeSeat = nil
            state.dealComplete = true
        } else {
            state.activeSeat = winner
            events.append(.turnChanged(from: nil, to: winner))
        }
        return events
    }

    // MARK: - Scoring

    public func advanceAutomatically(_ state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard state.finalResult == nil, state.dealComplete else { return [] }
        state.dealComplete = false
        var events = scoreDeal(state: &state)
        if state.finalResult != nil { return events }
        events += startNextDeal(state: &state, generator: &generator)
        return events
    }

    private func scoreDeal(state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        for team in [0, 1] {
            let members = state.seatOrder.filter { state.team($0) == team }
            var teamBid = 0
            var teamTricks = 0
            var delta = 0

            for seat in members {
                let bid = state.bids[seat] ?? 0
                let tricks = state.tricksWon[seat] ?? 0
                if bid == 0 {
                    // Nil is scored on its own, and its tricks do not help the
                    // partnership's contract.
                    if tricks == 0 {
                        delta += state.settings.nilValue
                        state.nilsMade[seat, default: 0] += 1
                        events.append(.highlight(code: "spades.nilMade", seat: seat, value: nil))
                    } else {
                        delta -= state.settings.nilValue
                    }
                    teamTricks += tricks
                } else {
                    teamBid += bid
                    teamTricks += tricks
                }
            }

            if teamBid > 0 {
                if teamTricks >= teamBid {
                    let overtricks = teamTricks - teamBid
                    delta += teamBid * 10 + overtricks
                    state.teamBags[team, default: 0] += overtricks
                    if state.teamBags[team, default: 0] >= state.settings.bagLimit {
                        state.teamBags[team] = (state.teamBags[team] ?? 0) - state.settings.bagLimit
                        delta -= state.settings.bagPenalty
                        events.append(.highlight(code: "spades.bagged", seat: members.first, value: nil))
                    }
                } else {
                    delta -= teamBid * 10
                }
            }

            state.teamScores[team, default: 0] += delta
            for seat in members {
                events.append(.scoreChanged(seat: seat, delta: delta, total: state.teamScores[team] ?? 0))
            }
        }

        var seatScores: [SeatID: Int] = [:]
        for seat in state.seatOrder { seatScores[seat] = state.teamScores[state.team(seat)] ?? 0 }
        events.append(.roundEnded(scores: seatScores))

        let target = state.settings.targetScore
        let reached = (state.teamScores[0] ?? 0) >= target || (state.teamScores[1] ?? 0) >= target
        if reached {
            let result = buildResult(state: state)
            state.finalResult = result
            state.activeSeat = nil
            events.append(.gameEnded(result))
        }
        return events
    }

    private func startNextDeal(state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        state.roundNumber += 1
        state.board = Self.deal(seats: state.seatOrder, generator: &generator)
        state.phase = .bidding
        state.bids = [:]
        state.tricksWon = [:]
        state.trickPlays = []
        state.ledSuit = nil
        state.trickNumber = 1
        state.spadesBroken = false
        state.dealerSeat = nextSeat(after: state.dealerSeat, in: state.seatOrder)
        state.activeSeat = nextSeat(after: state.dealerSeat, in: state.seatOrder)
        return [.roundStarted(number: state.roundNumber),
                .handsDealt(counts: Dictionary(uniqueKeysWithValues: state.seatOrder.map { ($0, 13) }))]
    }

    private func buildResult(state: State) -> GameResult {
        let scoreZero = state.teamScores[0] ?? 0
        let scoreOne = state.teamScores[1] ?? 0
        let winningTeam = scoreZero == scoreOne ? nil : (scoreZero > scoreOne ? 0 : 1)
        let winners = winningTeam.map { team in state.seatOrder.filter { state.team($0) == team } } ?? []
        var seatScores: [SeatID: Int] = [:]
        for seat in state.seatOrder { seatScores[seat] = state.teamScores[state.team(seat)] ?? 0 }
        let ranked = state.seatOrder.sorted { (seatScores[$0] ?? 0) > (seatScores[$1] ?? 0) }
        let leader = winners.first ?? ranked[0]
        var metrics: [String: Int] = [:]
        metrics[SpadesStatistics.tricksWon] = state.tricksWon[leader] ?? 0
        metrics[SpadesStatistics.nilsMade] = state.nilsMade[leader] ?? 0
        metrics[SpadesStatistics.bags] = state.teamBags[state.team(leader)] ?? 0
        metrics[SpadesStatistics.finalScore] = seatScores[leader] ?? 0
        var highlights: [String] = []
        if (state.nilsMade[leader] ?? 0) > 0 { highlights.append("spades.nilMade") }
        return GameResult(winners: winners,
                          scores: seatScores,
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
        case let .bid(value):
            return ActionToken(id: TokenID.make(seat, "bid", [String(value)]),
                               kind: .bid,
                               seat: seat,
                               amount: value,
                               labelKey: value == 0 ? "action.bidNil" : "action.bid",
                               labelArguments: [String(value)])
        case let .play(cardID):
            let name = state.board.card(cardID)?.englishName ?? ""
            return ActionToken(id: TokenID.make(seat, "play", card: cardID),
                               kind: .playCard,
                               seat: seat,
                               cards: [cardID],
                               destination: .trick,
                               source: .hand(seat),
                               labelKey: "action.play",
                               labelArguments: [name])
        }
    }

    public func decodeAction(id: String, in state: State) -> Action? {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count >= 3 else { return nil }
        switch parts[1] {
        case "bid":
            guard let value = Int(parts[2]) else { return nil }
            return .bid(value)
        case "play":
            guard let raw = Int(parts[2]) else { return nil }
            return .play(CardID(rawValue: raw))
        default:
            return nil
        }
    }

    // MARK: - Observation

    public func observation(of state: State, for seat: SeatID) -> Observation {
        let plays = state.trickPlays.compactMap { play -> (seat: SeatID, card: Card)? in
            guard let card = state.board.card(play.card) else { return nil }
            return (play.seat, card)
        }
        var played: [(seat: SeatID, card: Card)] = []
        for other in state.seatOrder {
            for card in state.board.cardList(in: .captured(other)) { played.append((other, card)) }
        }
        let partner = state.seatOrder.first { $0 != seat && state.team($0) == state.team(seat) }
        return Observation(seat: seat,
                           hand: state.hand(seat),
                           phase: state.phase,
                           bids: state.bids,
                           partner: partner,
                           trickPlays: plays,
                           ledSuit: state.ledSuit,
                           trickNumber: state.trickNumber,
                           spadesBroken: state.spadesBroken,
                           tricksWon: state.tricksWon,
                           teamScores: state.teamScores,
                           teamBags: state.teamBags,
                           playedCards: played,
                           seatOrder: state.seatOrder,
                           settings: state.settings,
                           legalCards: legalCards(in: state, for: seat))
    }

    // MARK: - Presentation

    public func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation {
        var slots: [TableSlot] = []
        if let own = TableBuilder.ownHandSlot(viewer: viewer, seating: seating) { slots.append(own) }
        slots += TableBuilder.opponentSlots(seating: seating, viewer: viewer)
        slots.append(TableSlot(zone: .trick,
                               style: .row(overlap: 0.0),
                               anchor: .centre(order: 0),
                               titleKey: "zone.trick",
                               prominence: 1.4))

        var callouts: [TableCallout] = []
        if state.phase == .bidding {
            callouts.append(TableCallout(id: "bidding", labelKey: "callout.bidding", emphasis: .primary))
        } else {
            let teamZero = state.seatOrder.filter { state.team($0) == 0 }
            let teamOne = state.seatOrder.filter { state.team($0) == 1 }
            let bidZero = teamZero.reduce(0) { $0 + (state.bids[$1] ?? 0) }
            let bidOne = teamOne.reduce(0) { $0 + (state.bids[$1] ?? 0) }
            let wonZero = teamZero.reduce(0) { $0 + (state.tricksWon[$1] ?? 0) }
            let wonOne = teamOne.reduce(0) { $0 + (state.tricksWon[$1] ?? 0) }
            callouts.append(TableCallout(id: "contractUs",
                                         labelKey: "callout.contract",
                                         arguments: [String(wonZero), String(bidZero)],
                                         emphasis: .primary))
            callouts.append(TableCallout(id: "contractThem",
                                         labelKey: "callout.contractThem",
                                         arguments: [String(wonOne), String(bidOne)]))
            callouts.append(TableCallout(id: "trump",
                                         labelKey: "callout.trump",
                                         arguments: [Suit.spades.localizationKey],
                                         suit: .spades))
        }
        callouts.append(TableCallout(id: "bags",
                                     labelKey: "callout.bags",
                                     arguments: [String(state.teamBags[0] ?? 0), String(state.teamBags[1] ?? 0)]))

        var states: [SeatID: String] = [:]
        for seat in state.seatOrder {
            if let bid = state.bids[seat] {
                states[seat] = bid == 0 ? "state.nil" : "state.bid"
            }
        }
        var seatScores: [SeatID: Int] = [:]
        for seat in state.seatOrder { seatScores[seat] = state.tricksWon[seat] ?? 0 }

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
                                                                  scores: seatScores,
                                                                  scoreLabelKey: "label.tricks",
                                                                  states: states,
                                                                  wagers: state.bids),
                                 callouts: callouts,
                                 actions: actions,
                                 playableCards: Set(actions.flatMap(\.cards)),
                                 activeSeat: state.activeSeat,
                                 roundNumber: state.roundNumber,
                                 phaseKey: state.phase == .bidding ? "phase.bidding" : "phase.trick",
                                 phaseArguments: [String(state.trickNumber)],
                                 result: state.finalResult)
    }

    // MARK: - Hints

    public func hint(for state: State, seat: SeatID) -> Hint? {
        guard state.activeSeat == seat else { return nil }
        if state.phase == .bidding {
            let hand = state.hand(seat)
            let spades = hand.filter { $0.suit == .spades }.count
            let aces = hand.filter { $0.rank == .ace }.count
            return Hint(messageKey: "hint.spades.bidding",
                        arguments: [String(spades), String(aces)],
                        english: "Count your certain tricks: aces, guarded kings, and every spade past the third. You hold \(spades) spades and \(aces) aces.")
        }
        let legal = legalCards(in: state, for: seat)
        guard !legal.isEmpty else { return nil }
        let bid = state.bids[seat] ?? 0
        let won = state.tricksWon[seat] ?? 0
        if bid == 0 {
            return Hint(messageKey: "hint.spades.nil",
                        english: "You bid nil, so every trick is a disaster. Play your highest losing card and stay off the lead.",
                        cards: legal.map(\.id))
        }
        if won >= bid {
            return Hint(messageKey: "hint.spades.bags",
                        arguments: [String(won), String(bid)],
                        english: "You already have your \(bid). Extra tricks become bags, and ten bags costs a hundred points — duck from here.",
                        cards: legal.map(\.id))
        }
        return Hint(messageKey: "hint.spades.contract",
                    arguments: [String(bid - won)],
                    english: "You still need \(bid - won). Spades beat everything, so a low spade on a suit you are void in is a trick nobody can take from you.",
                    cards: legal.map(\.id))
    }
}

public enum SpadesStatistics {
    public static let tricksWon = "spades.tricksWon"
    public static let nilsMade = "spades.nilsMade"
    public static let bags = "spades.bags"
    public static let finalScore = "spades.finalScore"
}

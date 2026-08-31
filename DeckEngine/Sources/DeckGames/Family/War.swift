import Foundation
import DeckCore

/// War.
///
/// No decisions, no strategy, and everybody has played it. The interest is
/// entirely in the reveal, so the engine models each flip as its own step rather
/// than resolving a whole game at once — the tension is the product.
public struct WarRules: GameRules {
    public static let gameID = GameID.war
    public static let rulesVersion = 1

    public init() {}

    public struct Settings: Hashable, Codable, Sendable {
        /// Cards laid face down by each player in a war. Three is traditional.
        public var warStake: Int
        /// Flips after which the player holding more cards wins, so a game
        /// cannot run forever.
        public var flipLimit: Int

        public init(warStake: Int = 3, flipLimit: Int = 600) {
            self.warStake = warStake
            self.flipLimit = flipLimit
        }

        public static func from(_ configuration: GameConfiguration) -> Settings {
            Settings(warStake: configuration.option("warStake", default: 3),
                     flipLimit: configuration.option("flipLimit", default: 600))
        }
    }

    public struct State: GameStateProtocol {
        public var board: Board
        public var activeSeat: SeatID?
        public var roundNumber: Int
        public var finalResult: GameResult?

        public var settings: Settings
        public var seatOrder: [SeatID]
        /// Cards each player has flipped for the current battle.
        public var battle: [SeatID: [CardID]]
        /// True while a tie is being resolved.
        public var atWar: Bool
        public var warDepth: Int
        public var flips: Int
        public var warsFought: Int
        public var battlesWon: [SeatID: Int]
        /// Set after a battle resolves so the interface can show it before the
        /// cards are swept up.
        public var lastBattleWinner: SeatID?
        public var pendingResolution: Bool

        /// A player's face-down deck.
        public func deckZone(_ seat: SeatID) -> Zone { Zone(.stock, owner: seat) }
        /// Cards a player has won, shuffled back in when their deck runs out.
        public func wonZone(_ seat: SeatID) -> Zone { Zone(.captured, owner: seat) }
        public func totalCards(_ seat: SeatID) -> Int {
            board.count(in: deckZone(seat)) + board.count(in: wonZone(seat))
        }
    }

    public enum Action: Hashable, Sendable {
        /// Turn the next card. In a war this also lays the face-down stake.
        case flip
    }

    public struct Observation: Sendable {
        public var seat: SeatID
        public var ownDeckCount: Int
        public var ownWonCount: Int
        public var opponentTotals: [SeatID: Int]
        public var atWar: Bool
    }

    // MARK: - Setup

    public func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State {
        let settings = Settings.from(configuration)
        let seats = configuration.seating.ids
        var board = Board()
        var deck = DeckConfiguration.standard52.build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)

        var zones: [Zone] = [.stock, .trick]
        for seat in seats {
            zones.append(Zone(.stock, owner: seat))
            zones.append(Zone(.captured, owner: seat))
        }
        board.ensureZones(zones)

        // Deal the whole pack out one at a time.
        var index = 0
        while board.count(in: .stock) > 0 {
            let seat = seats[index % seats.count]
            board.draw(from: .stock, to: Zone(.stock, owner: seat), facing: .faceDown)
            index += 1
        }

        return State(board: board,
                     activeSeat: seats.first,
                     roundNumber: 1,
                     finalResult: nil,
                     settings: settings,
                     seatOrder: seats,
                     battle: [:],
                     atWar: false,
                     warDepth: 0,
                     flips: 0,
                     warsFought: 0,
                     battlesWon: [:],
                     lastBattleWinner: nil,
                     pendingResolution: false)
    }

    public func legalActions(in state: State, for seat: SeatID) -> [Action] {
        guard state.finalResult == nil, state.activeSeat == seat, !state.pendingResolution else { return [] }
        return [.flip]
    }

    public func rejection(for action: Action, in state: State) -> IllegalMove? {
        guard state.finalResult == nil else { return .gameOver }
        guard !state.pendingResolution else { return .noSuchAction }
        return nil
    }

    public func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        var events: [GameEvent] = []
        state.flips += 1

        // Everybody turns at once — one tap resolves the whole battle.
        for seat in state.seatOrder {
            if state.atWar {
                for _ in 0..<state.settings.warStake {
                    guard let card = drawCard(seat: seat, state: &state, generator: &generator) else { break }
                    state.board.move(card.id, to: .trick, facing: .faceDown)
                    state.battle[seat, default: []].append(card.id)
                }
            }
            guard let card = drawCard(seat: seat, state: &state, generator: &generator) else { continue }
            state.board.move(card.id, to: .trick, facing: .faceUp)
            state.battle[seat, default: []].append(card.id)
            events.append(.cardFlipped(card: card.id, faceUp: true))
        }
        state.pendingResolution = true
        return events
    }

    /// Draws from a player's deck, turning their winnings over when it empties.
    private func drawCard(seat: SeatID, state: inout State, generator: inout SeededGenerator) -> Card? {
        let deck = state.deckZone(seat)
        if state.board.isEmpty(deck) {
            let won = state.wonZone(seat)
            guard state.board.count(in: won) > 0 else { return nil }
            for id in state.board.contents(of: won) {
                state.board.move(id, to: deck, facing: .faceDown)
            }
            state.board.shuffle(deck, using: &generator)
        }
        guard let id = state.board.contents(of: deck).last else { return nil }
        return state.board.card(id)
    }

    public func advanceAutomatically(_ state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard state.finalResult == nil, state.pendingResolution else { return [] }
        state.pendingResolution = false
        var events: [GameEvent] = []

        // Compare the last face-up card each player laid.
        var best: (seat: SeatID, value: Int)?
        var tied: [SeatID] = []
        for seat in state.seatOrder {
            guard let last = state.battle[seat]?.last,
                  let card = state.board.card(last),
                  let rank = card.rank else { continue }
            let value = rank.rawValue
            if let current = best {
                if value > current.value {
                    best = (seat, value)
                    tied = [seat]
                } else if value == current.value {
                    tied.append(seat)
                }
            } else {
                best = (seat, value)
                tied = [seat]
            }
        }

        if tied.count > 1 {
            // A tie means war: the stake stays on the table and everybody flips
            // again on the next tap.
            state.atWar = true
            state.warDepth += 1
            state.warsFought += 1
            events.append(.highlight(code: "war.declared", seat: nil, value: state.warDepth))
            state.activeSeat = state.seatOrder.first
            events += checkForEnd(state: &state)
            return events
        }

        guard let winner = best?.seat else {
            events += checkForEnd(state: &state)
            return events
        }

        let spoils = state.board.contents(of: .trick)
        for id in spoils {
            state.board.move(id, to: state.wonZone(winner), facing: .faceDown)
        }
        state.battlesWon[winner, default: 0] += 1
        state.battle = [:]
        state.atWar = false
        state.warDepth = 0
        state.lastBattleWinner = winner
        state.roundNumber += 1
        events.append(.trickCompleted(winner: winner, cards: spoils))
        state.activeSeat = state.seatOrder.first
        events += checkForEnd(state: &state)
        return events
    }

    private func checkForEnd(state: inout State) -> [GameEvent] {
        let survivors = state.seatOrder.filter { state.totalCards($0) > 0 }
        let outOfFlips = state.flips >= state.settings.flipLimit
        guard survivors.count <= 1 || outOfFlips else { return [] }

        let ranked = state.seatOrder.sorted { state.totalCards($0) > state.totalCards($1) }
        let best = ranked.first.map { state.totalCards($0) } ?? 0
        let winners = state.seatOrder.filter { state.totalCards($0) == best }
        var scores: [SeatID: Int] = [:]
        for seat in state.seatOrder { scores[seat] = state.totalCards(seat) }
        let leader = winners.first ?? ranked[0]
        var metrics: [String: Int] = [:]
        metrics[WarStatistics.wars] = state.warsFought
        metrics[WarStatistics.battlesWon] = state.battlesWon[leader] ?? 0
        metrics[WarStatistics.flips] = state.flips
        var highlights: [String] = []
        if state.warsFought >= 5 { highlights.append("war.longCampaign") }
        if survivors.count <= 1 && !outOfFlips { highlights.append("war.total") }
        let result = GameResult(winners: winners,
                                scores: scores,
                                placements: ranked,
                                duration: 0,
                                turnCount: state.flips,
                                roundCount: state.roundNumber,
                                metrics: metrics,
                                highlights: highlights)
        state.finalResult = result
        state.activeSeat = nil
        return [.gameEnded(result)]
    }

    // MARK: - Tokens

    public func token(for action: Action, in state: State) -> ActionToken {
        let seat = state.activeSeat ?? state.seatOrder[0]
        return ActionToken(id: TokenID.make(seat, "flip"),
                           kind: .flipCard,
                           seat: seat,
                           labelKey: state.atWar ? "action.war" : "action.flip")
    }

    public func decodeAction(id: String, in state: State) -> Action? {
        id.contains("/flip") ? .flip : nil
    }

    public func observation(of state: State, for seat: SeatID) -> Observation {
        var totals: [SeatID: Int] = [:]
        for other in state.seatOrder where other != seat { totals[other] = state.totalCards(other) }
        return Observation(seat: seat,
                           ownDeckCount: state.board.count(in: state.deckZone(seat)),
                           ownWonCount: state.board.count(in: state.wonZone(seat)),
                           opponentTotals: totals,
                           atWar: state.atWar)
    }

    public func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation {
        var slots: [TableSlot] = []
        for (index, seat) in seating.ids.enumerated() {
            slots.append(TableSlot(zone: Zone(.stock, owner: seat),
                                   style: .stack,
                                   anchor: index == 0 ? .corner(.bottomLeading) : .corner(.topLeading),
                                   titleKey: "zone.yourDeck"))
        }
        slots.append(TableSlot(zone: .trick,
                               style: .row(overlap: 0.2),
                               anchor: .centre(order: 0),
                               titleKey: "zone.battle",
                               prominence: 1.8))

        var callouts: [TableCallout] = []
        if state.atWar {
            callouts.append(TableCallout(id: "war",
                                         labelKey: "callout.war",
                                         arguments: [String(state.warDepth)],
                                         emphasis: .alert))
        }
        callouts.append(TableCallout(id: "flips",
                                     labelKey: "callout.flips",
                                     arguments: [String(state.flips)]))

        var scores: [SeatID: Int] = [:]
        for seat in state.seatOrder { scores[seat] = state.totalCards(seat) }

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
                                                                  scoreLabelKey: "label.cards",
                                                                  handZone: { Zone(.stock, owner: $0) }),
                                 callouts: callouts,
                                 actions: actions,
                                 activeSeat: state.activeSeat,
                                 roundNumber: state.roundNumber,
                                 phaseKey: state.atWar ? "phase.war" : "phase.battle",
                                 result: state.finalResult)
    }

    public func hint(for state: State, seat: SeatID) -> Hint? {
        Hint(messageKey: "hint.war.noChoice",
             english: state.atWar
                ? "A tie means war: three cards face down and one up, and the winner takes the lot."
                : "There is nothing to decide in War — that is the game. Turn the card.")
    }
}

public enum WarStatistics {
    public static let wars = "war.wars"
    public static let battlesWon = "war.battlesWon"
    public static let flips = "war.flips"
}

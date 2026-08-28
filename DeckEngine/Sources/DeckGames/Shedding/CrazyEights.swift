import Foundation
import DeckCore

/// Crazy Eights.
///
/// Traditional rules: match the top of the discard pile by suit or rank, eights
/// are wild and their player nominates the next suit, and the first player to
/// shed their whole hand takes the deal. Two optional, clearly-labelled variants
/// change how drawing works and add the common household special cards.
public struct CrazyEightsRules: GameRules {
    public static let gameID = GameID.crazyEights
    public static let rulesVersion = 1

    public init() {}

    // MARK: - Settings

    /// The rules in force for one game. Stored inside the state so a saved game
    /// resumes under the rules it was dealt with, even if the defaults change.
    public struct Settings: Hashable, Codable, Sendable {
        /// Cards dealt to each player.
        public var handSize: Int
        /// Points that end the game. Zero means a single deal decides it.
        public var targetScore: Int
        /// Classic: keep drawing until something is playable. Otherwise draw one
        /// and pass if it still will not go.
        public var drawUntilPlayable: Bool
        /// Maximum cards a player may draw in one turn before passing, so an
        /// empty stock can never deadlock the game.
        public var drawLimit: Int
        /// Twos make the next player draw two, queens skip, aces reverse.
        public var houseSpecials: Bool
        /// Jokers in the deck, playable on anything and skipping the next player.
        public var useJokers: Bool

        public init(handSize: Int = 5,
                    targetScore: Int = 100,
                    drawUntilPlayable: Bool = true,
                    drawLimit: Int = 12,
                    houseSpecials: Bool = false,
                    useJokers: Bool = false) {
            self.handSize = handSize
            self.targetScore = targetScore
            self.drawUntilPlayable = drawUntilPlayable
            self.drawLimit = drawLimit
            self.houseSpecials = houseSpecials
            self.useJokers = useJokers
        }

        public static func from(_ configuration: GameConfiguration) -> Settings {
            let playerCount = configuration.seating.count
            return Settings(
                handSize: configuration.option("handSize", default: playerCount == 2 ? 7 : 5),
                targetScore: configuration.option("targetScore", default: 100),
                drawUntilPlayable: configuration.flag("drawUntilPlayable", default: true),
                drawLimit: configuration.option("drawLimit", default: 12),
                houseSpecials: configuration.flag("houseSpecials"),
                useJokers: configuration.flag("useJokers"))
        }
    }

    // MARK: - State

    public struct State: GameStateProtocol {
        public var board: Board
        public var activeSeat: SeatID?
        public var roundNumber: Int
        public var finalResult: GameResult?

        public var settings: Settings
        public var seatOrder: [SeatID]
        /// The suit that must be matched. Equals the top card's suit except
        /// after an eight, when it is whatever the player nominated.
        public var currentSuit: Suit
        /// Cards drawn by the active player this turn.
        public var drawsThisTurn: Int
        /// Cards the next player must draw before playing (house twos).
        public var pendingDraw: Int
        /// Whether the next player's turn is skipped (house queens, jokers).
        public var skipNext: Bool
        /// 1 clockwise, -1 anticlockwise (house aces).
        public var direction: Int
        public var scores: [SeatID: Int]
        /// Cumulative per-seat metrics for the statistics engine.
        public var eightsPlayed: [SeatID: Int]
        public var roundsWon: [SeatID: Int]
        public var turnsTaken: Int
        /// Set when the deal ends but the match continues.
        public var lastRoundWinner: SeatID?

        public func hand(_ seat: SeatID) -> [Card] { board.cardList(in: .hand(seat)) }
    }

    // MARK: - Actions

    public enum Action: Hashable, Sendable {
        /// Play a normal card.
        case play(CardID)
        /// Play an eight (or joker) and nominate the suit that follows.
        case playWild(CardID, Suit)
        /// Take a card from the stock.
        case draw
        /// Give up the turn after drawing.
        case pass
    }

    /// What an AI in a seat may know: its own hand, the public discard, the
    /// counts of everyone else's hands, and nothing whatsoever about the stock
    /// or about which cards the opponents hold.
    public struct Observation: Sendable {
        public var seat: SeatID
        public var hand: [Card]
        public var topCard: Card?
        public var currentSuit: Suit
        public var opponentCardCounts: [SeatID: Int]
        public var nextSeat: SeatID
        public var stockCount: Int
        public var discardCount: Int
        /// Cards visible in the discard pile, which every player has seen.
        public var seenCards: [Card]
        public var settings: Settings
        public var scores: [SeatID: Int]
        public var pendingDraw: Int
        public var drawsThisTurn: Int
    }

    // MARK: - Setup

    public func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State {
        let settings = Settings.from(configuration)
        let seats = configuration.seating.ids
        let deal = Self.deal(seats: seats, settings: settings, generator: &generator)
        let board = deal.board
        let starter = deal.starter
        let suit = starter?.suit ?? .spades
        var scores: [SeatID: Int] = [:]
        for seat in seats { scores[seat] = 0 }

        var state = State(board: board,
                          activeSeat: seats.first,
                          roundNumber: 1,
                          finalResult: nil,
                          settings: settings,
                          seatOrder: seats,
                          currentSuit: suit,
                          drawsThisTurn: 0,
                          pendingDraw: 0,
                          skipNext: false,
                          direction: 1,
                          scores: scores,
                          eightsPlayed: [:],
                          roundsWon: [:],
                          turnsTaken: 0,
                          lastRoundWinner: nil)

        // The starter's own special effect applies to the first player, which is
        // how it is played at a table.
        if settings.houseSpecials, let starter {
            applyStarterEffect(starter, to: &state)
        }
        return state
    }

    private func applyStarterEffect(_ card: Card, to state: inout State) {
        guard let rank = card.rank else { return }
        switch rank {
        case .two: state.pendingDraw = 2
        case .queen: state.skipNext = true
        case .ace where state.seatOrder.count > 2: state.direction = -1
        default: break
        }
    }

    /// Deals one hand: shuffle, five (or seven) each, turn the starter.
    ///
    /// An eight on the starter would leave the suit undefined before anyone has
    /// played, so it is buried and another card turned — the standard fix.
    static func deal(seats: [SeatID],
                     settings: Settings,
                     generator: inout SeededGenerator) -> (board: Board, starter: Card?) {
        var board = Board()
        var deckConfiguration = DeckConfiguration.standard52
        if settings.useJokers { deckConfiguration = .standard54 }
        // A big table needs a second pack or the stock runs dry every deal.
        if seats.count >= 5 { deckConfiguration.packs = 2 }

        var deck = deckConfiguration.build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)
        board.ensureZones(seats.map { Zone.hand($0) } + [.stock, .discard])

        // One card at a time around the table, as you would in person.
        for _ in 0..<settings.handSize {
            for seat in seats {
                board.draw(from: .stock, to: .hand(seat), facing: .hand(seat))
            }
        }
        for seat in seats {
            board.sort(.hand(seat), by: HandSort.bySuitThenRank)
        }

        var starter = board.draw(from: .stock, to: .discard, facing: .faceUp)
        var attempts = 0
        while let card = starter, card.rank == .eight || card.isJoker, attempts < 20 {
            board.move(card.id, to: .stock, facing: .faceDown)
            board.shuffle(.stock, using: &generator)
            starter = board.draw(from: .stock, to: .discard, facing: .faceUp)
            attempts += 1
        }
        return (board, starter)
    }

    // MARK: - Legality

    /// A card goes if it matches the nominated suit, matches the top card's
    /// rank, or is wild.
    public func isPlayable(_ card: Card, in state: State) -> Bool {
        if isWild(card, settings: state.settings) { return true }
        guard let top = state.board.top(of: .discard) else { return true }
        if card.suit == state.currentSuit { return true }
        if let cardRank = card.rank, let topRank = top.rank, cardRank == topRank { return true }
        return false
    }

    private func isWild(_ card: Card, settings: Settings) -> Bool {
        if card.rank == .eight { return true }
        if settings.useJokers && card.isJoker { return true }
        return false
    }

    public func legalActions(in state: State, for seat: SeatID) -> [Action] {
        guard state.finalResult == nil, state.activeSeat == seat else { return [] }
        let hand = state.hand(seat)

        // A pending draw penalty must be served before anything else. Stacking
        // is not part of the house rules here: you take the cards.
        if state.pendingDraw > 0 {
            return [.draw]
        }

        var actions: [Action] = []
        for card in hand where isPlayable(card, in: state) {
            if isWild(card, settings: state.settings) {
                for suit in Suit.allCases {
                    actions.append(.playWild(card.id, suit))
                }
            } else {
                actions.append(.play(card.id))
            }
        }

        let canDraw = state.board.count(in: .stock) > 0 || state.board.count(in: .discard) > 1
        let underDrawLimit = state.drawsThisTurn < state.settings.drawLimit

        if state.settings.drawUntilPlayable {
            // Classic: you may only draw while you have nothing to play, and you
            // may only pass once the stock cannot help you.
            if actions.isEmpty {
                if canDraw && underDrawLimit {
                    actions.append(.draw)
                } else {
                    actions.append(.pass)
                }
            }
        } else {
            // Draw-one: you may always choose to draw once, then pass.
            if state.drawsThisTurn == 0 && canDraw {
                actions.append(.draw)
            }
            if actions.isEmpty || state.drawsThisTurn > 0 {
                actions.append(.pass)
            }
        }
        return actions
    }

    public func rejection(for action: Action, in state: State) -> IllegalMove? {
        guard state.finalResult == nil else { return .gameOver }
        guard let seat = state.activeSeat else { return .notYourTurn }
        switch action {
        case let .play(cardID), let .playWild(cardID, _):
            guard state.board.zone(of: cardID) == Zone.hand(seat) else { return .cardNotInHand }
            guard let card = state.board.card(cardID) else { return .cardNotInHand }
            if state.pendingDraw > 0 {
                return IllegalMove("mustDrawPenalty",
                                   arguments: [String(state.pendingDraw)],
                                   english: "Take your \(state.pendingDraw) cards first.")
            }
            guard isPlayable(card, in: state) else {
                return IllegalMove("mustMatchSuitOrRank",
                                   arguments: [state.currentSuit.localizationKey],
                                   english: "Play a \(state.currentSuit.englishName), match the rank, or play an eight.")
            }
            if case .play = action, isWild(card, settings: state.settings) {
                return IllegalMove("wildNeedsSuit", english: "Choose the suit that follows your eight.")
            }
            return nil
        case .draw:
            guard state.board.count(in: .stock) > 0 || state.board.count(in: .discard) > 1 else {
                return .emptyPile
            }
            if state.settings.drawUntilPlayable,
               state.hand(seat).contains(where: { isPlayable($0, in: state) }),
               state.pendingDraw == 0 {
                return IllegalMove("mustPlayIfAble", english: "You have a card that goes — play it.")
            }
            return nil
        case .pass:
            if state.pendingDraw > 0 {
                return IllegalMove("mustDrawPenalty",
                                   arguments: [String(state.pendingDraw)],
                                   english: "Take your \(state.pendingDraw) cards first.")
            }
            if state.settings.drawUntilPlayable,
               state.hand(seat).contains(where: { isPlayable($0, in: state) }) {
                return IllegalMove("mustPlayIfAble", english: "You have a card that goes — play it.")
            }
            return nil
        }
    }

    // MARK: - Applying

    public func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard let seat = state.activeSeat else { return [] }
        var events: [GameEvent] = []

        switch action {
        case let .play(cardID):
            events += playCard(cardID, nominating: nil, seat: seat, state: &state)
        case let .playWild(cardID, suit):
            events += playCard(cardID, nominating: suit, seat: seat, state: &state)
        case .draw:
            let servingPenalty = state.pendingDraw > 0
            events += drawCard(seat: seat, state: &state, generator: &generator)
            // A penalty ends the turn once the last card has been taken. A
            // voluntary draw does not: the player carries on and either plays
            // the card they just found or passes.
            if servingPenalty && state.pendingDraw == 0 {
                events += advanceTurn(from: seat, state: &state)
            }
            return events
        case .pass:
            events.append(.turnSkipped(seat: seat))
            events += advanceTurn(from: seat, state: &state)
            return events
        }

        // Shed the last card and the deal is over.
        if state.board.isEmpty(Zone.hand(seat)) {
            events += finishRound(winner: seat, state: &state)
            return events
        }
        events += advanceTurn(from: seat, state: &state)
        return events
    }

    private func playCard(_ cardID: CardID, nominating suit: Suit?, seat: SeatID, state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        guard let card = state.board.card(cardID) else { return events }
        state.board.move(cardID, to: .discard, facing: .faceUp)
        state.turnsTaken += 1
        state.drawsThisTurn = 0
        events.append(.cardPlayed(card: cardID, by: seat, to: .discard))

        if let suit {
            state.currentSuit = suit
            state.eightsPlayed[seat, default: 0] += 1
            events.append(.suitChosen(suit, by: seat))
            events.append(.highlight(code: "crazy8.wild", seat: seat, value: nil))
        } else if let cardSuit = card.suit {
            state.currentSuit = cardSuit
        }

        if state.settings.useJokers && card.isJoker {
            state.skipNext = true
        }
        if state.settings.houseSpecials, let rank = card.rank {
            switch rank {
            case .two:
                state.pendingDraw += 2
            case .queen:
                state.skipNext = true
                events.append(.highlight(code: "crazy8.skip", seat: seat, value: nil))
            case .ace where state.seatOrder.count > 2:
                state.direction *= -1
                events.append(.directionReversed)
            default:
                break
            }
        }
        return events
    }

    private func drawCard(seat: SeatID, state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        var events: [GameEvent] = []
        if state.board.isEmpty(.stock) {
            // Turn the discard pile over, leaving the face-up starter in place.
            guard state.board.count(in: .discard) > 1 else { return events }
            state.board.recycleDiscard(into: .stock, from: .discard, keepingTop: true, using: &generator)
            events.append(.deckRecycled(from: .discard, to: .stock))
        }
        guard let card = state.board.draw(from: .stock, to: .hand(seat), facing: .hand(seat)) else {
            return events
        }
        state.board.sort(.hand(seat), by: HandSort.bySuitThenRank)
        events.append(.cardDrawn(card: card.id, by: seat, from: .stock))

        if state.pendingDraw > 0 {
            state.pendingDraw -= 1
        } else {
            state.drawsThisTurn += 1
        }
        return events
    }

    private func advanceTurn(from seat: SeatID, state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        state.drawsThisTurn = 0
        var next = step(from: seat, in: state)
        if state.skipNext {
            state.skipNext = false
            events.append(.turnSkipped(seat: next))
            next = step(from: next, in: state)
        }
        state.activeSeat = next
        events.append(.turnChanged(from: seat, to: next))
        return events
    }

    private func step(from seat: SeatID, in state: State) -> SeatID {
        guard let index = state.seatOrder.firstIndex(of: seat), !state.seatOrder.isEmpty else {
            return state.seatOrder.first ?? seat
        }
        let count = state.seatOrder.count
        let shifted = ((index + state.direction) % count + count) % count
        return state.seatOrder[shifted]
    }

    private func finishRound(winner: SeatID, state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        events.append(.highlight(code: "crazy8.shed", seat: winner, value: nil))
        state.roundsWon[winner, default: 0] += 1

        // The winner scores the value of everybody else's remaining cards.
        var roundPoints = 0
        var perSeat: [SeatID: Int] = [:]
        for seat in state.seatOrder where seat != winner {
            let value = state.hand(seat).reduce(0) { $0 + CardScoring.standardPoints($1) }
            perSeat[seat] = value
            roundPoints += value
        }
        state.scores[winner, default: 0] += roundPoints
        events.append(.scoreChanged(seat: winner, delta: roundPoints, total: state.scores[winner] ?? 0))
        events.append(.roundEnded(scores: state.scores))
        state.lastRoundWinner = winner

        let target = state.settings.targetScore
        let reachedTarget = target > 0 && (state.scores[winner] ?? 0) >= target
        if target == 0 || reachedTarget {
            let result = buildResult(state: state, winner: winner)
            state.finalResult = result
            state.activeSeat = nil
            events.append(.gameEnded(result))
        }
        return events
    }

    private func buildResult(state: State, winner: SeatID) -> GameResult {
        let ranked = state.seatOrder.sorted { (state.scores[$0] ?? 0) > (state.scores[$1] ?? 0) }
        var metrics: [String: Int] = [:]
        metrics[CrazyEightsStatistics.eightsPlayed] = state.eightsPlayed[winner] ?? 0
        metrics[CrazyEightsStatistics.roundsWon] = state.roundsWon[winner] ?? 0
        metrics[CrazyEightsStatistics.finalScore] = state.scores[winner] ?? 0
        var highlights: [String] = []
        if state.roundNumber == 1 && state.settings.targetScore == 0 {
            highlights.append("crazy8.oneDeal")
        }
        return GameResult(winners: [winner],
                          scores: state.scores,
                          placements: ranked,
                          duration: 0,
                          turnCount: state.turnsTaken,
                          roundCount: state.roundNumber,
                          metrics: metrics,
                          highlights: highlights)
    }

    /// Starts the next deal when the match target has not been reached yet.
    public func advanceAutomatically(_ state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard state.finalResult == nil, let winner = state.lastRoundWinner else { return [] }
        state.lastRoundWinner = nil
        state.roundNumber += 1

        let deal = Self.deal(seats: state.seatOrder, settings: state.settings, generator: &generator)
        let starter = deal.starter
        state.board = deal.board
        state.currentSuit = starter?.suit ?? .spades
        state.drawsThisTurn = 0
        state.pendingDraw = 0
        state.skipNext = false
        state.direction = 1
        // The deal moves on: the previous winner's left leads the new hand.
        let previousIndex = state.seatOrder.firstIndex(of: winner) ?? 0
        state.activeSeat = state.seatOrder[(previousIndex + 1) % state.seatOrder.count]
        if state.settings.houseSpecials, let starter {
            applyStarterEffect(starter, to: &state)
        }
        return [.roundStarted(number: state.roundNumber),
                .handsDealt(counts: Dictionary(uniqueKeysWithValues: state.seatOrder.map { ($0, state.settings.handSize) }))]
    }

    // MARK: - Tokens

    public func token(for action: Action, in state: State) -> ActionToken {
        let seat = state.activeSeat ?? state.seatOrder.first ?? SeatID(0)
        switch action {
        case let .play(cardID):
            let name = state.board.card(cardID)?.englishName ?? ""
            return ActionToken(id: TokenID.make(seat, "play", card: cardID),
                               kind: .playCard,
                               seat: seat,
                               cards: [cardID],
                               destination: .discard,
                               source: .hand(seat),
                               labelKey: "action.play",
                               labelArguments: [name])
        case let .playWild(cardID, suit):
            return ActionToken(id: TokenID.make(seat, "wild", [String(cardID.rawValue), suit.token]),
                               kind: .playCard,
                               seat: seat,
                               cards: [cardID],
                               destination: .discard,
                               source: .hand(seat),
                               labelKey: "action.playWild",
                               labelArguments: [suit.localizationKey])
        case .draw:
            return ActionToken(id: TokenID.make(seat, "draw"),
                               kind: .drawCard,
                               seat: seat,
                               source: .stock,
                               labelKey: "action.draw")
        case .pass:
            return ActionToken(id: TokenID.make(seat, "pass"),
                               kind: .passTurn,
                               seat: seat,
                               labelKey: "action.pass")
        }
    }

    public func decodeAction(id: String, in state: State) -> Action? {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        switch parts[1] {
        case "play":
            guard parts.count >= 3, let raw = Int(parts[2]) else { return nil }
            return .play(CardID(rawValue: raw))
        case "wild":
            guard parts.count >= 4, let raw = Int(parts[2]), let suit = Suit(token: parts[3]) else { return nil }
            return .playWild(CardID(rawValue: raw), suit)
        case "draw":
            return .draw
        case "pass":
            return .pass
        default:
            return nil
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
                           topCard: state.board.top(of: .discard),
                           currentSuit: state.currentSuit,
                           opponentCardCounts: counts,
                           nextSeat: step(from: seat, in: state),
                           stockCount: state.board.count(in: .stock),
                           discardCount: state.board.count(in: .discard),
                           seenCards: state.board.cardList(in: .discard),
                           settings: state.settings,
                           scores: state.scores,
                           pendingDraw: state.pendingDraw,
                           drawsThisTurn: state.drawsThisTurn)
    }

    // MARK: - Presentation

    public func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation {
        var slots: [TableSlot] = []
        if let own = TableBuilder.ownHandSlot(viewer: viewer, seating: seating) {
            slots.append(own)
        }
        slots += TableBuilder.opponentSlots(seating: seating, viewer: viewer)
        slots.append(TableSlot(zone: .stock,
                               style: .stack,
                               anchor: .centre(order: 0),
                               titleKey: "zone.stock",
                               emptyHintKey: "zone.stock.empty",
                               acceptsDrop: true))
        slots.append(TableSlot(zone: .discard,
                               style: .stack,
                               anchor: .centre(order: 1),
                               titleKey: "zone.discard",
                               acceptsDrop: true,
                               prominence: 1.3))

        var callouts: [TableCallout] = []
        callouts.append(TableCallout(id: "suit",
                                     labelKey: "callout.suitInPlay",
                                     arguments: [state.currentSuit.localizationKey],
                                     emphasis: .primary,
                                     suit: state.currentSuit))
        if state.pendingDraw > 0 {
            callouts.append(TableCallout(id: "penalty",
                                         labelKey: "callout.mustDraw",
                                         arguments: [String(state.pendingDraw)],
                                         emphasis: .alert))
        }
        if state.settings.targetScore > 0 {
            callouts.append(TableCallout(id: "target",
                                         labelKey: "callout.playingTo",
                                         arguments: [String(state.settings.targetScore)]))
        }
        callouts.append(TableCallout(id: "stock",
                                     labelKey: "callout.cardsInStock",
                                     arguments: [String(state.board.count(in: .stock))]))

        let actions = viewer.map { availableTokens(in: state, for: $0) } ?? []
        let playable = Set(actions.flatMap(\.cards))

        return TablePresentation(gameID: Self.gameID,
                                 viewer: viewer,
                                 board: state.board.redacted(for: viewer),
                                 slots: slots,
                                 seats: TableBuilder.seatStatuses(seating: seating,
                                                                  board: state.board,
                                                                  activeSeat: state.activeSeat,
                                                                  scores: state.scores,
                                                                  scoreLabelKey: "label.points"),
                                 callouts: callouts,
                                 actions: actions,
                                 playableCards: playable,
                                 activeSeat: state.activeSeat,
                                 roundNumber: state.roundNumber,
                                 phaseKey: "phase.deal",
                                 phaseArguments: [String(state.roundNumber)],
                                 result: state.finalResult)
    }

    private func availableTokens(in state: State, for seat: SeatID) -> [ActionToken] {
        legalActions(in: state, for: seat).map { token(for: $0, in: state) }
    }

    // MARK: - Hints

    public func hint(for state: State, seat: SeatID) -> Hint? {
        guard state.activeSeat == seat else { return nil }
        if state.pendingDraw > 0 {
            return Hint(messageKey: "hint.crazy8.penalty",
                        arguments: [String(state.pendingDraw)],
                        english: "A two was played against you. Take \(state.pendingDraw) cards before you can play again.")
        }
        let hand = state.hand(seat)
        let playable = hand.filter { isPlayable($0, in: state) }
        guard !playable.isEmpty else {
            return Hint(messageKey: "hint.crazy8.mustDraw",
                        arguments: [state.currentSuit.localizationKey],
                        english: "Nothing in your hand matches \(state.currentSuit.englishName) or the top rank, so you draw.")
        }
        let wilds = playable.filter { isWild($0, settings: state.settings) }
        if playable.count == wilds.count && !wilds.isEmpty {
            return Hint(messageKey: "hint.crazy8.onlyWild",
                        english: "Only your eight will go. Nominate the suit you hold most of.",
                        cards: wilds.map(\.id))
        }
        let nonWild = playable.filter { !isWild($0, settings: state.settings) }
        return Hint(messageKey: "hint.crazy8.matches",
                    arguments: [state.currentSuit.localizationKey, String(nonWild.count)],
                    english: "These \(nonWild.count) cards match the suit or the rank. Saving your eight for a suit you cannot follow is usually worth more than playing it now.",
                    cards: nonWild.map(\.id))
    }
}

/// Metric keys this game reports. Declared once so the definition, the engine
/// and the tests cannot drift apart.
public enum CrazyEightsStatistics {
    public static let eightsPlayed = "crazy8.eightsPlayed"
    public static let roundsWon = "crazy8.roundsWon"
    public static let finalScore = "crazy8.finalScore"
}

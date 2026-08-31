import Foundation
import DeckCore

/// Hearts.
///
/// Four players, thirteen tricks, and the whole game is about *not* winning.
/// Every heart costs a point and the Queen of Spades costs thirteen; take all
/// twenty-six and you shoot the moon, handing them to everybody else instead.
public struct HeartsRules: GameRules {
    public static let gameID = GameID.hearts
    public static let rulesVersion = 1

    public init() {}

    // MARK: - Settings

    public struct Settings: Hashable, Codable, Sendable {
        /// Score that ends the match. The lowest total then wins.
        public var targetScore: Int
        /// The Jack of Diamonds is worth −10 (the "Omnibus" rule).
        public var jackOfDiamondsBonus: Bool
        /// Shooting the moon subtracts 26 from the shooter instead of adding 26
        /// to everyone else.
        public var shootSubtracts: Bool
        /// The Queen of Spades may not be played on the opening trick.
        public var protectQueenFirstTrick: Bool
        /// Hearts may not be led until one has been discarded.
        public var mustBreakHearts: Bool

        public init(targetScore: Int = 100,
                    jackOfDiamondsBonus: Bool = false,
                    shootSubtracts: Bool = false,
                    protectQueenFirstTrick: Bool = true,
                    mustBreakHearts: Bool = true) {
            self.targetScore = targetScore
            self.jackOfDiamondsBonus = jackOfDiamondsBonus
            self.shootSubtracts = shootSubtracts
            self.protectQueenFirstTrick = protectQueenFirstTrick
            self.mustBreakHearts = mustBreakHearts
        }

        public static func from(_ configuration: GameConfiguration) -> Settings {
            Settings(targetScore: configuration.option("targetScore", default: 100),
                     jackOfDiamondsBonus: configuration.flag("jackOfDiamondsBonus"),
                     shootSubtracts: configuration.flag("shootSubtracts"),
                     protectQueenFirstTrick: configuration.flag("protectQueenFirstTrick", default: true),
                     mustBreakHearts: configuration.flag("mustBreakHearts", default: true))
        }
    }

    /// Which way the three cards go this deal. The cycle is fixed and repeats.
    public enum PassDirection: Int, Codable, Sendable, CaseIterable {
        case left = 0
        case right = 1
        case across = 2
        case hold = 3

        public var localizationKey: String { "hearts.pass.\(self)" }

        /// Seat offset the cards travel. `hold` passes nothing.
        public func offset(playerCount: Int) -> Int {
            switch self {
            case .left: return 1
            case .right: return playerCount - 1
            case .across: return playerCount / 2
            case .hold: return 0
            }
        }

        public static func forRound(_ round: Int) -> PassDirection {
            PassDirection(rawValue: (round - 1) % 4) ?? .left
        }
    }

    public enum Phase: Hashable, Codable, Sendable {
        /// Each player chooses three cards to give away.
        case passing
        /// Thirteen tricks.
        case playing
        /// The deal is scored and the next one is about to start.
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
        public var phase: Phase
        public var passDirection: PassDirection
        /// Seats that have chosen their three cards this deal.
        public var seatsThatPassed: [SeatID]
        public var trickPlays: [TrickPlay]
        public var ledSuit: Suit?
        public var trickNumber: Int
        public var heartsBroken: Bool
        /// Match totals.
        public var scores: [SeatID: Int]
        /// Penalty points taken in the current deal.
        public var roundPoints: [SeatID: Int]
        public var tricksTaken: [SeatID: Int]
        public var queensCaptured: [SeatID: Int]
        public var moonShots: [SeatID: Int]
        public var turnsTaken: Int
        /// Set when a deal has been scored, so the next one can be dealt.
        public var dealComplete: Bool

        public func hand(_ seat: SeatID) -> [Card] { board.cardList(in: .hand(seat)) }
    }

    public enum Action: Hashable, Sendable {
        /// Give away exactly three cards.
        case passCards([CardID])
        case play(CardID)
    }

    /// What a Hearts AI may know. Its own hand, everything already played, and
    /// public score — never another player's hand.
    public struct Observation: Sendable {
        public var seat: SeatID
        public var hand: [Card]
        public var phase: Phase
        public var passDirection: PassDirection
        public var trickPlays: [(seat: SeatID, card: Card)]
        public var ledSuit: Suit?
        public var trickNumber: Int
        public var heartsBroken: Bool
        /// Every card played to a completed trick this deal, with who played it.
        public var playedCards: [(seat: SeatID, card: Card)]
        /// Points already taken this deal, which is public.
        public var roundPoints: [SeatID: Int]
        public var scores: [SeatID: Int]
        public var seatOrder: [SeatID]
        public var settings: Settings
        public var legalCards: [Card]
    }

    // MARK: - Setup

    public func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State {
        let settings = Settings.from(configuration)
        let seats = configuration.seating.ids
        let direction = PassDirection.forRound(1)
        let board = Self.deal(seats: seats, generator: &generator)
        var scores: [SeatID: Int] = [:]
        for seat in seats { scores[seat] = 0 }

        var state = State(board: board,
                          activeSeat: seats.first,
                          roundNumber: 1,
                          finalResult: nil,
                          settings: settings,
                          seatOrder: seats,
                          phase: direction == .hold ? .playing : .passing,
                          passDirection: direction,
                          seatsThatPassed: [],
                          trickPlays: [],
                          ledSuit: nil,
                          trickNumber: 1,
                          heartsBroken: false,
                          scores: scores,
                          roundPoints: [:],
                          tricksTaken: [:],
                          queensCaptured: [:],
                          moonShots: [:],
                          turnsTaken: 0,
                          dealComplete: false)
        if state.phase == .playing {
            state.activeSeat = Self.holderOfTwoOfClubs(in: state) ?? seats.first
        }
        return state
    }

    static func deal(seats: [SeatID], generator: inout SeededGenerator) -> Board {
        var board = Board()
        var deck = DeckConfiguration.standard52.build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)
        board.ensureZones(seats.flatMap { [Zone.hand($0), Zone.captured($0), Zone.exchange($0)] } + [.trick, .stock])
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

    static func holderOfTwoOfClubs(in state: State) -> SeatID? {
        for seat in state.seatOrder {
            if state.hand(seat).contains(where: { $0.suit == .clubs && $0.rank == .two }) {
                return seat
            }
        }
        return nil
    }

    // MARK: - Legality

    /// The cards a seat may play right now, with every Hearts restriction applied.
    public func legalCards(in state: State, for seat: SeatID) -> [Card] {
        let hand = state.hand(seat)
        guard !hand.isEmpty else { return [] }
        let isFirstTrick = state.trickNumber == 1
        let isLeading = state.trickPlays.isEmpty

        if isLeading {
            // The 2 of clubs opens the deal, always.
            if isFirstTrick, let two = hand.first(where: { $0.suit == .clubs && $0.rank == .two }) {
                return [two]
            }
            guard state.settings.mustBreakHearts, !state.heartsBroken else { return hand }
            let nonHearts = hand.filter { $0.suit != .hearts }
            // A hand of nothing but hearts may of course lead one.
            return nonHearts.isEmpty ? hand : nonHearts
        }

        guard let ledSuit = state.ledSuit else { return hand }
        var candidates = TrickEngine.followingCards(hand: hand, ledSuit: ledSuit)

        if isFirstTrick {
            // Nothing that scores may be discarded on the opening trick — unless
            // the player's entire hand scores, which is possible but rare.
            let safe = candidates.filter { card in
                if card.suit == .hearts { return false }
                if state.settings.protectQueenFirstTrick, card.suit == .spades, card.rank == .queen { return false }
                return true
            }
            if !safe.isEmpty { candidates = safe }
        }
        return candidates
    }

    public func legalActions(in state: State, for seat: SeatID) -> [Action] {
        guard state.finalResult == nil, state.activeSeat == seat else { return [] }
        switch state.phase {
        case .passing:
            // Offering every 3-card combination of a 13-card hand would be 286
            // tokens, which is fine for a machine but useless for a UI. The
            // selection is made in the interface and submitted as one action, so
            // the engine exposes the combinations only for the AI to search.
            return Self.threeCardCombinations(of: state.hand(seat)).map { Action.passCards($0) }
        case .playing:
            return legalCards(in: state, for: seat).map { Action.play($0.id) }
        case .scoring:
            return []
        }
    }

    /// All ways to choose three cards from a hand, in a stable order.
    static func threeCardCombinations(of hand: [Card]) -> [[CardID]] {
        let ids = hand.map(\.id).sorted()
        guard ids.count >= 3 else { return ids.isEmpty ? [] : [ids] }
        var result: [[CardID]] = []
        result.reserveCapacity(286)
        for i in 0..<(ids.count - 2) {
            for j in (i + 1)..<(ids.count - 1) {
                for k in (j + 1)..<ids.count {
                    result.append([ids[i], ids[j], ids[k]])
                }
            }
        }
        return result
    }

    public func rejection(for action: Action, in state: State) -> IllegalMove? {
        guard state.finalResult == nil else { return .gameOver }
        guard let seat = state.activeSeat else { return .notYourTurn }
        switch action {
        case let .passCards(ids):
            guard state.phase == .passing else { return .noSuchAction }
            guard ids.count == 3 else {
                return IllegalMove("passExactlyThree", english: "Choose exactly three cards to pass.")
            }
            guard Set(ids).count == 3 else {
                return IllegalMove("passExactlyThree", english: "Choose three different cards.")
            }
            for id in ids where state.board.zone(of: id) != Zone.hand(seat) {
                return .cardNotInHand
            }
            return nil
        case let .play(cardID):
            guard state.phase == .playing else { return .noSuchAction }
            guard state.board.zone(of: cardID) == Zone.hand(seat) else { return .cardNotInHand }
            guard let card = state.board.card(cardID) else { return .cardNotInHand }
            let legal = legalCards(in: state, for: seat)
            guard legal.contains(where: { $0.id == cardID }) else {
                if let ledSuit = state.ledSuit,
                   TrickEngine.canFollow(hand: state.hand(seat), ledSuit: ledSuit),
                   card.suit != ledSuit {
                    return .mustFollowSuit(ledSuit)
                }
                if state.trickNumber == 1 && (card.suit == .hearts || (card.suit == .spades && card.rank == .queen)) {
                    return IllegalMove("noPointsFirstTrick",
                                       english: "Points cannot be dropped on the first trick.")
                }
                if state.trickPlays.isEmpty && card.suit == .hearts && !state.heartsBroken {
                    return IllegalMove("heartsNotBroken",
                                       english: "Hearts have not been broken, so you cannot lead one.")
                }
                return .noSuchAction
            }
            return nil
        }
    }

    // MARK: - Applying

    public func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard let seat = state.activeSeat else { return [] }
        switch action {
        case let .passCards(ids):
            return applyPass(ids, seat: seat, state: &state)
        case let .play(cardID):
            return applyPlay(cardID, seat: seat, state: &state)
        }
    }

    private func applyPass(_ ids: [CardID], seat: SeatID, state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        for id in ids {
            // The cards sit in a private holding zone until everyone has chosen,
            // so nothing is revealed early and the exchange is simultaneous.
            state.board.move(id, to: .exchange(seat), facing: .privateFaceUp([seat]))
        }
        state.seatsThatPassed.append(seat)
        events.append(.cardsMoved(cards: ids, from: .hand(seat), to: .exchange(seat)))

        if state.seatsThatPassed.count == state.seatOrder.count {
            events += deliverPasses(state: &state)
        } else {
            let next = nextSeat(after: seat, in: state)
            state.activeSeat = next
            events.append(.turnChanged(from: seat, to: next))
        }
        return events
    }

    private func deliverPasses(state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        let count = state.seatOrder.count
        let offset = state.passDirection.offset(playerCount: count)
        for (index, seat) in state.seatOrder.enumerated() {
            let recipient = state.seatOrder[(index + offset) % count]
            let cards = state.board.contents(of: .exchange(seat))
            for id in cards {
                state.board.move(id, to: .hand(recipient), facing: .hand(recipient))
            }
            if !cards.isEmpty {
                events.append(.cardsMoved(cards: cards, from: .exchange(seat), to: .hand(recipient)))
            }
        }
        for seat in state.seatOrder {
            state.board.sort(.hand(seat), by: HandSort.bySuitThenRank)
        }
        state.phase = .playing
        state.seatsThatPassed = []
        let leader = Self.holderOfTwoOfClubs(in: state) ?? state.seatOrder[0]
        state.activeSeat = leader
        events.append(.turnChanged(from: nil, to: leader))
        return events
    }

    private func applyPlay(_ cardID: CardID, seat: SeatID, state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        guard let card = state.board.card(cardID) else { return events }
        state.board.move(cardID, to: .trick, facing: .faceUp)
        state.trickPlays.append(TrickPlay(seat: seat, card: cardID))
        state.turnsTaken += 1
        events.append(.cardPlayed(card: cardID, by: seat, to: .trick))

        if state.trickPlays.count == 1 {
            state.ledSuit = card.suit
        }
        if card.suit == .hearts && !state.heartsBroken {
            state.heartsBroken = true
            events.append(.highlight(code: "hearts.broken", seat: seat, value: nil))
        }

        if state.trickPlays.count == state.seatOrder.count {
            events += completeTrick(state: &state)
        } else {
            let next = nextSeat(after: seat, in: state)
            state.activeSeat = next
            events.append(.turnChanged(from: seat, to: next))
        }
        return events
    }

    private func completeTrick(state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        guard let ledSuit = state.ledSuit else { return events }
        let winner = TrickEngine.winner(plays: state.trickPlays,
                                        cards: state.board.cards,
                                        ledSuit: ledSuit,
                                        trump: nil) ?? state.trickPlays[0].seat

        let cards = state.trickPlays.map(\.card)
        for id in cards {
            // Captured tricks are public — everyone at the table watched them.
            state.board.move(id, to: .captured(winner), facing: .faceUp)
        }
        state.tricksTaken[winner, default: 0] += 1

        var points = 0
        for id in cards {
            guard let card = state.board.card(id) else { continue }
            if card.suit == .hearts { points += 1 }
            if card.suit == .spades && card.rank == .queen {
                points += 13
                state.queensCaptured[winner, default: 0] += 1
                events.append(.highlight(code: "hearts.queen", seat: winner, value: nil))
            }
        }
        state.roundPoints[winner, default: 0] += points

        events.append(.trickCompleted(winner: winner, cards: cards))
        state.trickPlays = []
        state.ledSuit = nil
        state.trickNumber += 1

        if state.board.isEmpty(Zone.hand(winner)) && state.seatOrder.allSatisfy({ state.board.isEmpty(Zone.hand($0)) }) {
            state.phase = .scoring
            state.activeSeat = nil
            state.dealComplete = true
        } else {
            state.activeSeat = winner
            events.append(.turnChanged(from: nil, to: winner))
        }
        return events
    }

    private func nextSeat(after seat: SeatID, in state: State) -> SeatID {
        guard let index = state.seatOrder.firstIndex(of: seat) else { return state.seatOrder[0] }
        return state.seatOrder[(index + 1) % state.seatOrder.count]
    }

    // MARK: - Scoring and the next deal

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

        // The Jack of Diamonds bonus is credited to whoever captured it.
        var adjusted = state.roundPoints
        if state.settings.jackOfDiamondsBonus {
            for seat in state.seatOrder {
                let hasJack = state.board.cardList(in: .captured(seat))
                    .contains { $0.suit == .diamonds && $0.rank == .jack }
                if hasJack {
                    adjusted[seat, default: 0] -= 10
                    events.append(.highlight(code: "hearts.jackOfDiamonds", seat: seat, value: nil))
                }
            }
        }

        // Shooting the moon: all 26 penalty points in one hand.
        let shooter = state.seatOrder.first { (state.roundPoints[$0] ?? 0) == 26 }
        if let shooter {
            state.moonShots[shooter, default: 0] += 1
            events.append(.highlight(code: "hearts.shootTheMoon", seat: shooter, value: nil))
            if state.settings.shootSubtracts {
                adjusted = [shooter: -26]
                for seat in state.seatOrder where seat != shooter { adjusted[seat] = 0 }
            } else {
                for seat in state.seatOrder {
                    adjusted[seat] = seat == shooter ? 0 : 26
                }
            }
            if state.settings.jackOfDiamondsBonus {
                for seat in state.seatOrder {
                    let hasJack = state.board.cardList(in: .captured(seat))
                        .contains { $0.suit == .diamonds && $0.rank == .jack }
                    if hasJack { adjusted[seat, default: 0] -= 10 }
                }
            }
        }

        for seat in state.seatOrder {
            let delta = adjusted[seat] ?? 0
            state.scores[seat, default: 0] += delta
            events.append(.scoreChanged(seat: seat, delta: delta, total: state.scores[seat] ?? 0))
        }
        events.append(.roundEnded(scores: state.scores))

        let reached = state.seatOrder.contains { (state.scores[$0] ?? 0) >= state.settings.targetScore }
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
        state.passDirection = PassDirection.forRound(state.roundNumber)
        state.phase = state.passDirection == .hold ? .playing : .passing
        state.seatsThatPassed = []
        state.trickPlays = []
        state.ledSuit = nil
        state.trickNumber = 1
        state.heartsBroken = false
        state.roundPoints = [:]
        if state.phase == .passing {
            // Passing starts with the player left of the previous dealer.
            let index = (state.roundNumber - 1) % state.seatOrder.count
            state.activeSeat = state.seatOrder[index]
        } else {
            state.activeSeat = Self.holderOfTwoOfClubs(in: state) ?? state.seatOrder[0]
        }
        return [.roundStarted(number: state.roundNumber),
                .handsDealt(counts: Dictionary(uniqueKeysWithValues: state.seatOrder.map { ($0, 13) }))]
    }

    private func buildResult(state: State) -> GameResult {
        // Lowest score wins.
        let ranked = state.seatOrder.sorted { (state.scores[$0] ?? 0) < (state.scores[$1] ?? 0) }
        let lowest = state.scores.values.min() ?? 0
        let winners = state.seatOrder.filter { (state.scores[$0] ?? 0) == lowest }
        var metrics: [String: Int] = [:]
        let leader = winners.first ?? ranked[0]
        metrics[HeartsStatistics.queensCaptured] = state.queensCaptured[leader] ?? 0
        metrics[HeartsStatistics.moonShots] = state.moonShots[leader] ?? 0
        metrics[HeartsStatistics.tricksTaken] = state.tricksTaken[leader] ?? 0
        metrics[HeartsStatistics.finalScore] = state.scores[leader] ?? 0
        var highlights: [String] = []
        if (state.moonShots[leader] ?? 0) > 0 { highlights.append("hearts.shootTheMoon") }
        if (state.scores[leader] ?? 0) == 0 { highlights.append("hearts.spotless") }
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
        case let .passCards(ids):
            let sorted = ids.sorted()
            return ActionToken(id: TokenID.make(seat, "pass", cards: sorted),
                               kind: .selectCards,
                               seat: seat,
                               cards: sorted,
                               destination: .exchange(seat),
                               source: .hand(seat),
                               labelKey: "action.passThree",
                               labelArguments: [state.passDirection.localizationKey])
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
        guard parts.count >= 2 else { return nil }
        switch parts[1] {
        case "pass":
            let ids = parts.dropFirst(2).compactMap { Int($0) }.map { CardID(rawValue: $0) }
            guard ids.count == 3 else { return nil }
            return .passCards(ids)
        case "play":
            guard parts.count >= 3, let raw = Int(parts[2]) else { return nil }
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
            for card in state.board.cardList(in: .captured(other)) {
                played.append((other, card))
            }
        }
        return Observation(seat: seat,
                           hand: state.hand(seat),
                           phase: state.phase,
                           passDirection: state.passDirection,
                           trickPlays: plays,
                           ledSuit: state.ledSuit,
                           trickNumber: state.trickNumber,
                           heartsBroken: state.heartsBroken,
                           playedCards: played,
                           roundPoints: state.roundPoints,
                           scores: state.scores,
                           seatOrder: state.seatOrder,
                           settings: state.settings,
                           legalCards: legalCards(in: state, for: seat))
    }

    // MARK: - Presentation

    public func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation {
        var slots: [TableSlot] = []
        if let own = TableBuilder.ownHandSlot(viewer: viewer, seating: seating) {
            slots.append(own)
        }
        slots += TableBuilder.opponentSlots(seating: seating, viewer: viewer)
        slots.append(TableSlot(zone: .trick,
                               style: .row(overlap: 0.0),
                               anchor: .centre(order: 0),
                               titleKey: "zone.trick",
                               prominence: 1.4))

        var callouts: [TableCallout] = []
        switch state.phase {
        case .passing:
            callouts.append(TableCallout(id: "pass",
                                         labelKey: "callout.passDirection",
                                         arguments: [state.passDirection.localizationKey],
                                         emphasis: .primary))
        case .playing:
            if let led = state.ledSuit {
                callouts.append(TableCallout(id: "led",
                                             labelKey: "callout.suitLed",
                                             arguments: [led.localizationKey],
                                             emphasis: .primary,
                                             suit: led))
            }
            callouts.append(TableCallout(id: "hearts",
                                         labelKey: state.heartsBroken ? "callout.heartsBroken" : "callout.heartsIntact",
                                         emphasis: state.heartsBroken ? .alert : .secondary,
                                         suit: .hearts))
        case .scoring:
            break
        }
        callouts.append(TableCallout(id: "target",
                                     labelKey: "callout.playingTo",
                                     arguments: [String(state.settings.targetScore)]))

        // The passing phase would otherwise offer 286 tokens; the interface
        // builds the selection itself and submits one, so only the play phase
        // publishes per-card actions.
        var actions: [ActionToken] = []
        var playable: Set<CardID> = []
        if let viewer, state.activeSeat == viewer {
            switch state.phase {
            case .playing:
                actions = legalActions(in: state, for: viewer).map { token(for: $0, in: state) }
                playable = Set(actions.flatMap(\.cards))
            case .passing:
                playable = Set(state.hand(viewer).map(\.id))
            case .scoring:
                break
            }
        }

        var states: [SeatID: String] = [:]
        if state.phase == .passing {
            for seat in state.seatsThatPassed { states[seat] = "state.ready" }
        }

        return TablePresentation(gameID: Self.gameID,
                                 viewer: viewer,
                                 board: state.board.redacted(for: viewer),
                                 slots: slots,
                                 seats: TableBuilder.seatStatuses(seating: seating,
                                                                  board: state.board,
                                                                  activeSeat: state.activeSeat,
                                                                  scores: state.scores,
                                                                  scoreLabelKey: "label.points",
                                                                  states: states),
                                 callouts: callouts,
                                 actions: actions,
                                 playableCards: playable,
                                 activeSeat: state.activeSeat,
                                 roundNumber: state.roundNumber,
                                 phaseKey: state.phase == .passing ? "phase.passing" : "phase.trick",
                                 phaseArguments: [String(state.trickNumber)],
                                 result: state.finalResult)
    }

    // MARK: - Hints

    public func hint(for state: State, seat: SeatID) -> Hint? {
        guard state.activeSeat == seat else { return nil }
        if state.phase == .passing {
            return Hint(messageKey: "hint.hearts.passing",
                        arguments: [state.passDirection.localizationKey],
                        english: "Pass your high spades if you hold fewer than three, and dump a whole short suit so you can discard into it later.")
        }
        let legal = legalCards(in: state, for: seat)
        guard !legal.isEmpty else { return nil }
        if let ledSuit = state.ledSuit {
            if TrickEngine.canFollow(hand: state.hand(seat), ledSuit: ledSuit) {
                return Hint(messageKey: "hint.hearts.follow",
                            arguments: [ledSuit.localizationKey],
                            english: "You hold \(ledSuit.englishName), so you must follow. Play under the highest card already down and you cannot take the trick.",
                            cards: legal.map(\.id))
            }
            return Hint(messageKey: "hint.hearts.discard",
                        english: "You are void, so nothing you play can win this trick. That makes it the moment to get rid of the Queen of Spades or a high heart.",
                        cards: legal.map(\.id))
        }
        if !state.heartsBroken {
            return Hint(messageKey: "hint.hearts.lead",
                        english: "Hearts are not broken, so you lead a black or diamond card. Leading low keeps you off the trick.",
                        cards: legal.map(\.id))
        }
        return Hint(messageKey: "hint.hearts.leadOpen",
                    english: "Leading a low card keeps the trick away from you. Whoever wins it takes whatever is in it.",
                    cards: legal.map(\.id))
    }
}

public enum HeartsStatistics {
    public static let queensCaptured = "hearts.queensCaptured"
    public static let moonShots = "hearts.moonShots"
    public static let tricksTaken = "hearts.tricksTaken"
    public static let finalScore = "hearts.finalScore"
}

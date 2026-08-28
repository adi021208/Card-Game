import Foundation
import DeckCore

/// Euchre.
///
/// Twenty-four cards, five tricks, and the two jacks that decide everything: the
/// jack of trumps and the jack of the same colour outrank every other card, and
/// the second one changes suit when trump is named. Getting the bowers right is
/// most of getting Euchre right.
public struct EuchreRules: GameRules {
    public static let gameID = GameID.euchre
    public static let rulesVersion = 1

    public init() {}

    public struct Settings: Hashable, Codable, Sendable {
        public var targetScore: Int
        /// A player may go alone, sitting their partner out for a bigger prize.
        public var allowGoingAlone: Bool
        /// Taking all five when you named trump. Two normally, four alone.
        public var marchPoints: Int
        public var aloneMarchPoints: Int
        /// Points to the defenders when the makers fail.
        public var euchrePoints: Int

        public init(targetScore: Int = 10,
                    allowGoingAlone: Bool = true,
                    marchPoints: Int = 2,
                    aloneMarchPoints: Int = 4,
                    euchrePoints: Int = 2) {
            self.targetScore = targetScore
            self.allowGoingAlone = allowGoingAlone
            self.marchPoints = marchPoints
            self.aloneMarchPoints = aloneMarchPoints
            self.euchrePoints = euchrePoints
        }

        public static func from(_ configuration: GameConfiguration) -> Settings {
            Settings(targetScore: configuration.option("targetScore", default: 10),
                     allowGoingAlone: configuration.flag("allowGoingAlone", default: true),
                     marchPoints: configuration.option("marchPoints", default: 2),
                     aloneMarchPoints: configuration.option("aloneMarchPoints", default: 4),
                     euchrePoints: configuration.option("euchrePoints", default: 2))
        }
    }

    public enum Phase: Hashable, Codable, Sendable {
        /// Order the dealer to pick up the turned card, or pass.
        case bidRoundOne
        /// Name any other suit, or pass.
        case bidRoundTwo
        /// The dealer discards after picking up.
        case dealerDiscard
        case playing
        case scoring
    }

    public struct State: GameStateProtocol {
        public var board: Board
        public var activeSeat: SeatID?
        public var roundNumber: Int
        public var finalResult: GameResult?

        public var settings: Settings
        public var seatOrder: [SeatID]
        public var teams: [SeatID: Int]
        public var phase: Phase
        public var dealerSeat: SeatID
        /// The card turned up for the first round of bidding.
        public var upcard: CardID?
        public var trump: Suit?
        /// Who named trump.
        public var makerSeat: SeatID?
        /// A partner sitting out this hand.
        public var sittingOut: SeatID?
        public var passCount: Int
        public var trickPlays: [TrickPlay]
        public var ledSuit: Suit?
        public var trickNumber: Int
        public var tricksWon: [SeatID: Int]
        public var teamScores: [Int: Int]
        public var marches: [SeatID: Int]
        public var euchres: [SeatID: Int]
        public var lonerWins: [SeatID: Int]
        public var turnsTaken: Int
        public var dealComplete: Bool

        public func hand(_ seat: SeatID) -> [Card] { board.cardList(in: .hand(seat)) }
        public func team(_ seat: SeatID) -> Int { teams[seat] ?? 0 }
        /// Seats actually playing this hand.
        public var activePlayers: [SeatID] { seatOrder.filter { $0 != sittingOut } }
    }

    public enum Action: Hashable, Sendable {
        /// Tell the dealer to pick the turned card up. `alone` sits your partner out.
        case orderUp(alone: Bool)
        /// Name a suit in the second round.
        case callTrump(Suit, alone: Bool)
        case passBid
        case discard(CardID)
        case play(CardID)
    }

    public struct Observation: Sendable {
        public var seat: SeatID
        public var hand: [Card]
        public var phase: Phase
        public var upcard: Card?
        public var trump: Suit?
        public var makerSeat: SeatID?
        public var partner: SeatID?
        public var dealerSeat: SeatID
        public var trickPlays: [(seat: SeatID, card: Card)]
        public var ledSuit: Suit?
        public var trickNumber: Int
        public var tricksWon: [SeatID: Int]
        public var teamScores: [Int: Int]
        public var playedCards: [Card]
        public var settings: Settings
        public var legalCards: [Card]
    }

    // MARK: - Trump mechanics

    /// The suit a card counts as. The left bower joins the trump suit.
    public static func effectiveSuit(_ card: Card, trump: Suit?) -> Suit? {
        guard let suit = card.suit else { return nil }
        guard let trump, card.rank == .jack, suit == sameColour(as: trump) else { return suit }
        return trump
    }

    /// The other suit of the same colour.
    public static func sameColour(as suit: Suit) -> Suit {
        switch suit {
        case .hearts: return .diamonds
        case .diamonds: return .hearts
        case .spades: return .clubs
        case .clubs: return .spades
        }
    }

    /// Strength within the trump suit. The right bower is highest, the left
    /// bower next, then ace down to nine.
    public static func trumpValue(_ card: Card, trump: Suit) -> Int {
        guard let suit = card.suit, let rank = card.rank else { return 0 }
        if rank == .jack && suit == trump { return 100 }
        if rank == .jack && suit == sameColour(as: trump) { return 99 }
        guard suit == trump else { return 0 }
        return rank.rawValue
    }

    /// Rank value used when comparing cards of the led suit.
    public static func plainValue(_ card: Card) -> Int { card.rank?.rawValue ?? 0 }

    // MARK: - Setup

    public func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State {
        let settings = Settings.from(configuration)
        let seats = configuration.seating.ids
        var teams: [SeatID: Int] = [:]
        for (index, seat) in seats.enumerated() {
            teams[seat] = configuration.seating[seat]?.team ?? (index % 2)
        }
        var state = State(board: Board(),
                          activeSeat: nil,
                          roundNumber: 1,
                          finalResult: nil,
                          settings: settings,
                          seatOrder: seats,
                          teams: teams,
                          phase: .bidRoundOne,
                          dealerSeat: seats[0],
                          upcard: nil,
                          trump: nil,
                          makerSeat: nil,
                          sittingOut: nil,
                          passCount: 0,
                          trickPlays: [],
                          ledSuit: nil,
                          trickNumber: 1,
                          tricksWon: [:],
                          teamScores: [0: 0, 1: 0],
                          marches: [:],
                          euchres: [:],
                          lonerWins: [:],
                          turnsTaken: 0,
                          dealComplete: false)
        dealHand(state: &state, generator: &generator)
        return state
    }

    private func dealHand(state: inout State, generator: inout SeededGenerator) {
        var board = Board()
        var deck = DeckConfiguration.euchre24.build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)
        board.ensureZones(state.seatOrder.flatMap { [Zone.hand($0), Zone.captured($0)] }
                          + [.stock, .trick, .discard, .reserve])
        // Five each, dealt in the traditional 3-2 / 2-3 pattern.
        let order = rotate(state.seatOrder, startingAfter: state.dealerSeat)
        for (index, seat) in order.enumerated() {
            let first = index % 2 == 0 ? 3 : 2
            for _ in 0..<first { board.draw(from: .stock, to: .hand(seat), facing: .hand(seat)) }
        }
        for (index, seat) in order.enumerated() {
            let second = index % 2 == 0 ? 2 : 3
            for _ in 0..<second { board.draw(from: .stock, to: .hand(seat), facing: .hand(seat)) }
        }
        for seat in state.seatOrder { board.sort(.hand(seat), by: HandSort.bySuitThenRank) }
        let upcard = board.draw(from: .stock, to: .reserve, facing: .faceUp)

        state.board = board
        state.upcard = upcard?.id
        state.trump = nil
        state.makerSeat = nil
        state.sittingOut = nil
        state.passCount = 0
        state.phase = .bidRoundOne
        state.trickPlays = []
        state.ledSuit = nil
        state.trickNumber = 1
        state.tricksWon = [:]
        state.activeSeat = nextSeat(after: state.dealerSeat, in: state.seatOrder)
    }

    private func rotate(_ seats: [SeatID], startingAfter seat: SeatID) -> [SeatID] {
        guard let index = seats.firstIndex(of: seat) else { return seats }
        return (1...seats.count).map { seats[(index + $0) % seats.count] }
    }

    private func nextSeat(after seat: SeatID, in seats: [SeatID]) -> SeatID {
        guard let index = seats.firstIndex(of: seat) else { return seats[0] }
        return seats[(index + 1) % seats.count]
    }

    private func nextPlayingSeat(after seat: SeatID, in state: State) -> SeatID {
        var candidate = nextSeat(after: seat, in: state.seatOrder)
        if candidate == state.sittingOut {
            candidate = nextSeat(after: candidate, in: state.seatOrder)
        }
        return candidate
    }

    private func partner(of seat: SeatID, in state: State) -> SeatID? {
        state.seatOrder.first { $0 != seat && state.team($0) == state.team(seat) }
    }

    // MARK: - Rules

    public func legalCards(in state: State, for seat: SeatID) -> [Card] {
        let hand = state.hand(seat)
        guard let ledSuit = state.ledSuit, !state.trickPlays.isEmpty else { return hand }
        // Following suit uses the *effective* suit, so the left bower follows
        // trump and not its printed suit — the rule people forget.
        let following = hand.filter { Self.effectiveSuit($0, trump: state.trump) == ledSuit }
        return following.isEmpty ? hand : following
    }

    public func legalActions(in state: State, for seat: SeatID) -> [Action] {
        guard state.finalResult == nil, state.activeSeat == seat else { return [] }
        switch state.phase {
        case .bidRoundOne:
            var actions: [Action] = [.orderUp(alone: false), .passBid]
            if state.settings.allowGoingAlone { actions.insert(.orderUp(alone: true), at: 1) }
            return actions
        case .bidRoundTwo:
            guard let upcardID = state.upcard, let upcard = state.board.card(upcardID),
                  let turnedSuit = upcard.suit else { return [.passBid] }
            var actions: [Action] = []
            for suit in Suit.allCases where suit != turnedSuit {
                actions.append(.callTrump(suit, alone: false))
                if state.settings.allowGoingAlone { actions.append(.callTrump(suit, alone: true)) }
            }
            // The dealer is stuck and has to name something.
            if seat != state.dealerSeat { actions.append(.passBid) }
            return actions
        case .dealerDiscard:
            return state.hand(seat).map { Action.discard($0.id) }
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
        case .orderUp:
            guard state.phase == .bidRoundOne else { return .noSuchAction }
            return nil
        case let .callTrump(suit, _):
            guard state.phase == .bidRoundTwo else { return .noSuchAction }
            guard let upcardID = state.upcard, let upcard = state.board.card(upcardID) else { return nil }
            guard suit != upcard.suit else {
                return IllegalMove("cannotNameTurnedSuit",
                                   arguments: [suit.localizationKey],
                                   english: "That is the suit that was turned down — name a different one.")
            }
            return nil
        case .passBid:
            guard state.phase == .bidRoundOne || state.phase == .bidRoundTwo else { return .noSuchAction }
            if state.phase == .bidRoundTwo && seat == state.dealerSeat {
                return IllegalMove("dealerIsStuck",
                                   english: "You are stuck — somebody has to name trump, and it is you.")
            }
            return nil
        case let .discard(cardID):
            guard state.phase == .dealerDiscard else { return .noSuchAction }
            guard state.board.zone(of: cardID) == Zone.hand(seat) else { return .cardNotInHand }
            return nil
        case let .play(cardID):
            guard state.phase == .playing else { return .noSuchAction }
            guard state.board.zone(of: cardID) == Zone.hand(seat) else { return .cardNotInHand }
            guard legalCards(in: state, for: seat).contains(where: { $0.id == cardID }) else {
                if let led = state.ledSuit { return .mustFollowSuit(led) }
                return .noSuchAction
            }
            return nil
        }
    }

    // MARK: - Applying

    public func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard let seat = state.activeSeat else { return [] }
        var events: [GameEvent] = []
        state.turnsTaken += 1

        switch action {
        case let .orderUp(alone):
            guard let upcardID = state.upcard, let upcard = state.board.card(upcardID) else { break }
            state.trump = upcard.suit
            state.makerSeat = seat
            if alone { state.sittingOut = partner(of: seat, in: state) }
            // The dealer takes the card into their hand and throws one away.
            state.board.move(upcardID, to: .hand(state.dealerSeat), facing: .hand(state.dealerSeat))
            state.board.sort(.hand(state.dealerSeat), by: HandSort.bySuitThenRank)
            state.phase = .dealerDiscard
            state.activeSeat = state.dealerSeat
            events.append(.suitChosen(upcard.suit ?? .spades, by: seat))
            if alone { events.append(.highlight(code: "euchre.alone", seat: seat, value: nil)) }

        case let .callTrump(suit, alone):
            state.trump = suit
            state.makerSeat = seat
            if alone { state.sittingOut = partner(of: seat, in: state) }
            state.phase = .playing
            let leader = nextPlayingSeat(after: state.dealerSeat, in: state)
            state.activeSeat = leader
            events.append(.suitChosen(suit, by: seat))
            if alone { events.append(.highlight(code: "euchre.alone", seat: seat, value: nil)) }
            events.append(.turnChanged(from: seat, to: leader))

        case .passBid:
            state.passCount += 1
            if state.phase == .bidRoundOne && state.passCount >= state.seatOrder.count {
                state.phase = .bidRoundTwo
                state.passCount = 0
                // The turned card is out of play once it has been turned down.
                if let upcardID = state.upcard {
                    state.board.flip(upcardID, faceUp: false)
                }
                let next = nextSeat(after: state.dealerSeat, in: state.seatOrder)
                state.activeSeat = next
                events.append(.turnChanged(from: seat, to: next))
            } else {
                let next = nextSeat(after: seat, in: state.seatOrder)
                state.activeSeat = next
                events.append(.turnChanged(from: seat, to: next))
            }

        case let .discard(cardID):
            state.board.move(cardID, to: .discard, facing: .faceDown)
            state.phase = .playing
            let leader = nextPlayingSeat(after: state.dealerSeat, in: state)
            state.activeSeat = leader
            events.append(.cardDiscarded(card: cardID, by: seat))
            events.append(.turnChanged(from: seat, to: leader))

        case let .play(cardID):
            guard let card = state.board.card(cardID) else { break }
            state.board.move(cardID, to: .trick, facing: .faceUp)
            state.trickPlays.append(TrickPlay(seat: seat, card: cardID))
            events.append(.cardPlayed(card: cardID, by: seat, to: .trick))
            if state.trickPlays.count == 1 {
                state.ledSuit = Self.effectiveSuit(card, trump: state.trump)
            }
            if state.trickPlays.count == state.activePlayers.count {
                events += completeTrick(state: &state)
            } else {
                let next = nextPlayingSeat(after: seat, in: state)
                state.activeSeat = next
                events.append(.turnChanged(from: seat, to: next))
            }
        }
        return events
    }

    private func completeTrick(state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        guard let ledSuit = state.ledSuit, let trump = state.trump else { return events }
        // `TrickEngine` compares by printed suit, which is wrong here: the left
        // bower has to be treated as trump before anything is compared. Euchre
        // therefore resolves its own tricks.
        let resolvedWinner = resolveWinner(state: state, ledSuit: ledSuit, trump: trump)
            ?? state.trickPlays[0].seat

        let cards = state.trickPlays.map(\.card)
        for id in cards { state.board.move(id, to: .captured(resolvedWinner), facing: .faceUp) }
        state.tricksWon[resolvedWinner, default: 0] += 1
        events.append(.trickCompleted(winner: resolvedWinner, cards: cards))
        state.trickPlays = []
        state.ledSuit = nil
        state.trickNumber += 1

        if state.activePlayers.allSatisfy({ state.board.isEmpty(Zone.hand($0)) }) {
            state.phase = .scoring
            state.activeSeat = nil
            state.dealComplete = true
        } else {
            state.activeSeat = resolvedWinner
            events.append(.turnChanged(from: nil, to: resolvedWinner))
        }
        return events
    }

    /// Trick resolution with the bowers and the effective-suit rule applied.
    private func resolveWinner(state: State, ledSuit: Suit, trump: Suit) -> SeatID? {
        var best: (seat: SeatID, value: Int, isTrump: Bool)?
        for play in state.trickPlays {
            guard let card = state.board.card(play.card) else { continue }
            let effective = Self.effectiveSuit(card, trump: trump)
            let isTrump = effective == trump
            guard isTrump || effective == ledSuit else { continue }
            let value = isTrump ? Self.trumpValue(card, trump: trump) : Self.plainValue(card)
            if let current = best {
                if isTrump && !current.isTrump {
                    best = (play.seat, value, true)
                } else if isTrump == current.isTrump && value > current.value {
                    best = (play.seat, value, isTrump)
                }
            } else {
                best = (play.seat, value, isTrump)
            }
        }
        return best?.seat
    }

    // MARK: - Scoring

    public func advanceAutomatically(_ state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard state.finalResult == nil, state.dealComplete else { return [] }
        state.dealComplete = false
        var events = scoreDeal(state: &state)
        if state.finalResult != nil { return events }
        state.roundNumber += 1
        state.dealerSeat = nextSeat(after: state.dealerSeat, in: state.seatOrder)
        dealHand(state: &state, generator: &generator)
        events.append(.roundStarted(number: state.roundNumber))
        return events
    }

    private func scoreDeal(state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        guard let maker = state.makerSeat else { return events }
        let makerTeam = state.team(maker)
        let makerTricks = state.seatOrder
            .filter { state.team($0) == makerTeam }
            .reduce(0) { $0 + (state.tricksWon[$1] ?? 0) }
        let alone = state.sittingOut != nil

        var points = 0
        var scoringTeam = makerTeam
        if makerTricks >= 5 {
            points = alone ? state.settings.aloneMarchPoints : state.settings.marchPoints
            state.marches[maker, default: 0] += 1
            if alone { state.lonerWins[maker, default: 0] += 1 }
            events.append(.highlight(code: alone ? "euchre.loneMarch" : "euchre.march", seat: maker, value: nil))
        } else if makerTricks >= 3 {
            points = 1
        } else {
            // Euchred: the defenders take the points instead.
            scoringTeam = 1 - makerTeam
            points = state.settings.euchrePoints
            let defender = state.seatOrder.first { state.team($0) != makerTeam }
            state.euchres[defender ?? maker, default: 0] += 1
            events.append(.highlight(code: "euchre.euchred", seat: defender, value: nil))
        }

        state.teamScores[scoringTeam, default: 0] += points
        for seat in state.seatOrder where state.team(seat) == scoringTeam {
            events.append(.scoreChanged(seat: seat, delta: points, total: state.teamScores[scoringTeam] ?? 0))
        }
        var seatScores: [SeatID: Int] = [:]
        for seat in state.seatOrder { seatScores[seat] = state.teamScores[state.team(seat)] ?? 0 }
        events.append(.roundEnded(scores: seatScores))

        if (state.teamScores[0] ?? 0) >= state.settings.targetScore
            || (state.teamScores[1] ?? 0) >= state.settings.targetScore {
            let result = buildResult(state: state)
            state.finalResult = result
            state.activeSeat = nil
            events.append(.gameEnded(result))
        }
        return events
    }

    private func buildResult(state: State) -> GameResult {
        let scoreZero = state.teamScores[0] ?? 0
        let scoreOne = state.teamScores[1] ?? 0
        let winningTeam = scoreZero >= scoreOne ? 0 : 1
        let winners = state.seatOrder.filter { state.team($0) == winningTeam }
        var seatScores: [SeatID: Int] = [:]
        for seat in state.seatOrder { seatScores[seat] = state.teamScores[state.team(seat)] ?? 0 }
        let ranked = state.seatOrder.sorted { (seatScores[$0] ?? 0) > (seatScores[$1] ?? 0) }
        let leader = winners.first ?? ranked[0]
        var metrics: [String: Int] = [:]
        metrics[EuchreStatistics.marches] = state.marches[leader] ?? 0
        metrics[EuchreStatistics.euchres] = state.euchres[leader] ?? 0
        metrics[EuchreStatistics.lonerWins] = state.lonerWins[leader] ?? 0
        metrics[EuchreStatistics.finalScore] = seatScores[leader] ?? 0
        var highlights: [String] = []
        if (state.lonerWins[leader] ?? 0) > 0 { highlights.append("euchre.loneMarch") }
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
        case let .orderUp(alone):
            return ActionToken(id: TokenID.make(seat, "order", [alone ? "1" : "0"]),
                               kind: .bid, seat: seat,
                               labelKey: alone ? "action.orderUpAlone" : "action.orderUp")
        case let .callTrump(suit, alone):
            return ActionToken(id: TokenID.make(seat, "call", [suit.token, alone ? "1" : "0"]),
                               kind: .bid, seat: seat,
                               labelKey: alone ? "action.callTrumpAlone" : "action.callTrump",
                               labelArguments: [suit.localizationKey])
        case .passBid:
            return ActionToken(id: TokenID.make(seat, "passbid"), kind: .passTurn, seat: seat,
                               labelKey: "action.pass")
        case let .discard(cardID):
            return ActionToken(id: TokenID.make(seat, "discard", card: cardID),
                               kind: .discardCard, seat: seat, cards: [cardID],
                               destination: .discard, source: .hand(seat),
                               labelKey: "action.discard")
        case let .play(cardID):
            return ActionToken(id: TokenID.make(seat, "play", card: cardID),
                               kind: .playCard, seat: seat, cards: [cardID],
                               destination: .trick, source: .hand(seat),
                               labelKey: "action.play")
        }
    }

    public func decodeAction(id: String, in state: State) -> Action? {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        switch parts[1] {
        case "passbid": return .passBid
        case "order":
            return .orderUp(alone: parts.count >= 3 && parts[2] == "1")
        case "call":
            guard parts.count >= 4, let suit = Suit(token: parts[2]) else { return nil }
            return .callTrump(suit, alone: parts[3] == "1")
        case "discard":
            guard parts.count >= 3, let raw = Int(parts[2]) else { return nil }
            return .discard(CardID(rawValue: raw))
        case "play":
            guard parts.count >= 3, let raw = Int(parts[2]) else { return nil }
            return .play(CardID(rawValue: raw))
        default: return nil
        }
    }

    // MARK: - Observation

    public func observation(of state: State, for seat: SeatID) -> Observation {
        let plays = state.trickPlays.compactMap { play -> (seat: SeatID, card: Card)? in
            guard let card = state.board.card(play.card) else { return nil }
            return (play.seat, card)
        }
        var played: [Card] = []
        for other in state.seatOrder { played.append(contentsOf: state.board.cardList(in: .captured(other))) }
        return Observation(seat: seat,
                           hand: state.hand(seat),
                           phase: state.phase,
                           upcard: state.upcard.flatMap { state.board.card($0) },
                           trump: state.trump,
                           makerSeat: state.makerSeat,
                           partner: partner(of: seat, in: state),
                           dealerSeat: state.dealerSeat,
                           trickPlays: plays,
                           ledSuit: state.ledSuit,
                           trickNumber: state.trickNumber,
                           tricksWon: state.tricksWon,
                           teamScores: state.teamScores,
                           playedCards: played,
                           settings: state.settings,
                           legalCards: legalCards(in: state, for: seat))
    }

    // MARK: - Presentation

    public func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation {
        var slots: [TableSlot] = []
        if let own = TableBuilder.ownHandSlot(viewer: viewer, seating: seating) { slots.append(own) }
        slots += TableBuilder.opponentSlots(seating: seating, viewer: viewer)
        slots.append(TableSlot(zone: .trick, style: .row(overlap: 0.0), anchor: .centre(order: 0),
                               titleKey: "zone.trick", prominence: 1.4))
        if state.phase == .bidRoundOne {
            slots.append(TableSlot(zone: .reserve, style: .single, anchor: .centre(order: 1),
                                   titleKey: "zone.upcard", prominence: 1.2))
        }

        var callouts: [TableCallout] = []
        if let trump = state.trump {
            callouts.append(TableCallout(id: "trump", labelKey: "callout.trump",
                                         arguments: [trump.localizationKey],
                                         emphasis: .primary, suit: trump))
        } else {
            callouts.append(TableCallout(id: "bidding", labelKey: "callout.namingTrump", emphasis: .primary))
        }
        let teamZero = state.seatOrder.filter { state.team($0) == 0 }.reduce(0) { $0 + (state.tricksWon[$1] ?? 0) }
        let teamOne = state.seatOrder.filter { state.team($0) == 1 }.reduce(0) { $0 + (state.tricksWon[$1] ?? 0) }
        callouts.append(TableCallout(id: "tricks", labelKey: "callout.tricksSplit",
                                     arguments: [String(teamZero), String(teamOne)]))
        callouts.append(TableCallout(id: "score", labelKey: "callout.gameScore",
                                     arguments: [String(state.teamScores[0] ?? 0), String(state.teamScores[1] ?? 0)]))

        var states: [SeatID: String] = [:]
        if let maker = state.makerSeat { states[maker] = "state.maker" }
        if let sitting = state.sittingOut { states[sitting] = "state.sittingOut" }

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
                                                                  states: states),
                                 callouts: callouts,
                                 actions: actions,
                                 playableCards: Set(actions.flatMap(\.cards)),
                                 activeSeat: state.activeSeat,
                                 roundNumber: state.roundNumber,
                                 phaseKey: state.trump == nil ? "phase.bidding" : "phase.trick",
                                 phaseArguments: [String(state.trickNumber)],
                                 result: state.finalResult)
    }

    public func hint(for state: State, seat: SeatID) -> Hint? {
        guard state.activeSeat == seat else { return nil }
        switch state.phase {
        case .bidRoundOne, .bidRoundTwo:
            guard let upcardID = state.upcard, let upcard = state.board.card(upcardID),
                  let candidate = upcard.suit else { return nil }
            let strength = state.hand(seat).filter { Self.trumpValue($0, trump: candidate) > 0 }.count
            return Hint(messageKey: "hint.euchre.bidding",
                        arguments: [String(strength), candidate.localizationKey],
                        english: "Count the bowers, not the suits: with the jack of \(candidate.englishName.lowercased()) and the other jack of the same colour you already hold the two best cards. You have \(strength) cards that would be trump.")
        case .dealerDiscard:
            return Hint(messageKey: "hint.euchre.discard",
                        english: "Throw a singleton in a side suit if you can — being void lets you trump in later.")
        case .playing:
            guard let trump = state.trump else { return nil }
            let legal = legalCards(in: state, for: seat)
            let trumps = legal.filter { Self.trumpValue($0, trump: trump) > 0 }
            if !trumps.isEmpty && state.ledSuit != trump {
                return Hint(messageKey: "hint.euchre.trumping",
                            english: "Remember the left bower counts as trump, not as its printed suit. Spending a bower to take a trick nobody was contesting is how hands get euchred.",
                            cards: trumps.map(\.id))
            }
            return Hint(messageKey: "hint.euchre.follow",
                        english: "Three tricks out of five is all the makers need. Work out which side is short and play to that.",
                        cards: legal.map(\.id))
        case .scoring:
            return nil
        }
    }
}

public enum EuchreStatistics {
    public static let marches = "euchre.marches"
    public static let euchres = "euchre.euchres"
    public static let lonerWins = "euchre.lonerWins"
    public static let finalScore = "euchre.finalScore"
}

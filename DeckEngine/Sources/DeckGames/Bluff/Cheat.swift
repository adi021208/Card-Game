import Foundation
import DeckCore

/// Cheat (also played as I Doubt It, or Bullshit).
///
/// You put cards face down and say what they are. Everyone else decides whether
/// to believe you. It is the purest Pass & Play game in the library: the cards
/// on the table are genuinely secret, and calling wrong costs you the whole pile.
public struct CheatRules: GameRules {
    public static let gameID = GameID.cheat
    public static let rulesVersion = 1

    public init() {}

    public struct Settings: Hashable, Codable, Sendable {
        /// Cards that may be laid in one go.
        public var maximumPerTurn: Int
        /// The claimed rank must be one higher than the last. Otherwise the
        /// player names any rank they like.
        public var sequentialRanks: Bool
        /// Only the next player may call, rather than everybody in turn.
        public var onlyNextPlayerChallenges: Bool
        /// Turns after which the round is called and hands are counted.
        ///
        /// Between players who count perfectly, Cheat is a treadmill: roughly
        /// as many cards come back on the next call as went down on the lay,
        /// so a round can run indefinitely. Real tables call it and count
        /// hands. Zero means play until somebody goes out, however long.
        public var turnLimit: Int

        public init(maximumPerTurn: Int = 4,
                    sequentialRanks: Bool = true,
                    onlyNextPlayerChallenges: Bool = false,
                    turnLimit: Int = 120) {
            self.maximumPerTurn = max(1, min(4, maximumPerTurn))
            self.sequentialRanks = sequentialRanks
            self.onlyNextPlayerChallenges = onlyNextPlayerChallenges
            self.turnLimit = max(0, turnLimit)
        }

        public static func from(_ configuration: GameConfiguration) -> Settings {
            Settings(maximumPerTurn: configuration.option("maximumPerTurn", default: 4),
                     sequentialRanks: configuration.flag("sequentialRanks", default: true),
                     onlyNextPlayerChallenges: configuration.flag("onlyNextPlayerChallenges"),
                     turnLimit: configuration.option("turnLimit", default: 120))
        }
    }

    public enum Phase: Hashable, Codable, Sendable {
        /// Somebody is choosing what to put down.
        case laying
        /// The table is deciding whether to believe the claim.
        case challenging
    }

    public struct State: GameStateProtocol {
        public var board: Board
        public var activeSeat: SeatID?
        public var roundNumber: Int
        public var finalResult: GameResult?

        public var settings: Settings
        public var seatOrder: [SeatID]
        public var phase: Phase
        /// The rank that must be claimed next.
        public var requiredRank: Rank
        /// Who put the last cards down.
        public var lastLayer: SeatID?
        /// What they said they were.
        public var claimedRank: Rank?
        /// How many they laid.
        public var claimedCount: Int
        /// The actual cards they laid, which only they know.
        public var lastLaidCards: [CardID]
        /// Seats yet to decide whether to challenge.
        public var challengeQueue: [SeatID]
        /// Set when a challenge has been resolved, so the result can be shown
        /// before the pile is swept up.
        public var lastChallenge: ChallengeOutcome?
        public var turnsTaken: Int
        public var bluffsMade: [SeatID: Int]
        public var bluffsCaught: [SeatID: Int]
        public var badCalls: [SeatID: Int]
        public var finishOrder: [SeatID]
        public var pendingSweep: Bool

        public func hand(_ seat: SeatID) -> [Card] { board.cardList(in: .hand(seat)) }
        public var pileCount: Int { board.count(in: .discard) }

        public struct ChallengeOutcome: Hashable, Codable, Sendable {
            public var challenger: SeatID
            public var accused: SeatID
            public var claimWasTrue: Bool
            public var revealed: [CardID]
            public var loser: SeatID
        }
    }

    public enum Action: Hashable, Sendable {
        /// Put cards down claiming they are all this rank.
        case lay(cards: [CardID], claiming: Rank)
        /// Say you believe them.
        case believe
        /// Call it.
        case challenge
    }

    /// A Cheat agent sees its own hand, the public claims, and how many cards
    /// everyone holds. It never sees what is actually in the pile — which is the
    /// entire game.
    public struct Observation: Sendable {
        public var seat: SeatID
        public var hand: [Card]
        public var phase: Phase
        public var requiredRank: Rank
        public var claimedRank: Rank?
        public var claimedCount: Int
        public var lastLayer: SeatID?
        public var pileCount: Int
        public var opponentCardCounts: [SeatID: Int]
        /// Ranks the agent holds, which bound how many of a rank can be elsewhere.
        public var ownRankCounts: [Rank: Int]
        public var settings: Settings
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
        board.ensureZones(seats.map { Zone.hand($0) } + [.stock, .discard])

        var index = 0
        while board.count(in: .stock) > 0 {
            board.draw(from: .stock, to: .hand(seats[index % seats.count]), facing: .hand(seats[index % seats.count]))
            index += 1
        }
        for seat in seats { board.sort(.hand(seat), by: HandSort.byRankThenSuit) }

        return State(board: board,
                     activeSeat: seats.first,
                     roundNumber: 1,
                     finalResult: nil,
                     settings: settings,
                     seatOrder: seats,
                     phase: .laying,
                     requiredRank: .ace,
                     lastLayer: nil,
                     claimedRank: nil,
                     claimedCount: 0,
                     lastLaidCards: [],
                     challengeQueue: [],
                     lastChallenge: nil,
                     turnsTaken: 0,
                     bluffsMade: [:],
                     bluffsCaught: [:],
                     badCalls: [:],
                     finishOrder: [],
                     pendingSweep: false)
    }

    // MARK: - Rules

    public func legalActions(in state: State, for seat: SeatID) -> [Action] {
        guard state.finalResult == nil, state.activeSeat == seat else { return [] }
        switch state.phase {
        case .laying:
            let hand = state.hand(seat)
            guard !hand.isEmpty else { return [] }
            let ranks: [Rank] = state.settings.sequentialRanks ? [state.requiredRank] : Rank.allCases
            var actions: [Action] = []
            // Offer every subset size up to the limit. The interface builds the
            // selection; the AI searches these.
            for rank in ranks {
                let truthful = hand.filter { $0.rank == rank }.map(\.id)
                let others = hand.filter { $0.rank != rank }.map(\.id)
                let limit = min(state.settings.maximumPerTurn, hand.count)
                for count in 1...limit {
                    // The honest play, when it exists.
                    if truthful.count >= count {
                        actions.append(.lay(cards: Array(truthful.prefix(count)), claiming: rank))
                    }
                    // Bluffs: pad with the cards the player least wants.
                    if truthful.count < count {
                        let padding = others.suffix(count - truthful.count)
                        let cards = truthful + padding
                        if cards.count == count {
                            actions.append(.lay(cards: cards, claiming: rank))
                        }
                    }
                }
            }
            return actions
        case .challenging:
            return [.believe, .challenge]
        }
    }

    public func rejection(for action: Action, in state: State) -> IllegalMove? {
        guard state.finalResult == nil else { return .gameOver }
        guard let seat = state.activeSeat else { return .notYourTurn }
        switch action {
        case let .lay(cards, claiming):
            guard state.phase == .laying else { return .noSuchAction }
            guard !cards.isEmpty, cards.count <= state.settings.maximumPerTurn else {
                return IllegalMove("layOneToFour",
                                   arguments: [String(state.settings.maximumPerTurn)],
                                   english: "Put down between one and \(state.settings.maximumPerTurn) cards.")
            }
            guard Set(cards).count == cards.count else {
                return IllegalMove("duplicateCards", english: "Choose different cards.")
            }
            for card in cards where state.board.zone(of: card) != Zone.hand(seat) {
                return .cardNotInHand
            }
            if state.settings.sequentialRanks && claiming != state.requiredRank {
                return IllegalMove("mustClaimNextRank",
                                   arguments: [state.requiredRank.localizationKey],
                                   english: "The pile is on \(state.requiredRank.englishName.lowercased())s — that is what you have to claim.")
            }
            return nil
        case .believe, .challenge:
            guard state.phase == .challenging else { return .noSuchAction }
            return nil
        }
    }

    public func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard let seat = state.activeSeat else { return [] }
        var events: [GameEvent] = []
        state.turnsTaken += 1

        switch action {
        case let .lay(cards, claiming):
            for card in cards {
                // Face down: nobody, not even the player who put them there once
                // they leave their hand, can look at the pile.
                state.board.move(card, to: .discard, facing: .faceDown)
            }
            let truthful = cards.allSatisfy { state.board.card($0)?.rank == claiming }
            if !truthful { state.bluffsMade[seat, default: 0] += 1 }
            state.lastLayer = seat
            state.claimedRank = claiming
            state.claimedCount = cards.count
            state.lastLaidCards = cards
            state.lastChallenge = nil
            events.append(.cardsPlayed(cards: cards, by: seat, to: .discard))
            events.append(.claimMade(seat: seat, claim: "\(cards.count)x\(claiming.token)"))

            // Whoever wants to call gets their chance, in turn order.
            let others = orderedOthers(after: seat, in: state).filter { !state.finishOrder.contains($0) }
            state.challengeQueue = state.settings.onlyNextPlayerChallenges
                ? Array(others.prefix(1))
                : others
            if state.challengeQueue.isEmpty {
                events += finishLayingTurn(state: &state, layer: seat)
            } else {
                state.phase = .challenging
                let next = state.challengeQueue[0]
                state.activeSeat = next
                events.append(.turnChanged(from: seat, to: next))
            }

        case .believe:
            state.challengeQueue.removeAll { $0 == seat }
            if let next = state.challengeQueue.first {
                state.activeSeat = next
                events.append(.turnChanged(from: seat, to: next))
            } else if let layer = state.lastLayer {
                events += finishLayingTurn(state: &state, layer: layer)
            }

        case .challenge:
            events += resolveChallenge(challenger: seat, state: &state)
        }
        return events
    }

    private func resolveChallenge(challenger: SeatID, state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        guard let accused = state.lastLayer, let claimed = state.claimedRank else { return events }
        let laid = state.lastLaidCards
        let claimWasTrue = laid.allSatisfy { state.board.card($0)?.rank == claimed }

        // The laid cards are turned over for everyone; the rest of the pile is
        // not, because nobody at a real table gets to sift through it.
        for card in laid {
            state.board.setVisibility(.everyone, for: card)
            state.board.flip(card, faceUp: true)
        }
        events.append(.cardsRevealed(cards: laid, to: Set(state.seatOrder)))

        let loser = claimWasTrue ? challenger : accused
        if claimWasTrue {
            state.badCalls[challenger, default: 0] += 1
        } else {
            state.bluffsCaught[challenger, default: 0] += 1
        }
        events.append(.challengeResolved(challenger: challenger, target: accused, claimWasTrue: claimWasTrue))
        events.append(.highlight(code: claimWasTrue ? "cheat.badCall" : "cheat.caught",
                                 seat: challenger,
                                 value: state.pileCount))

        state.lastChallenge = State.ChallengeOutcome(challenger: challenger,
                                                    accused: accused,
                                                    claimWasTrue: claimWasTrue,
                                                    revealed: laid,
                                                    loser: loser)
        state.pendingSweep = true
        state.phase = .laying
        state.activeSeat = nil
        return events
    }

    /// Sweeps the pile to whoever lost the call, then hands play on.
    public func advanceAutomatically(_ state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard state.finalResult == nil, state.pendingSweep, let outcome = state.lastChallenge else { return [] }
        state.pendingSweep = false
        var events: [GameEvent] = []

        let pile = state.board.contents(of: .discard)
        for card in pile {
            state.board.move(card, to: .hand(outcome.loser), facing: .hand(outcome.loser))
        }
        state.board.sort(.hand(outcome.loser), by: HandSort.byRankThenSuit)
        events.append(.cardsMoved(cards: pile, from: .discard, to: .hand(outcome.loser)))

        state.lastLaidCards = []
        state.claimedRank = nil
        state.claimedCount = 0
        state.requiredRank = .ace
        state.challengeQueue = []

        // Anybody who emptied their hand before the call is out.
        events += recordFinishers(state: &state)
        if let result = checkForEnd(state: &state) {
            events.append(.gameEnded(result))
            return events
        }
        // The loser leads the new pile, unless they are out.
        let leader = state.finishOrder.contains(outcome.loser)
            ? nextActiveSeat(after: outcome.loser, in: state)
            : outcome.loser
        state.activeSeat = leader
        events.append(.turnChanged(from: nil, to: leader))
        return events
    }

    private func finishLayingTurn(state: inout State, layer: SeatID) -> [GameEvent] {
        var events: [GameEvent] = []
        state.phase = .laying
        state.challengeQueue = []
        state.requiredRank = nextRank(after: state.requiredRank)

        events += recordFinishers(state: &state)
        if let result = checkForEnd(state: &state) {
            events.append(.gameEnded(result))
            return events
        }
        let next = nextActiveSeat(after: layer, in: state)
        state.activeSeat = next
        events.append(.turnChanged(from: layer, to: next))
        return events
    }

    private func recordFinishers(state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        for seat in state.seatOrder
        where state.board.isEmpty(Zone.hand(seat)) && !state.finishOrder.contains(seat) {
            state.finishOrder.append(seat)
            events.append(.playerOut(seat: seat, place: state.finishOrder.count))
            events.append(.highlight(code: "cheat.out", seat: seat, value: state.finishOrder.count))
        }
        return events
    }

    private func checkForEnd(state: inout State) -> GameResult? {
        let remaining = state.seatOrder.filter { !state.finishOrder.contains($0) }
        let calledTime = state.settings.turnLimit > 0
            && state.turnsTaken >= state.settings.turnLimit
        guard remaining.count <= 1 || calledTime else { return nil }
        var placements = state.finishOrder
        // Round called: whoever is still holding cards places by how few they
        // hold, which is how a real table settles a hand that will not end.
        placements.append(contentsOf: remaining.sorted {
            state.board.count(in: Zone.hand($0)) < state.board.count(in: Zone.hand($1))
        })
        var scores: [SeatID: Int] = [:]
        for (index, seat) in placements.enumerated() {
            scores[seat] = placements.count - index
        }
        let winners = placements.first.map { [$0] } ?? []
        let leader = winners.first ?? state.seatOrder[0]
        var metrics: [String: Int] = [:]
        metrics[CheatStatistics.bluffsMade] = state.bluffsMade[leader] ?? 0
        metrics[CheatStatistics.bluffsCaught] = state.bluffsCaught[leader] ?? 0
        metrics[CheatStatistics.badCalls] = state.badCalls[leader] ?? 0
        var highlights: [String] = []
        if (state.badCalls[leader] ?? 0) == 0 { highlights.append("cheat.perfectRead") }
        if (state.bluffsMade[leader] ?? 0) >= 5 { highlights.append("cheat.serialLiar") }
        let result = GameResult(winners: winners,
                                scores: scores,
                                placements: placements,
                                duration: 0,
                                turnCount: state.turnsTaken,
                                roundCount: 1,
                                metrics: metrics,
                                highlights: highlights)
        state.finalResult = result
        state.activeSeat = nil
        return result
    }

    private func orderedOthers(after seat: SeatID, in state: State) -> [SeatID] {
        guard let index = state.seatOrder.firstIndex(of: seat) else { return [] }
        let count = state.seatOrder.count
        return (1..<count).map { state.seatOrder[(index + $0) % count] }
    }

    private func nextActiveSeat(after seat: SeatID, in state: State) -> SeatID {
        guard let index = state.seatOrder.firstIndex(of: seat) else { return state.seatOrder[0] }
        let count = state.seatOrder.count
        for offset in 1...count {
            let candidate = state.seatOrder[(index + offset) % count]
            if !state.finishOrder.contains(candidate) { return candidate }
        }
        return seat
    }

    private func nextRank(after rank: Rank) -> Rank {
        // A, 2, 3 ... K, then back to A.
        if rank == .ace { return .two }
        if rank == .king { return .ace }
        return Rank(rawValue: rank.rawValue + 1) ?? .ace
    }

    // MARK: - Tokens

    public func token(for action: Action, in state: State) -> ActionToken {
        let seat = state.activeSeat ?? state.seatOrder[0]
        switch action {
        case let .lay(cards, claiming):
            let sorted = cards.sorted()
            return ActionToken(id: TokenID.make(seat, "lay", [claiming.token] + sorted.map { String($0.rawValue) }),
                               kind: .claim,
                               seat: seat,
                               cards: sorted,
                               destination: .discard,
                               source: .hand(seat),
                               amount: cards.count,
                               labelKey: "action.claimCards",
                               labelArguments: [String(cards.count), claiming.localizationKey])
        case .believe:
            return ActionToken(id: TokenID.make(seat, "believe"),
                               kind: .passTurn,
                               seat: seat,
                               labelKey: "action.believe")
        case .challenge:
            return ActionToken(id: TokenID.make(seat, "challenge"),
                               kind: .challenge,
                               seat: seat,
                               labelKey: "action.cheat")
        }
    }

    public func decodeAction(id: String, in state: State) -> Action? {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        switch parts[1] {
        case "believe": return .believe
        case "challenge": return .challenge
        case "lay":
            guard parts.count >= 4, let rank = Rank(token: parts[2]) else { return nil }
            let cards = parts.dropFirst(3).compactMap { Int($0) }.map { CardID(rawValue: $0) }
            guard !cards.isEmpty else { return nil }
            return .lay(cards: cards, claiming: rank)
        default: return nil
        }
    }

    // MARK: - Observation

    public func observation(of state: State, for seat: SeatID) -> Observation {
        var counts: [SeatID: Int] = [:]
        for other in state.seatOrder where other != seat {
            counts[other] = state.board.count(in: .hand(other))
        }
        var rankCounts: [Rank: Int] = [:]
        for card in state.hand(seat) {
            if let rank = card.rank { rankCounts[rank, default: 0] += 1 }
        }
        return Observation(seat: seat,
                           hand: state.hand(seat),
                           phase: state.phase,
                           requiredRank: state.requiredRank,
                           claimedRank: state.claimedRank,
                           claimedCount: state.claimedCount,
                           lastLayer: state.lastLayer,
                           pileCount: state.pileCount,
                           opponentCardCounts: counts,
                           ownRankCounts: rankCounts,
                           settings: state.settings,
                           seatOrder: state.seatOrder)
    }

    // MARK: - Presentation

    public func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation {
        var slots: [TableSlot] = []
        if let own = TableBuilder.ownHandSlot(viewer: viewer, seating: seating) { slots.append(own) }
        slots += TableBuilder.opponentSlots(seating: seating, viewer: viewer)
        slots.append(TableSlot(zone: .discard,
                               style: .stack,
                               anchor: .centre(order: 0),
                               titleKey: "zone.pile",
                               emptyHintKey: "zone.pile.empty",
                               prominence: 1.5))

        var callouts: [TableCallout] = []
        if state.settings.sequentialRanks {
            callouts.append(TableCallout(id: "required",
                                         labelKey: "callout.claimRank",
                                         arguments: [state.requiredRank.localizationKey],
                                         emphasis: .primary))
        }
        if let claimed = state.claimedRank, state.claimedCount > 0 {
            callouts.append(TableCallout(id: "claim",
                                         labelKey: "callout.lastClaim",
                                         arguments: [String(state.claimedCount), claimed.localizationKey],
                                         emphasis: .alert))
        }
        callouts.append(TableCallout(id: "pile",
                                     labelKey: "callout.pileSize",
                                     arguments: [String(state.pileCount)]))

        var states: [SeatID: String] = [:]
        for seat in state.finishOrder { states[seat] = "state.out" }
        if let layer = state.lastLayer, state.phase == .challenging { states[layer] = "state.claiming" }

        var scores: [SeatID: Int] = [:]
        for seat in state.seatOrder { scores[seat] = state.board.count(in: .hand(seat)) }

        var actions: [ActionToken] = []
        var playable: Set<CardID> = []
        if let viewer, state.activeSeat == viewer {
            if state.phase == .challenging {
                actions = legalActions(in: state, for: viewer).map { token(for: $0, in: state) }
            } else {
                // The interface builds the selection; laying every combination
                // would be thousands of tokens.
                playable = Set(state.hand(viewer).map(\.id))
            }
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
                                                                  states: states),
                                 callouts: callouts,
                                 actions: actions,
                                 playableCards: playable,
                                 activeSeat: state.activeSeat,
                                 roundNumber: 1,
                                 phaseKey: state.phase == .challenging ? "phase.challenge" : "phase.lay",
                                 result: state.finalResult)
    }

    public func hint(for state: State, seat: SeatID) -> Hint? {
        guard state.activeSeat == seat else { return nil }
        if state.phase == .challenging {
            guard let claimed = state.claimedRank else { return nil }
            let held = state.hand(seat).filter { $0.rank == claimed }.count
            let impossible = held + state.claimedCount > 4
            if impossible {
                return Hint(messageKey: "hint.cheat.impossible",
                            arguments: [String(held), claimed.localizationKey],
                            english: "You hold \(held) of them and they claimed \(state.claimedCount). There are only four in the pack, so at least one of those is a lie.")
            }
            return Hint(messageKey: "hint.cheat.count",
                        arguments: [String(held), claimed.localizationKey],
                        english: "You hold \(held) of that rank. The more you hold, the less likely their claim is — and the bigger the pile, the more a wrong call costs.")
        }
        let truthful = state.hand(seat).filter { $0.rank == state.requiredRank }
        if truthful.isEmpty {
            return Hint(messageKey: "hint.cheat.mustLie",
                        arguments: [state.requiredRank.localizationKey],
                        english: "You have no \(state.requiredRank.englishName.lowercased())s, so whatever you put down is a lie. Lay one card, not three — a small lie is a smaller loss.")
        }
        return Hint(messageKey: "hint.cheat.truth",
                    arguments: [String(truthful.count)],
                    english: "You can play \(truthful.count) honestly. Getting rid of cards matters, but so does keeping a rank back for when you are forced to lie later.",
                    cards: truthful.map(\.id))
    }
}

public enum CheatStatistics {
    public static let bluffsMade = "cheat.bluffsMade"
    public static let bluffsCaught = "cheat.bluffsCaught"
    public static let badCalls = "cheat.badCalls"
}

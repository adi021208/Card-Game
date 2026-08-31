import Foundation
import DeckCore

/// Texas Hold'em, No Limit.
///
/// A real implementation: blinds, position, four betting rounds, minimum raise
/// sizing, all-ins that do not reopen the betting, layered side pots, exact hand
/// comparison at showdown and split pots down to the odd chip.
public struct TexasHoldemRules: GameRules {
    public static let gameID = GameID.texasHoldem
    public static let rulesVersion = 1

    public init() {}

    // MARK: - Settings

    public struct Settings: Hashable, Codable, Sendable {
        public var startingChips: Int
        public var smallBlind: Int
        public var bigBlind: Int
        /// Hands between blind increases. Zero keeps the blinds flat.
        public var blindIncreaseEvery: Int
        /// Percentage the blinds grow by at each increase.
        public var blindIncreasePercent: Int
        /// Hands after which the game ends on chip count. Zero plays to the last
        /// player standing.
        public var handLimit: Int

        public init(startingChips: Int = 1000,
                    smallBlind: Int = 10,
                    bigBlind: Int = 20,
                    blindIncreaseEvery: Int = 0,
                    blindIncreasePercent: Int = 50,
                    handLimit: Int = 0) {
            self.startingChips = startingChips
            self.smallBlind = smallBlind
            self.bigBlind = bigBlind
            self.blindIncreaseEvery = blindIncreaseEvery
            self.blindIncreasePercent = blindIncreasePercent
            self.handLimit = handLimit
        }

        public static func from(_ configuration: GameConfiguration) -> Settings {
            Settings(startingChips: configuration.option("startingChips", default: 1000),
                     smallBlind: configuration.option("smallBlind", default: 10),
                     bigBlind: configuration.option("bigBlind", default: 20),
                     blindIncreaseEvery: configuration.option("blindIncreaseEvery", default: 0),
                     blindIncreasePercent: configuration.option("blindIncreasePercent", default: 50),
                     handLimit: configuration.option("handLimit", default: 0))
        }
    }

    public enum Street: Int, Codable, Sendable, CaseIterable, Comparable {
        case preflop = 0
        case flop = 1
        case turn = 2
        case river = 3
        case showdown = 4

        public static func < (lhs: Street, rhs: Street) -> Bool { lhs.rawValue < rhs.rawValue }
        public var localizationKey: String { "poker.street.\(self)" }
        public var communityCardCount: Int {
            switch self {
            case .preflop: return 0
            case .flop: return 3
            case .turn: return 4
            case .river, .showdown: return 5
            }
        }
    }

    // MARK: - State

    public struct State: GameStateProtocol {
        public var board: Board
        public var activeSeat: SeatID?
        /// Hand number.
        public var roundNumber: Int
        public var finalResult: GameResult?

        public var settings: Settings
        public var seatOrder: [SeatID]
        public var street: Street
        public var dealerSeat: SeatID
        public var stacks: [SeatID: Int]
        /// Chips put in on the current street.
        public var committed: [SeatID: Int]
        /// Chips put in across the whole hand, which is what the side pots use.
        public var totalCommitted: [SeatID: Int]
        public var folded: Set<SeatID>
        public var allIn: Set<SeatID>
        /// Out of chips and out of the game.
        public var eliminated: Set<SeatID>
        /// Seats that still owe an action on this street, in order.
        public var actionQueue: [SeatID]
        /// Highest amount committed on this street.
        public var currentBet: Int
        /// Size of the last full raise, which sets the minimum for the next one.
        public var lastRaiseSize: Int
        public var currentSmallBlind: Int
        public var currentBigBlind: Int
        /// Chips awarded when the hand ends, for the result screen.
        public var lastPayouts: [SeatID: Int]
        /// Hands revealed at showdown.
        public var revealedHands: [SeatID: [CardID]]
        public var showdownRanks: [SeatID: PokerHandRank]
        public var handComplete: Bool
        public var handsPlayed: Int
        public var turnsTaken: Int
        /// Per-seat running metrics.
        public var handsWon: [SeatID: Int]
        public var biggestPot: [SeatID: Int]
        public var bestHandCategory: [SeatID: Int]
        public var showdownsWon: [SeatID: Int]
        public var bluffsWon: [SeatID: Int]

        public func hole(_ seat: SeatID) -> [Card] { board.cardList(in: .hand(seat)) }
        public var community: [Card] { board.cardList(in: .community) }
        public var pot: Int { totalCommitted.values.reduce(0, +) }
        public func toCall(_ seat: SeatID) -> Int {
            max(0, currentBet - (committed[seat] ?? 0))
        }
        public func stack(_ seat: SeatID) -> Int { stacks[seat] ?? 0 }
        /// Seats still contesting the pot.
        public var contenders: [SeatID] {
            seatOrder.filter { !folded.contains($0) && !eliminated.contains($0) }
        }
        /// Seats that can still act (not folded, not all-in).
        public var actors: [SeatID] {
            contenders.filter { !allIn.contains($0) }
        }
    }

    public enum Action: Hashable, Sendable {
        case fold
        case check
        case call
        /// Raise the total on this street to `to`. A bet into an unopened pot is
        /// the same move with `currentBet` at zero.
        case raise(to: Int)
        case allIn
    }

    /// What a poker AI may see: its own two cards, the board, the betting, the
    /// stacks. It has no access to opponents' hole cards or to the deck.
    public struct Observation: Sendable {
        public var seat: SeatID
        public var hole: [Card]
        public var community: [Card]
        public var street: Street
        public var pot: Int
        public var toCall: Int
        public var stack: Int
        public var currentBet: Int
        public var minimumRaise: Int
        public var bigBlind: Int
        public var stacks: [SeatID: Int]
        public var committed: [SeatID: Int]
        public var totalCommitted: [SeatID: Int]
        public var folded: Set<SeatID>
        public var allIn: Set<SeatID>
        public var activeOpponents: Int
        public var seatOrder: [SeatID]
        public var dealerSeat: SeatID
        /// Position from the button, 0 being the button itself.
        public var positionFromButton: Int
    }

    // MARK: - Setup

    public func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State {
        let settings = Settings.from(configuration)
        let seats = configuration.seating.ids
        var stacks: [SeatID: Int] = [:]
        for seat in seats { stacks[seat] = settings.startingChips }

        var state = State(board: Board(),
                          activeSeat: nil,
                          roundNumber: 1,
                          finalResult: nil,
                          settings: settings,
                          seatOrder: seats,
                          street: .preflop,
                          dealerSeat: seats[0],
                          stacks: stacks,
                          committed: [:],
                          totalCommitted: [:],
                          folded: [],
                          allIn: [],
                          eliminated: [],
                          actionQueue: [],
                          currentBet: 0,
                          lastRaiseSize: settings.bigBlind,
                          currentSmallBlind: settings.smallBlind,
                          currentBigBlind: settings.bigBlind,
                          lastPayouts: [:],
                          revealedHands: [:],
                          showdownRanks: [:],
                          handComplete: false,
                          handsPlayed: 0,
                          turnsTaken: 0,
                          handsWon: [:],
                          biggestPot: [:],
                          bestHandCategory: [:],
                          showdownsWon: [:],
                          bluffsWon: [:])
        dealHand(state: &state, generator: &generator)
        return state
    }

    /// Deals a fresh hand: shuffle, post the blinds, two cards each.
    private func dealHand(state: inout State, generator: inout SeededGenerator) {
        var board = Board()
        var deck = DeckConfiguration.standard52.build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)
        board.ensureZones(state.seatOrder.map { Zone.hand($0) } + [.stock, .community, .reserve])

        let live = state.seatOrder.filter { !state.eliminated.contains($0) }
        state.folded = Set(state.seatOrder).subtracting(live)
        state.allIn = []
        state.committed = [:]
        state.totalCommitted = [:]
        state.revealedHands = [:]
        state.showdownRanks = [:]
        state.lastPayouts = [:]
        state.street = .preflop
        state.currentBet = 0
        state.handComplete = false

        // Two cards each, one at a time round the table, starting left of the button.
        let order = rotate(live, startingAfter: state.dealerSeat)
        for _ in 0..<2 {
            for seat in order {
                board.draw(from: .stock, to: .hand(seat), facing: .hand(seat))
            }
        }
        state.board = board

        // Blinds. Heads-up, the button posts the small blind and acts first
        // pre-flop, which is the standard rule and easy to get backwards.
        let smallBlindSeat: SeatID
        let bigBlindSeat: SeatID
        if live.count == 2 {
            smallBlindSeat = state.dealerSeat
            bigBlindSeat = order.first { $0 != state.dealerSeat } ?? live[0]
        } else {
            smallBlindSeat = order[0]
            bigBlindSeat = order.count > 1 ? order[1] : order[0]
        }
        post(state: &state, seat: smallBlindSeat, amount: state.currentSmallBlind)
        post(state: &state, seat: bigBlindSeat, amount: state.currentBigBlind)
        state.currentBet = state.currentBigBlind
        state.lastRaiseSize = state.currentBigBlind

        // Pre-flop action starts left of the big blind (or with the button
        // heads-up, which is the same seat as the small blind).
        let firstToAct: SeatID
        if live.count == 2 {
            firstToAct = smallBlindSeat
        } else {
            firstToAct = rotate(live, startingAfter: bigBlindSeat).first ?? live[0]
        }
        state.actionQueue = buildQueue(state: state, startingAt: firstToAct)
        state.activeSeat = state.actionQueue.first
        state.handsPlayed += 1
    }

    /// Puts chips in without it counting as a voluntary action.
    private func post(state: inout State, seat: SeatID, amount: Int) {
        let available = state.stack(seat)
        let paid = min(available, amount)
        state.stacks[seat] = available - paid
        state.committed[seat, default: 0] += paid
        state.totalCommitted[seat, default: 0] += paid
        if state.stacks[seat] == 0 { state.allIn.insert(seat) }
    }

    /// Seats in clockwise order starting with the one after `seat`.
    private func rotate(_ seats: [SeatID], startingAfter seat: SeatID) -> [SeatID] {
        guard let index = seats.firstIndex(of: seat) else { return seats }
        let count = seats.count
        return (1...count).map { seats[(index + $0) % count] }
    }

    /// Everyone who can still act, in order from `seat`.
    private func buildQueue(state: State, startingAt seat: SeatID) -> [SeatID] {
        let actors = state.actors
        guard !actors.isEmpty else { return [] }
        guard let index = actors.firstIndex(of: seat) else {
            // `seat` is all-in or folded; start from the next one that can act.
            let order = state.seatOrder
            guard let seatIndex = order.firstIndex(of: seat) else { return actors }
            for offset in 0..<order.count {
                let candidate = order[(seatIndex + offset) % order.count]
                if let candidateIndex = actors.firstIndex(of: candidate) {
                    return Array(actors[candidateIndex...] + actors[..<candidateIndex])
                }
            }
            return actors
        }
        return Array(actors[index...] + actors[..<index])
    }

    // MARK: - Legality

    /// The smallest legal raise total on this street.
    public func minimumRaiseTotal(in state: State) -> Int {
        state.currentBet + max(state.lastRaiseSize, state.currentBigBlind)
    }

    public func legalActions(in state: State, for seat: SeatID) -> [Action] {
        guard state.finalResult == nil, state.activeSeat == seat, !state.handComplete else { return [] }
        guard !state.folded.contains(seat), !state.allIn.contains(seat) else { return [] }

        var actions: [Action] = []
        let toCall = state.toCall(seat)
        let stack = state.stack(seat)

        if toCall == 0 {
            actions.append(.check)
        } else {
            // Folding when nothing is owed is legal but never correct, so it is
            // not offered; a player can still fold when facing a bet.
            actions.append(.fold)
            if stack > 0 { actions.append(.call) }
        }

        let minimumTotal = minimumRaiseTotal(in: state)
        let maximumTotal = (state.committed[seat] ?? 0) + stack
        if maximumTotal > state.currentBet && stack > 0 {
            if maximumTotal >= minimumTotal {
                // A representative ladder for the AI and the quick buttons; the
                // interface may submit any amount in range and it is validated
                // on the way in.
                var sizes: Set<Int> = [minimumTotal, maximumTotal]
                let pot = state.pot
                for fraction in [0.5, 0.75, 1.0] {
                    let target = state.currentBet + toCall + Int(Double(pot) * fraction)
                    if target >= minimumTotal && target < maximumTotal { sizes.insert(target) }
                }
                for size in sizes.sorted() where size < maximumTotal {
                    actions.append(.raise(to: size))
                }
            }
            actions.append(.allIn)
        }
        return actions
    }

    public func rejection(for action: Action, in state: State) -> IllegalMove? {
        guard state.finalResult == nil, !state.handComplete else { return .gameOver }
        guard let seat = state.activeSeat else { return .notYourTurn }
        guard !state.folded.contains(seat) else { return .notYourTurn }
        let toCall = state.toCall(seat)
        let stack = state.stack(seat)

        switch action {
        case .fold:
            guard toCall > 0 else {
                return IllegalMove("cannotFoldForFree", english: "Nothing to call — check instead.")
            }
            return nil
        case .check:
            guard toCall == 0 else {
                return IllegalMove("mustCallOrFold",
                                   arguments: [String(toCall)],
                                   english: "There is \(toCall) to call. Call, raise or fold.")
            }
            return nil
        case .call:
            guard toCall > 0 else {
                return IllegalMove("nothingToCall", english: "Nothing to call — check instead.")
            }
            guard stack > 0 else { return IllegalMove("noChips", english: "You have no chips left.") }
            return nil
        case let .raise(to):
            let maximumTotal = (state.committed[seat] ?? 0) + stack
            guard to > state.currentBet else {
                return IllegalMove("raiseTooSmall",
                                   arguments: [String(minimumRaiseTotal(in: state))],
                                   english: "A raise has to beat \(state.currentBet).")
            }
            guard to <= maximumTotal else {
                return IllegalMove("notEnoughChips",
                                   arguments: [String(maximumTotal)],
                                   english: "You only have \(maximumTotal) to put in.")
            }
            // Going all-in for less than a full raise is always allowed.
            if to < minimumRaiseTotal(in: state) && to < maximumTotal {
                return IllegalMove("raiseTooSmall",
                                   arguments: [String(minimumRaiseTotal(in: state))],
                                   english: "The minimum raise is to \(minimumRaiseTotal(in: state)).")
            }
            return nil
        case .allIn:
            guard stack > 0 else { return IllegalMove("noChips", english: "You have no chips left.") }
            return nil
        }
    }

    // MARK: - Applying

    public func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard let seat = state.activeSeat else { return [] }
        var events: [GameEvent] = []
        state.turnsTaken += 1

        switch action {
        case .fold:
            state.folded.insert(seat)
            events.append(.betPlaced(seat: seat, amount: 0, kind: .fold))
        case .check:
            events.append(.betPlaced(seat: seat, amount: 0, kind: .check))
        case .call:
            let paid = commit(state: &state, seat: seat, amount: state.toCall(seat))
            events.append(.betPlaced(seat: seat, amount: paid, kind: .call))
        case let .raise(to):
            let delta = to - (state.committed[seat] ?? 0)
            let paid = commit(state: &state, seat: seat, amount: delta)
            let newTotal = state.committed[seat] ?? 0
            events += registerAggression(state: &state, seat: seat, newTotal: newTotal)
            events.append(.betPlaced(seat: seat, amount: paid, kind: .raise))
        case .allIn:
            let paid = commit(state: &state, seat: seat, amount: state.stack(seat))
            let newTotal = state.committed[seat] ?? 0
            if newTotal > state.currentBet {
                events += registerAggression(state: &state, seat: seat, newTotal: newTotal)
            }
            events.append(.betPlaced(seat: seat, amount: paid, kind: .allIn))
        }

        state.actionQueue.removeAll { $0 == seat }
        events += advance(state: &state, generator: &generator)
        return events
    }

    /// Moves chips from a stack into the pot, capped at what the player has.
    @discardableResult
    private func commit(state: inout State, seat: SeatID, amount: Int) -> Int {
        let paid = min(max(0, amount), state.stack(seat))
        state.stacks[seat] = state.stack(seat) - paid
        state.committed[seat, default: 0] += paid
        state.totalCommitted[seat, default: 0] += paid
        if state.stacks[seat] == 0 {
            state.allIn.insert(seat)
            state.actionQueue.removeAll { $0 == seat }
        }
        return paid
    }

    /// A raise reopens the betting: everybody still able to act owes a response.
    ///
    /// An all-in that does not reach a full raise increases the bet but does
    /// *not* reset the minimum raise size and does not reopen the action for
    /// players who have already called the larger amount.
    private func registerAggression(state: inout State, seat: SeatID, newTotal: Int) -> [GameEvent] {
        let increase = newTotal - state.currentBet
        let isFullRaise = increase >= max(state.lastRaiseSize, state.currentBigBlind)
        state.currentBet = max(state.currentBet, newTotal)
        if isFullRaise {
            state.lastRaiseSize = increase
        }
        var queue = state.actionQueue
        // Rebuild the queue so it runs from the player after the aggressor,
        // round to the aggressor, skipping anyone who cannot act.
        let responders = state.actors.filter { $0 != seat }
        if isFullRaise || queue.isEmpty {
            queue = orderedResponders(state: state, after: seat, among: responders)
        } else {
            // Not a full raise: only players who have not yet matched the new
            // amount still owe an action.
            let owing = responders.filter { (state.committed[$0] ?? 0) < state.currentBet }
            queue = orderedResponders(state: state, after: seat, among: owing)
        }
        state.actionQueue = queue
        return []
    }

    private func orderedResponders(state: State, after seat: SeatID, among candidates: [SeatID]) -> [SeatID] {
        let order = state.seatOrder
        guard let index = order.firstIndex(of: seat) else { return candidates }
        var result: [SeatID] = []
        for offset in 1...order.count {
            let candidate = order[(index + offset) % order.count]
            if candidates.contains(candidate) { result.append(candidate) }
        }
        return result
    }

    /// Moves the hand forward: next player, next street, or showdown.
    private func advance(state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        var events: [GameEvent] = []

        // Everyone folded but one — no showdown needed.
        if state.contenders.count <= 1 {
            events += concludeHand(state: &state, showdown: false)
            return events
        }

        if let next = state.actionQueue.first {
            state.activeSeat = next
            events.append(.turnChanged(from: nil, to: next))
            return events
        }

        // Betting on this street is done.
        events += collectStreet(state: &state)

        // With at most one player able to act, the rest of the board is dealt
        // out and the hand goes straight to showdown.
        if state.actors.count <= 1 {
            while state.street != .showdown {
                events += dealNextStreet(state: &state)
            }
            events += concludeHand(state: &state, showdown: true)
            return events
        }

        if state.street == .river {
            state.street = .showdown
            events += concludeHand(state: &state, showdown: true)
            return events
        }

        events += dealNextStreet(state: &state)
        let firstToAct = firstActor(state: state)
        state.actionQueue = firstToAct.map { buildQueue(state: state, startingAt: $0) } ?? []
        state.activeSeat = state.actionQueue.first
        if let seat = state.activeSeat {
            events.append(.turnChanged(from: nil, to: seat))
        }
        return events
    }

    /// Clears the per-street commitments; the chips stay in `totalCommitted`.
    private func collectStreet(state: inout State) -> [GameEvent] {
        state.committed = [:]
        state.currentBet = 0
        state.lastRaiseSize = state.currentBigBlind
        return []
    }

    /// Post-flop, action starts with the first live player left of the button.
    private func firstActor(state: State) -> SeatID? {
        let actors = state.actors
        guard !actors.isEmpty else { return nil }
        let order = state.seatOrder
        guard let index = order.firstIndex(of: state.dealerSeat) else { return actors.first }
        for offset in 1...order.count {
            let candidate = order[(index + offset) % order.count]
            if actors.contains(candidate) { return candidate }
        }
        return actors.first
    }

    /// Burns a card and turns the next street, exactly as at a table.
    private func dealNextStreet(state: inout State) -> [GameEvent] {
        var events: [GameEvent] = []
        switch state.street {
        case .preflop:
            state.street = .flop
            state.board.draw(from: .stock, to: .reserve, facing: .faceDown)
            for _ in 0..<3 {
                if let card = state.board.draw(from: .stock, to: .community, facing: .faceUp) {
                    events.append(.cardDealt(card: card.id, to: .community, faceUp: true))
                }
            }
        case .flop:
            state.street = .turn
            state.board.draw(from: .stock, to: .reserve, facing: .faceDown)
            if let card = state.board.draw(from: .stock, to: .community, facing: .faceUp) {
                events.append(.cardDealt(card: card.id, to: .community, faceUp: true))
            }
        case .turn:
            state.street = .river
            state.board.draw(from: .stock, to: .reserve, facing: .faceDown)
            if let card = state.board.draw(from: .stock, to: .community, facing: .faceUp) {
                events.append(.cardDealt(card: card.id, to: .community, faceUp: true))
            }
        case .river:
            state.street = .showdown
        case .showdown:
            break
        }
        return events
    }

    /// Works out who won, moves the chips, and records what happened.
    private func concludeHand(state: inout State, showdown: Bool) -> [GameEvent] {
        var events: [GameEvent] = []
        let contenders = Set(state.contenders)
        var ranks: [SeatID: PokerHandRank] = [:]

        if showdown && contenders.count > 1 {
            let community = state.community
            for seat in contenders {
                let hole = state.hole(seat)
                guard hole.count + community.count >= 5 else { continue }
                let rank = PokerEvaluator.best(from: hole + community)
                ranks[seat] = rank
                state.revealedHands[seat] = hole.map(\.id)
                // At showdown the hands become public information.
                for card in hole {
                    state.board.setVisibility(.everyone, for: card.id)
                }
                let previousBest = state.bestHandCategory[seat] ?? -1
                if rank.category.rawValue > previousBest {
                    state.bestHandCategory[seat] = rank.category.rawValue
                }
                if rank.isRoyalFlush {
                    events.append(.highlight(code: "poker.royalFlush", seat: seat, value: nil))
                } else if rank.category == .straightFlush {
                    events.append(.highlight(code: "poker.straightFlush", seat: seat, value: nil))
                } else if rank.category == .fourOfAKind {
                    events.append(.highlight(code: "poker.quads", seat: seat, value: nil))
                }
            }
            state.showdownRanks = ranks
            events.append(.showdown(revealed: state.revealedHands))
        }

        let pots = PotSolver.pots(contributions: state.totalCommitted, contenders: contenders)
        let oddChipOrder = rotate(state.seatOrder, startingAfter: state.dealerSeat)
        let payouts = PotSolver.award(pots: pots, ranks: ranks, oddChipOrder: oddChipOrder)
        state.lastPayouts = payouts

        let potSize = state.pot
        for (seat, amount) in payouts.sorted(by: { $0.key < $1.key }) {
            state.stacks[seat, default: 0] += amount
            events.append(.potAwarded(seat: seat, amount: amount))
            if amount > (state.biggestPot[seat] ?? 0) {
                state.biggestPot[seat] = amount
            }
            // Getting an uncalled bet handed back is not winning a hand.
            if amount > (state.totalCommitted[seat] ?? 0) {
                state.handsWon[seat, default: 0] += 1
            }
            if showdown && contenders.count > 1 {
                state.showdownsWon[seat, default: 0] += 1
            } else if contenders.count == 1 && state.street != .preflop {
                // Took it down without showing, after the flop.
                state.bluffsWon[seat, default: 0] += 1
                events.append(.highlight(code: "poker.tookItDown", seat: seat, value: potSize))
            }
        }

        state.handComplete = true
        state.activeSeat = nil
        state.actionQueue = []
        return events
    }

    // MARK: - Between hands

    public func advanceAutomatically(_ state: inout State, generator: inout SeededGenerator) -> [GameEvent] {
        guard state.finalResult == nil, state.handComplete else { return [] }
        var events: [GameEvent] = []

        // Anyone out of chips is out of the game.
        for seat in state.seatOrder where state.stack(seat) <= 0 && !state.eliminated.contains(seat) {
            state.eliminated.insert(seat)
            let place = state.seatOrder.count - state.eliminated.count + 1
            events.append(.playerOut(seat: seat, place: place))
        }

        let survivors = state.seatOrder.filter { !state.eliminated.contains($0) }
        let handLimitReached = state.settings.handLimit > 0 && state.handsPlayed >= state.settings.handLimit
        if survivors.count <= 1 || handLimitReached {
            let result = buildResult(state: state)
            state.finalResult = result
            state.handComplete = false
            events.append(.gameEnded(result))
            return events
        }

        state.handComplete = false
        state.roundNumber += 1

        // Blinds go up on schedule.
        if state.settings.blindIncreaseEvery > 0,
           state.handsPlayed % state.settings.blindIncreaseEvery == 0 {
            let growth = 100 + state.settings.blindIncreasePercent
            state.currentSmallBlind = max(1, state.currentSmallBlind * growth / 100)
            state.currentBigBlind = max(2, state.currentBigBlind * growth / 100)
        }

        // Move the button to the next surviving player.
        if let index = state.seatOrder.firstIndex(of: state.dealerSeat) {
            for offset in 1...state.seatOrder.count {
                let candidate = state.seatOrder[(index + offset) % state.seatOrder.count]
                if survivors.contains(candidate) {
                    state.dealerSeat = candidate
                    break
                }
            }
        }

        dealHand(state: &state, generator: &generator)
        events.append(.roundStarted(number: state.roundNumber))
        events.append(.handsDealt(counts: Dictionary(uniqueKeysWithValues: survivors.map { ($0, 2) })))
        return events
    }

    private func buildResult(state: State) -> GameResult {
        let ranked = state.seatOrder.sorted { state.stack($0) > state.stack($1) }
        let best = ranked.first.map { state.stack($0) } ?? 0
        var winners = state.seatOrder.filter { state.stack($0) == best && best > 0 }
        if winners.isEmpty { winners = [ranked[0]] }
        let leader = winners[0]
        var metrics: [String: Int] = [:]
        metrics[PokerStatistics.handsPlayed] = state.handsPlayed
        metrics[PokerStatistics.handsWon] = state.handsWon[leader] ?? 0
        metrics[PokerStatistics.biggestPot] = state.biggestPot[leader] ?? 0
        metrics[PokerStatistics.bestHand] = state.bestHandCategory[leader] ?? 0
        metrics[PokerStatistics.showdownsWon] = state.showdownsWon[leader] ?? 0
        metrics[PokerStatistics.finalStack] = state.stack(leader)
        var highlights: [String] = []
        if (state.bestHandCategory[leader] ?? 0) == PokerHandRank.Category.straightFlush.rawValue {
            highlights.append("poker.straightFlush")
        }
        return GameResult(winners: winners,
                          scores: state.stacks,
                          placements: ranked,
                          duration: 0,
                          turnCount: state.turnsTaken,
                          roundCount: state.handsPlayed,
                          metrics: metrics,
                          highlights: highlights)
    }

    // MARK: - Tokens

    public func token(for action: Action, in state: State) -> ActionToken {
        let seat = state.activeSeat ?? state.seatOrder[0]
        switch action {
        case .fold:
            return ActionToken(id: TokenID.make(seat, "fold"), kind: .fold, seat: seat, labelKey: "action.fold")
        case .check:
            return ActionToken(id: TokenID.make(seat, "check"), kind: .check, seat: seat, labelKey: "action.check")
        case .call:
            let amount = state.toCall(seat)
            return ActionToken(id: TokenID.make(seat, "call"),
                               kind: .call,
                               seat: seat,
                               amount: amount,
                               labelKey: "action.call",
                               labelArguments: [String(amount)])
        case let .raise(to):
            return ActionToken(id: TokenID.make(seat, "raise", [String(to)]),
                               kind: .raise,
                               seat: seat,
                               amount: to,
                               labelKey: state.currentBet == 0 ? "action.bet" : "action.raiseTo",
                               labelArguments: [String(to)])
        case .allIn:
            let amount = (state.committed[seat] ?? 0) + state.stack(seat)
            return ActionToken(id: TokenID.make(seat, "allin"),
                               kind: .allIn,
                               seat: seat,
                               amount: amount,
                               labelKey: "action.allIn",
                               labelArguments: [String(amount)])
        }
    }

    public func decodeAction(id: String, in state: State) -> Action? {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        switch parts[1] {
        case "fold": return .fold
        case "check": return .check
        case "call": return .call
        case "allin": return .allIn
        case "raise":
            guard parts.count >= 3, let amount = Int(parts[2]) else { return nil }
            return .raise(to: amount)
        default: return nil
        }
    }

    // MARK: - Observation

    public func observation(of state: State, for seat: SeatID) -> Observation {
        let order = state.seatOrder
        let buttonIndex = order.firstIndex(of: state.dealerSeat) ?? 0
        let seatIndex = order.firstIndex(of: seat) ?? 0
        let position = ((seatIndex - buttonIndex) % order.count + order.count) % order.count
        return Observation(seat: seat,
                           hole: state.hole(seat),
                           community: state.community,
                           street: state.street,
                           pot: state.pot,
                           toCall: state.toCall(seat),
                           stack: state.stack(seat),
                           currentBet: state.currentBet,
                           minimumRaise: minimumRaiseTotal(in: state),
                           bigBlind: state.currentBigBlind,
                           stacks: state.stacks,
                           committed: state.committed,
                           totalCommitted: state.totalCommitted,
                           folded: state.folded,
                           allIn: state.allIn,
                           activeOpponents: max(0, state.contenders.count - 1),
                           seatOrder: order,
                           dealerSeat: state.dealerSeat,
                           positionFromButton: position)
    }

    // MARK: - Presentation

    public func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation {
        var slots: [TableSlot] = []
        if let own = TableBuilder.ownHandSlot(viewer: viewer, seating: seating, style: .row(overlap: 0.28)) {
            slots.append(own)
        }
        slots += TableBuilder.opponentSlots(seating: seating, viewer: viewer)
        slots.append(TableSlot(zone: .community,
                               style: .row(overlap: 0.0),
                               anchor: .centre(order: 0),
                               titleKey: "zone.community",
                               prominence: 1.5))

        var callouts: [TableCallout] = []
        callouts.append(TableCallout(id: "pot",
                                     labelKey: "callout.pot",
                                     arguments: [String(state.pot)],
                                     emphasis: .primary))
        callouts.append(TableCallout(id: "street",
                                     labelKey: state.street.localizationKey,
                                     emphasis: .secondary))
        callouts.append(TableCallout(id: "blinds",
                                     labelKey: "callout.blinds",
                                     arguments: [String(state.currentSmallBlind), String(state.currentBigBlind)]))
        if let viewer, state.toCall(viewer) > 0, state.activeSeat == viewer {
            callouts.append(TableCallout(id: "tocall",
                                         labelKey: "callout.toCall",
                                         arguments: [String(state.toCall(viewer))],
                                         emphasis: .alert))
        }

        var states: [SeatID: String] = [:]
        for seat in state.seatOrder {
            if state.eliminated.contains(seat) { states[seat] = "state.out" }
            else if state.folded.contains(seat) { states[seat] = "state.folded" }
            else if state.allIn.contains(seat) { states[seat] = "state.allIn" }
            else if (state.committed[seat] ?? 0) > 0 { states[seat] = "state.in" }
        }

        // Chips in front of each seat on this street: the number people actually
        // read at a poker table.
        let wagers = state.committed.filter { $0.value > 0 }
        let seats = TableBuilder.seatStatuses(seating: seating,
                                              board: state.board,
                                              activeSeat: state.activeSeat,
                                              dealer: state.dealerSeat,
                                              scores: state.stacks,
                                              scoreLabelKey: "label.chips",
                                              states: states,
                                              wagers: wagers)

        let actions = viewer.flatMap { seat -> [ActionToken]? in
            guard state.activeSeat == seat else { return nil }
            return legalActions(in: state, for: seat).map { token(for: $0, in: state) }
        } ?? []

        return TablePresentation(gameID: Self.gameID,
                                 viewer: viewer,
                                 board: state.board.redacted(for: viewer),
                                 slots: slots,
                                 seats: seats,
                                 callouts: callouts,
                                 actions: actions,
                                 playableCards: [],
                                 activeSeat: state.activeSeat,
                                 roundNumber: state.roundNumber,
                                 phaseKey: state.street.localizationKey,
                                 phaseArguments: [],
                                 result: state.finalResult)
    }

    // MARK: - Hints

    public func hint(for state: State, seat: SeatID) -> Hint? {
        guard state.activeSeat == seat else { return nil }
        let hole = state.hole(seat)
        let community = state.community
        let toCall = state.toCall(seat)
        let pot = state.pot

        if state.street == .preflop {
            guard hole.count == 2, let first = hole.first?.rank, let second = hole.last?.rank else { return nil }
            let suited = hole[0].suit == hole[1].suit
            if first == second {
                return Hint(messageKey: "hint.poker.pair",
                            english: "A pocket pair is already a made hand. It plays well against one or two opponents and badly against five.")
            }
            if suited {
                return Hint(messageKey: "hint.poker.suited",
                            english: "Suited cards make a flush about one time in sixteen by the river — worth a call in position, not worth a big raise.")
            }
            return Hint(messageKey: "hint.poker.offsuit",
                        english: "Unpaired, unsuited cards need help from the board. Position matters more than the cards here.")
        }

        guard hole.count + community.count >= 5 else { return nil }
        let rank = PokerEvaluator.best(from: hole + community)
        if toCall > 0 {
            let odds = Int((Double(toCall) / Double(max(1, pot + toCall))) * 100)
            return Hint(messageKey: "hint.poker.potOdds",
                        arguments: [rank.category.localizationKey, String(odds)],
                        english: "You hold \(rank.category.englishName.lowercased()). Calling \(toCall) into \(pot) means you need to win about \(odds)% of the time to break even.",
                        cards: rank.cards.map(\.id))
        }
        return Hint(messageKey: "hint.poker.made",
                    arguments: [rank.category.localizationKey],
                    english: "You hold \(rank.category.englishName.lowercased()). Betting is how you get paid; checking a strong hand only helps opponents catch up for free.",
                    cards: rank.cards.map(\.id))
    }
}

public enum PokerStatistics {
    public static let handsPlayed = "poker.handsPlayed"
    public static let handsWon = "poker.handsWon"
    public static let biggestPot = "poker.biggestPot"
    public static let bestHand = "poker.bestHand"
    public static let showdownsWon = "poker.showdownsWon"
    public static let finalStack = "poker.finalStack"
}

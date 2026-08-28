import Foundation
import DeckCore
import DeckGames

/// The Spades opponent.
///
/// Bidding is the game: an agent that counts its tricks honestly and then plays
/// to that number beats one that simply takes everything it can, because bags
/// cost a hundred points and nobody notices them arriving.
public enum SpadesAgent {

    public static func choose(observation: SpadesRules.Observation,
                              legalActions: [SpadesRules.Action],
                              profile: AIProfile,
                              generator: inout SeededGenerator) -> SpadesRules.Action? {
        guard !legalActions.isEmpty else { return nil }
        guard legalActions.count > 1 else { return legalActions[0] }

        switch observation.phase {
        case .bidding:
            return chooseBid(observation: observation, legalActions: legalActions,
                             profile: profile, generator: &generator)
        case .playing:
            return choosePlay(observation: observation, legalActions: legalActions,
                              profile: profile, generator: &generator)
        case .scoring:
            return legalActions.first
        }
    }

    /// Counts the tricks the hand should take, then bids that.
    static func estimateTricks(hand: [Card]) -> Double {
        var counts: [Suit: [Card]] = [:]
        for card in hand {
            guard let suit = card.suit else { continue }
            counts[suit, default: []].append(card)
        }
        var tricks = 0.0
        let spades = counts[.spades] ?? []

        // Every spade past the third is very likely a trick.
        if spades.count > 3 { tricks += Double(spades.count - 3) }
        for card in spades {
            guard let rank = card.rank else { continue }
            switch rank {
            case .ace: tricks += 1
            case .king: tricks += spades.count >= 2 ? 0.9 : 0.5
            case .queen: tricks += spades.count >= 3 ? 0.7 : 0.3
            case .jack: tricks += spades.count >= 4 ? 0.4 : 0.1
            default: break
            }
        }
        // Side-suit aces are near-certain; kings depend on protection.
        for (suit, cards) in counts where suit != .spades {
            for card in cards {
                guard let rank = card.rank else { continue }
                switch rank {
                case .ace: tricks += 0.95
                case .king: tricks += cards.count >= 2 ? 0.6 : 0.25
                case .queen: tricks += cards.count >= 3 ? 0.25 : 0.05
                default: break
                }
            }
        }
        return tricks
    }

    private static func chooseBid(observation: SpadesRules.Observation,
                                  legalActions: [SpadesRules.Action],
                                  profile: AIProfile,
                                  generator: inout SeededGenerator) -> SpadesRules.Action? {
        let estimate = estimateTricks(hand: observation.hand)
        // A hand with no high spades and no aces is a nil candidate.
        let highSpades = observation.hand.filter {
            $0.suit == .spades && ($0.rank?.rawValue ?? 0) >= Rank.queen.rawValue
        }.count
        let aces = observation.hand.filter { $0.rank == .ace }.count
        let spadeCount = observation.hand.filter { $0.suit == .spades }.count
        let nilViable = highSpades == 0 && aces == 0 && spadeCount <= 3 && estimate < 1.6

        var moves: [ScoredMove<SpadesRules.Action>] = []
        for action in legalActions {
            guard case let .bid(value) = action else { continue }
            var score: Double
            if value == 0 {
                score = nilViable ? 6.0 + profile.riskTolerance * 5.0 : -14.0
                // Behind on score, a nil is a way back into the game.
                let ours = observation.teamScores[0] ?? 0
                let theirs = observation.teamScores[1] ?? 0
                if nilViable && ours < theirs - 100 { score += 4.0 }
            } else {
                // Closeness to the honest count, with aggression nudging it up.
                let target = estimate + (profile.aggression - 0.5) * 1.4
                score = 10.0 - abs(Double(value) - target) * 3.0
                // Underbidding piles up bags, so it is punished a little harder
                // than overbidding by a cautious agent.
                if Double(value) < target - 1 { score -= (1.0 - profile.riskTolerance) * 2.0 }
            }
            moves.append(ScoredMove(action: action, score: score, reason: "bid \(value)"))
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }

    private static func choosePlay(observation: SpadesRules.Observation,
                                   legalActions: [SpadesRules.Action],
                                   profile: AIProfile,
                                   generator: inout SeededGenerator) -> SpadesRules.Action? {
        let seat = observation.seat
        let bid = observation.bids[seat] ?? 0
        let won = observation.tricksWon[seat] ?? 0
        let partnerBid = observation.partner.flatMap { observation.bids[$0] } ?? 0
        let partnerWon = observation.partner.flatMap { observation.tricksWon[$0] } ?? 0
        let teamNeeds = max(0, (bid + partnerBid) - (won + partnerWon))
        let onNil = bid == 0
        let partnerOnNil = partnerBid == 0 && observation.partner != nil

        // Who is winning the trick so far.
        var winningSeat: SeatID?
        var winningValue = -1
        var winningIsSpade = false
        for entry in observation.trickPlays {
            guard let suit = entry.card.suit, let rank = entry.card.rank else { continue }
            let isSpade = suit == .spades
            guard isSpade || suit == observation.ledSuit else { continue }
            if (isSpade && !winningIsSpade) || (isSpade == winningIsSpade && rank.rawValue > winningValue) {
                winningSeat = entry.seat
                winningValue = rank.rawValue
                winningIsSpade = isSpade
            }
        }
        let partnerIsWinning = winningSeat != nil && winningSeat == observation.partner

        var moves: [ScoredMove<SpadesRules.Action>] = []
        for action in legalActions {
            guard case let .play(cardID) = action,
                  let card = observation.hand.first(where: { $0.id == cardID }),
                  let rank = card.rank, let suit = card.suit else { continue }

            let isSpade = suit == .spades
            let wouldWin: Bool
            if observation.trickPlays.isEmpty {
                wouldWin = true
            } else if isSpade && !winningIsSpade {
                wouldWin = true
            } else if isSpade == winningIsSpade && suit == (winningIsSpade ? .spades : observation.ledSuit) {
                wouldWin = rank.rawValue > winningValue
            } else {
                wouldWin = false
            }

            var score = 0.0
            if onNil {
                // Never win a trick. Play the highest card that still loses.
                score = wouldWin ? -60.0 : 12.0 + Double(rank.rawValue) * 0.8
                if isSpade && wouldWin { score -= 20 }
            } else if partnerOnNil && partnerIsWinning {
                // Cover the partner: take the trick off them.
                score = wouldWin ? 30.0 : -8.0
            } else if teamNeeds > 0 {
                score = wouldWin ? 16.0 - Double(rank.rawValue) * 0.4 : Double(15 - rank.rawValue) * 0.6
                if wouldWin && partnerIsWinning { score -= 12.0 }
                if isSpade && !wouldWin { score -= 10.0 }
            } else {
                // Contract already made: every extra trick is a bag.
                score = wouldWin ? -14.0 : 10.0 + Double(rank.rawValue) * 0.5
                if isSpade && wouldWin { score -= 6.0 }
            }
            // Spending a spade on a trick you could win with a side card is waste.
            if isSpade && observation.ledSuit != nil && observation.ledSuit != .spades && !wouldWin {
                score -= 14.0
            }
            score += (profile.aggression - 0.5) * (wouldWin ? 3.0 : -3.0)
            moves.append(ScoredMove(action: action, score: score, reason: card.token))
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }
}

/// The Euchre opponent.
///
/// Bidding is a count of bowers and aces against the suit on offer, with the
/// dealer's position taken into account — ordering it up when the dealer is your
/// partner hands them a card, and when it is not, it hands the enemy one.
public enum EuchreAgent {

    public static func choose(observation: EuchreRules.Observation,
                              legalActions: [EuchreRules.Action],
                              profile: AIProfile,
                              generator: inout SeededGenerator) -> EuchreRules.Action? {
        guard !legalActions.isEmpty else { return nil }
        guard legalActions.count > 1 else { return legalActions[0] }

        switch observation.phase {
        case .bidRoundOne, .bidRoundTwo:
            return chooseBid(observation: observation, legalActions: legalActions,
                             profile: profile, generator: &generator)
        case .dealerDiscard:
            return chooseDiscard(observation: observation, legalActions: legalActions,
                                 profile: profile, generator: &generator)
        case .playing:
            return choosePlay(observation: observation, legalActions: legalActions,
                              profile: profile, generator: &generator)
        case .scoring:
            return legalActions.first
        }
    }

    /// Expected tricks if `suit` were trump.
    static func handStrength(hand: [Card], trump: Suit) -> Double {
        var strength = 0.0
        for card in hand {
            let trumpValue = EuchreRules.trumpValue(card, trump: trump)
            switch trumpValue {
            case 100: strength += 1.0          // right bower
            case 99: strength += 0.9           // left bower
            case Rank.ace.rawValue: strength += 0.75
            case Rank.king.rawValue: strength += 0.55
            case Rank.queen.rawValue: strength += 0.35
            case Rank.jack.rawValue, Rank.ten.rawValue, Rank.nine.rawValue: strength += 0.2
            default:
                if card.rank == .ace { strength += 0.5 }   // off-suit ace
            }
        }
        // Being void in a side suit means you can trump in.
        var suits: Set<Suit> = []
        for card in hand {
            if let effective = EuchreRules.effectiveSuit(card, trump: trump) { suits.insert(effective) }
        }
        strength += Double(4 - suits.count) * 0.3
        return strength
    }

    private static func chooseBid(observation: EuchreRules.Observation,
                                  legalActions: [EuchreRules.Action],
                                  profile: AIProfile,
                                  generator: inout SeededGenerator) -> EuchreRules.Action? {
        let dealerIsPartner = observation.dealerSeat == observation.partner
        let dealerIsSelf = observation.dealerSeat == observation.seat

        var moves: [ScoredMove<EuchreRules.Action>] = []
        for action in legalActions {
            switch action {
            case let .orderUp(alone):
                guard let upcard = observation.upcard, let suit = upcard.suit else { continue }
                var hand = observation.hand
                // Ordering it up puts the card in the dealer's hand, which helps
                // them — good if that is your partner, bad if it is not.
                if dealerIsSelf { hand.append(upcard) }
                var strength = handStrength(hand: hand, trump: suit)
                if dealerIsPartner { strength += 0.4 }
                else if !dealerIsSelf { strength -= 0.5 }
                let threshold = alone ? 4.2 : 2.6
                var score = (strength - threshold) * 4.0
                score += profile.aggression * (alone ? 0.8 : 1.4)
                if alone { score -= (1.0 - profile.riskTolerance) * 2.0 }
                moves.append(ScoredMove(action: action, score: score, reason: "order \(suit.token)"))

            case let .callTrump(suit, alone):
                var strength = handStrength(hand: observation.hand, trump: suit)
                // Naming the same colour as the turned-down suit is a known
                // strong play, because the left bower has moved.
                if suit == EuchreRules.sameColour(as: observation.upcard?.suit ?? suit) { strength += 0.3 }
                let threshold = alone ? 4.2 : 2.7
                var score = (strength - threshold) * 4.0
                score += profile.aggression * (alone ? 0.6 : 1.2)
                if alone { score -= (1.0 - profile.riskTolerance) * 2.0 }
                moves.append(ScoredMove(action: action, score: score, reason: "call \(suit.token)"))

            case .passBid:
                moves.append(ScoredMove(action: action, score: 0.0, reason: "pass"))

            default:
                continue
            }
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }

    private static func chooseDiscard(observation: EuchreRules.Observation,
                                      legalActions: [EuchreRules.Action],
                                      profile: AIProfile,
                                      generator: inout SeededGenerator) -> EuchreRules.Action? {
        guard let trump = observation.trump else { return legalActions.first }
        var suitCounts: [Suit: Int] = [:]
        for card in observation.hand {
            guard let effective = EuchreRules.effectiveSuit(card, trump: trump) else { continue }
            suitCounts[effective, default: 0] += 1
        }
        var moves: [ScoredMove<EuchreRules.Action>] = []
        for action in legalActions {
            guard case let .discard(cardID) = action,
                  let card = observation.hand.first(where: { $0.id == cardID }),
                  let effective = EuchreRules.effectiveSuit(card, trump: trump) else { continue }
            var score = 0.0
            if effective == trump {
                score -= 40.0        // never throw trump
            } else {
                score += Double(15 - (card.rank?.rawValue ?? 9))
                // Throwing your last card in a suit makes you void: worth a lot.
                if suitCounts[effective] == 1 { score += 8.0 }
                if card.rank == .ace { score -= 12.0 }
            }
            moves.append(ScoredMove(action: action, score: score, reason: card.token))
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }

    private static func choosePlay(observation: EuchreRules.Observation,
                                   legalActions: [EuchreRules.Action],
                                   profile: AIProfile,
                                   generator: inout SeededGenerator) -> EuchreRules.Action? {
        guard let trump = observation.trump else { return legalActions.first }

        // Who currently holds the trick.
        var winningSeat: SeatID?
        var winningValue = -1
        var winningIsTrump = false
        for entry in observation.trickPlays {
            let effective = EuchreRules.effectiveSuit(entry.card, trump: trump)
            let isTrump = effective == trump
            guard isTrump || effective == observation.ledSuit else { continue }
            let value = isTrump ? EuchreRules.trumpValue(entry.card, trump: trump)
                                : EuchreRules.plainValue(entry.card)
            if (isTrump && !winningIsTrump) || (isTrump == winningIsTrump && value > winningValue) {
                winningSeat = entry.seat
                winningValue = value
                winningIsTrump = isTrump
            }
        }
        let partnerIsWinning = winningSeat != nil && winningSeat == observation.partner
        let weAreMakers = observation.makerSeat == observation.seat
            || observation.makerSeat == observation.partner

        var moves: [ScoredMove<EuchreRules.Action>] = []
        for action in legalActions {
            guard case let .play(cardID) = action,
                  let card = observation.hand.first(where: { $0.id == cardID }) else { continue }
            let effective = EuchreRules.effectiveSuit(card, trump: trump)
            let isTrump = effective == trump
            let value = isTrump ? EuchreRules.trumpValue(card, trump: trump) : EuchreRules.plainValue(card)

            let wouldWin: Bool
            if observation.trickPlays.isEmpty { wouldWin = true }
            else if isTrump && !winningIsTrump { wouldWin = true }
            else if isTrump == winningIsTrump && (isTrump || effective == observation.ledSuit) {
                wouldWin = value > winningValue
            } else { wouldWin = false }

            var score = 0.0
            if partnerIsWinning && !observation.trickPlays.isEmpty {
                // Do not take your partner's trick; throw the cheapest thing.
                score = wouldWin ? -12.0 : 10.0 - Double(value) * 0.4
                if isTrump && !wouldWin { score -= 10.0 }
            } else if wouldWin {
                score = 14.0 - Double(value) * 0.25
                if weAreMakers { score += 3.0 }
                // Winning with the cheapest card that does the job.
                if isTrump && value >= 99 && observation.trickNumber < 4 { score -= 3.0 }
            } else {
                score = Double(15 - value) * 0.5
                if isTrump { score -= 12.0 }        // never waste trump on a lost trick
            }
            score += (profile.aggression - 0.5) * (wouldWin ? 2.0 : -2.0)
            moves.append(ScoredMove(action: action, score: score, reason: card.token))
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }
}

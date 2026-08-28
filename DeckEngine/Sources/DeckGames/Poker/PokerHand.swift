import Foundation
import DeckCore

/// The strength of a five-card poker hand.
///
/// Comparison is total and exact: category first, then the tiebreakers in
/// descending significance. Two hands compare equal only when they would split
/// a pot at a real table, which is what the side-pot code relies on.
public struct PokerHandRank: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public enum Category: Int, Comparable, Codable, Sendable, CaseIterable {
        case highCard = 0
        case pair = 1
        case twoPair = 2
        case threeOfAKind = 3
        case straight = 4
        case flush = 5
        case fullHouse = 6
        case fourOfAKind = 7
        case straightFlush = 8

        public static func < (lhs: Category, rhs: Category) -> Bool { lhs.rawValue < rhs.rawValue }

        public var localizationKey: String { "poker.hand.\(self)" }

        public var englishName: String {
            switch self {
            case .highCard: return "High Card"
            case .pair: return "Pair"
            case .twoPair: return "Two Pair"
            case .threeOfAKind: return "Three of a Kind"
            case .straight: return "Straight"
            case .flush: return "Flush"
            case .fullHouse: return "Full House"
            case .fourOfAKind: return "Four of a Kind"
            case .straightFlush: return "Straight Flush"
            }
        }
    }

    public let category: Category
    /// Rank values, most significant first. Aces are 14 except in the wheel,
    /// where the straight's high card is 5.
    public let tiebreakers: [Int]
    /// The exact five cards that make the hand, best first.
    public let cards: [Card]

    public init(category: Category, tiebreakers: [Int], cards: [Card]) {
        self.category = category
        self.tiebreakers = tiebreakers
        self.cards = cards
    }

    /// A royal flush is not a separate category — it is the top straight flush.
    public var isRoyalFlush: Bool {
        category == .straightFlush && tiebreakers.first == Rank.ace.rawValue
    }

    public static func < (lhs: PokerHandRank, rhs: PokerHandRank) -> Bool {
        if lhs.category != rhs.category { return lhs.category < rhs.category }
        for (left, right) in zip(lhs.tiebreakers, rhs.tiebreakers) where left != right {
            return left < right
        }
        return false
    }

    /// Equality here means "would split the pot": the cards themselves are not
    /// compared, only the strength.
    public static func == (lhs: PokerHandRank, rhs: PokerHandRank) -> Bool {
        lhs.category == rhs.category && lhs.tiebreakers == rhs.tiebreakers
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(category)
        hasher.combine(tiebreakers)
    }

    public var description: String {
        "\(category.englishName) \(tiebreakers) [\(cards.map(\.token).joined(separator: " "))]"
    }
}

/// Evaluates poker hands.
///
/// Written for clarity over raw speed: it builds the best five from any number
/// of cards by examining rank and suit counts directly rather than enumerating
/// all 21 combinations, which is both faster and easier to reason about.
public enum PokerEvaluator {

    /// Best five-card hand from five, six or seven cards.
    public static func best(from cards: [Card]) -> PokerHandRank {
        let usable = cards.filter { !$0.isJoker }
        precondition(usable.count >= 5, "Poker needs at least five cards to evaluate")

        // Rank buckets, ace high.
        var byRank: [Int: [Card]] = [:]
        var bySuit: [Suit: [Card]] = [:]
        for card in usable {
            guard let rank = card.rank, let suit = card.suit else { continue }
            byRank[rank.rawValue, default: []].append(card)
            bySuit[suit, default: []].append(card)
        }

        var candidates: [PokerHandRank] = []

        // --- Flush family -----------------------------------------------------
        if let flushSuit = bySuit.first(where: { $0.value.count >= 5 })?.key,
           let suited = bySuit[flushSuit] {
            let sortedSuited = suited.sorted { rankValue($0) > rankValue($1) }
            if let straightFlush = straight(in: sortedSuited) {
                candidates.append(PokerHandRank(category: .straightFlush,
                                                tiebreakers: [straightFlush.high],
                                                cards: straightFlush.cards))
            }
            let topFive = Array(sortedSuited.prefix(5))
            candidates.append(PokerHandRank(category: .flush,
                                            tiebreakers: topFive.map(rankValue),
                                            cards: topFive))
        }

        // --- Straight ---------------------------------------------------------
        let sortedAll = usable.sorted { rankValue($0) > rankValue($1) }
        if let plain = straight(in: sortedAll) {
            candidates.append(PokerHandRank(category: .straight,
                                            tiebreakers: [plain.high],
                                            cards: plain.cards))
        }

        // --- Rank-count family ------------------------------------------------
        // Groups sorted by size, then by rank: four of a kind first, then trips,
        // then pairs, each highest-first.
        let groups = byRank
            .map { (rank: $0.key, cards: $0.value) }
            .sorted { lhs, rhs in
                if lhs.cards.count != rhs.cards.count { return lhs.cards.count > rhs.cards.count }
                return lhs.rank > rhs.rank
            }

        if let quad = groups.first(where: { $0.cards.count == 4 }) {
            let kickers = sortedAll.filter { rankValue($0) != quad.rank }.prefix(1)
            candidates.append(PokerHandRank(category: .fourOfAKind,
                                            tiebreakers: [quad.rank] + kickers.map(rankValue),
                                            cards: Array(quad.cards.prefix(4)) + kickers))
        }

        let trips = groups.filter { $0.cards.count == 3 }
        let pairs = groups.filter { $0.cards.count == 2 }

        if let topTrip = trips.first {
            // A full house can be trips plus a pair, or trips plus a second set
            // of trips (using two of them as the pair).
            let pairCandidates = pairs.map(\.rank) + trips.dropFirst().map(\.rank)
            if let bestPair = pairCandidates.max() {
                let pairCards = byRank[bestPair]?.prefix(2) ?? []
                candidates.append(PokerHandRank(category: .fullHouse,
                                                tiebreakers: [topTrip.rank, bestPair],
                                                cards: Array(topTrip.cards.prefix(3)) + Array(pairCards)))
            }
            let kickers = sortedAll.filter { rankValue($0) != topTrip.rank }.prefix(2)
            candidates.append(PokerHandRank(category: .threeOfAKind,
                                            tiebreakers: [topTrip.rank] + kickers.map(rankValue),
                                            cards: Array(topTrip.cards.prefix(3)) + kickers))
        }

        if pairs.count >= 2 {
            let high = pairs[0]
            let low = pairs[1]
            let kickers = sortedAll
                .filter { rankValue($0) != high.rank && rankValue($0) != low.rank }
                .prefix(1)
            candidates.append(PokerHandRank(category: .twoPair,
                                            tiebreakers: [high.rank, low.rank] + kickers.map(rankValue),
                                            cards: Array(high.cards.prefix(2)) + Array(low.cards.prefix(2)) + kickers))
        }

        if let onlyPair = pairs.first, trips.isEmpty {
            let kickers = sortedAll.filter { rankValue($0) != onlyPair.rank }.prefix(3)
            candidates.append(PokerHandRank(category: .pair,
                                            tiebreakers: [onlyPair.rank] + kickers.map(rankValue),
                                            cards: Array(onlyPair.cards.prefix(2)) + kickers))
        }

        let topFive = Array(sortedAll.prefix(5))
        candidates.append(PokerHandRank(category: .highCard,
                                        tiebreakers: topFive.map(rankValue),
                                        cards: topFive))

        // `max` compares by strength, which is exactly the ordering we want.
        return candidates.max() ?? PokerHandRank(category: .highCard,
                                                 tiebreakers: topFive.map(rankValue),
                                                 cards: topFive)
    }

    /// The best straight inside a set of cards, or nil.
    ///
    /// Handles the wheel: A-2-3-4-5 is a straight with the five as its high card,
    /// which is why an ace-low straight loses to 2-3-4-5-6.
    static func straight(in sortedDescending: [Card]) -> (high: Int, cards: [Card])? {
        var byRank: [Int: Card] = [:]
        for card in sortedDescending {
            guard let rank = card.rank else { continue }
            if byRank[rank.rawValue] == nil { byRank[rank.rawValue] = card }
        }
        // The ace also plays as a one at the bottom of the wheel.
        if let ace = byRank[Rank.ace.rawValue] { byRank[1] = ace }

        var high = Rank.ace.rawValue
        while high >= 5 {
            let needed = [high, high - 1, high - 2, high - 3, high - 4]
            if needed.allSatisfy({ byRank[$0] != nil }) {
                return (high, needed.compactMap { byRank[$0] })
            }
            high -= 1
        }
        return nil
    }

    private static func rankValue(_ card: Card) -> Int { card.rank?.rawValue ?? 0 }

    /// Best hand from two hole cards plus the board. Hold'em lets a player use
    /// any five of the seven, including playing the board.
    public static func bestHoldem(hole: [Card], board: [Card]) -> PokerHandRank {
        best(from: hole + board)
    }

    /// Compares two hold'em hands. Returns nil when they tie.
    public static func compare(_ lhs: PokerHandRank, _ rhs: PokerHandRank) -> Bool? {
        if lhs > rhs { return true }
        if lhs < rhs { return false }
        return nil
    }
}

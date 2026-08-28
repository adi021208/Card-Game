import Foundation
import DeckCore

/// A meld: three or more cards of the same rank, or three or more in sequence in
/// one suit.
public enum MeldKind: String, Codable, Sendable {
    case set
    case run
}

public struct Meld: Hashable, Codable, Sendable {
    public var kind: MeldKind
    public var cards: [CardID]

    public init(kind: MeldKind, cards: [CardID]) {
        self.kind = kind
        self.cards = cards
    }
}

/// The best way to break a hand into melds, with what is left over.
public struct MeldSolution: Sendable {
    public var melds: [[Card]]
    public var deadwood: [Card]
    public var deadwoodPoints: Int

    public init(melds: [[Card]], deadwood: [Card], deadwoodPoints: Int) {
        self.melds = melds
        self.deadwood = deadwood
        self.deadwoodPoints = deadwoodPoints
    }

    public var isGin: Bool { deadwood.isEmpty }
    public func meldIDs() -> [Meld] {
        melds.map { cards in
            let sameRank = Set(cards.compactMap(\.rank)).count == 1
            return Meld(kind: sameRank ? .set : .run, cards: cards.map(\.id))
        }
    }
}

/// Finds the arrangement of a rummy hand with the least deadwood.
///
/// Greedily taking the longest melds is a well-known way to get this wrong: a
/// four-card run can be worth less than a three-card run plus a set that reuses
/// one of its cards. This searches every combination of disjoint melds, which is
/// cheap at rummy hand sizes and always exact.
public enum MeldSolver {

    /// Every valid meld that can be formed from the hand, including sub-runs.
    public static func enumerateMelds(_ hand: [Card]) -> [[Card]] {
        var melds: [[Card]] = []

        // Sets: three or four of a rank.
        var byRank: [Rank: [Card]] = [:]
        for card in hand {
            guard let rank = card.rank else { continue }
            byRank[rank, default: []].append(card)
        }
        for (_, cards) in byRank.sorted(by: { $0.key < $1.key }) where cards.count >= 3 {
            let sorted = cards.sorted { ($0.suit?.rawValue ?? 0) < ($1.suit?.rawValue ?? 0) }
            if sorted.count == 3 {
                melds.append(sorted)
            } else {
                melds.append(sorted)
                // Every three-card subset of a four-card set is also a meld, and
                // sometimes the better one.
                for excluded in 0..<sorted.count {
                    var subset = sorted
                    subset.remove(at: excluded)
                    melds.append(subset)
                }
            }
        }

        // Runs: three or more in sequence in one suit. Aces are low in rummy.
        var bySuit: [Suit: [Card]] = [:]
        for card in hand {
            guard let suit = card.suit else { continue }
            bySuit[suit, default: []].append(card)
        }
        for (_, cards) in bySuit.sorted(by: { $0.key < $1.key }) {
            // Duplicate ranks cannot both sit in one run; keep one of each.
            var uniqueByValue: [Int: Card] = [:]
            for card in cards {
                guard let rank = card.rank else { continue }
                let value = rank.aceLowValue
                if uniqueByValue[value] == nil { uniqueByValue[value] = card }
            }
            let values = uniqueByValue.keys.sorted()
            guard values.count >= 3 else { continue }
            for start in 0..<values.count {
                guard let first = uniqueByValue[values[start]] else { continue }
                var sequence: [Card] = [first]
                var previous = values[start]
                for index in (start + 1)..<values.count {
                    guard values[index] == previous + 1, let next = uniqueByValue[values[index]] else { break }
                    sequence.append(next)
                    previous = values[index]
                    if sequence.count >= 3 { melds.append(sequence) }
                }
            }
        }
        return melds
    }

    /// The lowest-deadwood arrangement of the hand.
    public static func best(_ hand: [Card],
                            points: (Card) -> Int = CardScoring.deadwoodPoints) -> MeldSolution {
        let melds = enumerateMelds(hand)
        guard !melds.isEmpty else {
            return MeldSolution(melds: [],
                                deadwood: hand,
                                deadwoodPoints: hand.reduce(0) { $0 + points($1) })
        }

        // Index the hand so each meld becomes a bitmask.
        var index: [CardID: Int] = [:]
        for (position, card) in hand.enumerated() { index[card.id] = position }
        let masks: [Int] = melds.map { meld in
            meld.reduce(0) { partial, card in
                guard let position = index[card.id] else { return partial }
                return partial | (1 << position)
            }
        }
        let cardPoints = hand.map(points)
        let allMask = hand.isEmpty ? 0 : (1 << hand.count) - 1

        var bestMask = 0
        var bestDeadwood = Int.max
        var bestChoice: [Int] = []
        var visited: Set<Int> = []

        func deadwoodValue(for mask: Int) -> Int {
            var total = 0
            for position in 0..<hand.count where mask & (1 << position) == 0 {
                total += cardPoints[position]
            }
            return total
        }

        // Depth-first over every combination of disjoint melds. Each meld is
        // considered once, in index order, so no arrangement is visited twice.
        func search(from start: Int, used: Int, chosen: [Int]) {
            let key = start &* (allMask &+ 1) &+ used
            if visited.contains(key) { return }
            visited.insert(key)

            let deadwood = deadwoodValue(for: used)
            if deadwood < bestDeadwood {
                bestDeadwood = deadwood
                bestMask = used
                bestChoice = chosen
            }
            guard start < masks.count else { return }
            for position in start..<masks.count where masks[position] & used == 0 {
                search(from: position + 1, used: used | masks[position], chosen: chosen + [position])
            }
        }

        search(from: 0, used: 0, chosen: [])

        let chosenMelds = bestChoice.map { melds[$0] }
        var deadwood: [Card] = []
        for (position, card) in hand.enumerated() where bestMask & (1 << position) == 0 {
            deadwood.append(card)
        }
        deadwood.sort { points($0) > points($1) }
        return MeldSolution(melds: chosenMelds,
                            deadwood: deadwood,
                            deadwoodPoints: deadwood.reduce(0) { $0 + points($1) })
    }

    /// Whether a card can be laid off onto an opponent's meld.
    public static func canLayOff(_ card: Card, on meld: [Card]) -> Bool {
        guard meld.count >= 3, let rank = card.rank, let suit = card.suit else { return false }
        let ranks = Set(meld.compactMap(\.rank))
        if ranks.count == 1 {
            // A set takes the fourth card of the same rank.
            return ranks.first == rank && meld.count < 4 && !meld.contains { $0.id == card.id }
        }
        // A run extends at either end, in suit.
        guard meld.allSatisfy({ $0.suit == suit }) else { return false }
        let values = meld.compactMap { $0.rank?.aceLowValue }.sorted()
        guard let low = values.first, let high = values.last else { return false }
        let value = rank.aceLowValue
        return value == low - 1 || value == high + 1
    }

    /// Deadwood after laying every card that will go onto the given melds.
    public static func layOff(deadwood: [Card], onto melds: [[Card]]) -> (remaining: [Card], laidOff: [Card]) {
        var workingMelds = melds
        var remaining: [Card] = []
        var laidOff: [Card] = []
        // Repeat until nothing more fits: extending a run can open the next card.
        var pool = deadwood
        var progressed = true
        while progressed {
            progressed = false
            var stillPooled: [Card] = []
            for card in pool {
                var placed = false
                for index in workingMelds.indices where canLayOff(card, on: workingMelds[index]) {
                    workingMelds[index].append(card)
                    laidOff.append(card)
                    placed = true
                    progressed = true
                    break
                }
                if !placed { stillPooled.append(card) }
            }
            pool = stillPooled
        }
        remaining = pool
        return (remaining, laidOff)
    }
}

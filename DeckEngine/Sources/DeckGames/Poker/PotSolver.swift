import Foundation
import DeckCore

/// One pot and the players entitled to contest it.
public struct Pot: Hashable, Codable, Sendable {
    public var amount: Int
    /// Seats still in the hand that put in at least this pot's level.
    public var contenders: [SeatID]
    /// True for everything after the first pot.
    public var isSidePot: Bool

    public init(amount: Int, contenders: [SeatID], isSidePot: Bool) {
        self.amount = amount
        self.contenders = contenders
        self.isSidePot = isSidePot
    }
}

/// Splits the chips on the table into a main pot and any side pots, and works
/// out who gets what.
///
/// Side pots exist because a short stack can only win as much as they put in
/// from each opponent. Getting this wrong is the classic poker-implementation
/// bug, so it is isolated here and tested on its own.
public enum PotSolver {

    /// Layers the contributions into pots.
    ///
    /// - Parameters:
    ///   - contributions: every seat's total chips in this hand, folded players
    ///     included — their money stays in the pot.
    ///   - contenders: seats that have not folded.
    public static func pots(contributions: [SeatID: Int], contenders: Set<SeatID>) -> [Pot] {
        let positive = contributions.filter { $0.value > 0 }
        guard !positive.isEmpty else { return [] }
        let levels = Set(positive.values).sorted()

        var pots: [Pot] = []
        var previousLevel = 0
        for level in levels {
            var amount = 0
            for (_, contribution) in positive {
                amount += min(contribution, level) - min(contribution, previousLevel)
            }
            guard amount > 0 else {
                previousLevel = level
                continue
            }
            let eligible = contenders
                .filter { (contributions[$0] ?? 0) >= level }
                .sorted()
            // Money nobody can win (everyone who could contest it folded) still
            // has to go somewhere; it is folded into the previous pot.
            if eligible.isEmpty {
                if var last = pots.popLast() {
                    last.amount += amount
                    pots.append(last)
                }
            } else {
                pots.append(Pot(amount: amount, contenders: eligible, isSidePot: !pots.isEmpty))
            }
            previousLevel = level
        }
        return pots
    }

    /// Awards each pot to the strongest hand or hands contesting it.
    ///
    /// - Parameter oddChipOrder: seats in the order chips are handed out when a
    ///   split does not divide evenly — at a real table, the first player left
    ///   of the button.
    public static func award(pots: [Pot],
                             ranks: [SeatID: PokerHandRank],
                             oddChipOrder: [SeatID]) -> [SeatID: Int] {
        var payouts: [SeatID: Int] = [:]
        for pot in pots {
            let ranked = pot.contenders.compactMap { seat -> (SeatID, PokerHandRank)? in
                guard let rank = ranks[seat] else { return nil }
                return (seat, rank)
            }
            guard let best = ranked.map(\.1).max() else {
                // No showdown ranks (everyone else folded): a single contender
                // takes it uncontested.
                if let sole = pot.contenders.first {
                    payouts[sole, default: 0] += pot.amount
                }
                continue
            }
            let winners = ranked.filter { $0.1 == best }.map(\.0)
            guard !winners.isEmpty else { continue }
            let share = pot.amount / winners.count
            var remainder = pot.amount % winners.count
            for seat in winners {
                payouts[seat, default: 0] += share
            }
            // Odd chips go clockwise from the button.
            for seat in oddChipOrder where remainder > 0 {
                if winners.contains(seat) {
                    payouts[seat, default: 0] += 1
                    remainder -= 1
                }
            }
            // If the odd-chip order did not cover every winner, hand the rest to
            // the first winner rather than losing chips off the table.
            if remainder > 0, let first = winners.first {
                payouts[first, default: 0] += remainder
            }
        }
        return payouts
    }

    /// Total chips currently in front of the players.
    public static func total(_ contributions: [SeatID: Int]) -> Int {
        contributions.values.reduce(0, +)
    }
}

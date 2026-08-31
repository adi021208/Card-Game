import Foundation
import DeckCore

/// Shared building blocks for game implementations.
///
/// Everything here is optional convenience — a game can lay out its own table
/// however it likes — but using it means new games inherit consistent seat
/// placement, hand sorting and status reporting for free.
public enum TableBuilder {
    /// Places opponents around the table relative to the viewer, so the person
    /// holding the device is always at the bottom.
    public static func opponentSlots(seating: SeatingPlan,
                                     viewer: SeatID?,
                                     style: PileStyle = .opponentFan) -> [TableSlot] {
        let anchorSeat = viewer ?? seating.ids.first
        guard let anchorSeat, let anchorIndex = seating.index(of: anchorSeat) else { return [] }
        var slots: [TableSlot] = []
        for offset in 1..<max(1, seating.count) {
            let seat = seating.seats[(anchorIndex + offset) % seating.count].id
            slots.append(TableSlot(zone: .hand(seat),
                                   style: style,
                                   anchor: .opponent(offset: offset)))
        }
        return slots
    }

    /// The viewer's own hand along the bottom edge.
    public static func ownHandSlot(viewer: SeatID?, seating: SeatingPlan, style: PileStyle = .fan) -> TableSlot? {
        guard let seat = viewer ?? seating.humanSeats.first?.id else { return nil }
        return TableSlot(zone: .hand(seat), style: style, anchor: .ownHand, prominence: 1.6)
    }

    /// Standard seat readouts. `score` and `stateKey` are supplied by the game.
    public static func seatStatuses(seating: SeatingPlan,
                                    board: Board,
                                    activeSeat: SeatID?,
                                    dealer: SeatID? = nil,
                                    scores: [SeatID: Int] = [:],
                                    scoreLabelKey: String? = nil,
                                    states: [SeatID: String] = [:],
                                    wagers: [SeatID: Int] = [:],
                                    handZone: (SeatID) -> Zone = { Zone.hand($0) }) -> [SeatStatus] {
        seating.seats.map { seat in
            SeatStatus(seat: seat.id,
                       displayName: seat.displayName,
                       avatarID: seat.avatarID,
                       score: scores[seat.id],
                       scoreLabelKey: scoreLabelKey,
                       cardCount: board.count(in: handZone(seat.id)),
                       wager: wagers[seat.id],
                       isActive: activeSeat == seat.id,
                       isDealer: dealer == seat.id,
                       isHuman: seat.isHuman,
                       stateKey: states[seat.id],
                       team: seat.team)
        }
    }
}

/// Card comparators shared by games that keep hands tidy.
public enum HandSort {
    /// Suit then rank — the arrangement most players expect.
    public static func bySuitThenRank(_ lhs: Card, _ rhs: Card) -> Bool {
        switch (lhs.suit, rhs.suit) {
        case let (l?, r?) where l != r:
            return l < r
        default:
            break
        }
        if lhs.isJoker != rhs.isJoker { return rhs.isJoker }
        let leftRank = lhs.rank?.rawValue ?? 0
        let rightRank = rhs.rank?.rawValue ?? 0
        if leftRank != rightRank { return leftRank < rightRank }
        return lhs.id < rhs.id
    }

    /// Rank then suit — better for rummy, where sets matter more than runs.
    public static func byRankThenSuit(_ lhs: Card, _ rhs: Card) -> Bool {
        let leftRank = lhs.rank?.rawValue ?? 0
        let rightRank = rhs.rank?.rawValue ?? 0
        if leftRank != rightRank { return leftRank < rightRank }
        let leftSuit = lhs.suit?.rawValue ?? -1
        let rightSuit = rhs.suit?.rawValue ?? -1
        if leftSuit != rightSuit { return leftSuit < rightSuit }
        return lhs.id < rhs.id
    }
}

/// Standard card point values used by several games for end-of-round counting.
public enum CardScoring {
    /// Ace 1, face cards 10, pips face value. Used by Crazy Eights and Rummy.
    public static func standardPoints(_ card: Card, eightsAre: Int = 50) -> Int {
        guard let rank = card.rank else { return eightsAre }
        switch rank {
        case .eight: return eightsAre
        case .ace: return 1
        case .jack, .queen, .king: return 10
        default: return rank.rawValue
        }
    }

    /// Ace 1, face 10, pips face value, no special eight. Rummy deadwood.
    public static func deadwoodPoints(_ card: Card) -> Int {
        guard let rank = card.rank else { return 0 }
        switch rank {
        case .ace: return 1
        case .jack, .queen, .king: return 10
        default: return rank.rawValue
        }
    }
}

/// Small helper for building stable, seat-qualified action ids.
///
/// Token ids are the replay format, so they must be unique within a position
/// and identical across launches. Prefixing with the seat keeps two players'
/// otherwise-identical moves distinct.
public enum TokenID {
    public static func make(_ seat: SeatID, _ verb: String, _ parts: [String] = []) -> String {
        ([String(seat.rawValue), verb] + parts).joined(separator: "/")
    }

    public static func make(_ seat: SeatID, _ verb: String, card: CardID) -> String {
        make(seat, verb, [String(card.rawValue)])
    }

    public static func make(_ seat: SeatID, _ verb: String, cards: [CardID]) -> String {
        make(seat, verb, cards.map { String($0.rawValue) })
    }
}

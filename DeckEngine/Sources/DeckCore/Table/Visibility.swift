import Foundation

/// Who is permitted to know the face of a card.
///
/// This is the load-bearing type for Pass & Play. Privacy in DECK is never
/// "draw something on top of the card" — the state itself records permission,
/// and the render pipeline physically cannot produce a face the viewer is not
/// entitled to see (`Board.redacted(for:)`).
public indirect enum Visibility: Hashable, Codable, Sendable {
    /// Face-up on the table. Everyone at the table sees it.
    case everyone
    /// Private to a set of seats. One seat for a normal hand; several for
    /// partnership games where partners share information by rule.
    case seats(Set<SeatID>)
    /// Face-down and unknown to everybody, including the owner. Draw piles,
    /// undealt stock, face-down tableau cards.
    case hidden
    /// A peek: visible to `to` right now, and reverting to `restoring` when the
    /// peek ends. Used for Cheat challenges, Klondike hints and boss reveals.
    case temporarilyRevealed(to: Set<SeatID>, restoring: Visibility)

    /// Whether a given viewer may see the face. A `nil` seat is the "no viewer"
    /// state used during the pass handshake and by screenshot/backgrounding
    /// protection: nothing private is legible to nobody.
    public func canSee(_ seat: SeatID?) -> Bool {
        switch self {
        case .everyone:
            return true
        case .hidden:
            return false
        case let .seats(allowed):
            guard let seat else { return false }
            return allowed.contains(seat)
        case let .temporarilyRevealed(allowed, restoring):
            guard let seat else { return false }
            return allowed.contains(seat) || restoring.canSee(seat)
        }
    }

    /// Seats that can currently see the card. Empty for `.hidden`.
    public func audience(among all: [SeatID]) -> Set<SeatID> {
        Set(all.filter { canSee($0) })
    }

    /// Ends any temporary reveal, restoring the underlying permission.
    public var settled: Visibility {
        if case let .temporarilyRevealed(_, restoring) = self { return restoring.settled }
        return self
    }

    /// Convenience for a single owner's private card.
    public static func onlySeat(_ seat: SeatID) -> Visibility { .seats([seat]) }

    public var isPrivate: Bool {
        switch self {
        case .everyone: return false
        case .hidden, .seats, .temporarilyRevealed: return true
        }
    }
}

/// A card as delivered to one specific viewer.
///
/// Views never receive `Card` directly — they receive `VisibleCard`, so a card
/// the viewer may not see simply *has no face to draw*. This is what makes the
/// privacy guarantee structural rather than cosmetic, and it is also why
/// VoiceOver cannot leak a hidden card: the accessibility label is derived from
/// this same value.
public enum VisibleCard: Hashable, Sendable, Identifiable {
    case known(Card)
    case concealed(CardID)

    public var id: CardID {
        switch self {
        case let .known(card): return card.id
        case let .concealed(id): return id
        }
    }

    public var card: Card? {
        if case let .known(card) = self { return card }
        return nil
    }

    public var isKnown: Bool { card != nil }

    /// Debug/test description. Concealed cards deliberately reveal nothing but
    /// their identity, which the viewer already knows from the layout.
    public var token: String {
        switch self {
        case let .known(card): return card.token
        case .concealed: return "??"
        }
    }
}

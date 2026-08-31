import Foundation

/// The role a pile plays in a game. Games compose these rather than inventing
/// their own storage, so animation, accessibility and persistence work the same
/// way in every game in the library.
public enum ZoneKind: String, Codable, CaseIterable, Sendable {
    /// A player's hand.
    case hand
    /// Face-down pile cards are drawn from.
    case stock
    /// Face-up pile cards are discarded to.
    case discard
    /// Klondike's turned-over stock.
    case waste
    /// Solitaire build piles.
    case tableau
    /// Solitaire ordered ace-to-king piles.
    case foundation
    /// FreeCell's single-card holding cells.
    case freeCell
    /// The cards currently in play for a trick.
    case trick
    /// Cards won in tricks, kept for scoring.
    case captured
    /// Shared face-up cards (the poker board).
    case community
    /// Melds laid down in rummy games.
    case meld
    /// Cards being passed between players (Hearts).
    case exchange
    /// Cards temporarily out of play (burned, set aside).
    case reserve

    /// Whether cards in this kind of pile are ordered top-to-bottom in a way the
    /// player can see through. Drives the default renderer.
    public var isStacked: Bool {
        switch self {
        case .stock, .discard, .waste, .captured, .reserve, .foundation: return true
        case .hand, .tableau, .freeCell, .trick, .community, .meld, .exchange: return false
        }
    }
}

/// Identifies one pile on the table.
///
/// A zone is `(kind, owner, index)`: `tableau #3`, `hand of seat 2`,
/// `foundation #0`. Games address piles through this rather than through
/// stored references, which keeps game state a pure value type.
public struct Zone: Hashable, Codable, Sendable, CustomStringConvertible {
    public var kind: ZoneKind
    public var owner: SeatID?
    public var index: Int

    public init(_ kind: ZoneKind, owner: SeatID? = nil, index: Int = 0) {
        self.kind = kind
        self.owner = owner
        self.index = index
    }

    public var description: String {
        var text = kind.rawValue
        if let owner { text += "@\(owner.rawValue)" }
        if index != 0 { text += "#\(index)" }
        return text
    }

    // MARK: - Common shorthands

    public static func hand(_ seat: SeatID) -> Zone { Zone(.hand, owner: seat) }
    public static func captured(_ seat: SeatID) -> Zone { Zone(.captured, owner: seat) }
    public static func exchange(_ seat: SeatID) -> Zone { Zone(.exchange, owner: seat) }
    public static func meld(_ seat: SeatID, _ index: Int) -> Zone { Zone(.meld, owner: seat, index: index) }
    public static func tableau(_ index: Int) -> Zone { Zone(.tableau, index: index) }
    public static func foundation(_ index: Int) -> Zone { Zone(.foundation, index: index) }
    public static func freeCell(_ index: Int) -> Zone { Zone(.freeCell, index: index) }
    public static let stock = Zone(.stock)
    public static let discard = Zone(.discard)
    public static let waste = Zone(.waste)
    public static let trick = Zone(.trick)
    public static let community = Zone(.community)
    public static let reserve = Zone(.reserve)
}

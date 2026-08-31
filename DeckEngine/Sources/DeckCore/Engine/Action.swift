import Foundation

/// The semantic shape of a move, shared by every game.
///
/// The UI, the animation system, the haptics engine and the replay log all read
/// this instead of each game's private action enum, which is why adding a game
/// does not mean touching any of them.
public enum ActionKind: String, Codable, CaseIterable, Sendable {
    case playCard
    case drawCard
    case discardCard
    case passTurn
    case selectCards
    case bet
    case call
    case raise
    case check
    case fold
    case allIn
    case bid
    case claim
    case challenge
    case moveCards
    case flipCard
    case dealNext
    case knock
    case meld
    case layOff
    case undo
    case concede
    case acknowledge
}

/// A move offered to a player or taken by one, in a form every layer understands.
///
/// Games convert their own strongly typed action into a token and back. The
/// token's `id` is a stable string, which is what the replay log stores: a game
/// can therefore be reconstructed from `seed + [String]` alone.
public struct ActionToken: Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    /// Stable encoding of the move. Unique within the set of legal moves for a
    /// position, and stable across launches.
    public let id: String
    public let kind: ActionKind
    /// Seat taking the move.
    public let seat: SeatID
    /// Cards involved, in order.
    public let cards: [CardID]
    /// Where the cards are going, when that matters.
    public let destination: Zone?
    /// Where the cards came from, when that matters.
    public let source: Zone?
    /// Chips, points, bid level — whatever number the move carries.
    public let amount: Int?
    /// Localisation key for the button/menu label.
    public let labelKey: String
    /// Values interpolated into the localised label.
    public let labelArguments: [String]

    public init(id: String,
                kind: ActionKind,
                seat: SeatID,
                cards: [CardID] = [],
                destination: Zone? = nil,
                source: Zone? = nil,
                amount: Int? = nil,
                labelKey: String,
                labelArguments: [String] = []) {
        self.id = id
        self.kind = kind
        self.seat = seat
        self.cards = cards
        self.destination = destination
        self.source = source
        self.amount = amount
        self.labelKey = labelKey
        self.labelArguments = labelArguments
    }

    public var description: String { id }

    /// The card this move is "about", for hit-testing a tap on a card.
    public var primaryCard: CardID? { cards.first }
}

/// Why a move was refused.
///
/// Never fail silently and never return a bare bool: the reason is what the
/// hint system, the tutorial and the "Why?" button all render, and it is what
/// turns an invalid tap into a teaching moment instead of a dead end.
public struct IllegalMove: Error, Hashable, Codable, Sendable {
    /// Stable reason code. Also the localisation key suffix.
    public let reason: String
    /// Values interpolated into the localised explanation.
    public let arguments: [String]
    /// Untranslated fallback, so logs and tests read clearly.
    public let englishExplanation: String

    public init(_ reason: String, arguments: [String] = [], english: String) {
        self.reason = reason
        self.arguments = arguments
        self.englishExplanation = english
    }

    public var localizationKey: String { "illegal.\(reason)" }

    // MARK: - Shared reasons

    public static let notYourTurn = IllegalMove("notYourTurn", english: "It is not your turn.")
    public static let gameOver = IllegalMove("gameOver", english: "This game has finished.")
    public static let cardNotInHand = IllegalMove("cardNotInHand", english: "That card is not in your hand.")
    public static let noSuchAction = IllegalMove("noSuchAction", english: "That move is not available here.")
    public static let emptyPile = IllegalMove("emptyPile", english: "There are no cards left in that pile.")

    public static func mustFollowSuit(_ suit: Suit) -> IllegalMove {
        IllegalMove("mustFollowSuit",
                    arguments: [suit.localizationKey],
                    english: "You must follow \(suit.englishName).")
    }
}

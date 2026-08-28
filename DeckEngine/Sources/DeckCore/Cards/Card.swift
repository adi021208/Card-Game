import Foundation

/// The four French suits, ordered low-to-high in the "bridge" ordering used by
/// several games in the library (clubs < diamonds < hearts < spades).
public enum Suit: Int, Codable, CaseIterable, Sendable, Comparable {
    case clubs = 0
    case diamonds = 1
    case hearts = 2
    case spades = 3

    public static func < (lhs: Suit, rhs: Suit) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Traditional print colour of the suit. Never used as the *only* signal for
    /// game state — see `DeckDesign` for the non-colour indicators.
    public var isRed: Bool { self == .diamonds || self == .hearts }

    /// Stable single-character token, used in card identifiers and save files.
    public var token: String {
        switch self {
        case .clubs: return "C"
        case .diamonds: return "D"
        case .hearts: return "H"
        case .spades: return "S"
        }
    }

    /// Untranslated English name. UI must localise via `Suit.localizationKey`.
    public var englishName: String {
        switch self {
        case .clubs: return "Clubs"
        case .diamonds: return "Diamonds"
        case .hearts: return "Hearts"
        case .spades: return "Spades"
        }
    }

    public var localizationKey: String { "suit.\(self)" }

    public init?(token: String) {
        switch token.uppercased() {
        case "C": self = .clubs
        case "D": self = .diamonds
        case "H": self = .hearts
        case "S": self = .spades
        default: return nil
        }
    }
}

/// Card ranks. Raw values are the "ace high" numeric values, which is the
/// ordering most games in the library use; games that need ace-low (for example
/// the A-2-3-4-5 straight in poker, or the ace on a Klondike foundation) handle
/// that explicitly rather than mutating the rank.
public enum Rank: Int, Codable, CaseIterable, Sendable, Comparable {
    case two = 2, three, four, five, six, seven, eight, nine, ten
    case jack, queen, king, ace

    public static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Value when the ace is treated as the lowest card (1).
    public var aceLowValue: Int { self == .ace ? 1 : rawValue }

    /// Number of pips; face cards and the ace have no pip count.
    public var isFaceCard: Bool { self == .jack || self == .queen || self == .king }

    public var token: String {
        switch self {
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .ten: return "T"
        case .jack: return "J"
        case .queen: return "Q"
        case .king: return "K"
        case .ace: return "A"
        }
    }

    /// What is printed in the card corner. "10" is two glyphs, everything else is one.
    public var pipLabel: String { self == .ten ? "10" : token }

    public var englishName: String {
        switch self {
        case .two: return "Two"
        case .three: return "Three"
        case .four: return "Four"
        case .five: return "Five"
        case .six: return "Six"
        case .seven: return "Seven"
        case .eight: return "Eight"
        case .nine: return "Nine"
        case .ten: return "Ten"
        case .jack: return "Jack"
        case .queen: return "Queen"
        case .king: return "King"
        case .ace: return "Ace"
        }
    }

    public var localizationKey: String { "rank.\(self)" }

    public init?(token: String) {
        switch token.uppercased() {
        case "2": self = .two
        case "3": self = .three
        case "4": self = .four
        case "5": self = .five
        case "6": self = .six
        case "7": self = .seven
        case "8": self = .eight
        case "9": self = .nine
        case "T", "10": self = .ten
        case "J": self = .jack
        case "Q": self = .queen
        case "K": self = .king
        case "A": self = .ace
        default: return nil
        }
    }
}

public enum JokerColour: Int, Codable, CaseIterable, Sendable {
    case red = 0
    case black = 1

    public var token: String { self == .red ? "R" : "B" }
}

/// What is printed on the face of a card.
public enum CardKind: Hashable, Codable, Sendable {
    case standard(suit: Suit, rank: Rank)
    case joker(JokerColour)
}

/// A stable, compact identifier for one physical card in one physical deck.
///
/// The raw value packs `deckIndex` and an ordinal so that identifiers are stable
/// across launches, sort deterministically, and survive round-tripping through a
/// save file. Two cards from different decks in a multi-deck shoe are different
/// objects with different identifiers even though they show the same face.
public struct CardID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible, RawRepresentable {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }

    public init(deckIndex: Int, ordinal: Int) {
        self.rawValue = deckIndex * CardID.deckStride + ordinal
    }

    /// Room for 52 + 2 jokers plus headroom, keeping the arithmetic readable.
    static let deckStride = 64

    public var deckIndex: Int { rawValue / CardID.deckStride }
    public var ordinal: Int { rawValue % CardID.deckStride }

    public static func < (lhs: CardID, rhs: CardID) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { "card#\(rawValue)" }
}

/// A card. This is a pure value type with no reference to any UI framework, no
/// mutable presentation flags, and no knowledge of where it currently sits.
///
/// Position, orientation and visibility live in `Board` because they are
/// properties of the *game*, not of the piece of card stock.
public struct Card: Hashable, Codable, Sendable, Identifiable, Comparable, CustomStringConvertible {
    public let id: CardID
    public let kind: CardKind

    public init(id: CardID, kind: CardKind) {
        self.id = id
        self.kind = kind
    }

    public init(_ suit: Suit, _ rank: Rank, deckIndex: Int = 0) {
        self.kind = .standard(suit: suit, rank: rank)
        self.id = CardID(deckIndex: deckIndex, ordinal: Card.ordinal(suit: suit, rank: rank))
    }

    public init(joker colour: JokerColour, deckIndex: Int = 0) {
        self.kind = .joker(colour)
        self.id = CardID(deckIndex: deckIndex, ordinal: 52 + colour.rawValue)
    }

    static func ordinal(suit: Suit, rank: Rank) -> Int {
        suit.rawValue * 13 + (rank.rawValue - 2)
    }

    public var deckIndex: Int { id.deckIndex }

    public var suit: Suit? {
        if case let .standard(suit, _) = kind { return suit }
        return nil
    }

    public var rank: Rank? {
        if case let .standard(_, rank) = kind { return rank }
        return nil
    }

    public var jokerColour: JokerColour? {
        if case let .joker(colour) = kind { return colour }
        return nil
    }

    public var isJoker: Bool { jokerColour != nil }

    public var isRed: Bool {
        switch kind {
        case let .standard(suit, _): return suit.isRed
        case let .joker(colour): return colour == .red
        }
    }

    /// Compact token such as `AS`, `TD`, `JOKR`. Used in tests, replays and debug tools.
    public var token: String {
        switch kind {
        case let .standard(suit, rank): return "\(rank.token)\(suit.token)"
        case let .joker(colour): return "JOK\(colour.token)"
        }
    }

    public var description: String { token }

    /// Untranslated description; the UI builds VoiceOver labels from the
    /// localisation keys instead, but this keeps tests and logs readable.
    public var englishName: String {
        switch kind {
        case let .standard(suit, rank): return "\(rank.englishName) of \(suit.englishName)"
        case let .joker(colour): return colour == .red ? "Red Joker" : "Black Joker"
        }
    }

    public static func < (lhs: Card, rhs: Card) -> Bool { lhs.id < rhs.id }

    /// Parses `AS`, `10H`, `TD`, `JOKR`. Returns nil for anything else.
    public init?(token: String, deckIndex: Int = 0) {
        let upper = token.uppercased()
        if upper.hasPrefix("JOK") {
            let colourToken = String(upper.dropFirst(3))
            switch colourToken {
            case "R": self.init(joker: .red, deckIndex: deckIndex)
            case "B": self.init(joker: .black, deckIndex: deckIndex)
            default: return nil
            }
            return
        }
        guard upper.count >= 2 else { return nil }
        let suitToken = String(upper.suffix(1))
        let rankToken = String(upper.dropLast())
        guard let suit = Suit(token: suitToken), let rank = Rank(token: rankToken) else { return nil }
        self.init(suit, rank, deckIndex: deckIndex)
    }
}

public extension Sequence where Element == Card {
    var tokens: [String] { map(\.token) }
    var ids: [CardID] { map(\.id) }
}

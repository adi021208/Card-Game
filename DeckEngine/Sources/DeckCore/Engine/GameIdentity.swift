import Foundation

public struct GameID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible, Comparable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
    public var description: String { rawValue }
    public static func < (lhs: GameID, rhs: GameID) -> Bool { lhs.rawValue < rhs.rawValue }
}

public extension GameID {
    static let crazyEights = GameID("crazy-eights")
    static let hearts = GameID("hearts")
    static let spades = GameID("spades")
    static let euchre = GameID("euchre")
    static let texasHoldem = GameID("texas-holdem")
    static let ginRummy = GameID("gin-rummy")
    static let rummy = GameID("rummy")
    static let president = GameID("president")
    static let klondike = GameID("klondike")
    static let freeCell = GameID("freecell")
    static let spider = GameID("spider")
    static let goFish = GameID("go-fish")
    static let war = GameID("war")
    static let cheat = GameID("cheat")
    static let speed = GameID("speed")
}

/// Shelves in the library. A game may appear on several.
public enum GameCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case poker
    case trickTaking = "trick-taking"
    case rummy
    case solitaire
    case shedding
    case family
    case speed
    case bluff
    case strategy

    public var id: String { rawValue }
    public var localizationKey: String { "category.\(rawValue)" }
    public var englishName: String {
        switch self {
        case .poker: return "Poker"
        case .trickTaking: return "Trick Taking"
        case .rummy: return "Rummy"
        case .solitaire: return "Solitaire"
        case .shedding: return "Shedding"
        case .family: return "Family"
        case .speed: return "Speed"
        case .bluff: return "Bluff"
        case .strategy: return "Strategy"
        }
    }
}

/// Rough time to play one game, used for filtering and for the "Quick" shelf.
public enum GameDuration: Int, Codable, CaseIterable, Sendable, Comparable {
    case quick = 0      // under 5 minutes
    case short = 1      // 5-15 minutes
    case medium = 2     // 15-30 minutes
    case long = 3       // 30 minutes or more

    public static func < (lhs: GameDuration, rhs: GameDuration) -> Bool { lhs.rawValue < rhs.rawValue }
    public var localizationKey: String { "duration.\(self)" }
}

/// How hard the game is to *learn*, which is a different axis from how hard the
/// AI opponent is set.
public enum GameComplexity: Int, Codable, CaseIterable, Sendable, Comparable {
    case easy = 0
    case moderate = 1
    case involved = 2

    public static func < (lhs: GameComplexity, rhs: GameComplexity) -> Bool { lhs.rawValue < rhs.rawValue }
    public var localizationKey: String { "complexity.\(self)" }
}

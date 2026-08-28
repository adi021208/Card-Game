import Foundation

/// Everything needed to start a game, and everything needed to start the *same*
/// game again later. A configuration plus its seed fully determines the deal.
public struct GameConfiguration: Hashable, Codable, Sendable {
    public var gameID: GameID
    public var seating: SeatingPlan
    /// Selected rules variant, e.g. `hearts.jackOfDiamonds`.
    public var variantID: String
    /// Game-specific setup values, e.g. `startingChips`, `targetScore`, `drawCount`.
    public var options: [String: Int]
    /// Seed for every random decision in the game.
    public var seed: UInt64
    /// Difficulty multiplier applied by the daily challenge. 1.0 is normal;
    /// 0.5 is the −50% floor and 3.0 the +200% ceiling.
    public var difficultyScale: Double
    /// Boss modifier in force, if any.
    public var bossID: String?
    /// Whether this game counts towards a daily challenge.
    public var challengeID: String?

    public init(gameID: GameID,
                seating: SeatingPlan,
                variantID: String = "standard",
                options: [String: Int] = [:],
                seed: UInt64,
                difficultyScale: Double = 1.0,
                bossID: String? = nil,
                challengeID: String? = nil) {
        self.gameID = gameID
        self.seating = seating
        self.variantID = variantID
        self.options = options
        self.seed = seed
        self.difficultyScale = difficultyScale
        self.bossID = bossID
        self.challengeID = challengeID
    }

    public func option(_ key: String, default defaultValue: Int) -> Int {
        options[key] ?? defaultValue
    }

    public func flag(_ key: String, default defaultValue: Bool = false) -> Bool {
        guard let value = options[key] else { return defaultValue }
        return value != 0
    }

    public var isChallenge: Bool { challengeID != nil }
    public var isPassAndPlay: Bool { seating.isPassAndPlay }
    public var isSolo: Bool { seating.humanSeats.count == 1 }
}

/// One choice a game exposes on its setup screen.
///
/// Setup is game-aware because games declare their own options — Poker asks for
/// blinds and a starting stack, Klondike asks draw-one or draw-three, Hearts asks
/// for a scoring variant. There is no shared "settings form" that every game is
/// forced through.
public struct SetupOption: Hashable, Codable, Sendable, Identifiable {
    public enum Control: Hashable, Codable, Sendable {
        /// A row of mutually exclusive choices.
        case choice(values: [Int], labelKeys: [String])
        /// A stepper over a closed range.
        case stepper(range: ClosedRange<Int>, step: Int)
        /// An on/off switch, stored as 0 or 1.
        case toggle
    }

    public var id: String
    public var titleKey: String
    public var footnoteKey: String?
    public var control: Control
    public var defaultValue: Int
    /// True when only premium players may change it away from the default.
    public var requiresPremium: Bool

    public init(id: String,
                titleKey: String,
                footnoteKey: String? = nil,
                control: Control,
                defaultValue: Int,
                requiresPremium: Bool = false) {
        self.id = id
        self.titleKey = titleKey
        self.footnoteKey = footnoteKey
        self.control = control
        self.defaultValue = defaultValue
        self.requiresPremium = requiresPremium
    }
}

/// A named rules variant. Variants change configuration, not code paths, so
/// adding "Jack of Diamonds" to Hearts does not fork the Hearts implementation.
public struct GameVariant: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var nameKey: String
    public var summaryKey: String
    /// Option overrides this variant applies on top of the defaults.
    public var options: [String: Int]
    public var requiresPremium: Bool

    public init(id: String,
                nameKey: String,
                summaryKey: String,
                options: [String: Int] = [:],
                requiresPremium: Bool = false) {
        self.id = id
        self.nameKey = nameKey
        self.summaryKey = summaryKey
        self.options = options
        self.requiresPremium = requiresPremium
    }
}

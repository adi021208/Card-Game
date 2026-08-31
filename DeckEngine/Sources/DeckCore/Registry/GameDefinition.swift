import Foundation

/// A metric a game asks the statistics engine to keep for it.
///
/// The statistics engine has no idea what "Queens captured" or "biggest pot"
/// mean. Games emit numbers into `GameResult.metrics`; these definitions say how
/// to fold and format them. That is why there is no Poker-shaped hole anywhere
/// in the global statistics code.
public struct StatisticDefinition: Hashable, Codable, Sendable, Identifiable {
    public enum Aggregation: String, Codable, Sendable {
        /// Sum across all games.
        case total
        /// Highest value seen.
        case maximum
        /// Lowest value seen (fastest time, fewest moves).
        case minimum
        /// Mean across games where the metric was reported.
        case average
        /// Number of games where the metric was non-zero.
        case occurrences
    }

    public enum Format: String, Codable, Sendable {
        case integer
        /// Stored in seconds, shown as m:ss.
        case duration
        /// Stored in hundredths of a percent, shown as a percentage.
        case percentage
        /// Stored in cents/chips, shown with a separator.
        case chips
    }

    public var key: String
    public var titleKey: String
    public var aggregation: Aggregation
    public var format: Format
    /// Shown on the game's own statistics card. Non-headline metrics still get
    /// recorded but sit below the fold.
    public var isHeadline: Bool

    public var id: String { key }

    public init(key: String,
                titleKey: String,
                aggregation: Aggregation,
                format: Format = .integer,
                isHeadline: Bool = false) {
        self.key = key
        self.titleKey = titleKey
        self.aggregation = aggregation
        self.format = format
        self.isHeadline = isHeadline
    }
}

/// How progress towards an achievement is measured.
///
/// Data, not code: adding an achievement is adding a row, and the engine that
/// evaluates them never grows a `switch` over game identifiers.
public enum AchievementTracking: Hashable, Codable, Sendable {
    /// Wins, optionally restricted to one game.
    case wins(gameID: GameID?)
    /// Games completed, optionally restricted to one game.
    case gamesPlayed(gameID: GameID?)
    /// Times a `.highlight` code was emitted.
    case highlight(code: String, gameID: GameID?)
    /// A single game reported this metric at or above `value`.
    case metricAtLeast(key: String, value: Int, gameID: GameID?)
    /// A single game reported this metric at or below `value` (times, move counts).
    case metricAtMost(key: String, value: Int, gameID: GameID?)
    /// Daily challenge streak length.
    case dailyStreak(days: Int)
    /// Daily challenges completed.
    case dailyCompletions(count: Int)
    /// A named boss defeated.
    case bossDefeated(bossID: String)
    /// Every boss defeated.
    case allBossesDefeated
    /// Mastery level reached in one game.
    case mastery(gameID: GameID, level: Int)
    /// Distinct games won at least once.
    case distinctGamesWon(count: Int)
    /// Pass & Play games completed.
    case passAndPlayGames(count: Int)
    /// Wins against a difficulty band or higher.
    case winAtDifficulty(AIDifficulty, gameID: GameID?, count: Int)
    /// Cosmetics unlocked.
    case collectionSize(count: Int)

    /// The game this achievement belongs to, if any. Drives where it is listed.
    public var gameID: GameID? {
        switch self {
        case let .wins(gameID), let .gamesPlayed(gameID):
            return gameID
        case let .highlight(_, gameID):
            return gameID
        case let .metricAtLeast(_, _, gameID), let .metricAtMost(_, _, gameID):
            return gameID
        case let .mastery(gameID, _):
            return gameID
        case let .winAtDifficulty(_, gameID, _):
            return gameID
        default:
            return nil
        }
    }

    /// The count the player is working towards.
    public var target: Int {
        switch self {
        case .wins, .gamesPlayed:
            return 1
        case .highlight:
            return 1
        case .metricAtLeast, .metricAtMost:
            return 1
        case let .dailyStreak(days):
            return days
        case let .dailyCompletions(count):
            return count
        case .bossDefeated:
            return 1
        case .allBossesDefeated:
            return 7
        case .mastery:
            return 1
        case let .distinctGamesWon(count):
            return count
        case let .passAndPlayGames(count):
            return count
        case let .winAtDifficulty(_, _, count):
            return count
        case let .collectionSize(count):
            return count
        }
    }
}

public enum AchievementCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case wins
    case games
    case streak
    case speed
    case skill
    case collection
    case passAndPlay = "pass-and-play"
    case boss
    case mastery

    public var id: String { rawValue }
    public var localizationKey: String { "achievement.category.\(rawValue)" }
}

/// One achievement. `target` comes from the tracking rule unless overridden.
public struct AchievementDefinition: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var titleKey: String
    public var descriptionKey: String
    public var category: AchievementCategory
    public var tracking: AchievementTracking
    /// Overrides the count implied by `tracking`, for "win 10 games" style rules.
    public var targetOverride: Int?
    /// Cosmetic unlocked by earning it.
    public var rewardID: String?
    /// Hidden until earned. Use sparingly — a locked achievement should usually
    /// tell the player what to aim at.
    public var isSecret: Bool
    /// Which symbol the achievement poster is built around.
    public var emblem: AchievementEmblem
    /// Rarity band, purely for how loudly the unlock poster shouts.
    public var weight: Weight

    public enum Weight: Int, Codable, Sendable, Comparable {
        case standard = 0
        case notable = 1
        case landmark = 2
        public static func < (lhs: Weight, rhs: Weight) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var target: Int { targetOverride ?? tracking.target }
    public var gameID: GameID? { tracking.gameID }

    public init(id: String,
                titleKey: String,
                descriptionKey: String,
                category: AchievementCategory,
                tracking: AchievementTracking,
                targetOverride: Int? = nil,
                rewardID: String? = nil,
                isSecret: Bool = false,
                emblem: AchievementEmblem = .stamp,
                weight: Weight = .standard) {
        self.id = id
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.category = category
        self.tracking = tracking
        self.targetOverride = targetOverride
        self.rewardID = rewardID
        self.isSecret = isSecret
        self.emblem = emblem
        self.weight = weight
    }
}

/// The drawn symbol an achievement poster is built around. Resolved by the art
/// layer into a real composition, not an SF Symbol.
public enum AchievementEmblem: String, Codable, CaseIterable, Sendable {
    case stamp
    case crown
    case moon
    case flame
    case bolt
    case royalFan
    case spade
    case heart
    case club
    case diamond
    case clock
    case binder
    case skull
    case star
}

/// One beat of an interactive tutorial.
///
/// Tutorials are scripted positions, not walls of text: each step deals a
/// specific position, says one thing, and waits for the player to make the move
/// it is teaching.
public struct TutorialStep: Hashable, Codable, Sendable, Identifiable {
    public enum Goal: Hashable, Codable, Sendable {
        /// Just read it and tap on.
        case acknowledge
        /// Make any legal move.
        case anyMove
        /// Make a move of this kind.
        case moveOfKind(ActionKind)
        /// Play one of these specific cards.
        case playOneOf([String])
        /// Reach the end of the round.
        case finishRound
    }

    public var id: String
    public var titleKey: String
    public var bodyKey: String
    public var goal: Goal
    /// Cards to draw attention to, as tokens like `QS`.
    public var spotlight: [String]

    public init(id: String,
                titleKey: String,
                bodyKey: String,
                goal: Goal = .acknowledge,
                spotlight: [String] = []) {
        self.id = id
        self.titleKey = titleKey
        self.bodyKey = bodyKey
        self.goal = goal
        self.spotlight = spotlight
    }
}

public struct TutorialScript: Hashable, Codable, Sendable {
    public var steps: [TutorialStep]
    /// Seed for the tutorial's deal, so the taught position is always the same.
    public var seed: UInt64
    /// Configuration overrides for the tutorial game.
    public var options: [String: Int]

    public init(steps: [TutorialStep], seed: UInt64, options: [String: Int] = [:]) {
        self.steps = steps
        self.seed = seed
        self.options = options
    }

    public static let empty = TutorialScript(steps: [], seed: 1)
}

/// Everything the app needs to know about one game.
///
/// Registering one of these is the *entire* cost of adding a game: the library,
/// search, filters, setup, statistics, achievements, mastery, persistence, the
/// daily challenge and Pass & Play all read from here.
public struct GameDefinition: Identifiable, @unchecked Sendable {
    public var id: GameID
    public var nameKey: String
    /// Untranslated name. Established games keep their real names.
    public var englishName: String
    /// One line, written like a game studio wrote it.
    public var taglineKey: String
    public var descriptionKey: String
    public var categories: [GameCategory]
    public var playerRange: ClosedRange<Int>
    public var duration: GameDuration
    public var complexity: GameComplexity
    public var deckConfiguration: DeckConfiguration
    public var variants: [GameVariant]
    public var setupOptions: [SetupOption]
    public var supportsSolo: Bool
    public var supportsPassAndPlay: Bool
    /// Eligible to be picked as a daily challenge.
    public var supportsDailyChallenge: Bool
    public var supportsUndo: Bool
    /// Whether AI can fill empty seats.
    public var supportsAIOpponents: Bool
    /// Requires a premium entitlement to play.
    public var requiresPremium: Bool
    /// Art identifier resolved by the cover-art layer into a composition.
    public var artworkID: String
    /// Search keywords in English; localised keywords come from the catalogue.
    public var searchTerms: [String]
    public var statistics: [StatisticDefinition]
    public var achievements: [AchievementDefinition]
    public var tutorial: TutorialScript
    /// "Try next" suggestions shown on the result screen.
    public var recommendations: [GameID]
    /// Default option values, before variant overrides.
    public var defaultOptions: [String: Int]

    /// Builds a running session. The only place the concrete rules type is named.
    public var makeSession: (GameConfiguration) -> GameSessionProtocol
    /// Rebuilds a session from a save.
    public var restoreSession: (GameCheckpoint) throws -> GameSessionProtocol

    public init(id: GameID,
                nameKey: String,
                englishName: String,
                taglineKey: String,
                descriptionKey: String,
                categories: [GameCategory],
                playerRange: ClosedRange<Int>,
                duration: GameDuration,
                complexity: GameComplexity,
                deckConfiguration: DeckConfiguration,
                variants: [GameVariant] = [],
                setupOptions: [SetupOption] = [],
                supportsSolo: Bool = true,
                supportsPassAndPlay: Bool = true,
                supportsDailyChallenge: Bool = true,
                supportsUndo: Bool = false,
                supportsAIOpponents: Bool = true,
                requiresPremium: Bool = false,
                artworkID: String,
                searchTerms: [String] = [],
                statistics: [StatisticDefinition] = [],
                achievements: [AchievementDefinition] = [],
                tutorial: TutorialScript = .empty,
                recommendations: [GameID] = [],
                defaultOptions: [String: Int] = [:],
                makeSession: @escaping (GameConfiguration) -> GameSessionProtocol,
                restoreSession: @escaping (GameCheckpoint) throws -> GameSessionProtocol) {
        self.id = id
        self.nameKey = nameKey
        self.englishName = englishName
        self.taglineKey = taglineKey
        self.descriptionKey = descriptionKey
        self.categories = categories
        self.playerRange = playerRange
        self.duration = duration
        self.complexity = complexity
        self.deckConfiguration = deckConfiguration
        self.variants = variants
        self.setupOptions = setupOptions
        self.supportsSolo = supportsSolo
        self.supportsPassAndPlay = supportsPassAndPlay
        self.supportsDailyChallenge = supportsDailyChallenge
        self.supportsUndo = supportsUndo
        self.supportsAIOpponents = supportsAIOpponents
        self.requiresPremium = requiresPremium
        self.artworkID = artworkID
        self.searchTerms = searchTerms
        self.statistics = statistics
        self.achievements = achievements
        self.tutorial = tutorial
        self.recommendations = recommendations
        self.defaultOptions = defaultOptions
        self.makeSession = makeSession
        self.restoreSession = restoreSession
    }

    /// Whether a single human can play it, which drives the Solo shelf.
    public var isSinglePlayerOnly: Bool { playerRange.upperBound == 1 }

    /// Merges defaults, the chosen variant's overrides and explicit options.
    public func resolvedOptions(variantID: String, overrides: [String: Int]) -> [String: Int] {
        var options = defaultOptions
        if let variant = variants.first(where: { $0.id == variantID }) {
            for (key, value) in variant.options { options[key] = value }
        }
        for (key, value) in overrides { options[key] = value }
        for option in setupOptions where options[option.id] == nil {
            options[option.id] = option.defaultValue
        }
        return options
    }

    public func variant(_ id: String) -> GameVariant? {
        variants.first { $0.id == id }
    }

    public var defaultVariantID: String { variants.first?.id ?? "standard" }
}

import Foundation
import DeckCore

/// What a boss actually changes about a game.
///
/// A boss is not an avatar with a name on it. Each modifier is applied by the
/// challenge engine to the real `GameConfiguration`, so the difference is
/// visible in the deal, the opponent, or the target — and the player is told
/// exactly what it is before they start.
public enum BossModifier: Hashable, Codable, Sendable {
    /// The opponent plays above its usual band.
    case sharperOpponents(extraScale: Double)
    /// The objective moves: score higher, finish faster, use fewer turns.
    case harderObjective(percent: Int)
    /// The player starts behind.
    case startingHandicap(points: Int)
    /// Fewer moves are available: a stricter variant.
    case ruleChange(option: String, value: Int)
    /// A time limit in seconds. Zero means none.
    case timeLimit(seconds: Int)
    /// The player's score is multiplied on success.
    case rewardMultiplier(percent: Int)

    public var localizationKey: String {
        switch self {
        case .sharperOpponents: return "boss.modifier.sharper"
        case .harderObjective: return "boss.modifier.harder"
        case .startingHandicap: return "boss.modifier.handicap"
        case .ruleChange: return "boss.modifier.rules"
        case .timeLimit: return "boss.modifier.timeLimit"
        case .rewardMultiplier: return "boss.modifier.reward"
        }
    }

    public var arguments: [String] {
        switch self {
        case let .sharperOpponents(scale): return [String(Int(scale * 100))]
        case let .harderObjective(percent): return [String(percent)]
        case let .startingHandicap(points): return [String(points)]
        case let .ruleChange(option, value): return [option, String(value)]
        case let .timeLimit(seconds): return [String(seconds)]
        case let .rewardMultiplier(percent): return [String(percent)]
        }
    }

    /// Untranslated explanation, used in tests, logs and the debug menu.
    public var englishExplanation: String {
        switch self {
        case let .sharperOpponents(scale):
            return "Opponents play \(Int(scale * 100))% sharper."
        case let .harderObjective(percent):
            return "The target is \(percent)% harder."
        case let .startingHandicap(points):
            return "You start \(points) behind."
        case let .ruleChange(option, value):
            return "House rule: \(option) is set to \(value)."
        case let .timeLimit(seconds):
            return "You have \(seconds / 60) minutes."
        case let .rewardMultiplier(percent):
            return "Beating this is worth \(percent)% of the usual score."
        }
    }
}

/// One of the seven.
public struct Boss: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    /// Which AI personality sits behind the portrait.
    public var personalityID: AIPersonalityID
    public var displayName: String
    /// "The Strategist", "The Closer".
    public var titleKey: String
    /// Two or three lines, revealed when the boss is beaten.
    public var loreKey: String
    /// Untranslated lore, so tests and the debug menu read properly.
    public var englishLore: String
    /// Palette token resolved by the design system.
    public var colourToken: String
    /// Secondary palette token used for the poster's ground.
    public var groundToken: String
    /// What playing against them actually changes.
    public var modifiers: [BossModifier]
    /// Which idle animation the portrait runs.
    public var idle: IdleBehaviour
    /// Games this boss is a natural fit for. Empty means any.
    public var affinities: [GameID]

    /// A small movement that gives the portrait a pulse. Deliberately small —
    /// the goal is presence, not a cartoon.
    public enum IdleBehaviour: String, Codable, CaseIterable, Sendable {
        case blink
        case glanceAtCards
        case eyebrow
        case breathe
        case tapFingers
        case tiltHead
        case smirk
    }

    public init(id: String,
                personalityID: AIPersonalityID,
                displayName: String,
                titleKey: String,
                loreKey: String,
                englishLore: String,
                colourToken: String,
                groundToken: String,
                modifiers: [BossModifier],
                idle: IdleBehaviour,
                affinities: [GameID] = []) {
        self.id = id
        self.personalityID = personalityID
        self.displayName = displayName
        self.titleKey = titleKey
        self.loreKey = loreKey
        self.englishLore = englishLore
        self.colourToken = colourToken
        self.groundToken = groundToken
        self.modifiers = modifiers
        self.idle = idle
        self.affinities = affinities
    }

    /// Applies the boss's modifiers to a configuration.
    public func apply(to configuration: GameConfiguration) -> GameConfiguration {
        var updated = configuration
        updated.bossID = id
        for modifier in modifiers {
            switch modifier {
            case let .sharperOpponents(scale):
                updated.difficultyScale *= (1.0 + scale)
            case let .ruleChange(option, value):
                updated.options[option] = value
            case let .startingHandicap(points):
                updated.options["handicap"] = points
            case let .timeLimit(seconds):
                updated.options["timeLimit"] = seconds
            case .harderObjective, .rewardMultiplier:
                // These change the challenge objective rather than the deal;
                // `DailyChallenge` reads them directly.
                break
            }
        }
        return updated
    }

    /// Percentage the objective is tightened by.
    public var objectiveTightening: Int {
        for modifier in modifiers {
            if case let .harderObjective(percent) = modifier { return percent }
        }
        return 0
    }

    public var scoreMultiplierPercent: Int {
        for modifier in modifiers {
            if case let .rewardMultiplier(percent) = modifier { return percent }
        }
        return 100
    }
}

/// The seven. Each one plays differently because each one *is* a different set
/// of AI parameters — the portrait is the last thing about them, not the first.
public enum BossCast {

    public static let hal = Boss(
        id: "hal",
        personalityID: .hal,
        displayName: "Hal",
        titleKey: "boss.hal.title",
        loreKey: "boss.hal.lore",
        englishLore: "He has played the same opening for eleven years. It is still working.",
        colourToken: "cobalt",
        groundToken: "cream",
        modifiers: [.sharperOpponents(extraScale: 0.15), .harderObjective(percent: 10)],
        idle: .breathe)

    public static let pedro = Boss(
        id: "pedro",
        personalityID: .pedro,
        displayName: "Pedro",
        titleKey: "boss.pedro.title",
        loreKey: "boss.pedro.lore",
        englishLore: "Nobody has ever seen him fold first. Nobody has checked whether he can.",
        colourToken: "vermilion",
        groundToken: "ink",
        modifiers: [.sharperOpponents(extraScale: 0.30), .rewardMultiplier(percent: 125)],
        idle: .tapFingers,
        affinities: [.texasHoldem, .cheat, .president])

    public static let calvin = Boss(
        id: "calvin",
        personalityID: .calvin,
        displayName: "Calvin",
        titleKey: "boss.calvin.title",
        loreKey: "boss.calvin.lore",
        englishLore: "He does not need to win the hand. He needs you not to.",
        colourToken: "forest",
        groundToken: "cream",
        modifiers: [.harderObjective(percent: 25), .startingHandicap(points: 10)],
        idle: .glanceAtCards,
        affinities: [.hearts, .spades, .ginRummy])

    public static let rohan = Boss(
        id: "rohan",
        personalityID: .rohan,
        displayName: "Rohan",
        titleKey: "boss.rohan.title",
        loreKey: "boss.rohan.lore",
        englishLore: "He knows which cards are left. He has known since the third trick.",
        colourToken: "acid",
        groundToken: "ink",
        modifiers: [.sharperOpponents(extraScale: 0.45), .harderObjective(percent: 15)],
        idle: .tiltHead,
        affinities: [.hearts, .spades, .euchre, .ginRummy])

    public static let shayla = Boss(
        id: "shayla",
        personalityID: .shayla,
        displayName: "Shayla",
        titleKey: "boss.shayla.title",
        loreKey: "boss.shayla.lore",
        englishLore: "She is not playing the cards. She is playing whoever is holding them.",
        colourToken: "coral",
        groundToken: "ink",
        modifiers: [.sharperOpponents(extraScale: 0.35), .rewardMultiplier(percent: 140)],
        idle: .eyebrow,
        affinities: [.texasHoldem, .cheat, .goFish])

    public static let honey = Boss(
        id: "honey",
        personalityID: .honey,
        displayName: "Honey",
        titleKey: "boss.honey.title",
        loreKey: "boss.honey.lore",
        englishLore: "Half of what she does is a mistake. Working out which half is the game.",
        colourToken: "orange",
        groundToken: "cream",
        modifiers: [.sharperOpponents(extraScale: 0.20), .timeLimit(seconds: 420),
                    .rewardMultiplier(percent: 130)],
        idle: .smirk,
        affinities: [.crazyEights, .speed, .war, .cheat])

    public static let scarlet = Boss(
        id: "scarlet",
        personalityID: .scarlet,
        displayName: "Scarlet",
        titleKey: "boss.scarlet.title",
        loreKey: "boss.scarlet.lore",
        englishLore: "She has never believed the obvious move is the correct one.",
        colourToken: "crimson",
        groundToken: "ink",
        modifiers: [.sharperOpponents(extraScale: 0.60), .harderObjective(percent: 30),
                    .rewardMultiplier(percent: 175)],
        idle: .blink)

    public static let all: [Boss] = [hal, pedro, calvin, rohan, shayla, honey, scarlet]

    public static func boss(_ id: String) -> Boss? {
        all.first { $0.id == id }
    }

    /// Picks the boss for a challenge deterministically, preferring one whose
    /// style suits the game. The same date and game always produce the same boss.
    public static func boss(forSeed seed: UInt64, gameID: GameID) -> Boss {
        let affine = all.filter { $0.affinities.contains(gameID) }
        let pool = affine.isEmpty ? all : affine
        // A second hash so the boss choice does not correlate with the deal.
        let mixed = SeedFactory.avalanche(seed ^ 0xB055_B055_B055_B055)
        return pool[Int(mixed % UInt64(pool.count))]
    }

    /// Difficulty band the boss sits in, for sorting the collection screen.
    public static func threat(_ boss: Boss) -> Int {
        var total = 0
        for modifier in boss.modifiers {
            switch modifier {
            case let .sharperOpponents(scale): total += Int(scale * 100)
            case let .harderObjective(percent): total += percent
            case let .startingHandicap(points): total += points
            case .timeLimit: total += 20
            default: break
            }
        }
        return total
    }
}

import Foundation

/// The dials that make one opponent feel different from another.
///
/// These are *behavioural* parameters, not a difficulty number with noise on
/// top. A Trickster and a Strategist at the same difficulty make measurably
/// different choices from the same position because they weigh the same
/// evaluation differently — see the per-game agents in `DeckAI`.
public struct AIProfile: Hashable, Codable, Sendable {
    /// Willingness to commit chips/cards to pressure opponents. 0…1.
    public var aggression: Double
    /// Tolerance for high-variance lines. 0…1.
    public var riskTolerance: Double
    /// How often a strong-looking line is taken without the goods. 0…1.
    public var bluffFrequency: Double
    /// How far ahead the agent searches, in plies. 0 means immediate value only.
    public var planningDepth: Int
    /// Probability of choosing a knowingly worse move. 0…1.
    public var mistakeRate: Double
    /// How strongly the agent adjusts to opponents' observed tendencies. 0…1.
    public var adaptability: Double
    /// How reliably the agent remembers public information (which suits a player
    /// has shown void, which cards have gone). 0…1.
    public var memoryStrength: Double
    /// Seconds of simulated thinking. Purely presentational; never affects choice.
    public var reactionSpeed: Double
    /// Simulation budget for agents that sample (poker equity). Scales with difficulty.
    public var samplingBudget: Int

    public init(aggression: Double = 0.5,
                riskTolerance: Double = 0.5,
                bluffFrequency: Double = 0.1,
                planningDepth: Int = 1,
                mistakeRate: Double = 0.1,
                adaptability: Double = 0.3,
                memoryStrength: Double = 0.6,
                reactionSpeed: Double = 0.8,
                samplingBudget: Int = 200) {
        self.aggression = aggression.clampedToUnit
        self.riskTolerance = riskTolerance.clampedToUnit
        self.bluffFrequency = bluffFrequency.clampedToUnit
        self.planningDepth = max(0, planningDepth)
        self.mistakeRate = mistakeRate.clampedToUnit
        self.adaptability = adaptability.clampedToUnit
        self.memoryStrength = memoryStrength.clampedToUnit
        self.reactionSpeed = max(0, reactionSpeed)
        self.samplingBudget = max(1, samplingBudget)
    }

    /// Applies a difficulty band on top of a personality.
    ///
    /// Difficulty only ever changes *decision quality*: search depth, sampling
    /// budget and error rate. It never touches what the agent can see, and it
    /// never edits the deal.
    public func adjusted(for difficulty: AIDifficulty) -> AIProfile {
        var copy = self
        switch difficulty {
        case .beginner:
            copy.mistakeRate = min(1, mistakeRate + 0.34)
            copy.planningDepth = max(0, planningDepth - 1)
            copy.memoryStrength = memoryStrength * 0.35
            copy.samplingBudget = max(24, samplingBudget / 6)
            copy.adaptability = adaptability * 0.2
        case .casual:
            copy.mistakeRate = min(1, mistakeRate + 0.14)
            copy.memoryStrength = memoryStrength * 0.7
            copy.samplingBudget = max(48, samplingBudget / 2)
            copy.adaptability = adaptability * 0.6
        case .skilled:
            copy.mistakeRate = max(0, mistakeRate - 0.03)
            copy.memoryStrength = min(1, memoryStrength * 1.1)
        case .expert:
            copy.mistakeRate = max(0, mistakeRate - 0.09)
            copy.planningDepth = planningDepth + 1
            copy.memoryStrength = 1.0
            copy.samplingBudget = samplingBudget * 3
            copy.adaptability = min(1, adaptability * 1.3)
        }
        return copy
    }

    /// Applies a daily-challenge difficulty scale. `1.0` is a no-op; the range
    /// runs 0.5 (−50%) to 3.0 (+200%).
    public func scaled(by scale: Double) -> AIProfile {
        guard scale != 1.0 else { return self }
        var copy = self
        let delta = scale - 1.0
        copy.mistakeRate = (mistakeRate * (1.0 - delta * 0.5)).clampedToUnit
        copy.memoryStrength = (memoryStrength * (1.0 + delta * 0.3)).clampedToUnit
        copy.aggression = (aggression * (1.0 + delta * 0.15)).clampedToUnit
        copy.samplingBudget = max(16, Int(Double(samplingBudget) * max(0.3, scale)))
        if delta > 0.75 { copy.planningDepth += 1 }
        if delta < -0.25 { copy.planningDepth = max(0, planningDepth - 1) }
        return copy
    }
}

extension Double {
    var clampedToUnit: Double { Swift.min(1, Swift.max(0, self)) }
}

/// The named opponents. Personalities are shared across every game; each game's
/// agent interprets the same profile in its own terms.
public struct AIPersonality: Hashable, Codable, Sendable, Identifiable {
    public var id: AIPersonalityID
    public var displayName: String
    public var titleKey: String
    public var profile: AIProfile
    /// Palette token resolved by the design system.
    public var colourToken: String

    public init(id: AIPersonalityID,
                displayName: String,
                titleKey: String,
                profile: AIProfile,
                colourToken: String) {
        self.id = id
        self.displayName = displayName
        self.titleKey = titleKey
        self.profile = profile
        self.colourToken = colourToken
    }
}

public extension AIPersonalityID {
    static let hal = AIPersonalityID("hal")
    static let pedro = AIPersonalityID("pedro")
    static let calvin = AIPersonalityID("calvin")
    static let rohan = AIPersonalityID("rohan")
    static let shayla = AIPersonalityID("shayla")
    static let honey = AIPersonalityID("honey")
    static let scarlet = AIPersonalityID("scarlet")
}

public enum AICast {
    /// Steady, textbook, unshowy. The benchmark everyone else deviates from.
    public static let hal = AIPersonality(
        id: .hal,
        displayName: "Hal",
        titleKey: "boss.hal.title",
        profile: AIProfile(aggression: 0.45, riskTolerance: 0.40, bluffFrequency: 0.06,
                           planningDepth: 2, mistakeRate: 0.06, adaptability: 0.35,
                           memoryStrength: 0.85, reactionSpeed: 0.9, samplingBudget: 320),
        colourToken: "cobalt")

    /// Loud and forward. Applies pressure whether or not it is warranted.
    public static let pedro = AIPersonality(
        id: .pedro,
        displayName: "Pedro",
        titleKey: "boss.pedro.title",
        profile: AIProfile(aggression: 0.86, riskTolerance: 0.78, bluffFrequency: 0.30,
                           planningDepth: 1, mistakeRate: 0.14, adaptability: 0.25,
                           memoryStrength: 0.55, reactionSpeed: 0.55, samplingBudget: 220),
        colourToken: "vermilion")

    /// Folds early, protects a lead, never gambles a won position.
    public static let calvin = AIPersonality(
        id: .calvin,
        displayName: "Calvin",
        titleKey: "boss.calvin.title",
        profile: AIProfile(aggression: 0.18, riskTolerance: 0.15, bluffFrequency: 0.03,
                           planningDepth: 2, mistakeRate: 0.09, adaptability: 0.30,
                           memoryStrength: 0.70, reactionSpeed: 1.1, samplingBudget: 300),
        colourToken: "forest")

    /// Counts everything. Slow, accurate, unbothered.
    public static let rohan = AIPersonality(
        id: .rohan,
        displayName: "Rohan",
        titleKey: "boss.rohan.title",
        profile: AIProfile(aggression: 0.50, riskTolerance: 0.45, bluffFrequency: 0.09,
                           planningDepth: 3, mistakeRate: 0.03, adaptability: 0.55,
                           memoryStrength: 1.0, reactionSpeed: 1.3, samplingBudget: 620),
        colourToken: "acid")

    /// Reads the table and plays the person, not the cards.
    public static let shayla = AIPersonality(
        id: .shayla,
        displayName: "Shayla",
        titleKey: "boss.shayla.title",
        profile: AIProfile(aggression: 0.62, riskTolerance: 0.58, bluffFrequency: 0.22,
                           planningDepth: 2, mistakeRate: 0.06, adaptability: 0.92,
                           memoryStrength: 0.90, reactionSpeed: 0.75, samplingBudget: 420),
        colourToken: "coral")

    /// Charming, chaotic, impossible to put on a hand.
    public static let honey = AIPersonality(
        id: .honey,
        displayName: "Honey",
        titleKey: "boss.honey.title",
        profile: AIProfile(aggression: 0.70, riskTolerance: 0.85, bluffFrequency: 0.44,
                           planningDepth: 1, mistakeRate: 0.11, adaptability: 0.45,
                           memoryStrength: 0.60, reactionSpeed: 0.45, samplingBudget: 260),
        colourToken: "orange")

    /// Never believes the obvious move is the correct one.
    public static let scarlet = AIPersonality(
        id: .scarlet,
        displayName: "Scarlet",
        titleKey: "boss.scarlet.title",
        profile: AIProfile(aggression: 0.66, riskTolerance: 0.52, bluffFrequency: 0.26,
                           planningDepth: 3, mistakeRate: 0.02, adaptability: 0.85,
                           memoryStrength: 1.0, reactionSpeed: 0.95, samplingBudget: 760),
        colourToken: "crimson")

    public static let all: [AIPersonality] = [hal, pedro, calvin, rohan, shayla, honey, scarlet]

    public static func personality(_ id: AIPersonalityID) -> AIPersonality {
        all.first { $0.id == id } ?? hal
    }

    /// Resolves a seat's controller into the profile the agent should use.
    public static func profile(for controller: SeatController, difficultyScale: Double = 1.0) -> AIProfile {
        guard case let .ai(personalityID, difficulty) = controller else {
            return AIProfile()
        }
        return personality(personalityID)
            .profile
            .adjusted(for: difficulty)
            .scaled(by: difficultyScale)
    }
}

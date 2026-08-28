import Foundation
import DeckCore

/// What kind of thing an unlockable is.
public enum CosmeticKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case theme
    case cardBack = "card-back"
    case avatar
    case table
    case soundPack = "sound-pack"

    public var id: String { rawValue }
    public var localizationKey: String { "collection.kind.\(rawValue)" }
}

/// How something is earned.
public enum UnlockCondition: Hashable, Codable, Sendable {
    /// Available from the start.
    case fromTheStart
    /// Earned by unlocking an achievement.
    case achievement(id: String)
    /// Earned by reaching a daily streak.
    case streak(days: Int)
    /// Earned by mastering a game.
    case mastery(gameID: GameID, level: Int)
    /// Earned by beating a boss.
    case boss(id: String)
    /// Included with the premium subscription.
    case premium

    public var localizationKey: String {
        switch self {
        case .fromTheStart: return "unlock.default"
        case .achievement: return "unlock.achievement"
        case .streak: return "unlock.streak"
        case .mastery: return "unlock.mastery"
        case .boss: return "unlock.boss"
        case .premium: return "unlock.premium"
        }
    }

    public var isPremium: Bool { self == .premium }
}

/// One collectible.
public struct Cosmetic: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var kind: CosmeticKind
    public var nameKey: String
    public var englishName: String
    public var descriptionKey: String
    /// Art identifier resolved by the design system into a real composition.
    public var artworkID: String
    public var unlock: UnlockCondition
    /// Palette tokens the artwork is built from.
    public var palette: [String]

    public init(id: String,
                kind: CosmeticKind,
                nameKey: String,
                englishName: String,
                descriptionKey: String,
                artworkID: String,
                unlock: UnlockCondition,
                palette: [String] = []) {
        self.id = id
        self.kind = kind
        self.nameKey = nameKey
        self.englishName = englishName
        self.descriptionKey = descriptionKey
        self.artworkID = artworkID
        self.unlock = unlock
        self.palette = palette
    }

    public var requiresPremium: Bool { unlock.isPremium }
}

/// What the player currently owns and has chosen.
public struct CollectionState: Codable, Sendable, PersistablePayload {
    public static let schemaVersion = 1
    public static let storeKey = "deck.collection"

    public var unlocked: Set<String>
    public var selectedTheme: String
    public var selectedCardBack: String
    public var selectedTable: String
    public var selectedSoundPack: String
    /// Unlocks not yet shown as a poster.
    public var pendingReveals: [String]

    public init(unlocked: Set<String> = [],
                selectedTheme: String = "theme.streetPrint",
                selectedCardBack: String = "cardback.deck",
                selectedTable: String = "table.ink",
                selectedSoundPack: String = "sound.paper",
                pendingReveals: [String] = []) {
        self.unlocked = unlocked
        self.selectedTheme = selectedTheme
        self.selectedCardBack = selectedCardBack
        self.selectedTable = selectedTable
        self.selectedSoundPack = selectedSoundPack
        self.pendingReveals = pendingReveals
    }

    public func validate() -> String? { nil }
    public func owns(_ id: String) -> Bool { unlocked.contains(id) }
}

/// The catalogue of everything that can be earned or bought.
///
/// Deliberately weighted: the loudest pieces are earned, not purchased. Premium
/// widens the collection, it does not contain the best of it.
public enum CosmeticCatalog {

    public static let all: [Cosmetic] = [
        // MARK: Themes
        Cosmetic(id: "theme.streetPrint", kind: .theme,
                 nameKey: "cosmetic.theme.streetPrint", englishName: "Street Print",
                 descriptionKey: "cosmetic.theme.streetPrint.desc",
                 artworkID: "theme.streetPrint", unlock: .fromTheStart,
                 palette: ["ink", "cream", "vermilion", "cobalt"]),
        Cosmetic(id: "theme.sundayComic", kind: .theme,
                 nameKey: "cosmetic.theme.sundayComic", englishName: "Sunday Comic",
                 descriptionKey: "cosmetic.theme.sundayComic.desc",
                 artworkID: "theme.sundayComic", unlock: .streak(days: 7),
                 palette: ["newsprint", "ink", "acid", "coral"]),
        Cosmetic(id: "theme.archive", kind: .theme,
                 nameKey: "cosmetic.theme.archive", englishName: "Archive",
                 descriptionKey: "cosmetic.theme.archive.desc",
                 artworkID: "theme.archive", unlock: .achievement(id: "euchre.loner"),
                 palette: ["cream", "ink", "crimson"]),
        Cosmetic(id: "theme.midnight", kind: .theme,
                 nameKey: "cosmetic.theme.midnight", englishName: "Midnight Table",
                 descriptionKey: "cosmetic.theme.midnight.desc",
                 artworkID: "theme.midnight", unlock: .premium,
                 palette: ["ink", "forest", "acid"]),

        // MARK: Card backs
        Cosmetic(id: "cardback.deck", kind: .cardBack,
                 nameKey: "cosmetic.back.deck", englishName: "House Mark",
                 descriptionKey: "cosmetic.back.deck.desc",
                 artworkID: "cardback.deck", unlock: .fromTheStart,
                 palette: ["ink", "cream", "vermilion"]),
        Cosmetic(id: "cardback.spray", kind: .cardBack,
                 nameKey: "cosmetic.back.spray", englishName: "Sprayed",
                 descriptionKey: "cosmetic.back.spray.desc",
                 artworkID: "cardback.spray", unlock: .achievement(id: "crazy8.ten"),
                 palette: ["vermilion", "cream"]),
        Cosmetic(id: "cardback.moon", kind: .cardBack,
                 nameKey: "cosmetic.back.moon", englishName: "Moonshot",
                 descriptionKey: "cosmetic.back.moon.desc",
                 artworkID: "cardback.moon", unlock: .achievement(id: "hearts.moon"),
                 palette: ["ink", "acid"]),
        Cosmetic(id: "cardback.royal", kind: .cardBack,
                 nameKey: "cosmetic.back.royal", englishName: "Royal",
                 descriptionKey: "cosmetic.back.royal.desc",
                 artworkID: "cardback.royal", unlock: .achievement(id: "poker.royalFlush"),
                 palette: ["crimson", "cream", "acid"]),
        Cosmetic(id: "cardback.stencil", kind: .cardBack,
                 nameKey: "cosmetic.back.stencil", englishName: "Stencil",
                 descriptionKey: "cosmetic.back.stencil.desc",
                 artworkID: "cardback.stencil", unlock: .achievement(id: "spades.nil"),
                 palette: ["ink", "cobalt"]),
        Cosmetic(id: "cardback.archive", kind: .cardBack,
                 nameKey: "cosmetic.back.archive", englishName: "Catalogued",
                 descriptionKey: "cosmetic.back.archive.desc",
                 artworkID: "cardback.archive", unlock: .achievement(id: "gin.shutout"),
                 palette: ["cream", "ink"]),
        Cosmetic(id: "cardback.web", kind: .cardBack,
                 nameKey: "cosmetic.back.web", englishName: "Eight Legs",
                 descriptionKey: "cosmetic.back.web.desc",
                 artworkID: "cardback.web", unlock: .achievement(id: "spider.fourSuit"),
                 palette: ["ink", "forest"]),
        Cosmetic(id: "cardback.speed", kind: .cardBack,
                 nameKey: "cosmetic.back.speed", englishName: "Motion Lines",
                 descriptionKey: "cosmetic.back.speed.desc",
                 artworkID: "cardback.speed", unlock: .achievement(id: "klondike.fast"),
                 palette: ["orange", "ink"]),
        Cosmetic(id: "cardback.motion", kind: .cardBack,
                 nameKey: "cosmetic.back.motion", englishName: "Blur",
                 descriptionKey: "cosmetic.back.motion.desc",
                 artworkID: "cardback.motion", unlock: .achievement(id: "speed.clean"),
                 palette: ["acid", "ink"]),
        Cosmetic(id: "cardback.streak", kind: .cardBack,
                 nameKey: "cosmetic.back.streak", englishName: "Thirty Days",
                 descriptionKey: "cosmetic.back.streak.desc",
                 artworkID: "cardback.streak", unlock: .streak(days: 30),
                 palette: ["vermilion", "acid", "ink"]),
        Cosmetic(id: "cardback.gold", kind: .cardBack,
                 nameKey: "cosmetic.back.gold", englishName: "Fifty",
                 descriptionKey: "cosmetic.back.gold.desc",
                 artworkID: "cardback.gold", unlock: .achievement(id: "global.fiftyWins"),
                 palette: ["acid", "ink"]),
        Cosmetic(id: "cardback.table", kind: .cardBack,
                 nameKey: "cosmetic.back.table", englishName: "Around The Table",
                 descriptionKey: "cosmetic.back.table.desc",
                 artworkID: "cardback.table", unlock: .achievement(id: "passplay.ten"),
                 palette: ["coral", "cream"]),
        Cosmetic(id: "cardback.library", kind: .cardBack,
                 nameKey: "cosmetic.back.library", englishName: "The Whole Shelf",
                 descriptionKey: "cosmetic.back.library.desc",
                 artworkID: "cardback.library", unlock: .achievement(id: "library.everything"),
                 palette: ["cobalt", "cream", "vermilion"]),
        Cosmetic(id: "cardback.press", kind: .cardBack,
                 nameKey: "cosmetic.back.press", englishName: "Misregister",
                 descriptionKey: "cosmetic.back.press.desc",
                 artworkID: "cardback.press", unlock: .premium,
                 palette: ["cobalt", "vermilion", "cream"]),

        // MARK: Avatars
        Cosmetic(id: "avatar.default", kind: .avatar,
                 nameKey: "cosmetic.avatar.default", englishName: "Player",
                 descriptionKey: "cosmetic.avatar.default.desc",
                 artworkID: "avatar.default", unlock: .fromTheStart, palette: ["cobalt"]),
        Cosmetic(id: "avatar.shark", kind: .avatar,
                 nameKey: "cosmetic.avatar.shark", englishName: "Card Shark",
                 descriptionKey: "cosmetic.avatar.shark.desc",
                 artworkID: "avatar.shark", unlock: .achievement(id: "poker.expert"),
                 palette: ["crimson"]),
        Cosmetic(id: "avatar.liar", kind: .avatar,
                 nameKey: "cosmetic.avatar.liar", englishName: "Straight Face",
                 descriptionKey: "cosmetic.avatar.liar.desc",
                 artworkID: "avatar.liar", unlock: .achievement(id: "cheat.perfectRead"),
                 palette: ["orange"]),
        Cosmetic(id: "avatar.president", kind: .avatar,
                 nameKey: "cosmetic.avatar.president", englishName: "In Office",
                 descriptionKey: "cosmetic.avatar.president.desc",
                 artworkID: "avatar.president", unlock: .achievement(id: "president.dynasty"),
                 palette: ["acid"]),
        Cosmetic(id: "avatar.expert", kind: .avatar,
                 nameKey: "cosmetic.avatar.expert", englishName: "Ten Experts",
                 descriptionKey: "cosmetic.avatar.expert.desc",
                 artworkID: "avatar.expert", unlock: .achievement(id: "skill.expertTen"),
                 palette: ["forest"]),
        Cosmetic(id: "avatar.scarlet", kind: .avatar,
                 nameKey: "cosmetic.avatar.scarlet", englishName: "Scarlet's Mark",
                 descriptionKey: "cosmetic.avatar.scarlet.desc",
                 artworkID: "avatar.scarlet", unlock: .boss(id: "scarlet"), palette: ["crimson"]),

        // MARK: Tables
        Cosmetic(id: "table.ink", kind: .table,
                 nameKey: "cosmetic.table.ink", englishName: "Ink Field",
                 descriptionKey: "cosmetic.table.ink.desc",
                 artworkID: "table.ink", unlock: .fromTheStart, palette: ["ink", "cream"]),
        Cosmetic(id: "table.paper", kind: .table,
                 nameKey: "cosmetic.table.paper", englishName: "Torn Paper",
                 descriptionKey: "cosmetic.table.paper.desc",
                 artworkID: "table.paper", unlock: .mastery(gameID: .hearts, level: 3),
                 palette: ["cream", "vermilion"]),
        Cosmetic(id: "table.felt", kind: .table,
                 nameKey: "cosmetic.table.felt", englishName: "Painted Felt",
                 descriptionKey: "cosmetic.table.felt.desc",
                 artworkID: "table.felt", unlock: .mastery(gameID: .texasHoldem, level: 3),
                 palette: ["forest", "acid"]),
        Cosmetic(id: "table.press", kind: .table,
                 nameKey: "cosmetic.table.press", englishName: "Press Sheet",
                 descriptionKey: "cosmetic.table.press.desc",
                 artworkID: "table.press", unlock: .premium, palette: ["cream", "cobalt"]),

        // MARK: Sound
        Cosmetic(id: "sound.paper", kind: .soundPack,
                 nameKey: "cosmetic.sound.paper", englishName: "Paper",
                 descriptionKey: "cosmetic.sound.paper.desc",
                 artworkID: "sound.paper", unlock: .fromTheStart),
        Cosmetic(id: "sound.felt", kind: .soundPack,
                 nameKey: "cosmetic.sound.felt", englishName: "Felt",
                 descriptionKey: "cosmetic.sound.felt.desc",
                 artworkID: "sound.felt", unlock: .mastery(gameID: .klondike, level: 3)),
        Cosmetic(id: "sound.press", kind: .soundPack,
                 nameKey: "cosmetic.sound.press", englishName: "Print Shop",
                 descriptionKey: "cosmetic.sound.press.desc",
                 artworkID: "sound.press", unlock: .premium)
    ]

    public static func cosmetic(_ id: String) -> Cosmetic? {
        all.first { $0.id == id }
    }

    public static func items(of kind: CosmeticKind) -> [Cosmetic] {
        all.filter { $0.kind == kind }
    }

    /// Everything available without paying, which is most of it.
    public static var earnable: [Cosmetic] { all.filter { !$0.requiresPremium } }
}

/// Works out what the player owns, from what they have done.
public struct CollectionEngine: Sendable {

    public init() {}

    /// Returns the ids that have just become available.
    @discardableResult
    public func refresh(state: inout CollectionState,
                        achievements: AchievementState,
                        challenge: ChallengeProgress,
                        mastery: MasteryState,
                        hasPremium: Bool) -> [String] {
        var newlyUnlocked: [String] = []
        for cosmetic in CosmeticCatalog.all where !state.unlocked.contains(cosmetic.id) {
            guard isEarned(cosmetic.unlock,
                           achievements: achievements,
                           challenge: challenge,
                           mastery: mastery,
                           hasPremium: hasPremium) else { continue }
            state.unlocked.insert(cosmetic.id)
            newlyUnlocked.append(cosmetic.id)
        }
        state.pendingReveals.append(contentsOf: newlyUnlocked)
        // A premium item stops being usable when the subscription lapses, so the
        // selection falls back rather than silently rendering something locked.
        if !hasPremium {
            if let theme = CosmeticCatalog.cosmetic(state.selectedTheme), theme.requiresPremium {
                state.selectedTheme = "theme.streetPrint"
            }
            if let back = CosmeticCatalog.cosmetic(state.selectedCardBack), back.requiresPremium {
                state.selectedCardBack = "cardback.deck"
            }
            if let table = CosmeticCatalog.cosmetic(state.selectedTable), table.requiresPremium {
                state.selectedTable = "table.ink"
            }
            if let sound = CosmeticCatalog.cosmetic(state.selectedSoundPack), sound.requiresPremium {
                state.selectedSoundPack = "sound.paper"
            }
        }
        return newlyUnlocked
    }

    private func isEarned(_ condition: UnlockCondition,
                          achievements: AchievementState,
                          challenge: ChallengeProgress,
                          mastery: MasteryState,
                          hasPremium: Bool) -> Bool {
        switch condition {
        case .fromTheStart: return true
        case let .achievement(id): return achievements.isUnlocked(id)
        case let .streak(days): return challenge.bestStreak >= days
        case let .mastery(gameID, level): return mastery.level(for: gameID) >= level
        case let .boss(id): return challenge.bossesDefeated.contains(id)
        case .premium: return hasPremium
        }
    }

    /// Whether the player may select something right now.
    public func canSelect(_ cosmetic: Cosmetic, state: CollectionState, hasPremium: Bool) -> Bool {
        if cosmetic.requiresPremium && !hasPremium { return false }
        return state.owns(cosmetic.id)
    }
}

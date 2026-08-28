import Foundation
import DeckCore
import DeckGames
import DeckAI

/// The launch library.
///
/// Everything the app knows about a game lives in its `GameDefinition`. The home
/// screen, search, filters, setup, statistics, achievements, mastery, the daily
/// challenge and Pass & Play all read from here, so adding the sixteenth game
/// means adding a function to this file and nothing else.
public enum GameCatalog {

    /// Builds a registry with every launch game in it, in shelf order.
    public static func makeRegistry() -> GameRegistry {
        let registry = GameRegistry()
        registry.register([
            crazyEights(),
            hearts(),
            texasHoldem(),
            klondike(),
            spades(),
            ginRummy(),
            goFish(),
            cheat(),
            freeCell(),
            president(),
            spider(),
            euchre(),
            rummy(),
            speed(),
            war()
        ])
        return registry
    }

    // MARK: - Shedding

    public static func crazyEights() -> GameDefinition {
        let plumbing = GameFactory.session(CrazyEightsRules(), agent: CrazyEightsAgent.choose)
        return GameDefinition(
            id: .crazyEights,
            nameKey: "game.crazyEights.name",
            englishName: "Crazy Eights",
            taglineKey: "game.crazyEights.tagline",
            descriptionKey: "game.crazyEights.description",
            categories: [.shedding, .family],
            playerRange: 2...6,
            duration: .quick,
            complexity: .easy,
            deckConfiguration: .standard52,
            variants: [
                GameVariant(id: "standard",
                            nameKey: "variant.crazyEights.standard",
                            summaryKey: "variant.crazyEights.standard.summary",
                            options: ["drawUntilPlayable": 1, "houseSpecials": 0]),
                GameVariant(id: "quickfire",
                            nameKey: "variant.crazyEights.quickfire",
                            summaryKey: "variant.crazyEights.quickfire.summary",
                            options: ["drawUntilPlayable": 0, "targetScore": 0]),
                GameVariant(id: "houseRules",
                            nameKey: "variant.crazyEights.house",
                            summaryKey: "variant.crazyEights.house.summary",
                            options: ["houseSpecials": 1, "useJokers": 1])
            ],
            setupOptions: [
                SetupOption(id: "targetScore",
                            titleKey: "setup.targetScore",
                            footnoteKey: "setup.targetScore.zeroIsOneDeal",
                            control: .choice(values: [0, 50, 100, 200],
                                             labelKeys: ["setup.oneDeal", "setup.to50", "setup.to100", "setup.to200"]),
                            defaultValue: 100),
                SetupOption(id: "handSize",
                            titleKey: "setup.handSize",
                            control: .stepper(range: 5...9, step: 1),
                            defaultValue: 5)
            ],
            supportsUndo: false,
            artworkID: "art.crazyEights",
            searchTerms: ["eights", "shedding", "switch", "wild", "family"],
            statistics: [
                StatisticDefinition(key: CrazyEightsStatistics.roundsWon,
                                    titleKey: "stat.crazy8.roundsWon", aggregation: .total, isHeadline: true),
                StatisticDefinition(key: CrazyEightsStatistics.eightsPlayed,
                                    titleKey: "stat.crazy8.eightsPlayed", aggregation: .total),
                StatisticDefinition(key: CrazyEightsStatistics.finalScore,
                                    titleKey: "stat.crazy8.bestScore", aggregation: .maximum, isHeadline: true)
            ],
            achievements: [
                AchievementDefinition(id: "crazy8.first",
                                      titleKey: "ach.crazy8.first", descriptionKey: "ach.crazy8.first.desc",
                                      category: .wins, tracking: .wins(gameID: .crazyEights), emblem: .stamp),
                AchievementDefinition(id: "crazy8.ten",
                                      titleKey: "ach.crazy8.ten", descriptionKey: "ach.crazy8.ten.desc",
                                      category: .wins, tracking: .wins(gameID: .crazyEights),
                                      targetOverride: 10, rewardID: "cardback.spray", emblem: .club,
                                      weight: .notable),
                AchievementDefinition(id: "crazy8.wildRun",
                                      titleKey: "ach.crazy8.wildRun", descriptionKey: "ach.crazy8.wildRun.desc",
                                      category: .skill,
                                      tracking: .metricAtLeast(key: CrazyEightsStatistics.eightsPlayed,
                                                               value: 4, gameID: .crazyEights),
                                      emblem: .bolt),
                AchievementDefinition(id: "crazy8.cleanSweep",
                                      titleKey: "ach.crazy8.sweep", descriptionKey: "ach.crazy8.sweep.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "crazy8.shed", gameID: .crazyEights),
                                      targetOverride: 25, emblem: .flame, weight: .notable)
            ],
            tutorial: Tutorials.crazyEights,
            recommendations: [.president, .cheat, .goFish],
            defaultOptions: ["targetScore": 100, "drawUntilPlayable": 1, "drawLimit": 12],
            makeSession: plumbing.make,
            restoreSession: plumbing.restore)
    }

    public static func president() -> GameDefinition {
        let plumbing = GameFactory.session(PresidentRules(), agent: PresidentAgent.choose)
        return GameDefinition(
            id: .president,
            nameKey: "game.president.name",
            englishName: "President",
            taglineKey: "game.president.tagline",
            descriptionKey: "game.president.description",
            categories: [.shedding, .strategy],
            playerRange: 3...7,
            duration: .short,
            complexity: .moderate,
            deckConfiguration: .standard52,
            variants: [
                GameVariant(id: "standard", nameKey: "variant.president.standard",
                            summaryKey: "variant.president.standard.summary",
                            options: ["twosAreBombs": 1, "exchangeCards": 1]),
                GameVariant(id: "single", nameKey: "variant.president.single",
                            summaryKey: "variant.president.single.summary",
                            options: ["rounds": 1, "exchangeCards": 0]),
                GameVariant(id: "strict", nameKey: "variant.president.strict",
                            summaryKey: "variant.president.strict.summary",
                            options: ["twosAreBombs": 0, "completionClears": 0])
            ],
            setupOptions: [
                SetupOption(id: "rounds", titleKey: "setup.rounds",
                            control: .stepper(range: 1...9, step: 1), defaultValue: 3)
            ],
            artworkID: "art.president",
            searchTerms: ["scum", "arsehole", "daihinmin", "shedding", "party"],
            statistics: [
                StatisticDefinition(key: PresidentStatistics.presidencies,
                                    titleKey: "stat.president.terms", aggregation: .total, isHeadline: true),
                StatisticDefinition(key: PresidentStatistics.bombs,
                                    titleKey: "stat.president.bombs", aggregation: .total),
                StatisticDefinition(key: PresidentStatistics.finalScore,
                                    titleKey: "stat.president.bestScore", aggregation: .maximum)
            ],
            achievements: [
                AchievementDefinition(id: "president.first", titleKey: "ach.president.first",
                                      descriptionKey: "ach.president.first.desc",
                                      category: .wins, tracking: .wins(gameID: .president), emblem: .crown),
                AchievementDefinition(id: "president.dynasty", titleKey: "ach.president.dynasty",
                                      descriptionKey: "ach.president.dynasty.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "president.dynasty", gameID: .president),
                                      rewardID: "avatar.president", emblem: .crown, weight: .landmark),
                AchievementDefinition(id: "president.bombardier", titleKey: "ach.president.bombardier",
                                      descriptionKey: "ach.president.bombardier.desc",
                                      category: .skill,
                                      tracking: .metricAtLeast(key: PresidentStatistics.bombs, value: 3,
                                                               gameID: .president),
                                      emblem: .bolt)
            ],
            tutorial: Tutorials.president,
            recommendations: [.crazyEights, .cheat],
            defaultOptions: ["rounds": 3, "twosAreBombs": 1, "completionClears": 1, "exchangeCards": 1],
            makeSession: plumbing.make,
            restoreSession: plumbing.restore)
    }

    // MARK: - Trick taking

    public static func hearts() -> GameDefinition {
        let plumbing = GameFactory.session(HeartsRules(), agent: HeartsAgent.choose)
        return GameDefinition(
            id: .hearts,
            nameKey: "game.hearts.name",
            englishName: "Hearts",
            taglineKey: "game.hearts.tagline",
            descriptionKey: "game.hearts.description",
            categories: [.trickTaking, .strategy],
            playerRange: 4...4,
            duration: .medium,
            complexity: .moderate,
            deckConfiguration: .standard52,
            variants: [
                GameVariant(id: "standard", nameKey: "variant.hearts.standard",
                            summaryKey: "variant.hearts.standard.summary"),
                GameVariant(id: "omnibus", nameKey: "variant.hearts.omnibus",
                            summaryKey: "variant.hearts.omnibus.summary",
                            options: ["jackOfDiamondsBonus": 1]),
                GameVariant(id: "subtractMoon", nameKey: "variant.hearts.subtractMoon",
                            summaryKey: "variant.hearts.subtractMoon.summary",
                            options: ["shootSubtracts": 1])
            ],
            setupOptions: [
                SetupOption(id: "targetScore", titleKey: "setup.targetScore",
                            control: .choice(values: [50, 100, 150],
                                             labelKeys: ["setup.to50", "setup.to100", "setup.to150"]),
                            defaultValue: 100)
            ],
            artworkID: "art.hearts",
            searchTerms: ["hearts", "trick", "queen of spades", "black lady", "shoot the moon"],
            statistics: [
                StatisticDefinition(key: HeartsStatistics.finalScore,
                                    titleKey: "stat.hearts.bestScore", aggregation: .minimum, isHeadline: true),
                StatisticDefinition(key: HeartsStatistics.moonShots,
                                    titleKey: "stat.hearts.moonShots", aggregation: .total, isHeadline: true),
                StatisticDefinition(key: HeartsStatistics.queensCaptured,
                                    titleKey: "stat.hearts.queens", aggregation: .total),
                StatisticDefinition(key: HeartsStatistics.tricksTaken,
                                    titleKey: "stat.hearts.tricks", aggregation: .total)
            ],
            achievements: [
                AchievementDefinition(id: "hearts.first", titleKey: "ach.hearts.first",
                                      descriptionKey: "ach.hearts.first.desc",
                                      category: .wins, tracking: .wins(gameID: .hearts), emblem: .heart),
                AchievementDefinition(id: "hearts.moon", titleKey: "ach.hearts.moon",
                                      descriptionKey: "ach.hearts.moon.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "hearts.shootTheMoon", gameID: .hearts),
                                      rewardID: "cardback.moon", emblem: .moon, weight: .landmark),
                AchievementDefinition(id: "hearts.spotless", titleKey: "ach.hearts.spotless",
                                      descriptionKey: "ach.hearts.spotless.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "hearts.spotless", gameID: .hearts),
                                      emblem: .star, weight: .notable),
                AchievementDefinition(id: "hearts.ten", titleKey: "ach.hearts.ten",
                                      descriptionKey: "ach.hearts.ten.desc",
                                      category: .wins, tracking: .wins(gameID: .hearts),
                                      targetOverride: 10, emblem: .heart, weight: .notable)
            ],
            tutorial: Tutorials.hearts,
            recommendations: [.spades, .euchre],
            defaultOptions: ["targetScore": 100, "protectQueenFirstTrick": 1, "mustBreakHearts": 1],
            makeSession: plumbing.make,
            restoreSession: plumbing.restore)
    }

    public static func spades() -> GameDefinition {
        let plumbing = GameFactory.session(SpadesRules(), agent: SpadesAgent.choose)
        return GameDefinition(
            id: .spades,
            nameKey: "game.spades.name",
            englishName: "Spades",
            taglineKey: "game.spades.tagline",
            descriptionKey: "game.spades.description",
            categories: [.trickTaking, .strategy],
            playerRange: 4...4,
            duration: .medium,
            complexity: .involved,
            deckConfiguration: .standard52,
            variants: [
                GameVariant(id: "standard", nameKey: "variant.spades.standard",
                            summaryKey: "variant.spades.standard.summary"),
                GameVariant(id: "blindNil", nameKey: "variant.spades.blindNil",
                            summaryKey: "variant.spades.blindNil.summary",
                            options: ["allowBlindNil": 1]),
                GameVariant(id: "quick", nameKey: "variant.spades.quick",
                            summaryKey: "variant.spades.quick.summary",
                            options: ["targetScore": 250])
            ],
            setupOptions: [
                SetupOption(id: "targetScore", titleKey: "setup.targetScore",
                            control: .choice(values: [250, 500],
                                             labelKeys: ["setup.to250", "setup.to500"]),
                            defaultValue: 500)
            ],
            artworkID: "art.spades",
            searchTerms: ["spades", "trick", "partnership", "nil", "bidding"],
            statistics: [
                StatisticDefinition(key: SpadesStatistics.finalScore,
                                    titleKey: "stat.spades.bestScore", aggregation: .maximum, isHeadline: true),
                StatisticDefinition(key: SpadesStatistics.nilsMade,
                                    titleKey: "stat.spades.nils", aggregation: .total, isHeadline: true),
                StatisticDefinition(key: SpadesStatistics.tricksWon,
                                    titleKey: "stat.spades.tricks", aggregation: .total),
                StatisticDefinition(key: SpadesStatistics.bags,
                                    titleKey: "stat.spades.bags", aggregation: .total)
            ],
            achievements: [
                AchievementDefinition(id: "spades.first", titleKey: "ach.spades.first",
                                      descriptionKey: "ach.spades.first.desc",
                                      category: .wins, tracking: .wins(gameID: .spades), emblem: .spade),
                AchievementDefinition(id: "spades.nil", titleKey: "ach.spades.nil",
                                      descriptionKey: "ach.spades.nil.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "spades.nilMade", gameID: .spades),
                                      rewardID: "cardback.stencil", emblem: .spade, weight: .notable),
                AchievementDefinition(id: "spades.tripleNil", titleKey: "ach.spades.tripleNil",
                                      descriptionKey: "ach.spades.tripleNil.desc",
                                      category: .skill,
                                      tracking: .metricAtLeast(key: SpadesStatistics.nilsMade, value: 3,
                                                               gameID: .spades),
                                      emblem: .crown, weight: .landmark)
            ],
            tutorial: Tutorials.spades,
            recommendations: [.hearts, .euchre],
            defaultOptions: ["targetScore": 500, "bagLimit": 10, "bagPenalty": 100, "nilValue": 100],
            makeSession: plumbing.make,
            restoreSession: plumbing.restore)
    }

    public static func euchre() -> GameDefinition {
        let plumbing = GameFactory.session(EuchreRules(), agent: EuchreAgent.choose)
        return GameDefinition(
            id: .euchre,
            nameKey: "game.euchre.name",
            englishName: "Euchre",
            taglineKey: "game.euchre.tagline",
            descriptionKey: "game.euchre.description",
            categories: [.trickTaking, .strategy],
            playerRange: 4...4,
            duration: .short,
            complexity: .involved,
            deckConfiguration: .euchre24,
            variants: [
                GameVariant(id: "standard", nameKey: "variant.euchre.standard",
                            summaryKey: "variant.euchre.standard.summary"),
                GameVariant(id: "noLoners", nameKey: "variant.euchre.noLoners",
                            summaryKey: "variant.euchre.noLoners.summary",
                            options: ["allowGoingAlone": 0])
            ],
            setupOptions: [
                SetupOption(id: "targetScore", titleKey: "setup.targetScore",
                            control: .choice(values: [10, 15],
                                             labelKeys: ["setup.to10", "setup.to15"]),
                            defaultValue: 10)
            ],
            artworkID: "art.euchre",
            searchTerms: ["euchre", "bower", "trump", "partnership", "24 card"],
            statistics: [
                StatisticDefinition(key: EuchreStatistics.finalScore,
                                    titleKey: "stat.euchre.bestScore", aggregation: .maximum, isHeadline: true),
                StatisticDefinition(key: EuchreStatistics.marches,
                                    titleKey: "stat.euchre.marches", aggregation: .total, isHeadline: true),
                StatisticDefinition(key: EuchreStatistics.lonerWins,
                                    titleKey: "stat.euchre.loners", aggregation: .total),
                StatisticDefinition(key: EuchreStatistics.euchres,
                                    titleKey: "stat.euchre.euchres", aggregation: .total)
            ],
            achievements: [
                AchievementDefinition(id: "euchre.first", titleKey: "ach.euchre.first",
                                      descriptionKey: "ach.euchre.first.desc",
                                      category: .wins, tracking: .wins(gameID: .euchre), emblem: .stamp),
                AchievementDefinition(id: "euchre.loner", titleKey: "ach.euchre.loner",
                                      descriptionKey: "ach.euchre.loner.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "euchre.loneMarch", gameID: .euchre),
                                      rewardID: "theme.archive", emblem: .crown, weight: .landmark)
            ],
            tutorial: Tutorials.euchre,
            recommendations: [.spades, .hearts],
            defaultOptions: ["targetScore": 10, "allowGoingAlone": 1],
            makeSession: plumbing.make,
            restoreSession: plumbing.restore)
    }

    // MARK: - Poker

    public static func texasHoldem() -> GameDefinition {
        let plumbing = GameFactory.session(TexasHoldemRules(), agent: PokerAgent.choose)
        return GameDefinition(
            id: .texasHoldem,
            nameKey: "game.texasHoldem.name",
            englishName: "Texas Hold'em",
            taglineKey: "game.texasHoldem.tagline",
            descriptionKey: "game.texasHoldem.description",
            categories: [.poker, .strategy],
            playerRange: 2...8,
            duration: .medium,
            complexity: .involved,
            deckConfiguration: .standard52,
            variants: [
                GameVariant(id: "cash", nameKey: "variant.poker.cash",
                            summaryKey: "variant.poker.cash.summary"),
                GameVariant(id: "tournament", nameKey: "variant.poker.tournament",
                            summaryKey: "variant.poker.tournament.summary",
                            options: ["blindIncreaseEvery": 8, "blindIncreasePercent": 50]),
                GameVariant(id: "turbo", nameKey: "variant.poker.turbo",
                            summaryKey: "variant.poker.turbo.summary",
                            options: ["startingChips": 400, "blindIncreaseEvery": 4,
                                      "blindIncreasePercent": 75])
            ],
            setupOptions: [
                SetupOption(id: "startingChips", titleKey: "setup.startingChips",
                            control: .choice(values: [400, 1000, 2500, 5000],
                                             labelKeys: ["setup.chips400", "setup.chips1000",
                                                         "setup.chips2500", "setup.chips5000"]),
                            defaultValue: 1000),
                SetupOption(id: "bigBlind", titleKey: "setup.blinds",
                            footnoteKey: "setup.blinds.footnote",
                            control: .choice(values: [10, 20, 50],
                                             labelKeys: ["setup.blinds5_10", "setup.blinds10_20",
                                                         "setup.blinds25_50"]),
                            defaultValue: 20),
                SetupOption(id: "handLimit", titleKey: "setup.handLimit",
                            footnoteKey: "setup.handLimit.footnote",
                            control: .choice(values: [0, 20, 50],
                                             labelKeys: ["setup.untilOneLeft", "setup.hands20", "setup.hands50"]),
                            defaultValue: 0)
            ],
            artworkID: "art.poker",
            searchTerms: ["poker", "holdem", "hold em", "no limit", "flop", "bluff", "chips"],
            statistics: [
                StatisticDefinition(key: PokerStatistics.handsWon,
                                    titleKey: "stat.poker.handsWon", aggregation: .total, isHeadline: true),
                StatisticDefinition(key: PokerStatistics.biggestPot,
                                    titleKey: "stat.poker.biggestPot", aggregation: .maximum,
                                    format: .chips, isHeadline: true),
                StatisticDefinition(key: PokerStatistics.bestHand,
                                    titleKey: "stat.poker.bestHand", aggregation: .maximum),
                StatisticDefinition(key: PokerStatistics.showdownsWon,
                                    titleKey: "stat.poker.showdowns", aggregation: .total),
                StatisticDefinition(key: PokerStatistics.handsPlayed,
                                    titleKey: "stat.poker.handsPlayed", aggregation: .total)
            ],
            achievements: [
                AchievementDefinition(id: "poker.first", titleKey: "ach.poker.first",
                                      descriptionKey: "ach.poker.first.desc",
                                      category: .wins, tracking: .wins(gameID: .texasHoldem), emblem: .stamp),
                AchievementDefinition(id: "poker.royalFlush", titleKey: "ach.poker.royalFlush",
                                      descriptionKey: "ach.poker.royalFlush.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "poker.royalFlush", gameID: .texasHoldem),
                                      rewardID: "cardback.royal", emblem: .royalFan, weight: .landmark),
                AchievementDefinition(id: "poker.quads", titleKey: "ach.poker.quads",
                                      descriptionKey: "ach.poker.quads.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "poker.quads", gameID: .texasHoldem),
                                      emblem: .diamond, weight: .notable),
                AchievementDefinition(id: "poker.bluff", titleKey: "ach.poker.bluff",
                                      descriptionKey: "ach.poker.bluff.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "poker.tookItDown", gameID: .texasHoldem),
                                      targetOverride: 20, emblem: .flame),
                AchievementDefinition(id: "poker.expert", titleKey: "ach.poker.expert",
                                      descriptionKey: "ach.poker.expert.desc",
                                      category: .skill,
                                      tracking: .winAtDifficulty(.expert, gameID: .texasHoldem, count: 1),
                                      rewardID: "avatar.shark", emblem: .crown, weight: .landmark),
                AchievementDefinition(id: "poker.ten", titleKey: "ach.poker.ten",
                                      descriptionKey: "ach.poker.ten.desc",
                                      category: .wins, tracking: .wins(gameID: .texasHoldem),
                                      targetOverride: 10, emblem: .stamp, weight: .notable)
            ],
            tutorial: Tutorials.texasHoldem,
            recommendations: [.ginRummy, .cheat],
            defaultOptions: ["startingChips": 1000, "smallBlind": 10, "bigBlind": 20],
            makeSession: plumbing.make,
            restoreSession: plumbing.restore)
    }

    // MARK: - Rummy

    public static func ginRummy() -> GameDefinition {
        let plumbing = GameFactory.session(GinRummyRules(), agent: GinRummyAgent.choose)
        return GameDefinition(
            id: .ginRummy,
            nameKey: "game.ginRummy.name",
            englishName: "Gin Rummy",
            taglineKey: "game.ginRummy.tagline",
            descriptionKey: "game.ginRummy.description",
            categories: [.rummy, .strategy],
            playerRange: 2...2,
            duration: .short,
            complexity: .moderate,
            deckConfiguration: .standard52,
            variants: [
                GameVariant(id: "standard", nameKey: "variant.gin.standard",
                            summaryKey: "variant.gin.standard.summary"),
                GameVariant(id: "hollywood", nameKey: "variant.gin.hollywood",
                            summaryKey: "variant.gin.hollywood.summary",
                            options: ["targetScore": 150]),
                GameVariant(id: "oklahoma", nameKey: "variant.gin.oklahoma",
                            summaryKey: "variant.gin.oklahoma.summary",
                            options: ["knockThreshold": 5])
            ],
            setupOptions: [
                SetupOption(id: "targetScore", titleKey: "setup.targetScore",
                            control: .choice(values: [100, 150, 200],
                                             labelKeys: ["setup.to100", "setup.to150", "setup.to200"]),
                            defaultValue: 100)
            ],
            artworkID: "art.ginRummy",
            searchTerms: ["gin", "rummy", "melds", "knock", "two player"],
            statistics: [
                StatisticDefinition(key: GinRummyStatistics.gins,
                                    titleKey: "stat.gin.gins", aggregation: .total, isHeadline: true),
                StatisticDefinition(key: GinRummyStatistics.undercuts,
                                    titleKey: "stat.gin.undercuts", aggregation: .total, isHeadline: true),
                StatisticDefinition(key: GinRummyStatistics.knocks,
                                    titleKey: "stat.gin.knocks", aggregation: .total),
                StatisticDefinition(key: GinRummyStatistics.finalScore,
                                    titleKey: "stat.gin.bestScore", aggregation: .maximum)
            ],
            achievements: [
                AchievementDefinition(id: "gin.first", titleKey: "ach.gin.first",
                                      descriptionKey: "ach.gin.first.desc",
                                      category: .wins, tracking: .wins(gameID: .ginRummy), emblem: .stamp),
                AchievementDefinition(id: "gin.gin", titleKey: "ach.gin.gin",
                                      descriptionKey: "ach.gin.gin.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "gin.gin", gameID: .ginRummy),
                                      emblem: .star, weight: .notable),
                AchievementDefinition(id: "gin.shutout", titleKey: "ach.gin.shutout",
                                      descriptionKey: "ach.gin.shutout.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "gin.shutout", gameID: .ginRummy),
                                      rewardID: "cardback.archive", emblem: .crown, weight: .landmark)
            ],
            tutorial: Tutorials.ginRummy,
            recommendations: [.rummy, .texasHoldem],
            defaultOptions: ["targetScore": 100, "knockThreshold": 10, "ginBonus": 25, "undercutBonus": 25],
            makeSession: plumbing.make,
            restoreSession: plumbing.restore)
    }

    public static func rummy() -> GameDefinition {
        let plumbing = GameFactory.session(RummyRules(), agent: RummyAgent.choose)
        return GameDefinition(
            id: .rummy,
            nameKey: "game.rummy.name",
            englishName: "Rummy",
            taglineKey: "game.rummy.tagline",
            descriptionKey: "game.rummy.description",
            categories: [.rummy, .family],
            playerRange: 2...6,
            duration: .short,
            complexity: .easy,
            deckConfiguration: .standard52,
            variants: [
                GameVariant(id: "standard", nameKey: "variant.rummy.standard",
                            summaryKey: "variant.rummy.standard.summary"),
                GameVariant(id: "noLayOff", nameKey: "variant.rummy.noLayOff",
                            summaryKey: "variant.rummy.noLayOff.summary",
                            options: ["allowLayOff": 0]),
                GameVariant(id: "fiveHundred", nameKey: "variant.rummy.fiveHundred",
                            summaryKey: "variant.rummy.fiveHundred.summary",
                            options: ["targetScore": 500])
            ],
            setupOptions: [
                SetupOption(id: "targetScore", titleKey: "setup.targetScore",
                            control: .choice(values: [100, 250, 500],
                                             labelKeys: ["setup.to100", "setup.to250", "setup.to500"]),
                            defaultValue: 100)
            ],
            artworkID: "art.rummy",
            searchTerms: ["rummy", "melds", "sets", "runs", "family"],
            statistics: [
                StatisticDefinition(key: RummyStatistics.timesOut,
                                    titleKey: "stat.rummy.timesOut", aggregation: .total, isHeadline: true),
                StatisticDefinition(key: RummyStatistics.meldsLaid,
                                    titleKey: "stat.rummy.melds", aggregation: .total),
                StatisticDefinition(key: RummyStatistics.finalScore,
                                    titleKey: "stat.rummy.bestScore", aggregation: .maximum, isHeadline: true)
            ],
            achievements: [
                AchievementDefinition(id: "rummy.first", titleKey: "ach.rummy.first",
                                      descriptionKey: "ach.rummy.first.desc",
                                      category: .wins, tracking: .wins(gameID: .rummy), emblem: .stamp),
                AchievementDefinition(id: "rummy.rummy", titleKey: "ach.rummy.rummy",
                                      descriptionKey: "ach.rummy.rummy.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "rummy.rummy", gameID: .rummy),
                                      emblem: .bolt, weight: .notable)
            ],
            tutorial: Tutorials.rummy,
            recommendations: [.ginRummy, .goFish],
            defaultOptions: ["targetScore": 100, "allowLayOff": 1, "rummyBonus": 1],
            makeSession: plumbing.make,
            restoreSession: plumbing.restore)
    }

    // MARK: - Solitaire

    public static func klondike() -> GameDefinition {
        let plumbing = GameFactory.soloSession(KlondikeRules())
        return GameDefinition(
            id: .klondike,
            nameKey: "game.klondike.name",
            englishName: "Klondike",
            taglineKey: "game.klondike.tagline",
            descriptionKey: "game.klondike.description",
            categories: [.solitaire],
            playerRange: 1...1,
            duration: .short,
            complexity: .easy,
            deckConfiguration: .standard52,
            variants: [
                GameVariant(id: "drawOne", nameKey: "variant.klondike.drawOne",
                            summaryKey: "variant.klondike.drawOne.summary",
                            options: ["drawCount": 1]),
                GameVariant(id: "drawThree", nameKey: "variant.klondike.drawThree",
                            summaryKey: "variant.klondike.drawThree.summary",
                            options: ["drawCount": 3]),
                GameVariant(id: "limited", nameKey: "variant.klondike.limited",
                            summaryKey: "variant.klondike.limited.summary",
                            options: ["drawCount": 3, "redealLimit": 2])
            ],
            setupOptions: [
                SetupOption(id: "drawCount", titleKey: "setup.drawMode",
                            control: .choice(values: [1, 3], labelKeys: ["setup.drawOne", "setup.drawThree"]),
                            defaultValue: 1),
                SetupOption(id: "redealLimit", titleKey: "setup.redeals",
                            footnoteKey: "setup.redeals.zeroIsUnlimited",
                            control: .stepper(range: 0...5, step: 1), defaultValue: 0)
            ],
            supportsPassAndPlay: false,
            supportsUndo: true,
            supportsAIOpponents: false,
            artworkID: "art.klondike",
            searchTerms: ["klondike", "solitaire", "patience", "solo", "one player"],
            statistics: [
                StatisticDefinition(key: KlondikeStatistics.score,
                                    titleKey: "stat.klondike.bestScore", aggregation: .maximum, isHeadline: true),
                StatisticDefinition(key: KlondikeStatistics.moves,
                                    titleKey: "stat.klondike.fewestMoves", aggregation: .minimum, isHeadline: true),
                StatisticDefinition(key: KlondikeStatistics.foundationCards,
                                    titleKey: "stat.klondike.foundations", aggregation: .maximum)
            ],
            achievements: [
                AchievementDefinition(id: "klondike.first", titleKey: "ach.klondike.first",
                                      descriptionKey: "ach.klondike.first.desc",
                                      category: .wins, tracking: .wins(gameID: .klondike), emblem: .stamp),
                AchievementDefinition(id: "klondike.noUndo", titleKey: "ach.klondike.noUndo",
                                      descriptionKey: "ach.klondike.noUndo.desc",
                                      category: .skill,
                                      tracking: .metricAtMost(key: GlobalMetrics.undoCount, value: 0,
                                                              gameID: .klondike),
                                      emblem: .star, weight: .notable),
                AchievementDefinition(id: "klondike.fast", titleKey: "ach.klondike.fast",
                                      descriptionKey: "ach.klondike.fast.desc",
                                      category: .speed,
                                      tracking: .metricAtMost(key: GlobalMetrics.durationSeconds, value: 300,
                                                              gameID: .klondike),
                                      rewardID: "cardback.speed", emblem: .clock, weight: .notable),
                AchievementDefinition(id: "klondike.drawThree", titleKey: "ach.klondike.drawThree",
                                      descriptionKey: "ach.klondike.drawThree.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "klondike.drawThree", gameID: .klondike),
                                      emblem: .diamond)
            ],
            tutorial: Tutorials.klondike,
            recommendations: [.freeCell, .spider],
            defaultOptions: ["drawCount": 1, "redealLimit": 0],
            makeSession: plumbing.make,
            restoreSession: plumbing.restore)
    }

    public static func freeCell() -> GameDefinition {
        let plumbing = GameFactory.soloSession(FreeCellRules())
        return GameDefinition(
            id: .freeCell,
            nameKey: "game.freeCell.name",
            englishName: "FreeCell",
            taglineKey: "game.freeCell.tagline",
            descriptionKey: "game.freeCell.description",
            categories: [.solitaire, .strategy],
            playerRange: 1...1,
            duration: .short,
            complexity: .moderate,
            deckConfiguration: .standard52,
            variants: [
                GameVariant(id: "standard", nameKey: "variant.freecell.standard",
                            summaryKey: "variant.freecell.standard.summary", options: ["cellCount": 4]),
                GameVariant(id: "threeCells", nameKey: "variant.freecell.three",
                            summaryKey: "variant.freecell.three.summary", options: ["cellCount": 3]),
                GameVariant(id: "twoCells", nameKey: "variant.freecell.two",
                            summaryKey: "variant.freecell.two.summary", options: ["cellCount": 2])
            ],
            setupOptions: [
                SetupOption(id: "cellCount", titleKey: "setup.freeCells",
                            control: .stepper(range: 2...6, step: 1), defaultValue: 4)
            ],
            supportsPassAndPlay: false,
            supportsUndo: true,
            supportsAIOpponents: false,
            artworkID: "art.freeCell",
            searchTerms: ["freecell", "free cell", "solitaire", "patience", "solvable"],
            statistics: [
                StatisticDefinition(key: FreeCellStatistics.moves,
                                    titleKey: "stat.freecell.fewestMoves", aggregation: .minimum, isHeadline: true),
                StatisticDefinition(key: FreeCellStatistics.cellsUsed,
                                    titleKey: "stat.freecell.cells", aggregation: .minimum)
            ],
            achievements: [
                AchievementDefinition(id: "freecell.first", titleKey: "ach.freecell.first",
                                      descriptionKey: "ach.freecell.first.desc",
                                      category: .wins, tracking: .wins(gameID: .freeCell), emblem: .stamp),
                AchievementDefinition(id: "freecell.tight", titleKey: "ach.freecell.tight",
                                      descriptionKey: "ach.freecell.tight.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "freecell.fewCells", gameID: .freeCell),
                                      rewardID: "theme.streetPrint", emblem: .crown, weight: .landmark),
                AchievementDefinition(id: "freecell.efficient", titleKey: "ach.freecell.efficient",
                                      descriptionKey: "ach.freecell.efficient.desc",
                                      category: .skill,
                                      tracking: .metricAtMost(key: FreeCellStatistics.moves, value: 70,
                                                              gameID: .freeCell),
                                      emblem: .bolt, weight: .notable)
            ],
            tutorial: Tutorials.freeCell,
            recommendations: [.klondike, .spider],
            defaultOptions: ["cellCount": 4],
            makeSession: plumbing.make,
            restoreSession: plumbing.restore)
    }

    public static func spider() -> GameDefinition {
        let plumbing = GameFactory.soloSession(SpiderRules())
        return GameDefinition(
            id: .spider,
            nameKey: "game.spider.name",
            englishName: "Spider",
            taglineKey: "game.spider.tagline",
            descriptionKey: "game.spider.description",
            categories: [.solitaire, .strategy],
            playerRange: 1...1,
            duration: .medium,
            complexity: .involved,
            deckConfiguration: .spider(suitCount: 1),
            variants: [
                GameVariant(id: "oneSuit", nameKey: "variant.spider.one",
                            summaryKey: "variant.spider.one.summary", options: ["suitCount": 1]),
                GameVariant(id: "twoSuit", nameKey: "variant.spider.two",
                            summaryKey: "variant.spider.two.summary", options: ["suitCount": 2]),
                GameVariant(id: "fourSuit", nameKey: "variant.spider.four",
                            summaryKey: "variant.spider.four.summary", options: ["suitCount": 4])
            ],
            setupOptions: [
                SetupOption(id: "suitCount", titleKey: "setup.suits",
                            control: .choice(values: [1, 2, 4],
                                             labelKeys: ["setup.oneSuit", "setup.twoSuits", "setup.fourSuits"]),
                            defaultValue: 1)
            ],
            supportsPassAndPlay: false,
            supportsUndo: true,
            supportsAIOpponents: false,
            artworkID: "art.spider",
            searchTerms: ["spider", "solitaire", "two decks", "runs", "patience"],
            statistics: [
                StatisticDefinition(key: SpiderStatistics.moves,
                                    titleKey: "stat.spider.fewestMoves", aggregation: .minimum, isHeadline: true),
                StatisticDefinition(key: SpiderStatistics.suits,
                                    titleKey: "stat.spider.hardestSuits", aggregation: .maximum, isHeadline: true)
            ],
            achievements: [
                AchievementDefinition(id: "spider.first", titleKey: "ach.spider.first",
                                      descriptionKey: "ach.spider.first.desc",
                                      category: .wins, tracking: .wins(gameID: .spider), emblem: .stamp),
                AchievementDefinition(id: "spider.twoSuit", titleKey: "ach.spider.twoSuit",
                                      descriptionKey: "ach.spider.twoSuit.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "spider.twoSuit", gameID: .spider),
                                      emblem: .diamond, weight: .notable),
                AchievementDefinition(id: "spider.fourSuit", titleKey: "ach.spider.fourSuit",
                                      descriptionKey: "ach.spider.fourSuit.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "spider.fourSuit", gameID: .spider),
                                      rewardID: "cardback.web", emblem: .crown, weight: .landmark)
            ],
            tutorial: Tutorials.spider,
            recommendations: [.klondike, .freeCell],
            defaultOptions: ["suitCount": 1],
            makeSession: plumbing.make,
            restoreSession: plumbing.restore)
    }

    // MARK: - Family, bluff and speed

    public static func goFish() -> GameDefinition {
        let plumbing = GameFactory.session(GoFishRules(), agent: GoFishAgent.choose)
        return GameDefinition(
            id: .goFish,
            nameKey: "game.goFish.name",
            englishName: "Go Fish",
            taglineKey: "game.goFish.tagline",
            descriptionKey: "game.goFish.description",
            categories: [.family],
            playerRange: 2...6,
            duration: .quick,
            complexity: .easy,
            deckConfiguration: .standard52,
            variants: [
                GameVariant(id: "standard", nameKey: "variant.gofish.standard",
                            summaryKey: "variant.gofish.standard.summary"),
                GameVariant(id: "oneTurn", nameKey: "variant.gofish.oneTurn",
                            summaryKey: "variant.gofish.oneTurn.summary",
                            options: ["askAgainOnHit": 0])
            ],
            setupOptions: [
                SetupOption(id: "handSize", titleKey: "setup.handSize",
                            control: .stepper(range: 5...9, step: 1), defaultValue: 7)
            ],
            artworkID: "art.goFish",
            searchTerms: ["go fish", "fish", "books", "children", "family", "easy"],
            statistics: [
                StatisticDefinition(key: GoFishStatistics.books,
                                    titleKey: "stat.gofish.books", aggregation: .maximum, isHeadline: true),
                StatisticDefinition(key: GoFishStatistics.luckyDraws,
                                    titleKey: "stat.gofish.luckyDraws", aggregation: .total)
            ],
            achievements: [
                AchievementDefinition(id: "gofish.first", titleKey: "ach.gofish.first",
                                      descriptionKey: "ach.gofish.first.desc",
                                      category: .wins, tracking: .wins(gameID: .goFish), emblem: .stamp),
                AchievementDefinition(id: "gofish.landslide", titleKey: "ach.gofish.landslide",
                                      descriptionKey: "ach.gofish.landslide.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "gofish.landslide", gameID: .goFish),
                                      emblem: .star, weight: .notable)
            ],
            tutorial: Tutorials.goFish,
            recommendations: [.crazyEights, .war],
            defaultOptions: ["handSize": 7, "askAgainOnHit": 1, "luckyDrawContinues": 1],
            makeSession: plumbing.make,
            restoreSession: plumbing.restore)
    }

    public static func war() -> GameDefinition {
        let plumbing = GameFactory.session(WarRules(), agent: WarAgent.choose)
        return GameDefinition(
            id: .war,
            nameKey: "game.war.name",
            englishName: "War",
            taglineKey: "game.war.tagline",
            descriptionKey: "game.war.description",
            categories: [.family, .speed],
            playerRange: 2...4,
            duration: .quick,
            complexity: .easy,
            deckConfiguration: .standard52,
            variants: [
                GameVariant(id: "standard", nameKey: "variant.war.standard",
                            summaryKey: "variant.war.standard.summary"),
                GameVariant(id: "quick", nameKey: "variant.war.quick",
                            summaryKey: "variant.war.quick.summary",
                            options: ["flipLimit": 120, "warStake": 1])
            ],
            setupOptions: [
                SetupOption(id: "warStake", titleKey: "setup.warStake",
                            control: .stepper(range: 1...3, step: 1), defaultValue: 3)
            ],
            supportsDailyChallenge: false,
            artworkID: "art.war",
            searchTerms: ["war", "battle", "children", "luck", "easy", "quick"],
            statistics: [
                StatisticDefinition(key: WarStatistics.wars,
                                    titleKey: "stat.war.wars", aggregation: .total, isHeadline: true),
                StatisticDefinition(key: WarStatistics.battlesWon,
                                    titleKey: "stat.war.battles", aggregation: .total),
                StatisticDefinition(key: WarStatistics.flips,
                                    titleKey: "stat.war.shortestGame", aggregation: .minimum)
            ],
            achievements: [
                AchievementDefinition(id: "war.first", titleKey: "ach.war.first",
                                      descriptionKey: "ach.war.first.desc",
                                      category: .wins, tracking: .wins(gameID: .war), emblem: .stamp),
                AchievementDefinition(id: "war.campaign", titleKey: "ach.war.campaign",
                                      descriptionKey: "ach.war.campaign.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "war.longCampaign", gameID: .war),
                                      emblem: .flame)
            ],
            tutorial: Tutorials.war,
            recommendations: [.goFish, .speed],
            defaultOptions: ["warStake": 3, "flipLimit": 600],
            makeSession: plumbing.make,
            restoreSession: plumbing.restore)
    }

    public static func cheat() -> GameDefinition {
        let plumbing = GameFactory.session(CheatRules(), agent: CheatAgent.choose)
        return GameDefinition(
            id: .cheat,
            nameKey: "game.cheat.name",
            englishName: "Cheat",
            taglineKey: "game.cheat.tagline",
            descriptionKey: "game.cheat.description",
            categories: [.bluff, .family],
            playerRange: 3...6,
            duration: .short,
            complexity: .easy,
            deckConfiguration: .standard52,
            variants: [
                GameVariant(id: "standard", nameKey: "variant.cheat.standard",
                            summaryKey: "variant.cheat.standard.summary"),
                GameVariant(id: "freeChoice", nameKey: "variant.cheat.freeChoice",
                            summaryKey: "variant.cheat.freeChoice.summary",
                            options: ["sequentialRanks": 0]),
                GameVariant(id: "fast", nameKey: "variant.cheat.fast",
                            summaryKey: "variant.cheat.fast.summary",
                            options: ["onlyNextPlayerChallenges": 1])
            ],
            setupOptions: [
                SetupOption(id: "maximumPerTurn", titleKey: "setup.maxPerTurn",
                            control: .stepper(range: 1...4, step: 1), defaultValue: 4)
            ],
            artworkID: "art.cheat",
            searchTerms: ["cheat", "bluff", "i doubt it", "lying", "party", "pass and play"],
            statistics: [
                StatisticDefinition(key: CheatStatistics.bluffsCaught,
                                    titleKey: "stat.cheat.caught", aggregation: .total, isHeadline: true),
                StatisticDefinition(key: CheatStatistics.bluffsMade,
                                    titleKey: "stat.cheat.bluffs", aggregation: .total, isHeadline: true),
                StatisticDefinition(key: CheatStatistics.badCalls,
                                    titleKey: "stat.cheat.badCalls", aggregation: .total)
            ],
            achievements: [
                AchievementDefinition(id: "cheat.first", titleKey: "ach.cheat.first",
                                      descriptionKey: "ach.cheat.first.desc",
                                      category: .wins, tracking: .wins(gameID: .cheat), emblem: .stamp),
                AchievementDefinition(id: "cheat.perfectRead", titleKey: "ach.cheat.perfectRead",
                                      descriptionKey: "ach.cheat.perfectRead.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "cheat.perfectRead", gameID: .cheat),
                                      rewardID: "avatar.liar", emblem: .skull, weight: .notable),
                AchievementDefinition(id: "cheat.serialLiar", titleKey: "ach.cheat.serialLiar",
                                      descriptionKey: "ach.cheat.serialLiar.desc",
                                      category: .skill,
                                      tracking: .highlight(code: "cheat.serialLiar", gameID: .cheat),
                                      emblem: .flame)
            ],
            tutorial: Tutorials.cheat,
            recommendations: [.president, .crazyEights],
            defaultOptions: ["maximumPerTurn": 4, "sequentialRanks": 1],
            makeSession: plumbing.make,
            restoreSession: plumbing.restore)
    }

    public static func speed() -> GameDefinition {
        let plumbing = GameFactory.session(SpeedRules(), agent: SpeedAgent.choose)
        return GameDefinition(
            id: .speed,
            nameKey: "game.speed.name",
            englishName: "Speed",
            taglineKey: "game.speed.tagline",
            descriptionKey: "game.speed.description",
            categories: [.speed],
            playerRange: 2...2,
            duration: .quick,
            complexity: .easy,
            deckConfiguration: .standard52,
            variants: [
                GameVariant(id: "standard", nameKey: "variant.speed.standard",
                            summaryKey: "variant.speed.standard.summary"),
                GameVariant(id: "wide", nameKey: "variant.speed.wide",
                            summaryKey: "variant.speed.wide.summary", options: ["handSize": 7])
            ],
            setupOptions: [
                SetupOption(id: "handSize", titleKey: "setup.handSize",
                            control: .stepper(range: 3...7, step: 1), defaultValue: 5)
            ],
            // Both players reach for the same piles at once, so there is nothing
            // to pass and nothing to hide.
            supportsPassAndPlay: false,
            artworkID: "art.speed",
            searchTerms: ["speed", "spit", "fast", "reflex", "two player"],
            statistics: [
                StatisticDefinition(key: SpeedStatistics.cardsPlayed,
                                    titleKey: "stat.speed.cardsPlayed", aggregation: .total, isHeadline: true),
                StatisticDefinition(key: SpeedStatistics.flips,
                                    titleKey: "stat.speed.fewestFlips", aggregation: .minimum, isHeadline: true)
            ],
            achievements: [
                AchievementDefinition(id: "speed.first", titleKey: "ach.speed.first",
                                      descriptionKey: "ach.speed.first.desc",
                                      category: .wins, tracking: .wins(gameID: .speed), emblem: .bolt),
                AchievementDefinition(id: "speed.clean", titleKey: "ach.speed.clean",
                                      descriptionKey: "ach.speed.clean.desc",
                                      category: .speed,
                                      tracking: .highlight(code: "speed.clean", gameID: .speed),
                                      rewardID: "cardback.motion", emblem: .bolt, weight: .notable),
                AchievementDefinition(id: "speed.fast", titleKey: "ach.speed.fast",
                                      descriptionKey: "ach.speed.fast.desc",
                                      category: .speed,
                                      tracking: .metricAtMost(key: GlobalMetrics.durationSeconds, value: 90,
                                                              gameID: .speed),
                                      emblem: .clock)
            ],
            tutorial: Tutorials.speed,
            recommendations: [.war, .crazyEights],
            defaultOptions: ["handSize": 5, "replacementSize": 5],
            makeSession: plumbing.make,
            restoreSession: plumbing.restore)
    }
}

import XCTest
import DeckCore
import DeckGames
import DeckCatalog
@testable import DeckProgression

private func configuration(gameID: GameID = .hearts,
                           humans: Int = 1,
                           difficulty: AIDifficulty = .skilled,
                           seats total: Int = 4) -> GameConfiguration {
    var seats: [Seat] = []
    let cast: [AIPersonalityID] = [.hal, .pedro, .calvin, .rohan]
    for index in 0..<total {
        seats.append(index < humans
            ? Seat(id: SeatID(index), displayName: "P\(index)", controller: .human(profileID: "p\(index)"))
            : Seat(id: SeatID(index), displayName: "AI\(index)",
                   controller: .ai(personality: cast[index % cast.count], difficulty: difficulty)))
    }
    return GameConfiguration(gameID: gameID, seating: SeatingPlan(seats: seats), seed: 1)
}

final class BossTests: XCTestCase {

    func testThereAreSevenBossesAndTheyAreAllDistinct() {
        XCTAssertEqual(BossCast.all.count, 7)
        XCTAssertEqual(Set(BossCast.all.map(\.id)).count, 7)
        XCTAssertEqual(Set(BossCast.all.map(\.displayName)).count, 7)
        XCTAssertEqual(Set(BossCast.all.map(\.colourToken)).count, 7,
                       "seven bosses, seven colours")
        XCTAssertGreaterThanOrEqual(Set(BossCast.all.map(\.idle)).count, 5,
                                    "the portraits do not all do the same thing")
    }

    func testEveryBossIsFullyDressedAndHasLore() {
        for boss in BossCast.all {
            XCTAssertFalse(boss.titleKey.isEmpty, "\(boss.displayName) has no title")
            XCTAssertFalse(boss.loreKey.isEmpty)
            XCTAssertFalse(boss.englishLore.isEmpty, "\(boss.displayName) has no story")
            XCTAssertFalse(boss.groundToken.isEmpty)
            XCTAssertFalse(boss.modifiers.isEmpty,
                           "\(boss.displayName) changes nothing, so they are a picture")
            XCTAssertNotNil(AICast.all.first { $0.id == boss.personalityID },
                            "\(boss.displayName) is not backed by a real personality")
        }
    }

    func testEveryModifierExplainsItselfInWords() {
        for boss in BossCast.all {
            for modifier in boss.modifiers {
                XCTAssertFalse(modifier.localizationKey.isEmpty)
                XCTAssertFalse(modifier.englishExplanation.isEmpty,
                               "\(boss.displayName)'s modifier cannot be described to the player")
                XCTAssertFalse(modifier.arguments.isEmpty)
            }
        }
    }

    func testABossActuallyChangesTheConfiguration() {
        let base = configuration()
        for boss in BossCast.all {
            let modified = boss.apply(to: base)
            XCTAssertEqual(modified.bossID, boss.id)
            var changedSomething = modified.difficultyScale != base.difficultyScale
                || modified.options != base.options
            // A boss whose only modifiers move the objective changes the
            // challenge rather than the deal, which counts.
            if boss.objectiveTightening != 0 || boss.scoreMultiplierPercent != 100 {
                changedSomething = true
            }
            XCTAssertTrue(changedSomething,
                          "\(boss.displayName) leaves the game exactly as it was")
        }
    }

    func testSharperOpponentsRaisesTheDifficultyScale() {
        let base = configuration()
        let sharpened = BossCast.pedro.apply(to: base)
        XCTAssertGreaterThan(sharpened.difficultyScale, base.difficultyScale)
        XCTAssertEqual(sharpened.difficultyScale, base.difficultyScale * 1.30, accuracy: 0.0001)
    }

    func testBossSelectionIsDeterministicAndPrefersAffinity() {
        for gameID in [GameID.texasHoldem, .hearts, .cheat, .klondike] {
            for seed in [UInt64(1), 99, 12345, 987_654_321] {
                let first = BossCast.boss(forSeed: seed, gameID: gameID)
                let second = BossCast.boss(forSeed: seed, gameID: gameID)
                XCTAssertEqual(first.id, second.id, "the same day must bring the same boss")
                let affine = BossCast.all.filter { $0.affinities.contains(gameID) }
                if !affine.isEmpty {
                    XCTAssertTrue(affine.contains { $0.id == first.id },
                                  "\(gameID) should draw a boss who suits it")
                }
            }
        }
    }

    func testBossLookupByIDFindsThemAll() {
        for boss in BossCast.all {
            XCTAssertEqual(BossCast.boss(boss.id)?.id, boss.id)
        }
        XCTAssertNil(BossCast.boss("nobody"))
    }

    func testThreatOrdersTheBossesSensibly() {
        let threats = BossCast.all.map { BossCast.threat($0) }
        XCTAssertTrue(threats.allSatisfy { $0 > 0 }, "every boss is worth something")
        XCTAssertGreaterThan(Set(threats).count, 3, "they are not all equally dangerous")
    }
}

final class StatisticsTests: XCTestCase {
    private let registry = GameCatalog.makeRegistry()
    private var engine: StatisticsEngine { StatisticsEngine(registry: registry) }

    func testAWinIsCountedGloballyAndForTheGame() {
        var state = StatisticsState()
        engine.record(result: makeResult(score: 42, duration: 300, turns: 52),
                      gameID: .hearts, seat: SeatID(0),
                      configuration: configuration(), into: &state)

        XCTAssertEqual(state.global.gamesPlayed, 1)
        XCTAssertEqual(state.global.gamesWon, 1)
        XCTAssertEqual(state.record(for: .hearts).gamesWon, 1)
        XCTAssertEqual(state.record(for: .spades).gamesPlayed, 0, "other games are untouched")
        XCTAssertTrue(state.gamesWonAtLeastOnce.contains(.hearts))
        XCTAssertEqual(state.global.totalSeconds, 300)
        XCTAssertEqual(state.global.fastestWinSeconds, 300)
        XCTAssertNotNil(state.global.lastPlayed)
    }

    func testALossDoesNotSetAFastestWin() {
        var state = StatisticsState()
        engine.record(result: makeResult(won: false, duration: 20),
                      gameID: .hearts, seat: SeatID(0),
                      configuration: configuration(), into: &state)
        XCTAssertEqual(state.global.gamesLost, 1)
        XCTAssertNil(state.global.fastestWinSeconds, "you cannot have a fastest win without a win")
        XCTAssertFalse(state.gamesWonAtLeastOnce.contains(.hearts))
    }

    func testTheWinRateIsComputedFromDecidedGames() {
        var state = StatisticsState()
        for _ in 0..<3 {
            engine.record(result: makeResult(), gameID: .hearts, seat: SeatID(0),
                          configuration: configuration(), into: &state)
        }
        engine.record(result: makeResult(won: false), gameID: .hearts, seat: SeatID(0),
                      configuration: configuration(), into: &state)
        XCTAssertEqual(state.global.winRateBasisPoints, 7500, "three of four is 75.00%")
        XCTAssertEqual(StatisticsRecord().winRateBasisPoints, 0, "no games is not a zero win rate crash")
    }

    func testMetricsFoldTheWayTheirGameDeclared() throws {
        // Hearts declares its own metrics; the engine reads that declaration.
        let hearts = try XCTUnwrap(registry[.hearts])
        let totals = hearts.statistics.filter { $0.aggregation == .total }
        let maxima = hearts.statistics.filter { $0.aggregation == .maximum }
        XCTAssertFalse(totals.isEmpty, "hearts declares nothing to total")

        var state = StatisticsState()
        let totalKey = totals[0].key
        engine.record(result: makeResult(metrics: [totalKey: 4]),
                      gameID: .hearts, seat: SeatID(0), configuration: configuration(), into: &state)
        engine.record(result: makeResult(metrics: [totalKey: 6]),
                      gameID: .hearts, seat: SeatID(0), configuration: configuration(), into: &state)
        XCTAssertEqual(state.record(for: .hearts).metrics[totalKey], 10, "totals add up")

        if let maximumKey = maxima.first?.key {
            var peaks = StatisticsState()
            engine.record(result: makeResult(metrics: [maximumKey: 9]),
                          gameID: .hearts, seat: SeatID(0), configuration: configuration(), into: &peaks)
            engine.record(result: makeResult(metrics: [maximumKey: 3]),
                          gameID: .hearts, seat: SeatID(0), configuration: configuration(), into: &peaks)
            XCTAssertEqual(peaks.record(for: .hearts).metrics[maximumKey], 9, "a maximum keeps the peak")
        }
    }

    func testTheEngineNeverNeedsToKnowWhatAMetricMeans() {
        // A metric no game has ever declared still lands, folded as a total.
        var state = StatisticsState()
        engine.record(result: makeResult(metrics: ["something.invented": 5]),
                      gameID: .hearts, seat: SeatID(0), configuration: configuration(), into: &state)
        engine.record(result: makeResult(metrics: ["something.invented": 7]),
                      gameID: .hearts, seat: SeatID(0), configuration: configuration(), into: &state)
        XCTAssertEqual(state.record(for: .hearts).metrics["something.invented"], 12)
        XCTAssertEqual(state.record(for: .hearts).metricCounts["something.invented"], 2)
    }

    func testAverageMetricsDivideByTheGamesThatReportedThem() {
        let definition = StatisticDefinition(key: "test.average", titleKey: "t", aggregation: .average)
        var record = StatisticsRecord(metrics: ["test.average": 30], metricCounts: ["test.average": 4])
        XCTAssertEqual(record.value(for: definition), 7)
        XCTAssertTrue(record.hasValue(for: definition))
        record = StatisticsRecord()
        XCTAssertEqual(record.value(for: definition), 0, "no reports is zero, not a divide by zero")
        XCTAssertFalse(record.hasValue(for: definition))
    }

    func testAWinIsFiledUnderTheHardestOpponentAtTheTable() {
        var state = StatisticsState()
        engine.record(result: makeResult(), gameID: .hearts, seat: SeatID(0),
                      configuration: configuration(difficulty: .expert), into: &state)
        XCTAssertEqual(state.global.winsByDifficulty[AIDifficulty.expert.rawValue], 1)
        XCTAssertNil(state.global.winsByDifficulty[AIDifficulty.beginner.rawValue])
    }

    func testPassAndPlayAndSoloGamesAreCountedSeparately() {
        var state = StatisticsState()
        engine.record(result: makeResult(), gameID: .hearts, seat: SeatID(0),
                      configuration: configuration(humans: 3), into: &state)
        engine.record(result: makeResult(), gameID: .klondike, seat: SeatID(0),
                      configuration: configuration(gameID: .klondike, humans: 1, seats: 1),
                      into: &state)
        XCTAssertEqual(state.global.passAndPlayGames, 1)
        XCTAssertEqual(state.global.soloGames, 1)
    }

    func testTheFavouriteGameIsTheMostPlayedOne() {
        var state = StatisticsState()
        for _ in 0..<5 {
            engine.record(result: makeResult(), gameID: .spades, seat: SeatID(0),
                          configuration: configuration(gameID: .spades), into: &state)
        }
        engine.record(result: makeResult(), gameID: .hearts, seat: SeatID(0),
                      configuration: configuration(), into: &state)
        XCTAssertEqual(state.favouriteGame, .spades)
        XCTAssertNil(StatisticsState().favouriteGame, "no games means no favourite")
    }

    func testStatisticsValidateThemselves() {
        XCTAssertNil(StatisticsState().validate())
        var broken = StatisticsState()
        broken.global.gamesWon = 5
        broken.global.gamesPlayed = 1
        XCTAssertNotNil(broken.validate(), "more wins than games is not a valid record")
    }
}

final class AchievementTests: XCTestCase {
    private let registry = GameCatalog.makeRegistry()

    private func snapshot(statistics: StatisticsState = StatisticsState(),
                          challenge: ChallengeProgress = ChallengeProgress(),
                          mastery: MasteryState = MasteryState(),
                          collectionSize: Int = 0,
                          result: GameResult? = nil,
                          gameID: GameID? = nil,
                          seat: SeatID? = nil) -> ProgressSnapshot {
        ProgressSnapshot(statistics: statistics,
                         challenge: challenge,
                         mastery: mastery,
                         collectionSize: collectionSize,
                         lastResult: result,
                         lastGameID: gameID,
                         lastConfiguration: result == nil ? nil : configuration(),
                         lastSeat: seat)
    }

    /// The whole rulebook: each game's own achievements plus the global ones.
    private var engine: AchievementEngine {
        AchievementEngine(definitions: registry.allAchievements(global: GlobalAchievements.all))
    }

    func testNothingIsUnlockedFromAStandingStart() {
        var state = AchievementState()
        let unlocked = engine.evaluate(snapshot: snapshot(), into: &state)
        XCTAssertTrue(unlocked.isEmpty, "a fresh profile has earned nothing")
        XCTAssertFalse(state.entries.isEmpty, "but everything is being tracked")
        XCTAssertTrue(state.entries.values.allSatisfy { $0.unlockedAt == nil })
        XCTAssertTrue(state.entries.values.allSatisfy { $0.target > 0 },
                      "an achievement with no target can never be earned")
    }

    func testAWinUnlocksTheWinAchievementsForThatGameOnly() throws {
        var statistics = StatisticsState()
        StatisticsEngine(registry: registry).record(result: makeResult(), gameID: .hearts,
                                                    seat: SeatID(0),
                                                    configuration: configuration(),
                                                    into: &statistics)
        var state = AchievementState()
        let unlocked = engine.evaluate(snapshot: snapshot(statistics: statistics,
                                                          result: makeResult(),
                                                          gameID: .hearts,
                                                          seat: SeatID(0)),
                                       into: &state)
        for id in unlocked {
            let definition = try XCTUnwrap(engine.definition(id))
            switch definition.tracking {
            case let .wins(gameID):
                XCTAssertTrue(gameID == nil || gameID == .hearts,
                              "\(id) unlocked from a hearts win but belongs to \(String(describing: gameID))")
            case let .gamesPlayed(gameID):
                XCTAssertTrue(gameID == nil || gameID == .hearts)
            default:
                break
            }
        }
    }

    func testAnAchievementUnlocksOnceAndStaysUnlocked() {
        var statistics = StatisticsState()
        let statsEngine = StatisticsEngine(registry: registry)
        for _ in 0..<25 {
            statsEngine.record(result: makeResult(), gameID: .hearts, seat: SeatID(0),
                               configuration: configuration(), into: &statistics)
        }
        var state = AchievementState()
        let first = engine.evaluate(snapshot: snapshot(statistics: statistics), into: &state)
        XCTAssertFalse(first.isEmpty, "twenty-five wins earns something")
        let stamps = state.entries.compactMapValues(\.unlockedAt)

        let second = engine.evaluate(snapshot: snapshot(statistics: statistics), into: &state)
        XCTAssertTrue(second.isEmpty, "nothing unlocks twice")
        XCTAssertEqual(state.entries.compactMapValues(\.unlockedAt), stamps,
                       "the moment it was earned does not move")
    }

    func testProgressNeverGoesBackwards() {
        let statsEngine = StatisticsEngine(registry: registry)
        var statistics = StatisticsState()
        for _ in 0..<8 {
            statsEngine.record(result: makeResult(), gameID: .spades, seat: SeatID(0),
                               configuration: configuration(gameID: .spades), into: &statistics)
        }
        var state = AchievementState()
        engine.evaluate(snapshot: snapshot(statistics: statistics), into: &state)
        let high = state.entries.mapValues(\.progress)

        // Even handed a blank snapshot, recorded progress stands.
        engine.evaluate(snapshot: snapshot(), into: &state)
        for (id, value) in high {
            XCTAssertGreaterThanOrEqual(state.entries[id]?.progress ?? 0, value,
                                        "\(id) lost progress it had already made")
        }
    }

    func testStreakAchievementsReadTheChallengeLedger() {
        let streaks = engine.definitions.filter {
            if case .dailyStreak = $0.tracking { return true }
            return false
        }
        guard let definition = streaks.first,
              case let .dailyStreak(days) = definition.tracking else {
            return XCTFail("no streak achievement is defined anywhere in the library")
        }
        var state = AchievementState()
        var progress = ChallengeProgress()
        progress.currentStreak = days - 1
        progress.bestStreak = days - 1
        XCTAssertTrue(engine.evaluate(snapshot: snapshot(challenge: progress), into: &state).isEmpty)

        progress.currentStreak = days
        progress.bestStreak = days
        let unlocked = engine.evaluate(snapshot: snapshot(challenge: progress), into: &state)
        XCTAssertTrue(unlocked.contains(definition.id), "a \(days)-day streak did not land")
    }

    func testUnlocksAreQueuedForCelebrationExactlyOnce() {
        var statistics = StatisticsState()
        StatisticsEngine(registry: registry).record(result: makeResult(), gameID: .hearts,
                                                    seat: SeatID(0),
                                                    configuration: configuration(),
                                                    into: &statistics)
        var state = AchievementState()
        let unlocked = engine.evaluate(snapshot: snapshot(statistics: statistics), into: &state)
        XCTAssertEqual(Set(state.pendingCelebrations), Set(unlocked))
        engine.evaluate(snapshot: snapshot(statistics: statistics), into: &state)
        XCTAssertEqual(Set(state.pendingCelebrations), Set(unlocked),
                       "an unlock is not queued twice")
    }

    func testAchievementIDsAreUniqueAcrossGamesAndGlobals() {
        let ids = engine.definitions.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "two achievements share an id")
        XCTAssertFalse(GlobalAchievements.all.isEmpty)
    }

    func testEveryAchievementIsDescribedAndReachable() {
        for definition in engine.definitions {
            XCTAssertFalse(definition.titleKey.isEmpty)
            XCTAssertFalse(definition.descriptionKey.isEmpty)
            XCTAssertGreaterThan(definition.target, 0, "\(definition.id) can never be earned")
            if let reward = definition.rewardID {
                XCTAssertNotNil(CosmeticCatalog.cosmetic(reward),
                                "\(definition.id) rewards \(reward), which does not exist")
            }
        }
    }
}

final class MasteryTests: XCTestCase {
    private let registry = GameCatalog.makeRegistry()

    func testMasteryStartsAtNothing() {
        let record = MasteryRecord(gameID: .hearts)
        XCTAssertEqual(record.level, 0)
        XCTAssertFalse(record.isMastered)
        XCTAssertEqual(MasteryState().level(for: .hearts), 0)
        XCTAssertEqual(MasteryState().masteredCount, 0)
    }

    func testMasteryClimbsWithWinsAchievementsAndTheHardOpponent() {
        let novice = MasteryRecord(gameID: .hearts, wins: 3, achievementsUnlocked: 0,
                                   achievementsAvailable: 6)
        let seasoned = MasteryRecord(gameID: .hearts, wins: 9, achievementsUnlocked: 3,
                                     achievementsAvailable: 6, beatExpert: false)
        let master = MasteryRecord(gameID: .hearts, wins: 12, achievementsUnlocked: 6,
                                   achievementsAvailable: 6, beatExpert: true,
                                   dailyChallengesWon: 2)
        XCTAssertLessThan(novice.level, seasoned.level)
        XCTAssertLessThan(seasoned.level, master.level)
        XCTAssertTrue(master.isMastered)
        XCTAssertEqual(master.progressToNextLevel, 1, "there is nothing above mastered")
        XCTAssertFalse(master.levelKey.isEmpty)
    }

    func testProgressToTheNextBandStaysInRange() {
        for wins in 0...15 {
            for unlocked in 0...4 {
                let record = MasteryRecord(gameID: .spades, wins: wins,
                                           achievementsUnlocked: unlocked,
                                           achievementsAvailable: 4,
                                           beatExpert: wins > 8,
                                           dailyChallengesWon: unlocked)
                XCTAssertTrue((0...1).contains(record.progressToNextLevel),
                              "wins \(wins), unlocked \(unlocked) gives \(record.progressToNextLevel)")
                XCTAssertTrue((0...4).contains(record.level))
            }
        }
    }

    func testMasteryIsRebuiltFromTheOtherStoresRatherThanKeptSeparately() {
        var statistics = StatisticsState()
        let statsEngine = StatisticsEngine(registry: registry)
        for _ in 0..<7 {
            statsEngine.record(result: makeResult(), gameID: .spades, seat: SeatID(0),
                               configuration: configuration(gameID: .spades, difficulty: .expert),
                               into: &statistics)
        }
        let rebuilt = MasteryEngine(registry: registry)
            .rebuild(statistics: statistics, achievements: AchievementState(),
                     challenge: ChallengeProgress())
        XCTAssertEqual(rebuilt.record(for: .spades).wins, 7)
        XCTAssertTrue(rebuilt.record(for: .spades).beatExpert)
        XCTAssertGreaterThan(rebuilt.level(for: .spades), 0)
        XCTAssertEqual(rebuilt.level(for: .hearts), 0, "an unplayed game is not mastered")

        // Rebuilding from the same inputs gives the same answer, every time.
        let again = MasteryEngine(registry: registry)
            .rebuild(statistics: statistics, achievements: AchievementState(),
                     challenge: ChallengeProgress())
        XCTAssertEqual(rebuilt.records, again.records)
    }

    func testMasteryValidatesItself() {
        XCTAssertNil(MasteryState().validate())
        let broken = MasteryState(records: [.hearts: MasteryRecord(gameID: .hearts, wins: -2)])
        XCTAssertNotNil(broken.validate())
    }
}

final class CollectionTests: XCTestCase {
    private let engine = CollectionEngine()

    func testTheCatalogueIsCoherent() {
        XCTAssertFalse(CosmeticCatalog.all.isEmpty)
        XCTAssertEqual(Set(CosmeticCatalog.all.map(\.id)).count, CosmeticCatalog.all.count,
                       "two cosmetics share an id")
        for cosmetic in CosmeticCatalog.all {
            XCTAssertFalse(cosmetic.nameKey.isEmpty)
            XCTAssertFalse(cosmetic.englishName.isEmpty)
            XCTAssertFalse(cosmetic.artworkID.isEmpty, "\(cosmetic.id) has no artwork")
        }
        for kind in CosmeticKind.allCases {
            XCTAssertFalse(CosmeticCatalog.all.filter { $0.kind == kind }.isEmpty,
                           "nothing to collect of kind \(kind)")
        }
    }

    func testMostOfTheCollectionIsEarnedRatherThanBought() {
        let earnable = CosmeticCatalog.earnable.count
        let premium = CosmeticCatalog.all.count - earnable
        XCTAssertGreaterThan(earnable, premium,
                             "premium widens the collection; it must not contain most of it")
    }

    func testTheStartingKitIsUnlockedImmediately() {
        var state = CollectionState()
        let unlocked = engine.refresh(state: &state, achievements: AchievementState(),
                                      challenge: ChallengeProgress(), mastery: MasteryState(),
                                      hasPremium: false)
        XCTAssertFalse(unlocked.isEmpty)
        for id in [state.selectedTheme, state.selectedCardBack,
                   state.selectedTable, state.selectedSoundPack] {
            XCTAssertTrue(state.owns(id), "the default \(id) is not even owned")
        }
    }

    func testAStreakUnlocksWhatItPromised() {
        let streakItems = CosmeticCatalog.all.compactMap { cosmetic -> (Cosmetic, Int)? in
            if case let .streak(days) = cosmetic.unlock { return (cosmetic, days) }
            return nil
        }
        guard let (cosmetic, days) = streakItems.first else {
            return XCTFail("nothing in the collection rewards a streak")
        }
        var state = CollectionState()
        var progress = ChallengeProgress()
        progress.bestStreak = days - 1
        engine.refresh(state: &state, achievements: AchievementState(), challenge: progress,
                       mastery: MasteryState(), hasPremium: false)
        XCTAssertFalse(state.owns(cosmetic.id))

        progress.bestStreak = days
        let unlocked = engine.refresh(state: &state, achievements: AchievementState(),
                                      challenge: progress, mastery: MasteryState(),
                                      hasPremium: false)
        XCTAssertTrue(unlocked.contains(cosmetic.id))
        XCTAssertTrue(state.owns(cosmetic.id))
    }

    func testPremiumItemsNeedPremiumAndFallBackWhenItLapses() {
        guard let premiumItem = CosmeticCatalog.all.first(where: {
            $0.requiresPremium && $0.kind == .cardBack
        }) else {
            return XCTFail("no premium card back to test with")
        }
        var state = CollectionState()
        engine.refresh(state: &state, achievements: AchievementState(),
                       challenge: ChallengeProgress(), mastery: MasteryState(), hasPremium: true)
        XCTAssertTrue(state.owns(premiumItem.id))
        state.selectedCardBack = premiumItem.id
        XCTAssertTrue(engine.canSelect(premiumItem, state: state, hasPremium: true))

        // The subscription lapses.
        engine.refresh(state: &state, achievements: AchievementState(),
                       challenge: ChallengeProgress(), mastery: MasteryState(), hasPremium: false)
        XCTAssertNotEqual(state.selectedCardBack, premiumItem.id,
                          "a lapsed subscription must not keep rendering a locked card back")
        XCTAssertFalse(engine.canSelect(premiumItem, state: state, hasPremium: false))
    }

    func testNothingUnlocksTwice() {
        var state = CollectionState()
        var progress = ChallengeProgress()
        progress.bestStreak = 30
        let first = engine.refresh(state: &state, achievements: AchievementState(),
                                   challenge: progress, mastery: MasteryState(), hasPremium: true)
        let second = engine.refresh(state: &state, achievements: AchievementState(),
                                    challenge: progress, mastery: MasteryState(), hasPremium: true)
        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(state.pendingReveals.count, first.count)
    }
}

final class EntitlementTests: XCTestCase {

    func testAFreeAccountIsNotPremium() {
        XCTAssertFalse(Entitlements.free.isPremium())
        XCTAssertFalse(Entitlements(level: .free, expiresAt: .distantFuture).isPremium(),
                       "an expiry date on a free account grants nothing")
    }

    func testALifetimePurchaseNeverExpires() {
        let lifetime = Entitlements(level: .lifetime)
        XCTAssertTrue(lifetime.isPremium())
        XCTAssertTrue(lifetime.isPremium(now: .distantFuture))
    }

    func testASubscriptionIsPremiumUntilItsExpiryAndNotAfter() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let subscription = Entitlements(level: .subscribed, expiresAt: now.addingTimeInterval(60))
        XCTAssertTrue(subscription.isPremium(now: now))
        XCTAssertFalse(subscription.isPremium(now: now.addingTimeInterval(120)),
                       "a lapsed subscription is not premium")
        XCTAssertFalse(Entitlements(level: .subscribed).isPremium(),
                       "a subscription with no expiry date is not trusted")
    }

    func testARevokedPurchaseIsRefusedAtEveryLevel() {
        for level in [Entitlements.Level.subscribed, .lifetime] {
            let revoked = Entitlements(level: level,
                                       expiresAt: .distantFuture,
                                       isRevoked: true)
            XCTAssertFalse(revoked.isPremium(), "a revoked \(level) purchase still granted premium")
        }
    }

    func testEntitlementsSurviveARoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let original = Entitlements(level: .subscribed,
                                    expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
                                    isRevoked: false,
                                    verifiedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let restored = try decoder.decode(Entitlements.self, from: try encoder.encode(original))
        XCTAssertEqual(restored, original)
        XCTAssertNil(restored.validate())
    }
}

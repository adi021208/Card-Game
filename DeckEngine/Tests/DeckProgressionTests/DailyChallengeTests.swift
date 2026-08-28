import XCTest
import DeckCore
import DeckGames
import DeckCatalog
@testable import DeckProgression

func makeResult(seat: SeatID = SeatID(0),
                won: Bool = true,
                score: Int = 100,
                duration: TimeInterval = 120,
                turns: Int = 40,
                metrics: [String: Int] = [:],
                highlights: [String] = []) -> GameResult {
    GameResult(winners: won ? [seat] : [SeatID(9)],
               scores: [seat: score],
               placements: [seat],
               duration: duration,
               turnCount: turns,
               roundCount: 1,
               metrics: metrics,
               highlights: highlights)
}

final class ChallengeGenerationTests: XCTestCase {
    private let registry = GameCatalog.makeRegistry()

    private var generator: DailyChallengeGenerator { DailyChallengeGenerator(registry: registry) }

    func testTheSameDayGeneratesTheIdenticalChallenge() {
        let day = ChallengeDate(year: 2026, month: 8, day: 28)
        let first = try! XCTUnwrap(generator.challenge(for: day))
        let second = try! XCTUnwrap(DailyChallengeGenerator(registry: GameCatalog.makeRegistry())
            .challenge(for: day))
        XCTAssertEqual(first, second,
                       "two devices on the same day must get byte-identical challenges")
    }

    func testDifferentDaysGenerateDifferentChallenges() {
        let days = (0..<40).map { ChallengeDate(year: 2026, month: 1, day: 1).adding(days: $0) }
        let challenges = days.compactMap { generator.challenge(for: $0) }
        XCTAssertEqual(challenges.count, days.count)
        XCTAssertEqual(Set(challenges.map(\.id)).count, days.count, "each day is its own challenge")
        XCTAssertGreaterThan(Set(challenges.map(\.seed)).count, 35, "seeds are not repeating")
        XCTAssertGreaterThan(Set(challenges.map(\.gameID)).count, 4,
                             "the featured game moves around the library")
    }

    func testTheChallengeOnlyPicksGamesThatOptedIn() {
        let eligible = Set(registry.dailyEligible.map(\.id))
        XCTAssertFalse(eligible.isEmpty)
        for offset in 0..<120 {
            let day = ChallengeDate(year: 2026, month: 3, day: 1).adding(days: offset)
            guard let challenge = generator.challenge(for: day) else { continue }
            XCTAssertTrue(eligible.contains(challenge.gameID),
                          "\(day) featured a game that did not opt in")
        }
    }

    func testDifficultyStaysInsideTheAdvertisedRange() {
        var seenEasy = false
        var seenHard = false
        for offset in 0..<400 {
            let day = ChallengeDate(year: 2026, month: 1, day: 1).adding(days: offset)
            guard let challenge = generator.challenge(for: day) else { continue }
            XCTAssertGreaterThanOrEqual(challenge.difficultyScale, 0.5)
            XCTAssertLessThanOrEqual(challenge.difficultyScale, 3.0)
            XCTAssertGreaterThanOrEqual(challenge.difficultyPercent, -50)
            XCTAssertLessThanOrEqual(challenge.difficultyPercent, 200)
            if challenge.difficultyScale < 0.9 { seenEasy = true }
            if challenge.difficultyScale > 1.8 { seenHard = true }
        }
        XCTAssertTrue(seenEasy, "the easy end of the dial is never reached")
        XCTAssertTrue(seenHard, "the hard end of the dial is never reached")
    }

    func testTheHardestDaysAlwaysBringABoss() {
        for offset in 0..<400 {
            let day = ChallengeDate(year: 2026, month: 1, day: 1).adding(days: offset)
            guard let challenge = generator.challenge(for: day) else { continue }
            if challenge.difficultyScale > 1.8 {
                XCTAssertNotNil(challenge.bossID, "\(day) is brutal and faces you with nobody")
            }
            if let bossID = challenge.bossID {
                XCTAssertNotNil(BossCast.boss(bossID), "\(day) names a boss who does not exist")
            }
        }
    }

    func testTheChallengeIsPlayableAsConfigured() {
        for offset in 0..<25 {
            let day = ChallengeDate(year: 2026, month: 5, day: 1).adding(days: offset)
            guard let challenge = generator.challenge(for: day),
                  let definition = registry[challenge.gameID] else { continue }
            let total = challenge.opponentCount + 1
            XCTAssertTrue(definition.playerRange.contains(total),
                          "\(day) seats \(total) at a \(definition.englishName) table")
            if !definition.variants.isEmpty {
                XCTAssertTrue(definition.variants.contains { $0.id == challenge.variantID }
                              || challenge.variantID == "standard",
                              "\(day) names a variant \(definition.englishName) does not have")
            }
        }
    }

    func testObjectivesSuitTheGameTheyAreSetFor() {
        for offset in 0..<200 {
            let day = ChallengeDate(year: 2026, month: 2, day: 1).adding(days: offset)
            guard let challenge = generator.challenge(for: day),
                  let definition = registry[challenge.gameID] else { continue }
            switch challenge.objective {
            case let .score(target):
                XCTAssertGreaterThan(target, 0)
            case let .speed(seconds):
                XCTAssertGreaterThanOrEqual(seconds, 45, "an unreachable clock is not a challenge")
            case let .efficiency(turns):
                XCTAssertGreaterThanOrEqual(turns, 1)
            case let .target(value, key):
                XCTAssertGreaterThan(value, 0)
                XCTAssertTrue(definition.statistics.contains { $0.key == key },
                              "\(definition.englishName) never reports \(key)")
            case let .perfect(highlight):
                XCTAssertFalse(highlight.isEmpty)
            case .handicap, .boss:
                break
            }
            XCTAssertFalse(challenge.objective.englishDescription.isEmpty)
            XCTAssertFalse(challenge.objective.kindKey.isEmpty)
        }
    }

    func testAHarderDayReallyIsHarder() {
        // The difficulty scale is not decoration: it moves the AI profile.
        let base = AICast.hal.profile.adjusted(for: .skilled)
        let easyDay = base.scaled(by: 0.6)
        let hardDay = base.scaled(by: 2.6)
        XCTAssertGreaterThan(easyDay.mistakeRate, hardDay.mistakeRate)
        XCTAssertGreaterThan(hardDay.samplingBudget, easyDay.samplingBudget)
        XCTAssertGreaterThanOrEqual(hardDay.planningDepth, easyDay.planningDepth + 1)
    }

    func testAChallengeSurvivesBeingWrittenAndReadBack() throws {
        let day = ChallengeDate(year: 2026, month: 12, day: 25)
        let challenge = try XCTUnwrap(generator.challenge(for: day))
        let data = try JSONEncoder().encode(challenge)
        let restored = try JSONDecoder().decode(DailyChallenge.self, from: data)
        XCTAssertEqual(restored, challenge)
    }
}

final class ChallengeLedgerTests: XCTestCase {
    private let registry = GameCatalog.makeRegistry()

    private func challenge(_ day: ChallengeDate) -> DailyChallenge {
        DailyChallengeGenerator(registry: registry).challenge(for: day)!
    }

    private func day(_ offset: Int) -> ChallengeDate {
        ChallengeDate(year: 2026, month: 6, day: 1).adding(days: offset)
    }

    func testThreeFreeAttemptsAndThenNoMore() {
        var ledger = ChallengeLedger()
        let today = challenge(day(0))
        XCTAssertEqual(ledger.attemptsRemaining(for: today), 3)

        for expected in [2, 1, 0] {
            XCTAssertNotNil(ledger.beginAttempt(today))
            XCTAssertEqual(ledger.attemptsRemaining(for: today), expected)
        }
        XCTAssertFalse(ledger.canAttempt(today))
        XCTAssertNil(ledger.beginAttempt(today), "a fourth free attempt is not offered")
    }

    func testPremiumAttemptsAreUnlimitedAndSayThatRatherThanZero() {
        var ledger = ChallengeLedger(hasUnlimitedAttempts: true)
        let today = challenge(day(1))
        XCTAssertNil(ledger.attemptsRemaining(for: today), "unlimited is nil, not a big number")
        for _ in 0..<12 { XCTAssertNotNil(ledger.beginAttempt(today)) }
        XCTAssertTrue(ledger.canAttempt(today))
    }

    func testACompletedDayCannotBeReplayedForASecondReward() {
        var ledger = ChallengeLedger(hasUnlimitedAttempts: true)
        let today = challenge(day(2))
        let attempt = ledger.beginAttempt(today)!
        let outcome = ledger.finish(attempt: attempt, challenge: today,
                                    result: makeResult(), seat: SeatID(0),
                                    succeeded: true, replayLog: ["a", "b"])
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(outcome.streak, 1)
        XCTAssertFalse(ledger.canAttempt(today), "even a premium player finishes a day once")
        XCTAssertNil(ledger.beginAttempt(today))
    }

    func testAStreakAdvancesOncePerDayAndNeverTwice() {
        var ledger = ChallengeLedger(hasUnlimitedAttempts: true)
        for offset in 0..<5 {
            let today = challenge(day(offset))
            let attempt = ledger.beginAttempt(today)!
            let outcome = ledger.finish(attempt: attempt, challenge: today,
                                        result: makeResult(), seat: SeatID(0),
                                        succeeded: true, replayLog: [])
            XCTAssertEqual(outcome.streak, offset + 1)
            XCTAssertTrue(outcome.streakAdvanced)
        }
        XCTAssertEqual(ledger.progress.currentStreak, 5)
        XCTAssertEqual(ledger.progress.bestStreak, 5)
        XCTAssertEqual(ledger.progress.completedDays.count, 5)

        // Finishing an already-completed day again changes nothing.
        let repeated = challenge(day(4))
        let outcome = ledger.finish(attempt: ChallengeAttempt(challengeID: repeated.id,
                                                              date: repeated.date,
                                                              gameID: repeated.gameID,
                                                              attemptNumber: 9),
                                    challenge: repeated,
                                    result: makeResult(),
                                    seat: SeatID(0),
                                    succeeded: true,
                                    replayLog: [])
        XCTAssertFalse(outcome.streakAdvanced)
        XCTAssertEqual(ledger.progress.currentStreak, 5, "a replayed day cannot farm the streak")
        XCTAssertEqual(ledger.progress.completedDays.count, 5)
    }

    func testMissingADayResetsTheStreakButNotTheBest() {
        var ledger = ChallengeLedger(hasUnlimitedAttempts: true)
        for offset in [0, 1, 2] {
            let today = challenge(day(offset))
            let attempt = ledger.beginAttempt(today)!
            ledger.finish(attempt: attempt, challenge: today, result: makeResult(),
                          seat: SeatID(0), succeeded: true, replayLog: [])
        }
        XCTAssertEqual(ledger.progress.currentStreak, 3)

        // Skip day 3 entirely and play day 4.
        let later = challenge(day(4))
        let attempt = ledger.beginAttempt(later)!
        let outcome = ledger.finish(attempt: attempt, challenge: later, result: makeResult(),
                                    seat: SeatID(0), succeeded: true, replayLog: [])
        XCTAssertEqual(outcome.streak, 1, "the run is over; this is a new one")
        XCTAssertEqual(ledger.progress.bestStreak, 3, "the best run is remembered")
    }

    func testAnUnplayedDayExpiresTheStreakOnNextLaunch() {
        var ledger = ChallengeLedger(hasUnlimitedAttempts: true)
        let today = challenge(day(0))
        let attempt = ledger.beginAttempt(today)!
        ledger.finish(attempt: attempt, challenge: today, result: makeResult(),
                      seat: SeatID(0), succeeded: true, replayLog: [])
        XCTAssertEqual(ledger.progress.currentStreak, 1)

        ledger.expireStreakIfNeeded(today: day(1))
        XCTAssertEqual(ledger.progress.currentStreak, 1, "yesterday's run is still alive today")

        ledger.expireStreakIfNeeded(today: day(3))
        XCTAssertEqual(ledger.progress.currentStreak, 0, "two days away ends it")
        XCTAssertEqual(ledger.progress.bestStreak, 1)
    }

    func testFailingADayIsRecordedAndCostsAnAttemptButNotTheStreak() {
        var ledger = ChallengeLedger()
        let today = challenge(day(7))
        let attempt = ledger.beginAttempt(today)!
        let outcome = ledger.finish(attempt: attempt, challenge: today,
                                    result: makeResult(won: false, score: 10),
                                    seat: SeatID(0), succeeded: false, replayLog: [])
        XCTAssertFalse(outcome.succeeded)
        XCTAssertFalse(outcome.streakAdvanced)
        XCTAssertEqual(outcome.attemptsRemaining, 2)
        XCTAssertTrue(ledger.progress.failedDays.contains(today.date))
        XCTAssertFalse(ledger.progress.isCompleted(today.date))
        XCTAssertTrue(ledger.canAttempt(today), "there are two goes left")
    }

    func testASucceededAttemptClearsAnEarlierFailureOnTheSameDay() {
        var ledger = ChallengeLedger()
        let today = challenge(day(8))
        let first = ledger.beginAttempt(today)!
        ledger.finish(attempt: first, challenge: today, result: makeResult(won: false),
                      seat: SeatID(0), succeeded: false, replayLog: [])
        XCTAssertTrue(ledger.progress.failedDays.contains(today.date))

        let second = ledger.beginAttempt(today)!
        ledger.finish(attempt: second, challenge: today, result: makeResult(),
                      seat: SeatID(0), succeeded: true, replayLog: [])
        XCTAssertFalse(ledger.progress.failedDays.contains(today.date))
        XCTAssertTrue(ledger.progress.isCompleted(today.date))
        XCTAssertEqual(ledger.progress.attempts(for: today.id).count, 2,
                       "both goes are kept, not just the one that worked")
    }

    func testBestScoreAndBestTimeAreTrackedSeparatelyFromTheStreak() {
        var ledger = ChallengeLedger()
        let today = challenge(day(9))
        let first = ledger.beginAttempt(today)!
        ledger.finish(attempt: first, challenge: today,
                      result: makeResult(won: false, score: 300, duration: 90),
                      seat: SeatID(0), succeeded: false, replayLog: [])
        XCTAssertEqual(ledger.progress.bestScores[today.id], 300)
        XCTAssertNil(ledger.progress.bestTimes[today.id], "a failed run sets no best time")

        let second = ledger.beginAttempt(today)!
        ledger.finish(attempt: second, challenge: today,
                      result: makeResult(score: 120, duration: 60),
                      seat: SeatID(0), succeeded: true, replayLog: [])
        XCTAssertEqual(ledger.progress.bestScores[today.id], 300, "the higher score stands")
        XCTAssertEqual(ledger.progress.bestTimes[today.id], 60)
    }

    func testTheAttemptKeepsItsReplayLogSoTheResultCanBeChecked() {
        var ledger = ChallengeLedger()
        let today = challenge(day(10))
        let attempt = ledger.beginAttempt(today)!
        ledger.finish(attempt: attempt, challenge: today, result: makeResult(),
                      seat: SeatID(0), succeeded: true, replayLog: ["0/play/1", "1/play/2"])
        let stored = ledger.progress.attempts(for: today.id).first
        XCTAssertEqual(stored?.replayLog, ["0/play/1", "1/play/2"])
        XCTAssertEqual(stored?.difficultyPercent, today.difficultyPercent)
        XCTAssertNotNil(stored?.finishedAt)
    }

    func testBeatingABossIsRecordedOnce() {
        var ledger = ChallengeLedger(hasUnlimitedAttempts: true)
        var bossDay: DailyChallenge?
        for offset in 0..<60 where bossDay == nil {
            let candidate = challenge(day(offset))
            if candidate.bossID != nil { bossDay = candidate }
        }
        let boss = try! XCTUnwrap(bossDay, "no boss appeared in sixty days")
        let attempt = ledger.beginAttempt(boss)!
        let outcome = ledger.finish(attempt: attempt, challenge: boss, result: makeResult(),
                                    seat: SeatID(0), succeeded: true, replayLog: [])
        XCTAssertEqual(outcome.bossDefeated, boss.bossID)
        XCTAssertTrue(ledger.progress.bossesDefeated.contains(boss.bossID!))
    }

    func testProgressValidatesItself() {
        XCTAssertNil(ChallengeProgress().validate())
        XCTAssertNotNil(ChallengeProgress(currentStreak: -1).validate())
        XCTAssertNotNil(ChallengeProgress(currentStreak: 9, bestStreak: 2).validate(),
                        "a current streak cannot exceed the best one")
    }
}

final class ChallengeObjectiveTests: XCTestCase {

    func testScoreObjectivesReadTheSeatsOwnScore() {
        XCTAssertTrue(ChallengeLedger.evaluate(objective: .score(target: 100),
                                               result: makeResult(score: 100),
                                               seat: SeatID(0), bossID: nil))
        XCTAssertFalse(ChallengeLedger.evaluate(objective: .score(target: 101),
                                                result: makeResult(score: 100),
                                                seat: SeatID(0), bossID: nil))
        XCTAssertFalse(ChallengeLedger.evaluate(objective: .score(target: 100),
                                                result: makeResult(score: 100),
                                                seat: SeatID(5), bossID: nil),
                       "another seat's score is not yours")
    }

    func testTimedAndTurnObjectivesAlsoRequireAWin() {
        let fastLoss = makeResult(won: false, duration: 10, turns: 5)
        XCTAssertFalse(ChallengeLedger.evaluate(objective: .speed(seconds: 60),
                                                result: fastLoss, seat: SeatID(0), bossID: nil),
                       "losing quickly is not winning quickly")
        XCTAssertFalse(ChallengeLedger.evaluate(objective: .efficiency(turns: 20),
                                                result: fastLoss, seat: SeatID(0), bossID: nil))

        let fastWin = makeResult(duration: 45, turns: 18)
        XCTAssertTrue(ChallengeLedger.evaluate(objective: .speed(seconds: 60),
                                               result: fastWin, seat: SeatID(0), bossID: nil))
        XCTAssertTrue(ChallengeLedger.evaluate(objective: .efficiency(turns: 20),
                                               result: fastWin, seat: SeatID(0), bossID: nil))
        XCTAssertFalse(ChallengeLedger.evaluate(objective: .speed(seconds: 30),
                                                result: fastWin, seat: SeatID(0), bossID: nil))
    }

    func testMetricObjectivesReadTheGamesOwnNumbers() {
        let result = makeResult(metrics: ["poker.biggestPot": 4200])
        XCTAssertTrue(ChallengeLedger.evaluate(objective: .target(value: 4000,
                                                                  metricKey: "poker.biggestPot"),
                                               result: result, seat: SeatID(0), bossID: nil))
        XCTAssertFalse(ChallengeLedger.evaluate(objective: .target(value: 4201,
                                                                   metricKey: "poker.biggestPot"),
                                                result: result, seat: SeatID(0), bossID: nil))
        XCTAssertFalse(ChallengeLedger.evaluate(objective: .target(value: 1,
                                                                   metricKey: "nothing.reported"),
                                                result: result, seat: SeatID(0), bossID: nil))
    }

    func testPerfectObjectivesLookForTheGamesHighlight() {
        let shot = makeResult(highlights: ["hearts.shotTheMoon"])
        XCTAssertTrue(ChallengeLedger.evaluate(objective: .perfect(highlight: "hearts.shotTheMoon"),
                                               result: shot, seat: SeatID(0), bossID: nil))
        XCTAssertFalse(ChallengeLedger.evaluate(objective: .perfect(highlight: "hearts.shotTheMoon"),
                                                result: makeResult(), seat: SeatID(0), bossID: nil))
    }

    func testABossObjectiveNeedsABossAndAWin() {
        XCTAssertTrue(ChallengeLedger.evaluate(objective: .boss(bossID: "hal"),
                                               result: makeResult(), seat: SeatID(0), bossID: "hal"))
        XCTAssertFalse(ChallengeLedger.evaluate(objective: .boss(bossID: "hal"),
                                                result: makeResult(won: false),
                                                seat: SeatID(0), bossID: "hal"))
        XCTAssertFalse(ChallengeLedger.evaluate(objective: .boss(bossID: "hal"),
                                                result: makeResult(), seat: SeatID(0), bossID: nil),
                       "there was no boss to beat")
    }

    func testEveryObjectiveExplainsItself() {
        let objectives: [ChallengeObjective] = [
            .score(target: 500), .speed(seconds: 125), .efficiency(turns: 30),
            .target(value: 4, metricKey: "hearts.moonShots"), .handicap(points: 40),
            .perfect(highlight: "spades.nilMade"), .boss(bossID: "scarlet")
        ]
        for objective in objectives {
            XCTAssertFalse(objective.englishDescription.isEmpty)
            XCTAssertFalse(objective.kindKey.isEmpty)
            XCTAssertTrue(objective.descriptionKey.hasPrefix(objective.kindKey))
        }
        // A 2m05s target reads as two minutes and five seconds, not 125.
        XCTAssertEqual(ChallengeObjective.speed(seconds: 125).arguments, ["2", "5"])
    }
}

import XCTest
import DeckCore
import DeckGames
@testable import DeckAI

/// Drives a whole game with real agents in every seat.
///
/// Every agent is handed the rules-built observation for its own seat and the
/// list of legal moves, and nothing else. That is the point of these tests: an
/// agent that cheats would need something this harness cannot give it.
enum AgentHarness {

    static func seating(_ personalities: [AIPersonalityID],
                        difficulty: AIDifficulty = .skilled,
                        teams: Bool = false) -> SeatingPlan {
        SeatingPlan(seats: personalities.enumerated().map { index, id in
            Seat(id: SeatID(index),
                 displayName: "AI \(index)",
                 controller: .ai(personality: id, difficulty: difficulty),
                 team: teams ? index % 2 : nil)
        })
    }

    struct Run<R: GameRules> {
        var state: R.State
        var moves: Int
        var decisions: Int
        var longestDecision: TimeInterval
        /// Why the run stopped, so a failing agent test says something useful.
        var stop: String = "reached a result"
    }

    @discardableResult
    static func play<R: GameRules>(
        _ rules: R,
        configuration: GameConfiguration,
        agent: (R.Observation, [R.Action], AIProfile, inout SeededGenerator) -> R.Action?,
        profiles: [SeatID: AIProfile],
        maximumMoves: Int = 4000
    ) -> Run<R> {
        var generator = SeededGenerator(seed: configuration.seed)
        var state = rules.setup(configuration: configuration, generator: &generator)
        var moves = 0
        var decisions = 0
        var longest: TimeInterval = 0

        while state.finalResult == nil && moves < maximumMoves {
            var progressed = false
            for _ in 0..<512 {
                if rules.advanceAutomatically(&state, generator: &generator).isEmpty { break }
                progressed = true
            }
            guard state.finalResult == nil else { break }
            guard let seat = state.activeSeat else {
                XCTAssertTrue(progressed, "nothing to do and nobody to move")
                break
            }
            let legal = rules.legalActions(in: state, for: seat)
            guard !legal.isEmpty else {
                XCTFail("no legal move for \(seat) after \(moves) moves")
                break
            }
            let observation = rules.observation(of: state, for: seat)
            var thinking = generator.branch(UInt64(moves))
            let started = Date()
            let chosen = agent(observation, legal, profiles[seat] ?? AIProfile(), &thinking)
            longest = max(longest, Date().timeIntervalSince(started))
            decisions += 1

            let action = chosen ?? legal[0]
            XCTAssertTrue(legal.contains(action), "the agent chose a move that was not offered")
            XCTAssertNil(rules.rejection(for: action, in: state),
                         "the agent chose a move the rules then refused")
            _ = rules.apply(action, to: &state, generator: &generator)
            moves += 1
        }
        var stop = "reached a result"
        if state.finalResult == nil {
            stop = moves >= maximumMoves
                ? "hit the \(maximumMoves)-move cap with the game still running"
                : "stopped after \(moves) moves with no result"
        }
        return Run(state: state, moves: moves, decisions: decisions,
                   longestDecision: longest, stop: stop)
    }

    static func profiles(_ ids: [AIPersonalityID],
                         difficulty: AIDifficulty = .skilled) -> [SeatID: AIProfile] {
        var result: [SeatID: AIProfile] = [:]
        for (index, id) in ids.enumerated() {
            result[SeatID(index)] = AICast.personality(id).profile
                .adjusted(for: difficulty)
        }
        return result
    }
}

final class AIProfileTests: XCTestCase {

    func testTheCastIsSevenDistinctPersonalities() {
        XCTAssertEqual(AICast.all.count, 7)
        XCTAssertEqual(Set(AICast.all.map(\.id)).count, 7)
        XCTAssertEqual(Set(AICast.all.map(\.displayName)).count, 7)
        XCTAssertEqual(Set(AICast.all.map(\.colourToken)).count, 7,
                       "seven opponents, seven colours — no recoloured circles")
    }

    func testThePersonalitiesActuallyDifferOnTheDialsThatMatter() {
        let profiles = AICast.all.map(\.profile)
        XCTAssertGreaterThan(Set(profiles.map(\.aggression)).count, 4)
        XCTAssertGreaterThan(Set(profiles.map(\.bluffFrequency)).count, 4)
        XCTAssertGreaterThan(Set(profiles.map(\.planningDepth)).count, 2)
        XCTAssertGreaterThan(Set(profiles.map(\.memoryStrength)).count, 4)
        // And the spread is wide enough to be felt, not a rounding difference.
        let aggression = profiles.map(\.aggression)
        XCTAssertGreaterThan((aggression.max() ?? 0) - (aggression.min() ?? 0), 0.5)
    }

    func testDifficultyOnlyMovesDecisionQuality() {
        let base = AICast.hal.profile
        let beginner = base.adjusted(for: .beginner)
        let expert = base.adjusted(for: .expert)

        XCTAssertGreaterThan(beginner.mistakeRate, base.mistakeRate)
        XCTAssertLessThan(expert.mistakeRate, base.mistakeRate)
        XCTAssertLessThan(beginner.planningDepth, expert.planningDepth)
        XCTAssertLessThan(beginner.samplingBudget, expert.samplingBudget)

        // The personality itself is untouched: difficulty is not a new character.
        for adjusted in [beginner, expert, base.adjusted(for: .casual), base.adjusted(for: .skilled)] {
            XCTAssertEqual(adjusted.aggression, base.aggression)
            XCTAssertEqual(adjusted.riskTolerance, base.riskTolerance)
            XCTAssertEqual(adjusted.bluffFrequency, base.bluffFrequency)
        }
    }

    func testEveryProfileValueStaysInRange() {
        for personality in AICast.all {
            for difficulty in AIDifficulty.allCases {
                let profile = personality.profile.adjusted(for: difficulty)
                XCTAssertTrue((0...1).contains(profile.aggression))
                XCTAssertTrue((0...1).contains(profile.riskTolerance))
                XCTAssertTrue((0...1).contains(profile.bluffFrequency))
                XCTAssertTrue((0...1).contains(profile.mistakeRate))
                XCTAssertTrue((0...1).contains(profile.memoryStrength))
                XCTAssertTrue((0...1).contains(profile.adaptability))
                XCTAssertGreaterThanOrEqual(profile.planningDepth, 0)
                XCTAssertGreaterThan(profile.samplingBudget, 0)
            }
        }
    }

    func testChallengeScalingIsRealAtBothEnds() {
        let base = AICast.hal.profile.adjusted(for: .skilled)
        let easy = base.scaled(by: 0.5)
        let brutal = base.scaled(by: 3.0)

        XCTAssertGreaterThan(easy.mistakeRate, base.mistakeRate, "−50% really is easier")
        XCTAssertLessThan(brutal.mistakeRate, base.mistakeRate, "+200% really is harder")
        XCTAssertGreaterThan(brutal.samplingBudget, base.samplingBudget)
        XCTAssertLessThan(easy.samplingBudget, base.samplingBudget)
        XCTAssertGreaterThan(brutal.planningDepth, easy.planningDepth)
        XCTAssertEqual(base.scaled(by: 1.0), base, "the middle of the dial changes nothing")
    }
}

final class AISelectorTests: XCTestCase {

    private func moves(_ scores: [Double]) -> [ScoredMove<Int>] {
        scores.enumerated().map { ScoredMove(action: $0.offset, score: $0.element) }
    }

    func testAFlawlessProfileTakesTheBestMove() {
        var generator = SeededGenerator(seed: 1)
        let profile = AIProfile(mistakeRate: 0, memoryStrength: 1)
        for _ in 0..<50 {
            let chosen = AISelector.choose(moves([1, 9, 3, 5]), profile: profile, generator: &generator)
            XCTAssertEqual(chosen, 1, "index 1 has the best score")
        }
    }

    func testMistakesAreBadChoicesNotRandomOnes() {
        var generator = SeededGenerator(seed: 2)
        let profile = AIProfile(mistakeRate: 1.0, memoryStrength: 1)
        var picks: Set<Int> = []
        for _ in 0..<200 {
            if let chosen = AISelector.choose(moves([10, 9, 8, 7, 6, 5]),
                                              profile: profile, generator: &generator) {
                picks.insert(chosen)
            }
        }
        XCTAssertFalse(picks.contains(0), "a mistake is never the move it rated best")
        XCTAssertFalse(picks.contains(5), "nor is it reliably the very worst")
        XCTAssertGreaterThan(picks.count, 1, "mistakes vary")
    }

    func testAWeakerProfileMisplaysMoreOften() {
        func misplays(_ rate: Double) -> Int {
            var generator = SeededGenerator(seed: 99)
            let profile = AIProfile(mistakeRate: rate, memoryStrength: 1)
            var count = 0
            for _ in 0..<500 where AISelector.choose(moves([10, 5, 4, 3]),
                                                     profile: profile,
                                                     generator: &generator) != 0 {
                count += 1
            }
            return count
        }
        let strong = misplays(0.02)
        let weak = misplays(0.45)
        XCTAssertLessThan(strong, weak, "difficulty has to be visible in the play")
        XCTAssertLessThan(strong, 60, "an expert rarely throws one away")
        XCTAssertGreaterThan(weak, 120)
    }

    func testAnEmptyMoveListIsNilRatherThanACrash() {
        var generator = SeededGenerator(seed: 3)
        XCTAssertNil(AISelector.choose([ScoredMove<Int>](), profile: AIProfile(), generator: &generator))
        XCTAssertNil(AISelector.sample([ScoredMove<Int>](), temperature: 1, generator: &generator))
    }

    func testSamplingAtZeroTemperatureIsJustTheBestMove() {
        var generator = SeededGenerator(seed: 4)
        for _ in 0..<20 {
            XCTAssertEqual(AISelector.sample(moves([2, 7, 4]), temperature: 0, generator: &generator), 1)
        }
    }

    func testSamplingSpreadsOutAsTemperatureRises() {
        var cold: Set<Int> = []
        var hot: Set<Int> = []
        var generator = SeededGenerator(seed: 5)
        for _ in 0..<300 {
            if let pick = AISelector.sample(moves([5, 4.5, 4]), temperature: 0.05, generator: &generator) {
                cold.insert(pick)
            }
        }
        for _ in 0..<300 {
            if let pick = AISelector.sample(moves([5, 4.5, 4]), temperature: 5, generator: &generator) {
                hot.insert(pick)
            }
        }
        XCTAssertLessThanOrEqual(cold.count, hot.count)
        XCTAssertEqual(hot.count, 3, "a hot temperature reaches every option")
    }

    func testTheSameSeedGivesTheSameDecisions() {
        func run() -> [Int] {
            var generator = SeededGenerator(seed: 12345)
            let profile = AICast.pedro.profile
            return (0..<40).compactMap { _ in
                AISelector.choose(moves([3, 9, 1, 7, 5]), profile: profile, generator: &generator)
            }
        }
        XCTAssertEqual(run(), run(), "an agent's play is reproducible from its seed")
    }
}

final class AgentPlayTests: XCTestCase {

    private let cast: [AIPersonalityID] = [.hal, .pedro, .calvin, .rohan]

    func testHeartsAgentsPlayALegalGameToTheEnd() {
        let seating = AgentHarness.seating(cast)
        let configuration = GameConfiguration(gameID: .hearts, seating: seating, seed: 1234)
        let run = AgentHarness.play(HeartsRules(),
                                    configuration: configuration,
                                    agent: HeartsAgent.choose,
                                    profiles: AgentHarness.profiles(cast))
        XCTAssertNotNil(run.state.finalResult, "stopped because it \(run.stop)")
        XCTAssertGreaterThan(run.decisions, 40)
    }

    func testSpadesAgentsPlayALegalGameToTheEnd() {
        let seating = AgentHarness.seating(cast, teams: true)
        let configuration = GameConfiguration(gameID: .spades, seating: seating, seed: 2345)
        let run = AgentHarness.play(SpadesRules(),
                                    configuration: configuration,
                                    agent: SpadesAgent.choose,
                                    profiles: AgentHarness.profiles(cast))
        XCTAssertNotNil(run.state.finalResult, "stopped because it \(run.stop)")
    }

    func testEuchreAgentsPlayALegalGameToTheEnd() {
        let seating = AgentHarness.seating(cast, teams: true)
        let configuration = GameConfiguration(gameID: .euchre, seating: seating, seed: 3456)
        let run = AgentHarness.play(EuchreRules(),
                                    configuration: configuration,
                                    agent: EuchreAgent.choose,
                                    profiles: AgentHarness.profiles(cast))
        XCTAssertNotNil(run.state.finalResult, "stopped because it \(run.stop)")
    }

    func testCrazyEightsAgentsPlayALegalGameToTheEnd() {
        let seating = AgentHarness.seating(cast)
        let configuration = GameConfiguration(gameID: .crazyEights, seating: seating, seed: 4567)
        let run = AgentHarness.play(CrazyEightsRules(),
                                    configuration: configuration,
                                    agent: CrazyEightsAgent.choose,
                                    profiles: AgentHarness.profiles(cast))
        XCTAssertNotNil(run.state.finalResult, "stopped because it \(run.stop)")
    }

    func testPokerAgentsPlayALegalGameToTheEnd() {
        let seating = AgentHarness.seating([.hal, .pedro, .calvin, .scarlet, .rohan, .shayla])
        // No hand limit means the game is over only when one of six agents
        // holds all six thousand chips, which can outlast any move cap. Bound it
        // the way a tournament does.
        let configuration = GameConfiguration(gameID: .texasHoldem, seating: seating,
                                              options: ["handLimit": 60,
                                                        "blindIncreaseEvery": 6,
                                                        "blindIncreasePercent": 50],
                                              seed: 5678)
        let run = AgentHarness.play(TexasHoldemRules(),
                                    configuration: configuration,
                                    agent: PokerAgent.choose,
                                    profiles: AgentHarness.profiles([.hal, .pedro, .calvin,
                                                                     .scarlet, .rohan, .shayla]))
        XCTAssertNotNil(run.state.finalResult, "stopped because it \(run.stop)")
        XCTAssertLessThan(run.longestDecision, 2.0,
                          "no single poker decision may stall the table")
    }

    func testGinRummyAgentsPlayALegalGameToTheEnd() {
        let seating = AgentHarness.seating([.rohan, .shayla])
        let configuration = GameConfiguration(gameID: .ginRummy, seating: seating, seed: 6789)
        let run = AgentHarness.play(GinRummyRules(),
                                    configuration: configuration,
                                    agent: GinRummyAgent.choose,
                                    profiles: AgentHarness.profiles([.rohan, .shayla]))
        XCTAssertNotNil(run.state.finalResult, "stopped because it \(run.stop)")
    }

    func testRummyAgentsPlayALegalGameToTheEnd() {
        let seating = AgentHarness.seating([.hal, .honey, .calvin])
        let configuration = GameConfiguration(gameID: .rummy, seating: seating, seed: 7890)
        let run = AgentHarness.play(RummyRules(),
                                    configuration: configuration,
                                    agent: RummyAgent.choose,
                                    profiles: AgentHarness.profiles([.hal, .honey, .calvin]))
        // Says whether the scores were moving toward the target or the deals
        // themselves were not ending, which the stop reason alone cannot.
        XCTAssertNotNil(run.state.finalResult,
                        "stopped because it \(run.stop); after \(run.state.roundNumber) deals "
                        + "the scores were \(run.state.scores.sorted { $0.key < $1.key }.map(\.value)) "
                        + "against a target of \(run.state.settings.targetScore)")
    }

    func testPresidentCheatGoFishAndWarAgentsAllFinish() {
        let four: [AIPersonalityID] = [.hal, .pedro, .honey, .scarlet]
        let profiles = AgentHarness.profiles(four)

        let president = AgentHarness.play(
            PresidentRules(),
            configuration: GameConfiguration(gameID: .president,
                                             seating: AgentHarness.seating(four), seed: 111),
            agent: PresidentAgent.choose, profiles: profiles)
        XCTAssertNotNil(president.state.finalResult)

        let cheat = AgentHarness.play(
            CheatRules(),
            configuration: GameConfiguration(gameID: .cheat,
                                             seating: AgentHarness.seating(four), seed: 222),
            agent: CheatAgent.choose, profiles: profiles)
        XCTAssertNotNil(cheat.state.finalResult)

        let goFish = AgentHarness.play(
            GoFishRules(),
            configuration: GameConfiguration(gameID: .goFish,
                                             seating: AgentHarness.seating(four), seed: 333),
            agent: GoFishAgent.choose, profiles: profiles)
        XCTAssertNotNil(goFish.state.finalResult)

        let two: [AIPersonalityID] = [.hal, .pedro]
        let war = AgentHarness.play(
            WarRules(),
            configuration: GameConfiguration(gameID: .war,
                                             seating: AgentHarness.seating(two), seed: 444),
            agent: WarAgent.choose, profiles: AgentHarness.profiles(two))
        XCTAssertNotNil(war.state.finalResult)
    }

    func testSpeedAgentsFinish() {
        let two: [AIPersonalityID] = [.scarlet, .pedro]
        let rules = SpeedRules()
        let configuration = GameConfiguration(gameID: .speed,
                                              seating: AgentHarness.seating(two), seed: 555)
        var generator = SeededGenerator(seed: configuration.seed)
        var state = rules.setup(configuration: configuration, generator: &generator)
        let profiles = AgentHarness.profiles(two)
        var moves = 0
        // Speed has no turn order, so the harness alternates who gets to act.
        while state.finalResult == nil && moves < 3000 {
            let seat = state.seatOrder[moves % 2]
            var legal = rules.legalActions(in: state, for: seat)
            var actingSeat = seat
            if legal.isEmpty {
                actingSeat = state.seatOrder[(moves + 1) % 2]
                legal = rules.legalActions(in: state, for: actingSeat)
            }
            guard !legal.isEmpty else { break }
            var thinking = generator.branch(UInt64(moves))
            let observation = rules.observation(of: state, for: actingSeat)
            let action = SpeedAgent.choose(observation: observation,
                                           legalActions: legal,
                                           profile: profiles[actingSeat] ?? AIProfile(),
                                           generator: &thinking) ?? legal[0]
            XCTAssertNil(rules.rejection(for: action, in: state))
            _ = rules.apply(action, to: &state, generator: &generator)
            moves += 1
        }
        XCTAssertNotNil(state.finalResult)
    }

    /// Two personalities in the same seat, from the same deal, must actually
    /// play differently — otherwise the cast is decoration.
    func testDifferentPersonalitiesPlayDifferently() {
        func log(_ personality: AIPersonality) -> [String] {
            let rules = HeartsRules()
            let ids: [AIPersonalityID] = [personality.id, .hal, .hal, .hal]
            let seating = AgentHarness.seating(ids)
            let configuration = GameConfiguration(gameID: .hearts, seating: seating, seed: 99)
            var generator = SeededGenerator(seed: 99)
            var state = rules.setup(configuration: configuration, generator: &generator)
            var profiles = AgentHarness.profiles([.hal, .hal, .hal, .hal])
            profiles[SeatID(0)] = personality.profile
            var trace: [String] = []
            var moves = 0
            while state.finalResult == nil && moves < 200 {
                for _ in 0..<512 {
                    if rules.advanceAutomatically(&state, generator: &generator).isEmpty { break }
                }
                guard state.finalResult == nil, let seat = state.activeSeat else { break }
                let legal = rules.legalActions(in: state, for: seat)
                guard !legal.isEmpty else { break }
                var thinking = generator.branch(UInt64(moves))
                let action = HeartsAgent.choose(observation: rules.observation(of: state, for: seat),
                                                legalActions: legal,
                                                profile: profiles[seat] ?? AIProfile(),
                                                generator: &thinking) ?? legal[0]
                if seat == SeatID(0) {
                    trace.append(rules.token(for: action, in: state).id)
                }
                _ = rules.apply(action, to: &state, generator: &generator)
                moves += 1
            }
            return trace
        }

        let calvin = log(AICast.calvin)
        let pedro = log(AICast.pedro)
        XCTAssertFalse(calvin.isEmpty)
        XCTAssertNotEqual(calvin, pedro,
                          "the cautious player and the aggressive one made identical choices")
    }

    /// The same personality from the same seed must repeat itself exactly.
    func testTheSameAgentIsReproducible() {
        func run() -> [String] {
            let rules = CrazyEightsRules()
            let ids: [AIPersonalityID] = [.rohan, .honey, .scarlet]
            let configuration = GameConfiguration(gameID: .crazyEights,
                                                  seating: AgentHarness.seating(ids), seed: 4242)
            var generator = SeededGenerator(seed: 4242)
            var state = rules.setup(configuration: configuration, generator: &generator)
            let profiles = AgentHarness.profiles(ids)
            var trace: [String] = []
            var moves = 0
            while state.finalResult == nil && moves < 300 {
                for _ in 0..<512 {
                    if rules.advanceAutomatically(&state, generator: &generator).isEmpty { break }
                }
                guard state.finalResult == nil, let seat = state.activeSeat else { break }
                let legal = rules.legalActions(in: state, for: seat)
                guard !legal.isEmpty else { break }
                var thinking = generator.branch(UInt64(moves))
                let action = CrazyEightsAgent.choose(observation: rules.observation(of: state, for: seat),
                                                     legalActions: legal,
                                                     profile: profiles[seat] ?? AIProfile(),
                                                     generator: &thinking) ?? legal[0]
                trace.append(rules.token(for: action, in: state).id)
                _ = rules.apply(action, to: &state, generator: &generator)
                moves += 1
            }
            return trace
        }
        let first = run()
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, run())
    }

    /// The observation an agent is handed is the whole of what it may know.
    func testAnAgentIsNeverHandedAnotherPlayersCards() {
        let rules = HeartsRules()
        let ids: [AIPersonalityID] = [.hal, .pedro, .calvin, .rohan]
        let configuration = GameConfiguration(gameID: .hearts,
                                              seating: AgentHarness.seating(ids), seed: 808)
        var generator = SeededGenerator(seed: 808)
        let state = rules.setup(configuration: configuration, generator: &generator)

        for seat in state.seatOrder {
            let observation = rules.observation(of: state, for: seat)
            let known = Set(observation.hand.map(\.id))
            XCTAssertEqual(known.count, 13)
            for other in state.seatOrder where other != seat {
                XCTAssertTrue(known.isDisjoint(with: Set(state.board.contents(of: .hand(other)))),
                              "\(seat) was handed a card belonging to \(other)")
            }
        }
    }

    func testThinkingDoesNotDisturbTheDeal() {
        // An agent that burns a lot of randomness must not change what anybody
        // is dealt next round; deliberation runs on a branched generator.
        let rules = CrazyEightsRules()
        let ids: [AIPersonalityID] = [.rohan, .pedro]
        let configuration = GameConfiguration(gameID: .crazyEights,
                                              seating: AgentHarness.seating(ids), seed: 3141)

        func hands(burning: Int) -> [[String]] {
            var generator = SeededGenerator(seed: 3141)
            var state = rules.setup(configuration: configuration, generator: &generator)
            var moves = 0
            while state.finalResult == nil && moves < 30 {
                for _ in 0..<512 {
                    if rules.advanceAutomatically(&state, generator: &generator).isEmpty { break }
                }
                guard state.finalResult == nil, let seat = state.activeSeat else { break }
                let legal = rules.legalActions(in: state, for: seat)
                guard let action = legal.first else { break }
                var thinking = generator.branch(UInt64(moves))
                for _ in 0..<burning { _ = thinking.next() }
                _ = rules.apply(action, to: &state, generator: &generator)
                moves += 1
            }
            return state.seatOrder.map { state.board.cardList(in: .hand($0)).map(\.token) }
        }

        XCTAssertEqual(hands(burning: 0), hands(burning: 5000),
                       "how hard the AI thought changed the cards, which it must never do")
    }
}

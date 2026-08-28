import XCTest
import DeckCore
import DeckGames
@testable import DeckCatalog

/// The fifteen games the library ships with.
private let shipped: [GameID] = [
    .texasHoldem, .hearts, .spades, .euchre, .ginRummy, .rummy, .crazyEights,
    .president, .klondike, .freeCell, .spider, .goFish, .war, .cheat, .speed
]

private func seating(for definition: GameDefinition, humans: Int = 1) -> SeatingPlan {
    let count = min(max(definition.playerRange.lowerBound, humans + 3),
                    definition.playerRange.upperBound)
    let cast: [AIPersonalityID] = [.hal, .pedro, .calvin, .rohan, .shayla, .honey, .scarlet]
    var seats: [Seat] = []
    for index in 0..<count {
        if index < humans {
            seats.append(Seat(id: SeatID(index),
                              displayName: "P\(index)",
                              controller: .human(profileID: "p\(index)"),
                              team: definition.id == .spades || definition.id == .euchre
                                  ? index % 2 : nil))
        } else {
            seats.append(Seat(id: SeatID(index),
                              displayName: "AI \(index)",
                              controller: .ai(personality: cast[index % cast.count],
                                              difficulty: .skilled),
                              team: definition.id == .spades || definition.id == .euchre
                                  ? index % 2 : nil))
        }
    }
    return SeatingPlan(seats: seats)
}

final class GameRegistryTests: XCTestCase {

    func testTheLibraryHasEveryShippedGameAndNothingInvented() {
        let registry = GameCatalog.makeRegistry()
        XCTAssertEqual(Set(registry.ids), Set(shipped))
        XCTAssertEqual(registry.count, shipped.count, "no game is registered twice")
    }

    func testRegisteringTheSameGameTwiceReplacesRatherThanDuplicates() {
        let registry = GameRegistry()
        registry.register(GameCatalog.hearts())
        registry.register(GameCatalog.hearts())
        XCTAssertEqual(registry.count, 1)
        XCTAssertEqual(registry.ids, [.hearts])
    }

    func testEveryDefinitionIsFilledInProperly() {
        for definition in GameCatalog.makeRegistry().all {
            let name = definition.englishName
            XCTAssertFalse(definition.nameKey.isEmpty, "\(name) has no name key")
            XCTAssertFalse(definition.taglineKey.isEmpty, "\(name) has no tagline")
            XCTAssertFalse(definition.descriptionKey.isEmpty, "\(name) has no description")
            XCTAssertFalse(definition.artworkID.isEmpty, "\(name) has no artwork")
            XCTAssertFalse(definition.categories.isEmpty, "\(name) is in no category")
            XCTAssertFalse(definition.searchTerms.isEmpty, "\(name) cannot be searched for")
            XCTAssertGreaterThanOrEqual(definition.playerRange.lowerBound, 1)
            XCTAssertLessThanOrEqual(definition.playerRange.upperBound, 8)
            XCTAssertFalse(definition.statistics.isEmpty,
                           "\(name) keeps no statistics, so its results say nothing")
            XCTAssertFalse(definition.achievements.isEmpty, "\(name) has nothing to earn")
            XCTAssertFalse(definition.tutorial.steps.isEmpty, "\(name) teaches nothing")
        }
    }

    func testNoGameIsBehindAPaywall() {
        for definition in GameCatalog.makeRegistry().all {
            XCTAssertFalse(definition.requiresPremium,
                           "\(definition.englishName) is locked; the library is not the upsell")
        }
    }

    func testStatisticAndAchievementKeysAreUniqueWithinAGame() {
        for definition in GameCatalog.makeRegistry().all {
            let statKeys = definition.statistics.map(\.key)
            XCTAssertEqual(Set(statKeys).count, statKeys.count,
                           "\(definition.englishName) declares a statistic key twice")
            let achievementIDs = definition.achievements.map(\.id)
            XCTAssertEqual(Set(achievementIDs).count, achievementIDs.count,
                           "\(definition.englishName) declares an achievement twice")
        }
    }

    func testAchievementIDsAreUniqueAcrossTheWholeLibrary() {
        let all = GameCatalog.makeRegistry().all.flatMap { $0.achievements.map(\.id) }
        XCTAssertEqual(Set(all).count, all.count, "two games claim the same achievement id")
    }

    func testEveryRecommendationPointsAtARealGame() {
        let registry = GameCatalog.makeRegistry()
        let known = Set(registry.ids)
        for definition in registry.all {
            for suggestion in definition.recommendations {
                XCTAssertTrue(known.contains(suggestion),
                              "\(definition.englishName) recommends \(suggestion), which does not exist")
                XCTAssertNotEqual(suggestion, definition.id, "a game cannot recommend itself")
            }
        }
    }

    func testSoloGamesSeatOnePlayerAndSayTheyDoNotWantAI() {
        let registry = GameCatalog.makeRegistry()
        for id in [GameID.klondike, .freeCell, .spider] {
            let definition = try! XCTUnwrap(registry[id])
            XCTAssertEqual(definition.playerRange, 1...1)
            XCTAssertFalse(definition.supportsAIOpponents)
            XCTAssertFalse(definition.supportsPassAndPlay)
            XCTAssertTrue(definition.supportsUndo, "a solitaire with no hidden information can undo")
        }
    }

    func testGamesWithHiddenInformationDoNotOfferUndo() {
        let registry = GameCatalog.makeRegistry()
        for id in [GameID.texasHoldem, .hearts, .spades, .cheat, .goFish] {
            let definition = try! XCTUnwrap(registry[id])
            XCTAssertFalse(definition.supportsUndo,
                           "\(definition.englishName) would leak by rewinding")
        }
    }

    func testEveryVariantAndOptionIsCoherent() {
        for definition in GameCatalog.makeRegistry().all {
            for variant in definition.variants {
                XCTAssertFalse(variant.nameKey.isEmpty)
                XCTAssertFalse(variant.id.isEmpty)
            }
            XCTAssertEqual(Set(definition.variants.map(\.id)).count, definition.variants.count,
                           "\(definition.englishName) declares a variant id twice")
            for option in definition.setupOptions {
                XCTAssertFalse(option.id.isEmpty)
                XCTAssertFalse(option.titleKey.isEmpty)
            }
            XCTAssertEqual(Set(definition.setupOptions.map(\.id)).count,
                           definition.setupOptions.count,
                           "\(definition.englishName) declares an option key twice")
        }
    }

    func testFilteringAndSearchReadTheRegistryRatherThanAHardCodedList() {
        let registry = GameCatalog.makeRegistry()
        XCTAssertFalse(registry.games(in: .trickTaking).isEmpty)
        XCTAssertFalse(registry.games(in: .solitaire).isEmpty)
        XCTAssertFalse(registry.games(in: .poker).isEmpty)
        // Every game belongs to at least one category that the library shows.
        let categorised = Set(registry.all.flatMap { $0.categories }
            .flatMap { registry.games(in: $0).map(\.id) })
        XCTAssertEqual(categorised, Set(registry.ids))
    }
}

/// The next move available anywhere at the table.
///
/// Most games nominate an active seat; Speed does not, because both players may
/// move at once. Everything that drives a session generically has to cope with
/// both, which is exactly what this models.
private func nextMove(in session: GameSessionProtocol) -> ActionToken? {
    if let seat = session.activeSeat {
        return session.availableActions(for: seat).first
    }
    for seat in session.seating.ids {
        if let token = session.availableActions(for: seat).first { return token }
    }
    return nil
}

final class CatalogSessionTests: XCTestCase {

    func testEveryGameDealsOffersMovesAndFinishes() {
        for definition in GameCatalog.makeRegistry().all {
            let name = definition.englishName
            let configuration = GameConfiguration(gameID: definition.id,
                                                  seating: seating(for: definition),
                                                  options: definition.defaultOptions,
                                                  seed: 20260828)
            let session = definition.makeSession(configuration)
            XCTAssertEqual(session.gameID, definition.id, "\(name) built the wrong session")
            session.settle()

            var moves = 0
            while session.result == nil && moves < 6000 {
                guard let token = nextMove(in: session) else {
                    XCTFail("\(name) offered nobody a move after \(moves)")
                    break
                }
                do {
                    try session.perform(token)
                } catch {
                    return XCTFail("\(name) refused a move it had just offered: \(error)")
                }
                session.settle()
                moves += 1
            }

            let result = session.result
            XCTAssertNotNil(result, "\(name) never reached a result in \(moves) moves")
            XCTAssertGreaterThan(moves, 0, "\(name) finished without anybody moving")
            XCTAssertEqual(session.replayLog.count, moves, "\(name) lost a move from its log")
        }
    }

    func testEveryGameCheckpointsAndRestores() throws {
        for definition in GameCatalog.makeRegistry().all {
            let name = definition.englishName
            let configuration = GameConfiguration(gameID: definition.id,
                                                  seating: seating(for: definition),
                                                  options: definition.defaultOptions,
                                                  seed: 4242)
            let session = definition.makeSession(configuration)
            session.settle()
            // Take a handful of moves so the save is of a game in progress.
            for _ in 0..<6 {
                guard session.result == nil, let token = nextMove(in: session) else { break }
                try session.perform(token)
                session.settle()
            }

            let checkpoint = try session.checkpoint()
            XCTAssertEqual(checkpoint.gameID, definition.id)
            XCTAssertEqual(checkpoint.rulesVersion, session.rulesVersion)

            let restored = try definition.restoreSession(checkpoint)
            XCTAssertEqual(restored.activeSeat, session.activeSeat, "\(name) resumed on another turn")
            XCTAssertEqual(restored.turnCount, session.turnCount, "\(name) lost its turn count")
            XCTAssertEqual(restored.replayLog, session.replayLog, "\(name) lost its replay log")

            // The restored table looks the same to the same viewer.
            let viewer = session.seating.ids.first
            XCTAssertEqual(restored.presentation(for: viewer).board.knownCards,
                           session.presentation(for: viewer).board.knownCards,
                           "\(name) restored to a different table")
        }
    }

    func testEveryGameCanHandTheAIAMoveInEveryAISeat() {
        for definition in GameCatalog.makeRegistry().all where definition.supportsAIOpponents {
            let name = definition.englishName
            let plan = seating(for: definition, humans: 0)
            let configuration = GameConfiguration(gameID: definition.id,
                                                  seating: plan,
                                                  options: definition.defaultOptions,
                                                  seed: 909)
            let session = definition.makeSession(configuration)
            session.settle()
            var moves = 0
            while session.result == nil && moves < 400 {
                let candidates = session.activeSeat.map { [$0] } ?? plan.ids
                guard let token = candidates.lazy.compactMap({ session.aiMove(for: $0) }).first else {
                    XCTFail("\(name) had no AI move at \(candidates)")
                    break
                }
                try? session.perform(token)
                session.settle()
                moves += 1
            }
            XCTAssertGreaterThan(moves, 0, "\(name) never let the AI move")
        }
    }

    func testEveryGameOffersAHintThatExplainsItself() {
        for definition in GameCatalog.makeRegistry().all {
            let configuration = GameConfiguration(gameID: definition.id,
                                                  seating: seating(for: definition),
                                                  options: definition.defaultOptions,
                                                  seed: 77)
            let session = definition.makeSession(configuration)
            session.settle()
            let seat = session.activeSeat ?? session.seating.ids[0]
            guard let hint = session.hint(for: seat) else { continue }
            XCTAssertFalse(hint.messageKey.isEmpty,
                           "\(definition.englishName) gives a hint with nothing to say")
            XCTAssertFalse(hint.english.isEmpty)
            XCTAssertFalse(hint.english.lowercased().hasPrefix("play this"),
                           "a hint teaches the reason, it does not just point")
        }
    }

    func testAViewerSeesOnlyTheirOwnHand() {
        /// The card ids a redacted pile actually names.
        func named(_ cards: [VisibleCard]) -> Set<CardID> {
            Set(cards.compactMap { card -> CardID? in
                if case let .known(value) = card { return value.id }
                return nil
            })
        }

        for definition in GameCatalog.makeRegistry().all where definition.supportsPassAndPlay {
            let name = definition.englishName
            let plan = seating(for: definition, humans: 2)
            let configuration = GameConfiguration(gameID: definition.id,
                                                  seating: plan,
                                                  options: definition.defaultOptions,
                                                  seed: 1717)
            let session = definition.makeSession(configuration)
            session.settle()

            let seats = plan.ids
            let inTransit = session.presentation(for: nil).board
            var dealtToSomebody = false

            for owner in seats {
                let ownView = session.presentation(for: owner).board
                let ownHand = ownView.contents(of: .hand(owner))
                guard !ownHand.isEmpty else { continue }
                dealtToSomebody = true

                // A player can read their own hand — otherwise this proves nothing.
                XCTAssertEqual(named(ownHand).count, ownHand.count,
                               "\(name): a player cannot read their own cards")

                // Nobody else can, and nor can the device between players.
                for other in seats where other != owner {
                    XCTAssertTrue(session.presentation(for: other).board
                        .knownCards.isDisjoint(with: named(ownHand)),
                                  "\(name): \(other) can read \(owner)'s hand")
                }
                XCTAssertTrue(inTransit.knownCards.isDisjoint(with: named(ownHand)),
                              "\(name) leaks \(owner)'s hand while the device is in transit")
            }

            XCTAssertTrue(dealtToSomebody || definition.id == .war,
                          "\(name) offers pass and play but deals nobody a hand")
        }
    }

    func testTheSameSeedAlwaysDealsTheSameGame() {
        for definition in GameCatalog.makeRegistry().all {
            func deal() -> Set<CardID> {
                let configuration = GameConfiguration(gameID: definition.id,
                                                      seating: seating(for: definition),
                                                      options: definition.defaultOptions,
                                                      seed: 555_666)
                let session = definition.makeSession(configuration)
                session.settle()
                return session.presentation(for: session.seating.ids.first).board.knownCards
            }
            XCTAssertEqual(deal(), deal(),
                           "\(definition.englishName) dealt differently from the same seed")
        }
    }
}

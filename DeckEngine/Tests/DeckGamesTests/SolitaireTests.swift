import XCTest
import DeckCore
@testable import DeckGames

/// Sets a tableau column to exactly the named cards, face up.
private func stack(_ tokens: [String], into zone: Zone, on board: inout Board, spill: Zone = .stock) {
    board.ensureZones([zone, spill])
    for id in board.contents(of: zone) { board.move(id, to: spill, facing: .faceDown) }
    for token in tokens {
        board.move(Card(token: token)!.id, to: zone, facing: .faceUp)
    }
}

final class FreeCellTests: XCTestCase {
    private let rules = FreeCellRules()

    private func fresh(seed: UInt64 = 101, cells: Int = 4) -> FreeCellRules.State {
        let configuration = TestTable.configuration(.freeCell, humans: 1,
                                                    options: ["cellCount": cells], seed: seed)
        var generator = SeededGenerator(seed: seed)
        return rules.setup(configuration: configuration, generator: &generator)
    }

    func testTheWholeDeckIsDealtFaceUpAcrossEightColumns() {
        let state = fresh()
        var total = 0
        for column in 0..<FreeCellRules.columnCount {
            let count = state.board.count(in: .tableau(column))
            XCTAssertTrue(count == 6 || count == 7, "columns hold six or seven")
            total += count
            for id in state.board.contents(of: .tableau(column)) {
                XCTAssertTrue(state.board.isFaceUp(id), "freecell hides nothing")
            }
        }
        XCTAssertEqual(total, 52)
        XCTAssertEqual(state.freeCellCount, 4)
        XCTAssertEqual(state.foundationTotal, 0)
    }

    func testNothingIsHiddenFromTheSolitairePlayer() {
        let state = fresh()
        let redacted = state.board.redacted(for: state.seat)
        XCTAssertEqual(redacted.knownCards.count, 52,
                       "a solitaire with no hidden cards has nothing to redact")
    }

    func testFoundationsStartWithAnAceAndGoUpInSuit() {
        var state = fresh()
        stack(["AH"], into: .tableau(0), on: &state.board)
        XCTAssertTrue(rules.canPlaceOnFoundation(Card(token: "AH")!, foundation: .foundation(0), in: state))
        XCTAssertFalse(rules.canPlaceOnFoundation(Card(token: "2H")!, foundation: .foundation(0), in: state),
                       "a foundation opens with an ace, not a two")

        var generator = SeededGenerator(seed: 1)
        _ = rules.apply(.move(card: Card(token: "AH")!.id, to: .foundation(0)),
                        to: &state, generator: &generator)
        XCTAssertTrue(rules.canPlaceOnFoundation(Card(token: "2H")!, foundation: .foundation(0), in: state))
        XCTAssertFalse(rules.canPlaceOnFoundation(Card(token: "2S")!, foundation: .foundation(0), in: state),
                       "foundations stay in one suit")
        XCTAssertFalse(rules.canPlaceOnFoundation(Card(token: "3H")!, foundation: .foundation(0), in: state),
                       "and skip nothing")
    }

    func testColumnsGoDownInAlternatingColours() {
        var state = fresh()
        stack(["8H"], into: .tableau(0), on: &state.board)
        XCTAssertTrue(rules.canPlaceOnTableau(Card(token: "7S")!, column: .tableau(0), in: state))
        XCTAssertTrue(rules.canPlaceOnTableau(Card(token: "7C")!, column: .tableau(0), in: state))
        XCTAssertFalse(rules.canPlaceOnTableau(Card(token: "7D")!, column: .tableau(0), in: state),
                       "red on red is not a sequence")
        XCTAssertFalse(rules.canPlaceOnTableau(Card(token: "6S")!, column: .tableau(0), in: state),
                       "and it goes down by exactly one")
        stack([], into: .tableau(1), on: &state.board)
        XCTAssertTrue(rules.canPlaceOnTableau(Card(token: "KD")!, column: .tableau(1), in: state),
                      "an empty column in freecell takes anything")
    }

    func testALiftableRunMustAlternateAndDescend() {
        var state = fresh()
        stack(["KS", "9H", "8S", "7D"], into: .tableau(0), on: &state.board)
        XCTAssertEqual(rules.liftableRun(from: Card(token: "9H")!.id, in: state)?.count, 3)
        XCTAssertEqual(rules.liftableRun(from: Card(token: "7D")!.id, in: state)?.count, 1)
        XCTAssertNil(rules.liftableRun(from: Card(token: "KS")!.id, in: state),
                     "a king with a nine under it is not a run")
    }

    func testTheLiftLimitFollowsTheFreeCellsAndEmptyColumns() {
        var state = fresh()
        // Empty every column but two, so the multiplier is real.
        for column in 0..<FreeCellRules.columnCount {
            stack([], into: .tableau(column), on: &state.board)
        }
        stack(["9H", "8S", "7D", "6C"], into: .tableau(0), on: &state.board)
        stack(["TS"], into: .tableau(1), on: &state.board)

        // Four cells free, six empty columns: the formula gives (4+1) x 2^6.
        XCTAssertEqual(rules.maximumLift(in: state, movingToEmptyColumn: false), 5 * 64)
        XCTAssertEqual(rules.maximumLift(in: state, movingToEmptyColumn: true), 5 * 32,
                       "the destination column cannot stage its own move")

        // Fill the cells and the number falls.
        state.board.move(Card(token: "2C")!.id, to: .freeCell(0), facing: .faceUp)
        state.board.move(Card(token: "2D")!.id, to: .freeCell(1), facing: .faceUp)
        XCTAssertEqual(state.freeCellCount, 2)
        XCTAssertEqual(rules.maximumLift(in: state, movingToEmptyColumn: false), 3 * 64)
    }

    func testTooBigALiftIsRefusedWithTheNumberYouCanActuallyMove() {
        var state = fresh(cells: 1)
        for column in 0..<FreeCellRules.columnCount {
            stack([], into: .tableau(column), on: &state.board)
        }
        // One free cell, and the only non-empty columns are these two, so the
        // limit when moving onto a card is (1+1) x 2^6.
        stack(["9H", "8S", "7D", "6C", "5H", "4S"], into: .tableau(0), on: &state.board)
        stack(["TS"], into: .tableau(1), on: &state.board)
        state.board.move(Card(token: "2C")!.id, to: .freeCell(0), facing: .faceUp)
        // Now every cell is taken and only these two columns hold cards.
        XCTAssertEqual(state.freeCellCount, 0)
        XCTAssertEqual(rules.maximumLift(in: state, movingToEmptyColumn: false), 1 * 64)

        // Squeeze it: fill the other columns so nothing is free.
        let blockers = ["KC", "KD", "KH", "KS", "QC", "QD"]
        for (offset, token) in blockers.enumerated() {
            stack([token], into: .tableau(2 + offset), on: &state.board)
        }
        XCTAssertEqual(state.emptyColumnCount, 0)
        XCTAssertEqual(rules.maximumLift(in: state, movingToEmptyColumn: false), 1)
        let reason = rules.rejection(for: .move(card: Card(token: "9H")!.id, to: .tableau(1)), in: state)
        XCTAssertEqual(reason?.reason, "notEnoughSpace")
        XCTAssertEqual(reason?.arguments, ["1"], "the message says how many you can move")
    }

    func testACellHoldsExactlyOneCard() {
        var state = fresh()
        stack(["9H", "8S"], into: .tableau(0), on: &state.board)
        XCTAssertEqual(rules.rejection(for: .move(card: Card(token: "9H")!.id, to: .freeCell(0)),
                                       in: state)?.reason,
                       "cellOneCard")
        var generator = SeededGenerator(seed: 2)
        _ = rules.apply(.move(card: Card(token: "8S")!.id, to: .freeCell(0)),
                        to: &state, generator: &generator)
        XCTAssertEqual(rules.rejection(for: .move(card: Card(token: "9H")!.id, to: .freeCell(0)),
                                       in: state)?.reason,
                       "cellOccupied")
    }

    func testCollectIsOfferedOnlyWhenSomethingCanGoUp() {
        var state = fresh()
        for column in 0..<FreeCellRules.columnCount {
            stack([], into: .tableau(column), on: &state.board)
        }
        stack(["9H", "8S"], into: .tableau(0), on: &state.board)
        XCTAssertFalse(rules.canCollect(state: state), "nothing here belongs on a foundation yet")
        XCTAssertEqual(rules.rejection(for: .collect, in: state), .noSuchAction)

        stack(["AD"], into: .tableau(1), on: &state.board)
        XCTAssertTrue(rules.canCollect(state: state))
        XCTAssertNil(rules.rejection(for: .collect, in: state))
    }

    func testAWonGameIsRecognised() throws {
        var state = fresh()
        for column in 0..<FreeCellRules.columnCount {
            stack([], into: .tableau(column), on: &state.board)
        }
        // Everything but one card is already home.
        for (index, suit) in ["C", "D", "H", "S"].enumerated() {
            for rank in ["A", "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K"] {
                let token = "\(rank)\(suit)"
                if token == "KS" { continue }
                state.board.move(Card(token: token)!.id, to: .foundation(index), facing: .faceUp)
            }
        }
        stack(["KS"], into: .tableau(0), on: &state.board)
        XCTAssertEqual(state.foundationTotal, 51)

        var generator = SeededGenerator(seed: 3)
        _ = rules.apply(.move(card: Card(token: "KS")!.id, to: .foundation(3)),
                        to: &state, generator: &generator)
        let result = try XCTUnwrap(state.finalResult)
        XCTAssertEqual(result.winners, [state.seat])
        XCTAssertEqual(state.foundationTotal, 52)
        XCTAssertNil(state.activeSeat)
        XCTAssertGreaterThan(result.scores[state.seat] ?? 0, 0, "a win scores something")
    }

    func testEveryOfferedMoveIsAccepted() {
        for seed in UInt64(1)...25 {
            var state = fresh(seed: seed)
            var generator = SeededGenerator(seed: seed)
            for _ in 0..<60 {
                guard state.finalResult == nil else { break }
                let legal = rules.legalActions(in: state, for: state.seat)
                guard let action = legal.first else { break }
                for candidate in legal {
                    XCTAssertNil(rules.rejection(for: candidate, in: state),
                                 "seed \(seed) offered a move it then refused")
                }
                _ = rules.apply(action, to: &state, generator: &generator)
            }
        }
    }

    func testUndoIsSupportedBecauseThereIsNoHiddenInformation() {
        XCTAssertTrue(rules.supportsUndo)
    }
}

final class SpiderTests: XCTestCase {
    private let rules = SpiderRules()

    private func fresh(seed: UInt64 = 202, suits: Int = 1) -> SpiderRules.State {
        let configuration = TestTable.configuration(.spider, humans: 1,
                                                    options: ["suitCount": suits], seed: seed)
        var generator = SeededGenerator(seed: seed)
        return rules.setup(configuration: configuration, generator: &generator)
    }

    func testTheOpeningIsFiftyFourCardsWithFiftyLeftToDeal() {
        let state = fresh()
        var dealt = 0
        for column in 0..<SpiderRules.columnCount {
            let expected = column < 4 ? 6 : 5
            XCTAssertEqual(state.board.count(in: .tableau(column)), expected)
            dealt += expected
            let contents = state.board.contents(of: .tableau(column))
            XCTAssertTrue(state.board.isFaceUp(contents.last!), "the last card of each column is up")
            for id in contents.dropLast() {
                XCTAssertFalse(state.board.isFaceUp(id))
            }
        }
        XCTAssertEqual(dealt, 54)
        XCTAssertEqual(state.board.count(in: .stock), 50, "five more rows of ten")
        XCTAssertEqual(state.faceDownCount, 44)
    }

    func testTheDeckIsTwoPacksWhateverTheSuitCount() {
        for suits in [1, 2, 4] {
            let state = fresh(suits: suits)
            var all: [Card] = []
            for column in 0..<SpiderRules.columnCount { all += state.board.cardList(in: .tableau(column)) }
            all += state.board.cardList(in: .stock)
            XCTAssertEqual(all.count, 104, "spider is 104 cards at every difficulty")
            XCTAssertEqual(Set(all.compactMap(\.suit)).count, suits,
                           "a \(suits)-suit game uses exactly \(suits) suits")
        }
    }

    func testACardGoesOnOneExactlyARankHigherRegardlessOfSuit() {
        var state = fresh(suits: 4)
        stack(["9H"], into: .tableau(0), on: &state.board)
        XCTAssertTrue(rules.canPlaceOnTableau(Card(token: "8S")!, column: .tableau(0), in: state),
                      "placing ignores suit")
        XCTAssertTrue(rules.canPlaceOnTableau(Card(token: "8H")!, column: .tableau(0), in: state))
        XCTAssertFalse(rules.canPlaceOnTableau(Card(token: "7S")!, column: .tableau(0), in: state))
        XCTAssertFalse(rules.canPlaceOnTableau(Card(token: "TS")!, column: .tableau(0), in: state))
    }

    func testOnlyASameSuitRunLiftsAsAUnit() {
        var state = fresh(suits: 4)
        stack(["KC", "9S", "8S", "7S"], into: .tableau(0), on: &state.board)
        XCTAssertEqual(rules.liftableRun(from: Card(token: "9S")!.id, in: state)?.count, 3)

        stack(["KC", "9S", "8H", "7S"], into: .tableau(1), on: &state.board)
        XCTAssertNil(rules.liftableRun(from: Card(token: "9S")!.id, in: state),
                     "a heart in the middle breaks the run")
        XCTAssertEqual(rules.liftableRun(from: Card(token: "7S")!.id, in: state)?.count, 1,
                       "the bottom card always lifts on its own")
        XCTAssertEqual(rules.rejection(for: .move(card: Card(token: "9S")!.id, to: .tableau(2)),
                                       in: state)?.reason,
                       "runNotOneSuit")
    }

    func testMovingOffAColumnTurnsTheCardUnderneath() {
        var state = fresh(suits: 4)
        stack(["7D", "9S", "8S"], into: .tableau(0), on: &state.board)
        state.board.flip(Card(token: "7D")!.id, faceUp: false)
        stack(["TC"], into: .tableau(1), on: &state.board)
        XCTAssertFalse(state.board.isFaceUp(Card(token: "7D")!.id))

        var generator = SeededGenerator(seed: 1)
        _ = rules.apply(.move(card: Card(token: "9S")!.id, to: .tableau(1)),
                        to: &state, generator: &generator)

        XCTAssertEqual(state.board.count(in: .tableau(1)), 3, "the pair moves together")
        XCTAssertEqual(state.board.count(in: .tableau(0)), 1)
        XCTAssertTrue(state.board.isFaceUp(Card(token: "7D")!.id),
                      "the card underneath is turned over")
    }

    func testAFullRunIsHarvestedToAFoundation() {
        var state = fresh()
        stack(["KS", "QS", "JS", "TS", "9S", "8S", "7S", "6S", "5S", "4S", "3S", "2S"],
              into: .tableau(0), on: &state.board)
        stack(["AS"], into: .tableau(1), on: &state.board)
        let runsBefore = state.completedRuns

        var generator = SeededGenerator(seed: 2)
        _ = rules.apply(.move(card: Card(token: "AS")!.id, to: .tableau(0)),
                        to: &state, generator: &generator)

        XCTAssertEqual(state.completedRuns, runsBefore + 1, "king down to ace clears itself away")
        XCTAssertEqual(state.board.count(in: .tableau(0)), 0)
        let harvested = (0..<SpiderRules.foundationCount)
            .map { state.board.count(in: .foundation($0)) }
            .reduce(0, +)
        XCTAssertEqual(harvested, 13)
    }

    func testDealingARowNeedsEveryColumnOccupied() {
        var state = fresh()
        stack([], into: .tableau(3), on: &state.board)
        XCTAssertEqual(rules.rejection(for: .dealRow, in: state)?.reason, "fillEmptyColumnsFirst")

        // Any card will do; take one from a column that can spare it.
        let donor = state.board.contents(of: .tableau(0)).last!
        state.board.move(donor, to: .tableau(3), facing: .faceUp)
        XCTAssertNil(rules.rejection(for: .dealRow, in: state))

        var generator = SeededGenerator(seed: 3)
        let stockBefore = state.board.count(in: .stock)
        _ = rules.apply(.dealRow, to: &state, generator: &generator)
        XCTAssertEqual(state.board.count(in: .stock), stockBefore - 10)
        for column in 0..<SpiderRules.columnCount {
            XCTAssertTrue(state.board.isFaceUp(state.board.contents(of: .tableau(column)).last!),
                          "a dealt row lands face up")
        }
    }

    func testTheStockHoldsExactlyFiveMoreRows() {
        var state = fresh()
        var generator = SeededGenerator(seed: 4)
        var rows = 0
        while state.board.count(in: .stock) >= SpiderRules.columnCount {
            // Harvesting a run can empty a column, and a row cannot go down onto
            // an empty one; top it up so what is under test is the stock count.
            for column in 0..<SpiderRules.columnCount where state.board.isEmpty(.tableau(column)) {
                let donor = (0..<SpiderRules.columnCount).first {
                    state.board.count(in: .tableau($0)) > 1
                }
                if let donor, let spare = state.board.contents(of: .tableau(donor)).last {
                    state.board.move(spare, to: .tableau(column), facing: .faceUp)
                }
            }
            XCTAssertNil(rules.rejection(for: .dealRow, in: state), "row \(rows) should be dealable")
            _ = rules.apply(.dealRow, to: &state, generator: &generator)
            rows += 1
        }
        XCTAssertEqual(rows, 5, "fifty cards, ten at a time")
        XCTAssertEqual(state.board.count(in: .stock), 0)
        XCTAssertEqual(rules.rejection(for: .dealRow, in: state), .emptyPile)
    }

    func testEveryOfferedMoveIsAccepted() {
        for seed in UInt64(1)...20 {
            var state = fresh(seed: seed)
            var generator = SeededGenerator(seed: seed)
            for _ in 0..<80 {
                guard state.finalResult == nil else { break }
                let legal = rules.legalActions(in: state, for: state.seat)
                guard let action = legal.first else { break }
                for candidate in legal {
                    XCTAssertNil(rules.rejection(for: candidate, in: state),
                                 "seed \(seed) offered a move it then refused")
                }
                _ = rules.apply(action, to: &state, generator: &generator)
            }
        }
    }

    func testFaceDownCardsAreHiddenFromTheObservation() {
        let state = fresh()
        let observation = rules.observation(of: state, for: state.seat)
        let visible = observation.columns.reduce(0) { $0 + $1.count }
        XCTAssertEqual(visible, 10, "one face-up card per column at the start")
        XCTAssertEqual(observation.faceDownCounts.reduce(0, +), 44)
        XCTAssertEqual(observation.stockRowsLeft, 5)

        let redacted = state.board.redacted(for: state.seat)
        XCTAssertEqual(redacted.knownCards.count, 10,
                       "the player can only see what has been turned over")
    }
}

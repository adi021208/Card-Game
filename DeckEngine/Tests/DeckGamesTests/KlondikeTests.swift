import XCTest
import DeckCore
@testable import DeckGames

final class KlondikeTests: XCTestCase {
    private let rules = KlondikeRules()

    private func start(seed: UInt64 = 1234, options: [String: Int] = [:]) -> (KlondikeRules.State, SeededGenerator) {
        let configuration = TestTable.configuration(.klondike, humans: 1, options: options, seed: seed)
        var generator = SeededGenerator(seed: seed)
        return (rules.setup(configuration: configuration, generator: &generator), generator)
    }

    func testOpeningLayout() {
        let (state, _) = start()
        var dealt = 0
        for column in 0..<KlondikeRules.tableauCount {
            let contents = state.board.contents(of: .tableau(column))
            XCTAssertEqual(contents.count, column + 1)
            dealt += contents.count
            let faceUpCount = contents.filter { state.board.isFaceUp($0) }.count
            XCTAssertEqual(faceUpCount, 1, "only the last card of a column starts face up")
            XCTAssertTrue(state.board.isFaceUp(contents[contents.count - 1]))
        }
        XCTAssertEqual(dealt, 28)
        XCTAssertEqual(state.board.count(in: .stock), 24)
        XCTAssertEqual(state.board.count(in: .waste), 0)
        for index in 0..<KlondikeRules.foundationCount {
            XCTAssertEqual(state.board.count(in: .foundation(index)), 0)
        }
    }

    func testFoundationsOnlyAcceptAcesWhenEmpty() {
        let (state, _) = start()
        let foundation = Zone.foundation(0)
        XCTAssertTrue(rules.canPlaceOnFoundation(Card(.hearts, .ace), foundation: foundation, in: state))
        XCTAssertFalse(rules.canPlaceOnFoundation(Card(.hearts, .two), foundation: foundation, in: state))
        XCTAssertFalse(rules.canPlaceOnFoundation(Card(.hearts, .king), foundation: foundation, in: state))
    }

    func testFoundationsBuildUpInSuit() {
        var (state, _) = start()
        let ace = Card(.hearts, .ace)
        state.board.load([ace], into: .foundation(0))
        state.board.flip(ace.id, faceUp: true)
        XCTAssertTrue(rules.canPlaceOnFoundation(Card(.hearts, .two), foundation: .foundation(0), in: state))
        XCTAssertFalse(rules.canPlaceOnFoundation(Card(.spades, .two), foundation: .foundation(0), in: state),
                       "foundations are single suit")
        XCTAssertFalse(rules.canPlaceOnFoundation(Card(.hearts, .three), foundation: .foundation(0), in: state),
                       "foundations go up one at a time")
    }

    func testEmptyColumnsTakeOnlyKings() {
        var (state, _) = start()
        // Empty a column by moving everything out of the way.
        let column = Zone.tableau(0)
        for id in state.board.contents(of: column) {
            state.board.move(id, to: .reserve, facing: .faceDown)
        }
        XCTAssertTrue(state.board.isEmpty(column))
        XCTAssertTrue(rules.canPlaceOnTableau(Card(.spades, .king), column: column, in: state))
        XCTAssertFalse(rules.canPlaceOnTableau(Card(.spades, .queen), column: column, in: state))
    }

    func testTableauBuildsDownInAlternatingColours() {
        var (state, _) = start()
        let column = Zone.tableau(1)
        for id in state.board.contents(of: column) {
            state.board.move(id, to: .reserve, facing: .faceDown)
        }
        let blackNine = Card(.spades, .nine)
        state.board.load([blackNine], into: column)
        state.board.flip(blackNine.id, faceUp: true)

        XCTAssertTrue(rules.canPlaceOnTableau(Card(.hearts, .eight), column: column, in: state))
        XCTAssertTrue(rules.canPlaceOnTableau(Card(.diamonds, .eight), column: column, in: state))
        XCTAssertFalse(rules.canPlaceOnTableau(Card(.clubs, .eight), column: column, in: state),
                       "same colour will not stack")
        XCTAssertFalse(rules.canPlaceOnTableau(Card(.hearts, .seven), column: column, in: state),
                       "must be exactly one lower")
        XCTAssertFalse(rules.canPlaceOnTableau(Card(.hearts, .ten), column: column, in: state))
    }

    func testRunsMustBeProperlySequencedToLift() {
        var (state, _) = start()
        let column = Zone.tableau(2)
        for id in state.board.contents(of: column) {
            state.board.move(id, to: .reserve, facing: .faceDown)
        }
        let nine = Card(.spades, .nine)
        let eight = Card(.hearts, .eight)
        let seven = Card(.clubs, .seven)
        for card in [nine, eight, seven] {
            state.board.load([card], into: column)
            state.board.flip(card.id, faceUp: true)
        }
        XCTAssertEqual(rules.liftableRun(from: nine.id, in: state)?.count, 3)
        XCTAssertEqual(rules.liftableRun(from: eight.id, in: state)?.count, 2)
        XCTAssertEqual(rules.liftableRun(from: seven.id, in: state)?.count, 1)

        // Break the sequence and the run stops being liftable from the top.
        let broken = Card(.diamonds, .two)
        state.board.load([broken], into: column)
        state.board.flip(broken.id, faceUp: true)
        XCTAssertNil(rules.liftableRun(from: nine.id, in: state))
    }

    func testFaceDownCardsCannotBeLifted() {
        let (state, _) = start()
        let contents = state.board.contents(of: .tableau(6))
        guard let buried = contents.first else { return XCTFail("empty column") }
        XCTAssertFalse(state.board.isFaceUp(buried))
        XCTAssertNil(rules.liftableRun(from: buried, in: state))
    }

    func testTurningTheStockMovesCardsToTheWaste() {
        var (state, generator) = start(options: ["drawCount": 3])
        _ = rules.apply(.drawFromStock, to: &state, generator: &generator)
        XCTAssertEqual(state.board.count(in: .waste), 3)
        XCTAssertEqual(state.board.count(in: .stock), 21)
        XCTAssertTrue(state.board.contents(of: .waste).allSatisfy { state.board.isFaceUp($0) })
    }

    func testRecyclingRequiresAnEmptyStock() {
        var (state, generator) = start()
        XCTAssertNotNil(rules.rejection(for: .recycleWaste, in: state))
        for _ in 0..<24 {
            _ = rules.apply(.drawFromStock, to: &state, generator: &generator)
        }
        XCTAssertEqual(state.board.count(in: .stock), 0)
        XCTAssertNil(rules.rejection(for: .recycleWaste, in: state))
        _ = rules.apply(.recycleWaste, to: &state, generator: &generator)
        XCTAssertEqual(state.board.count(in: .stock), 24)
        XCTAssertEqual(state.board.count(in: .waste), 0)
        XCTAssertEqual(state.redealsUsed, 1)
    }

    func testRedealLimitIsEnforced() {
        var (state, generator) = start(options: ["redealLimit": 1])
        for _ in 0..<24 { _ = rules.apply(.drawFromStock, to: &state, generator: &generator) }
        _ = rules.apply(.recycleWaste, to: &state, generator: &generator)
        for _ in 0..<24 { _ = rules.apply(.drawFromStock, to: &state, generator: &generator) }
        XCTAssertNotNil(rules.rejection(for: .recycleWaste, in: state), "the redeal limit must bite")
    }

    func testMovingACardTurnsUpTheOneBeneath() {
        var (state, generator) = start()
        // Find any legal tableau-to-tableau move that uncovers a card.
        let actions = rules.legalActions(in: state, for: state.seat)
        for action in actions {
            guard case let .move(cardID, destination) = action,
                  destination.kind == .tableau,
                  let origin = state.board.zone(of: cardID),
                  origin.kind == .tableau,
                  let run = rules.liftableRun(from: cardID, in: state) else { continue }
            let contents = state.board.contents(of: origin)
            guard contents.count > run.count else { continue }
            let below = contents[contents.count - run.count - 1]
            XCTAssertFalse(state.board.isFaceUp(below))
            _ = rules.apply(action, to: &state, generator: &generator)
            XCTAssertTrue(state.board.isFaceUp(below), "the exposed card is turned up automatically")
            return
        }
    }

    func testEveryLegalMoveIsAccepted() {
        for seed in UInt64(1)...20 {
            var (state, generator) = start(seed: seed)
            var moves = 0
            while moves < 250, state.finalResult == nil {
                let actions = rules.legalActions(in: state, for: state.seat)
                guard let action = actions.first else { break }
                XCTAssertNil(rules.rejection(for: action, in: state),
                             "seed \(seed): a legal move was rejected")
                _ = rules.apply(action, to: &state, generator: &generator)
                moves += 1
            }
        }
    }

    func testFiftyTwoCardsAlwaysExist() {
        for seed in UInt64(1)...20 {
            var (state, generator) = start(seed: seed)
            for _ in 0..<120 {
                let actions = rules.legalActions(in: state, for: state.seat)
                guard let action = actions.first else { break }
                _ = rules.apply(action, to: &state, generator: &generator)
                let counted = state.board.allZones.reduce(0) { $0 + state.board.count(in: $1) }
                XCTAssertEqual(counted, 52, "seed \(seed): cards lost or duplicated")
            }
        }
    }

    func testWinningFillsEveryFoundation() {
        // Build a solved position directly and check the win is detected.
        let configuration = TestTable.configuration(.klondike, humans: 1)
        var generator = SeededGenerator(seed: 1)
        var state = rules.setup(configuration: configuration, generator: &generator)

        var board = Board()
        board.ensureZones((0..<KlondikeRules.tableauCount).map { Zone.tableau($0) }
                          + (0..<KlondikeRules.foundationCount).map { Zone.foundation($0) }
                          + [.stock, .waste])
        for (index, suit) in Suit.allCases.enumerated() {
            let cards = Rank.allCases.map { Card(suit, $0) }
            board.load(cards, into: .foundation(index))
            for card in cards { board.flip(card.id, faceUp: true) }
        }
        // Leave one card out so applying the last move triggers the win.
        let lastCard = Card(.spades, .king)
        board.move(lastCard.id, to: .tableau(0), facing: .faceUp)
        state.board = board
        XCTAssertEqual(state.foundationTotal, 51)

        _ = rules.apply(.move(card: lastCard.id, to: .foundation(3)), to: &state, generator: &generator)
        XCTAssertEqual(state.foundationTotal, 52)
        XCTAssertNotNil(state.finalResult)
        XCTAssertEqual(state.finalResult?.winners, [state.seat])
        XCTAssertTrue(state.finalResult?.highlights.contains("klondike.win") ?? false)
    }

    func testSolitaireHasNothingToHide() {
        let (state, _) = start()
        let view = state.board.redacted(for: state.seat)
        // Face-down tableau cards are hidden from the player too — that is the
        // game, not a privacy rule.
        let hiddenCount = view.piles.values.flatMap { $0 }.filter { !$0.isKnown }.count
        XCTAssertEqual(hiddenCount, 24 + 21, "the stock and the buried tableau cards stay unknown")
    }

    func testZoneTokenEncodingRoundTrips() {
        let zones: [Zone] = [.tableau(0), .tableau(6), .foundation(3), .waste, .stock, .freeCell(2)]
        for zone in zones {
            let encoded = KlondikeRules.encode(zone)
            XCTAssertEqual(KlondikeRules.decode(encoded), zone, "round trip failed for \(zone)")
        }
    }
}

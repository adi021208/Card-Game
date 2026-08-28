import XCTest
@testable import DeckCore

/// The privacy guarantee, tested at the level it is actually enforced: the
/// board's redaction, not the user interface.
final class VisibilityTests: XCTestCase {

    private let alice = SeatID(0)
    private let bob = SeatID(1)
    private let cara = SeatID(2)

    private func dealtBoard() -> Board {
        var board = Board()
        var generator = SeededGenerator(seed: 1)
        var deck = DeckConfiguration.standard52.build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)
        for _ in 0..<5 {
            for seat in [alice, bob, cara] {
                board.draw(from: .stock, to: .hand(seat), facing: .hand(seat))
            }
        }
        board.draw(from: .stock, to: .discard, facing: .faceUp)
        return board
    }

    func testAPlayerSeesOnlyTheirOwnHand() {
        let board = dealtBoard()
        let view = board.redacted(for: alice)

        for card in view.contents(of: .hand(alice)) {
            XCTAssertTrue(card.isKnown, "a player must see their own cards")
        }
        for seat in [bob, cara] {
            for card in view.contents(of: .hand(seat)) {
                XCTAssertFalse(card.isKnown, "\(seat) hand leaked to \(alice)")
            }
        }
    }

    func testFaceUpDiscardIsPublic() {
        let board = dealtBoard()
        for viewer in [alice, bob, cara] {
            let view = board.redacted(for: viewer)
            XCTAssertTrue(view.top(of: .discard)?.isKnown ?? false)
        }
    }

    func testStockIsHiddenFromEveryone() {
        let board = dealtBoard()
        for viewer: SeatID? in [alice, bob, cara, nil] {
            let view = board.redacted(for: viewer)
            for card in view.contents(of: .stock) {
                XCTAssertFalse(card.isKnown, "the undealt stock must be hidden from \(String(describing: viewer))")
            }
        }
    }

    func testNoViewerSeesNothingPrivate() {
        // This is the state the device is in between two players. Nothing
        // private may survive redaction, which is what makes backgrounding,
        // screenshots and the pass screen safe by construction.
        let board = dealtBoard()
        let view = board.redacted(for: nil)
        for seat in [alice, bob, cara] {
            for card in view.contents(of: .hand(seat)) {
                XCTAssertFalse(card.isKnown)
            }
        }
        XCTAssertTrue(view.top(of: .discard)?.isKnown ?? false, "public cards stay public")
    }

    func testRedactedViewCannotRecoverHiddenFaces() {
        let board = dealtBoard()
        let view = board.redacted(for: alice)
        let known = view.knownCards
        let bobsHand = Set(board.contents(of: .hand(bob)))
        XCTAssertTrue(known.isDisjoint(with: bobsHand))
    }

    func testTemporaryRevealRestoresTheOriginalPermission() {
        var board = dealtBoard()
        guard let card = board.contents(of: .hand(bob)).first else { return XCTFail("no card") }

        XCTAssertFalse(board.visibility(of: card).canSee(alice))
        board.temporarilyReveal(card, to: [alice])
        XCTAssertTrue(board.visibility(of: card).canSee(alice))
        XCTAssertTrue(board.visibility(of: card).canSee(bob), "the owner keeps seeing it")

        board.settleTemporaryReveals()
        XCTAssertFalse(board.visibility(of: card).canSee(alice))
        XCTAssertTrue(board.visibility(of: card).canSee(bob))
    }

    func testNestedTemporaryRevealsDoNotStack() {
        var board = dealtBoard()
        guard let card = board.contents(of: .hand(bob)).first else { return XCTFail("no card") }
        board.temporarilyReveal(card, to: [alice])
        board.temporarilyReveal(card, to: [cara])
        board.settleTemporaryReveals()
        XCTAssertFalse(board.visibility(of: card).canSee(alice))
        XCTAssertFalse(board.visibility(of: card).canSee(cara))
        XCTAssertTrue(board.visibility(of: card).canSee(bob))
    }

    func testPartnershipVisibility() {
        var board = dealtBoard()
        guard let card = board.contents(of: .hand(alice)).first else { return XCTFail("no card") }
        board.setVisibility(.seats([alice, bob]), for: card)
        XCTAssertTrue(board.visibility(of: card).canSee(alice))
        XCTAssertTrue(board.visibility(of: card).canSee(bob))
        XCTAssertFalse(board.visibility(of: card).canSee(cara))
        XCTAssertFalse(board.visibility(of: card).canSee(nil))
    }

    func testMovingACardIntoAHandMakesItPrivateToThatHand() {
        var board = dealtBoard()
        guard let card = board.top(of: .discard) else { return XCTFail("no discard") }
        XCTAssertTrue(board.visibility(of: card.id).canSee(bob))
        board.move(card.id, to: .hand(alice), facing: .hand(alice))
        XCTAssertTrue(board.visibility(of: card.id).canSee(alice))
        XCTAssertFalse(board.visibility(of: card.id).canSee(bob))
    }

    func testEveryCardIsAccountedForAfterMoves() {
        var board = dealtBoard()
        let total = board.cards.count
        for _ in 0..<20 {
            guard let card = board.top(of: .stock) else { break }
            board.move(card.id, to: .hand(cara), facing: .hand(cara))
        }
        let counted = board.allZones.reduce(0) { $0 + board.count(in: $1) }
        XCTAssertEqual(counted, total, "cards must not be lost or duplicated by moves")
    }
}

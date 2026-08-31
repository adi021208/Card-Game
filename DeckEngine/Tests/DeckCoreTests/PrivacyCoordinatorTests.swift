import XCTest
@testable import DeckCore

/// The Pass & Play handshake. These are the tests the product spec calls out by
/// name, plus the ones that fell out of writing the coordinator.
final class PrivacyCoordinatorTests: XCTestCase {

    private func seating(humans: Int, ai: Int = 0) -> SeatingPlan {
        var seats: [Seat] = []
        for index in 0..<humans {
            seats.append(Seat(id: SeatID(index),
                              displayName: ["Maya", "Ike", "Rue", "Jo", "Bex", "Sam"][index % 6],
                              controller: .human(profileID: "p\(index)")))
        }
        for index in 0..<ai {
            seats.append(Seat(id: SeatID(humans + index),
                              displayName: "Pedro",
                              controller: .ai(personality: .pedro, difficulty: .casual)))
        }
        return SeatingPlan(seats: seats)
    }

    private func dealtBoard(_ plan: SeatingPlan) -> Board {
        var board = Board()
        var generator = SeededGenerator(seed: 5)
        var deck = DeckConfiguration.standard52.build()
        deck.deterministicShuffle(using: &generator)
        board.load(deck, into: .stock)
        for _ in 0..<5 {
            for seat in plan.ids {
                board.draw(from: .stock, to: .hand(seat), facing: .hand(seat))
            }
        }
        return board
    }

    // Test 1: player A cannot see player B's cards.
    func testPlayerCannotSeeTheNextPlayersCards() {
        let plan = seating(humans: 2)
        let board = dealtBoard(plan)
        let coordinator = PrivacyCoordinator(seating: plan, startingSeat: SeatID(0))
        // A multi-human game opens on the pass screen with nobody looking.
        XCTAssertNil(coordinator.viewer)
        let view = board.redacted(for: coordinator.viewer)
        for seat in plan.ids {
            for card in view.contents(of: .hand(seat)) {
                XCTAssertFalse(card.isKnown)
            }
        }
    }

    // Test 5: the next player's hand only appears after they confirm.
    func testHandOnlyAppearsAfterConfirmation() {
        let plan = seating(humans: 2)
        let board = dealtBoard(plan)
        var coordinator = PrivacyCoordinator(seating: plan, startingSeat: SeatID(0))

        XCTAssertNil(coordinator.viewer, "nothing is visible before the reveal is confirmed")
        XCTAssertFalse(coordinator.acceptsInput)

        let directives = coordinator.confirmReveal()
        XCTAssertEqual(directives.first, .revealHand(seat: SeatID(0), duration: coordinator.revealDuration))
        coordinator.revealCompleted()

        XCTAssertEqual(coordinator.viewer, SeatID(0))
        XCTAssertTrue(coordinator.acceptsInput)
        let view = board.redacted(for: coordinator.viewer)
        XCTAssertTrue(view.contents(of: .hand(SeatID(0))).allSatisfy(\.isKnown))
        XCTAssertTrue(view.contents(of: .hand(SeatID(1))).allSatisfy { !$0.isKnown })
    }

    // Test 4: the previous player's selection is cleared before the pass.
    func testHandoffClearsInteractionFirst() {
        let plan = seating(humans: 3)
        var coordinator = PrivacyCoordinator(seating: plan, startingSeat: SeatID(0))
        _ = coordinator.confirmReveal()
        coordinator.revealCompleted()

        let directives = coordinator.turnPassed(to: SeatID(1))
        XCTAssertEqual(directives.first, .clearInteraction,
                       "interaction must stop before anything else happens")
        XCTAssertTrue(directives.contains(.presentHandoff(to: SeatID(1))))
        XCTAssertNil(coordinator.viewer, "the viewer drops the moment the pass starts")
        XCTAssertFalse(coordinator.acceptsInput)
    }

    // Test 3: backgrounding during a turn takes everything private off screen.
    func testShieldOnBackgroundingHidesEverythingAndRequiresReconfirmation() {
        let plan = seating(humans: 2)
        let board = dealtBoard(plan)
        var coordinator = PrivacyCoordinator(seating: plan, startingSeat: SeatID(0))
        _ = coordinator.confirmReveal()
        coordinator.revealCompleted()
        XCTAssertEqual(coordinator.viewer, SeatID(0))

        let directives = coordinator.shield()
        XCTAssertTrue(directives.contains(.clearInteraction))
        XCTAssertNil(coordinator.viewer)
        XCTAssertFalse(coordinator.phase.showsPrivateInformation)

        let view = board.redacted(for: coordinator.viewer)
        XCTAssertTrue(view.contents(of: .hand(SeatID(0))).allSatisfy { !$0.isKnown })

        // The same player has to confirm again before their hand comes back.
        _ = coordinator.confirmReveal()
        coordinator.revealCompleted()
        XCTAssertEqual(coordinator.viewer, SeatID(0))
    }

    func testShieldAsksForPeeksToBeSettled() {
        // The coordinator does not reach into game state; it asks for the peek
        // to be ended and the session does it. The directive is the contract.
        let plan = seating(humans: 2)
        var coordinator = PrivacyCoordinator(seating: plan, startingSeat: SeatID(0))
        _ = coordinator.confirmReveal()
        coordinator.revealCompleted()
        let directives = coordinator.shield()
        XCTAssertTrue(directives.contains(.settleReveals),
                      "a peek must not survive the device changing hands")
    }

    func testSettlingAPeekActuallyHidesTheCard() {
        let plan = seating(humans: 2)
        var board = dealtBoard(plan)
        guard let card = board.contents(of: .hand(SeatID(1))).first else { return XCTFail("no card") }
        board.temporarilyReveal(card, to: [SeatID(0)])
        XCTAssertTrue(board.visibility(of: card).canSee(SeatID(0)))
        board.settleTemporaryReveals()
        XCTAssertFalse(board.visibility(of: card).canSee(SeatID(0)))
    }

    // Test 6: six-player games work.
    func testSixPlayerRotation() {
        let plan = seating(humans: 6)
        let board = dealtBoard(plan)
        var coordinator = PrivacyCoordinator(seating: plan, startingSeat: SeatID(0))
        for index in 0..<6 {
            _ = coordinator.confirmReveal()
            coordinator.revealCompleted()
            XCTAssertEqual(coordinator.viewer, SeatID(index))
            let view = board.redacted(for: coordinator.viewer)
            for other in plan.ids where other != SeatID(index) {
                XCTAssertTrue(view.contents(of: .hand(other)).allSatisfy { !$0.isKnown },
                              "seat \(other) leaked to seat \(index)")
            }
            let next = SeatID((index + 1) % 6)
            _ = coordinator.turnPassed(to: next)
            coordinator.sealingCompleted()
        }
    }

    func testSoloGameNeverAsksForAHandoff() {
        let plan = seating(humans: 1, ai: 3)
        var coordinator = PrivacyCoordinator(seating: plan, startingSeat: SeatID(0))
        XCTAssertFalse(coordinator.requiresHandoff)
        XCTAssertEqual(coordinator.viewer, SeatID(0), "the one human sees their hand immediately")
        // An AI taking its turn does not take the device away.
        let directives = coordinator.turnPassed(to: SeatID(1))
        XCTAssertTrue(directives.isEmpty)
        XCTAssertEqual(coordinator.viewer, SeatID(0))
        XCTAssertTrue(coordinator.shield().isEmpty)
    }

    func testAITurnInAPassAndPlayGameKeepsTheDeviceWithItsHolder() {
        let plan = seating(humans: 2, ai: 2)
        var coordinator = PrivacyCoordinator(seating: plan, startingSeat: SeatID(0))
        _ = coordinator.confirmReveal()
        coordinator.revealCompleted()

        // Seats 2 and 3 are AI; the human holding the phone keeps looking at
        // their own hand while the opponents play.
        XCTAssertTrue(coordinator.turnPassed(to: SeatID(2)).isEmpty)
        XCTAssertEqual(coordinator.viewer, SeatID(0))
        XCTAssertTrue(coordinator.turnPassed(to: SeatID(3)).isEmpty)
        XCTAssertEqual(coordinator.viewer, SeatID(0))

        // Handing over to the other human runs the full ritual.
        let directives = coordinator.turnPassed(to: SeatID(1))
        XCTAssertFalse(directives.isEmpty)
        XCTAssertNil(coordinator.viewer)
    }

    func testSamePlayerActingTwiceDoesNotTriggerAHandoff() {
        let plan = seating(humans: 2)
        var coordinator = PrivacyCoordinator(seating: plan, startingSeat: SeatID(0))
        _ = coordinator.confirmReveal()
        coordinator.revealCompleted()
        XCTAssertTrue(coordinator.turnPassed(to: SeatID(0)).isEmpty)
        XCTAssertEqual(coordinator.viewer, SeatID(0))
    }

    func testReducedMotionKeepsTheConfirmationStep() {
        let plan = seating(humans: 2)
        var coordinator = PrivacyCoordinator(seating: plan, startingSeat: SeatID(0))
        coordinator.setReducedMotion(true)
        XCTAssertEqual(coordinator.sealDuration, 0)
        XCTAssertEqual(coordinator.revealDuration, 0)
        XCTAssertNil(coordinator.viewer, "the reveal still has to be confirmed")
        _ = coordinator.confirmReveal()
        coordinator.revealCompleted()
        XCTAssertEqual(coordinator.viewer, SeatID(0))
    }

    func testPhaseNeverExposesAViewerMidTransition() {
        XCTAssertNil(PrivacyPhase.sealing(next: SeatID(1)).viewer)
        XCTAssertNil(PrivacyPhase.handoff(next: SeatID(1)).viewer)
        XCTAssertNil(PrivacyPhase.concluded.viewer)
        XCTAssertFalse(PrivacyPhase.sealing(next: SeatID(1)).acceptsInput)
        XCTAssertFalse(PrivacyPhase.handoff(next: SeatID(1)).acceptsInput)
        XCTAssertFalse(PrivacyPhase.sealing(next: SeatID(1)).showsPrivateInformation)
        XCTAssertFalse(PrivacyPhase.handoff(next: SeatID(1)).showsPrivateInformation)
    }
}

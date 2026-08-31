import Foundation

/// Where the device is in the hand-off ritual.
///
/// The whole point of this type is that `viewer` is a *computed consequence* of
/// the phase. There is no code path that shows a hand while the phase says the
/// device is in transit, because the renderer is handed `viewer` and the board
/// redacts itself against it.
public enum PrivacyPhase: Hashable, Sendable {
    /// No privacy handshake needed — one human at the table.
    case open(seat: SeatID)
    /// A player is looking at their own hand and acting.
    case playing(seat: SeatID)
    /// Cards are gathering and turning face-down. Interaction is off, and the
    /// viewer has already dropped to nobody so nothing private can be captured
    /// mid-animation.
    case sealing(next: SeatID)
    /// "Pass to Maya." Nothing private is on screen or in the view hierarchy.
    case handoff(next: SeatID)
    /// The incoming player confirmed; their hand is coming up.
    case revealing(seat: SeatID)
    /// The game is over; everything that should be public is public.
    case concluded

    /// The seat whose information may be rendered. `nil` means nobody's.
    ///
    /// This is the single value the entire privacy guarantee rests on.
    public var viewer: SeatID? {
        switch self {
        case let .open(seat): return seat
        case let .playing(seat): return seat
        case let .revealing(seat): return seat
        case .sealing, .handoff: return nil
        case .concluded: return nil
        }
    }

    /// Whether the player may touch cards right now.
    public var acceptsInput: Bool {
        switch self {
        case .open, .playing: return true
        case .sealing, .handoff, .revealing, .concluded: return false
        }
    }

    /// Whether a private hand is on screen. Drives screenshot/recording
    /// protection and the "cover the screen when backgrounded" shield.
    public var showsPrivateInformation: Bool {
        switch self {
        case .open, .playing, .revealing: return true
        case .sealing, .handoff, .concluded: return false
        }
    }

    public var pendingSeat: SeatID? {
        switch self {
        case let .sealing(next), let .handoff(next): return next
        default: return nil
        }
    }
}

/// What the coordinator wants the rest of the app to do next.
public enum PrivacyDirective: Hashable, Sendable {
    /// Drop any selected card, close any open sheet, stop any drag.
    case clearInteraction
    /// End every outstanding peek in the game state, so a card somebody was
    /// shown does not survive the device changing hands.
    case settleReveals
    /// Gather private cards into a face-down stack over this duration.
    case sealCards(duration: TimeInterval)
    /// Show the pass screen naming this seat.
    case presentHandoff(to: SeatID)
    /// Play the reveal for this seat over this duration.
    case revealHand(seat: SeatID, duration: TimeInterval)
    /// Ordinary turn change with no hand-off (solo, or AI to AI).
    case resumePlay(seat: SeatID)
    /// The game finished.
    case conclude
}

/// Runs the Pass & Play hand-off.
///
/// Sequence, in order, every time the device changes hands:
/// 1. stop accepting input
/// 2. clear selection, drags and open sheets
/// 3. drop the viewer to nobody, which redacts every private card out of the
///    render model — they are not covered up, they are *gone*
/// 4. settle any temporary reveals in the board
/// 5. seal: cards gather and turn face-down
/// 6. present the pass screen naming the next player
/// 7. wait for an explicit confirmation from a human
/// 8. reveal only that player's information
public struct PrivacyCoordinator: Sendable {
    /// How long the sealing animation runs. Short enough not to be a tax on
    /// every turn of a six-player game.
    public var sealDuration: TimeInterval
    /// How long the reveal runs after confirmation.
    public var revealDuration: TimeInterval
    /// True when more than one human shares the device.
    public let requiresHandoff: Bool

    public private(set) var phase: PrivacyPhase

    private let seating: SeatingPlan

    public init(seating: SeatingPlan,
                startingSeat: SeatID,
                sealDuration: TimeInterval = 0.55,
                revealDuration: TimeInterval = 0.45) {
        self.seating = seating
        self.requiresHandoff = seating.isPassAndPlay
        self.sealDuration = sealDuration
        self.revealDuration = revealDuration
        // A multi-human game opens on the pass screen, so the very first hand is
        // revealed by its owner rather than being on screen when the game loads.
        self.phase = seating.isPassAndPlay ? .handoff(next: startingSeat) : .open(seat: startingSeat)
    }

    public var viewer: SeatID? { phase.viewer }
    public var acceptsInput: Bool { phase.acceptsInput }

    /// Reduced-motion and accessibility settings can collapse the animation
    /// without weakening the guarantee: the confirmation step never goes away.
    public mutating func setReducedMotion(_ reduced: Bool) {
        sealDuration = reduced ? 0.0 : 0.55
        revealDuration = reduced ? 0.0 : 0.45
    }

    /// Called by the game coordinator when the engine hands the turn to `seat`.
    ///
    /// Returns the directives to run, in order.
    ///
    /// An AI taking its turn does **not** move the device: whoever is holding it
    /// keeps looking at their own hand while the opponents play. The ritual runs
    /// only when a *different human* is next to act, which is the moment the
    /// phone actually changes hands.
    public mutating func turnPassed(to seat: SeatID) -> [PrivacyDirective] {
        guard isHuman(seat) else { return [] }
        if phase.viewer == seat {
            beganPlaying()
            return []
        }
        guard requiresHandoff else {
            phase = .open(seat: seat)
            return [.resumePlay(seat: seat)]
        }
        phase = .sealing(next: seat)
        return [.clearInteraction, .settleReveals,
                .sealCards(duration: sealDuration), .presentHandoff(to: seat)]
    }

    /// Called when the sealing animation finishes.
    public mutating func sealingCompleted() {
        guard case let .sealing(next) = phase else { return }
        phase = .handoff(next: next)
    }

    /// The incoming player tapped REVEAL. This is the only way out of `handoff`.
    public mutating func confirmReveal() -> [PrivacyDirective] {
        guard case let .handoff(next) = phase else { return [] }
        phase = .revealing(seat: next)
        return [.revealHand(seat: next, duration: revealDuration)]
    }

    /// Called when the reveal animation finishes.
    public mutating func revealCompleted() {
        guard case let .revealing(seat) = phase else { return }
        phase = .playing(seat: seat)
    }

    /// Marks the current player as having started acting. Distinguishes "the
    /// hand is up" from "the hand is being dealt".
    public mutating func beganPlaying() {
        if case let .open(seat) = phase { phase = .playing(seat: seat) }
        if case let .revealing(seat) = phase { phase = .playing(seat: seat) }
    }

    /// The app is going to the background, being screenshotted, or entering the
    /// app switcher. Everything private comes down immediately and the incoming
    /// player has to confirm again — the snapshot iOS takes for the switcher can
    /// then contain nothing private.
    public mutating func shield() -> [PrivacyDirective] {
        guard requiresHandoff else { return [] }
        switch phase {
        case let .open(seat), let .playing(seat), let .revealing(seat):
            phase = .handoff(next: seat)
            return [.clearInteraction, .settleReveals, .presentHandoff(to: seat)]
        case let .sealing(next):
            phase = .handoff(next: next)
            return [.clearInteraction, .settleReveals, .presentHandoff(to: next)]
        case .handoff, .concluded:
            return []
        }
    }

    /// The game finished. Results are public information, so the ritual stops.
    public mutating func conclude() -> [PrivacyDirective] {
        phase = .concluded
        return [.conclude]
    }

    /// Name shown on the pass screen.
    public func displayName(of seat: SeatID) -> String {
        seating[seat]?.displayName ?? ""
    }

    private func isHuman(_ seat: SeatID) -> Bool {
        seating[seat]?.isHuman ?? false
    }
}

import SwiftUI

/// Motion tokens.
///
/// Everything that moves in DECK moves for one of four reasons, and each has its
/// own curve. A card settling uses a spring because a card has weight; a screen
/// wiping uses an ease because paper does not bounce.
public enum DeckMotion {

    // MARK: - Durations

    public static let instant: TimeInterval = 0.12
    public static let quick: TimeInterval = 0.22
    public static let standard: TimeInterval = 0.34
    public static let deliberate: TimeInterval = 0.55
    /// The Pass & Play seal. Long enough to read as a physical action, short
    /// enough that a six-player game does not become a slideshow.
    public static let seal: TimeInterval = 0.55
    public static let reveal: TimeInterval = 0.45
    /// One card being dealt. Multiplied by its index for a stagger.
    public static let dealStep: TimeInterval = 0.055

    // MARK: - Curves

    /// A card landing. Slightly under-damped so it settles rather than stops.
    public static let cardSettle = Animation.spring(response: 0.34, dampingFraction: 0.72)
    /// A card being picked up.
    public static let cardLift = Animation.spring(response: 0.22, dampingFraction: 0.7)
    /// A card snapping back after an illegal drop. Stiffer, so it reads as a
    /// rejection rather than a placement.
    public static let cardReturn = Animation.spring(response: 0.28, dampingFraction: 0.62)
    /// A card being dealt from the deck.
    public static let deal = Animation.spring(response: 0.42, dampingFraction: 0.78)
    /// A flip. Linear through the middle so the halves match.
    public static let flip = Animation.timingCurve(0.35, 0, 0.2, 1, duration: 0.42)
    /// Screen transitions and painted wipes.
    public static let wipe = Animation.timingCurve(0.65, 0, 0.15, 1, duration: 0.5)
    /// Panels and sheets.
    public static let panel = Animation.spring(response: 0.4, dampingFraction: 0.86)
    /// A number counting up.
    public static let count = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.7)
    /// A stamp landing.
    public static let stamp = Animation.spring(response: 0.3, dampingFraction: 0.55)
    /// Selection and small state changes.
    public static let select = Animation.easeOut(duration: 0.16)

    /// Returns the animation, or nil when the player has asked for less motion.
    ///
    /// Reduced motion never removes the state change — only the movement.
    public static func respectingReduceMotion(_ animation: Animation, reduced: Bool) -> Animation? {
        reduced ? .easeInOut(duration: 0.12) : animation
    }

    /// Stagger for dealing a hand.
    public static func dealDelay(index: Int, reduced: Bool) -> TimeInterval {
        reduced ? 0 : Double(index) * dealStep
    }

    // MARK: - Intentional imperfection

    /// A small, *stable* rotation for a card or poster.
    ///
    /// The angle is derived from a seed, so a card sits at the same jaunty angle
    /// every time the view is rebuilt. This is composition, not noise: nothing
    /// in the app is perturbed randomly at run time.
    public static func settledAngle(seed: Int, spread: Double = 3.0) -> Angle {
        var hash = UInt64(bitPattern: Int64(seed &* 2_654_435_761))
        hash ^= hash >> 33
        hash = hash &* 0xFF51_AFD7_ED55_8CCD
        hash ^= hash >> 33
        let unit = Double(hash % 2000) / 1000.0 - 1.0    // -1…1
        return .degrees(unit * spread)
    }

    /// A stable small offset, for collage placement.
    public static func settledOffset(seed: Int, spread: CGFloat = 4) -> CGSize {
        let x = settledAngle(seed: seed &* 7, spread: 1).degrees
        let y = settledAngle(seed: seed &* 13, spread: 1).degrees
        return CGSize(width: CGFloat(x) * spread, height: CGFloat(y) * spread)
    }
}

/// Reads the system's reduce-motion setting and the player's own toggle, and
/// gives the whole app one answer.
public struct ReducedMotionKey: EnvironmentKey {
    public static let defaultValue = false
}

public extension EnvironmentValues {
    var deckReducedMotion: Bool {
        get { self[ReducedMotionKey.self] }
        set { self[ReducedMotionKey.self] = newValue }
    }
}

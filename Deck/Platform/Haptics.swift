import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CoreHaptics)
import CoreHaptics
#endif

/// The haptic vocabulary.
///
/// Each case is a *meaning*, not a waveform: callers say "a card landed", not
/// "medium impact". That keeps the feel consistent across fifteen games and
/// makes the whole thing tunable from one place.
public enum HapticEventKind {
    /// A button going down.
    case press
    /// A light tap on a control.
    case light
    /// A card lifting off the table.
    case pickUp
    /// A card landing where it belongs.
    case place
    /// A move the rules refused.
    case rejected
    /// Cards being shuffled.
    case shuffle
    /// One card dealt.
    case deal
    /// The turn passing to somebody else.
    case turnChange
    /// The device changing hands.
    case handoff
    /// A trick, a pot or a book being taken.
    case collect
    /// The game is won.
    case victory
    /// The game is lost.
    case defeat
    /// An achievement unlocking.
    case achievement
    /// A boss appearing.
    case boss
    /// A streak advancing.
    case streak
}

/// Plays haptics.
///
/// Uses Core Haptics for the patterns that need shape (the shuffle, the
/// hand-off, the victory) and the cheap feedback generators for everything that
/// is just a tap. Falls back cleanly on hardware without a Taptic Engine, and
/// does nothing at all when the player has turned haptics off.
public final class Haptics: @unchecked Sendable {
    public static let shared = Haptics()

    public var isEnabled: Bool = true

    #if canImport(CoreHaptics)
    private var engine: CHHapticEngine?
    private var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }
    #endif

    #if canImport(UIKit)
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()
    #endif

    private init() {}

    /// Warms the engine up so the first tap is not late.
    public func prepare() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        lightImpact.prepare()
        mediumImpact.prepare()
        rigidImpact.prepare()
        softImpact.prepare()
        #endif
        #if canImport(CoreHaptics)
        guard supportsHaptics, engine == nil else { return }
        engine = try? CHHapticEngine()
        // The engine is stopped by the system when the app backgrounds; restart
        // it rather than silently going dead for the rest of the session.
        engine?.resetHandler = { [weak self] in
            try? self?.engine?.start()
        }
        engine?.stoppedHandler = { _ in }
        try? engine?.start()
        #endif
    }

    public func tap(_ kind: HapticEventKind) {
        guard isEnabled else { return }
        #if canImport(UIKit)
        switch kind {
        case .press, .place:
            mediumImpact.impactOccurred()
        case .light, .deal:
            lightImpact.impactOccurred()
        case .pickUp:
            softImpact.impactOccurred(intensity: 0.7)
        case .rejected:
            notification.notificationOccurred(.warning)
        case .turnChange:
            selection.selectionChanged()
        case .collect:
            rigidImpact.impactOccurred(intensity: 0.8)
        case .victory, .achievement, .streak:
            notification.notificationOccurred(.success)
        case .defeat:
            notification.notificationOccurred(.error)
        case .shuffle, .handoff, .boss:
            playPattern(for: kind)
        }
        #endif
    }

    /// The shaped patterns. A shuffle is a run of quick taps; a hand-off is a
    /// firm double; a boss arriving is a slow swell.
    private func playPattern(for kind: HapticEventKind) {
        #if canImport(CoreHaptics)
        guard supportsHaptics, let engine else {
            #if canImport(UIKit)
            mediumImpact.impactOccurred()
            #endif
            return
        }
        var events: [CHHapticEvent] = []
        switch kind {
        case .shuffle:
            for index in 0..<9 {
                let time = Double(index) * 0.035
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                    ],
                    relativeTime: time))
            }
        case .handoff:
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: 0))
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                ],
                relativeTime: 0.12))
        case .boss:
            events.append(CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.55),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                ],
                relativeTime: 0,
                duration: 0.45))
        default:
            return
        }
        guard let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: 0)
        #endif
    }

    /// Reacts to an engine event. The audio and haptic layers subscribe to the
    /// same stream, which is why a card landing always sounds and feels like one.
    public func respond(to kind: HapticEventKind) { tap(kind) }
}

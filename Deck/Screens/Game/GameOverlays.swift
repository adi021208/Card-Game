import SwiftUI
import DeckCore
import DeckProgression

/// Why a move was refused.
///
/// The engine returns a structured reason, so this can explain the rule rather
/// than saying "invalid move". A refused tap is the best teaching moment a card
/// game gets.
public struct RejectionBanner: View {
    private let reason: IllegalMove

    @Environment(\.deckTheme) private var theme

    public init(reason: IllegalMove) {
        self.reason = reason
    }

    public var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: DeckSpace.xs) {
                InkArrow(seed: 3)
                    .stroke(DeckPalette.cream, style: StrokeStyle(lineWidth: 2.4,
                                                                  lineCap: .round,
                                                                  lineJoin: .round))
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(140))
                Text(text)
                    .font(DeckType.bodyEmphasis)
                    .foregroundStyle(DeckPalette.cream)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DeckSpace.m)
            .background(
                RoundedRectangle(cornerRadius: DeckRadius.panel, style: .continuous)
                    .fill(DeckPalette.crimson)
            )
            .padding(.horizontal, DeckSpace.page)
            .padding(.bottom, 120)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement()
        .accessibilityLabel(Text(text))
        .accessibilityAddTraits(.isStaticText)
    }

    private var text: String {
        let format = String.deck(reason.localizationKey, or: reason.englishExplanation)
        return CalloutRow.interpolate(format, arguments: reason.arguments)
    }
}

/// A hint.
///
/// Always the reasoning, never just the move. The suggested action is offered
/// separately, so a player who wants to be told can be told, and a player who
/// wants to learn is not.
public struct HintCard: View {
    private let hint: Hint
    private let onDismiss: () -> Void

    @Environment(\.deckTheme) private var theme

    public init(hint: Hint, onDismiss: @escaping () -> Void) {
        self.hint = hint
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: DeckSpace.s) {
                HStack(spacing: DeckSpace.xs) {
                    Text(String(localized: "hint.why", defaultValue: "WHY?"))
                        .font(DeckType.display(22))
                        .foregroundStyle(theme.accent)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(theme.ink.opacity(0.6))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(String(localized: "common.dismiss",
                                                    defaultValue: "Dismiss")))
                }
                Text(text)
                    .font(DeckType.body)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DeckSpace.m)
            .background(
                RoundedRectangle(cornerRadius: DeckRadius.panel, style: .continuous)
                    .fill(theme.surface)
            )
            .deckShadow(.panel)
            .padding(.horizontal, DeckSpace.page)
            .padding(.bottom, 120)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }

    private var text: String {
        let format = String.deck(hint.messageKey, or: hint.english)
        return CalloutRow.interpolate(format, arguments: hint.arguments)
    }
}

/// When a card can be played more than one way, the player chooses.
///
/// The eight in Crazy Eights is the obvious case: four suits, one card. Guessing
/// would be worse than asking.
public struct MoveChoiceSheet: View {
    private let card: CardID
    private let options: [ActionToken]
    private let onPick: (ActionToken) -> Void
    private let onCancel: () -> Void

    @Environment(\.deckTheme) private var theme

    public init(card: CardID,
                options: [ActionToken],
                onPick: @escaping (ActionToken) -> Void,
                onCancel: @escaping () -> Void) {
        self.card = card
        self.options = options
        self.onPick = onPick
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }
            VStack(spacing: DeckSpace.m) {
                Text(String(localized: "move.choose", defaultValue: "CHOOSE"))
                    .font(DeckType.display(30))
                    .foregroundStyle(theme.ink)
                // Suit choices get the drawn suits rather than a list of words.
                if options.allSatisfy({ suit(for: $0) != nil }) {
                    HStack(spacing: DeckSpace.m) {
                        ForEach(options) { token in
                            Button {
                                onPick(token)
                            } label: {
                                SuitMark(suit(for: token) ?? .spade,
                                         colour: (suit(for: token)?.isRed ?? false)
                                            ? DeckPalette.vermilion : DeckPalette.ink,
                                         offsetColour: theme.accent.opacity(0.3))
                                    .frame(width: 54, height: 54)
                                    .padding(DeckSpace.s)
                                    .background(
                                        RoundedRectangle(cornerRadius: DeckRadius.button,
                                                         style: .continuous)
                                            .fill(theme.surface)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(CalloutRow.humanised(token.labelArguments.first ?? "")))
                        }
                    }
                } else {
                    VStack(spacing: DeckSpace.xs) {
                        ForEach(options) { token in
                            DeckButton(labelText(token), emphasis: .secondary) { onPick(token) }
                        }
                    }
                }
                DeckButton(String(localized: "common.cancel", defaultValue: "CANCEL"),
                           emphasis: .quiet, action: onCancel)
            }
            .padding(DeckSpace.l)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: DeckRadius.poster, style: .continuous)
                    .fill(theme.surface)
            )
            .padding(DeckSpace.page)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func suit(for token: ActionToken) -> SuitShape.Kind? {
        guard let key = token.labelArguments.first, key.hasPrefix("suit.") else { return nil }
        switch key {
        case "suit.hearts": return .heart
        case "suit.spades": return .spade
        case "suit.clubs": return .club
        case "suit.diamonds": return .diamond
        default: return nil
        }
    }

    private func labelText(_ token: ActionToken) -> String {
        let format = String.deck(token.labelKey, or: CalloutRow.humanised(token.labelKey))
        return CalloutRow.interpolate(format, arguments: token.labelArguments).uppercased()
    }
}

/// The pause menu.
public struct PauseSheet: View {
    private let coordinator: GameCoordinator
    private let onResume: () -> Void
    private let onRules: () -> Void
    private let onQuit: () -> Void

    @Environment(\.deckTheme) private var theme

    public init(coordinator: GameCoordinator,
                onResume: @escaping () -> Void,
                onRules: @escaping () -> Void,
                onQuit: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onResume = onResume
        self.onRules = onRules
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DeckSpace.l) {
            DisplayText(String(localized: "game.paused", defaultValue: "PAUSED"),
                        size: 52, colour: theme.onGround)

            VStack(alignment: .leading, spacing: DeckSpace.xs) {
                infoRow(label: String(localized: "game.round", defaultValue: "Round"),
                        value: "\(coordinator.presentation.roundNumber)")
                infoRow(label: String(localized: "game.elapsed", defaultValue: "Time"),
                        value: formatted(coordinator.elapsed))
                if coordinator.isPassAndPlay {
                    infoRow(label: String(localized: "game.mode", defaultValue: "Mode"),
                            value: String(localized: "mode.passAndPlay", defaultValue: "Pass & Play"))
                }
            }

            VStack(spacing: DeckSpace.xs) {
                DeckButton(String(localized: "game.resume", defaultValue: "RESUME"),
                           emphasis: .primary, action: onResume)
                DeckButton(String(localized: "game.rules", defaultValue: "HOW TO PLAY"),
                           emphasis: .secondary, action: onRules)
                DeckButton(String(localized: "game.quit", defaultValue: "END GAME"),
                           emphasis: .destructive, action: onQuit)
            }
            Text(String(localized: "game.saveNote",
                        defaultValue: "Your game is saved. You can come back to it from Today."))
                .font(DeckType.footnote)
                .foregroundStyle(theme.onGroundMuted)
            Spacer()
        }
        .padding(DeckSpace.page)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.ground.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DeckType.caption)
                .foregroundStyle(theme.onGroundMuted)
            Spacer()
            Text(value)
                .font(DeckType.tabular(16, weight: .bold))
                .foregroundStyle(theme.onGround)
        }
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

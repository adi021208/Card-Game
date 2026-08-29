import SwiftUI
import DeckCore

/// How a card is being presented right now.
public struct CardPresentation: Equatable {
    public var isFaceUp: Bool
    public var isSelected: Bool
    public var isPlayable: Bool
    public var isDimmed: Bool
    public var isDragging: Bool
    /// A light treatment for a card a hint is pointing at.
    public var isHighlighted: Bool
    /// Stable rotation, so a card in a pile sits at the same angle every redraw.
    public var settleSeed: Int

    public init(isFaceUp: Bool = true,
                isSelected: Bool = false,
                isPlayable: Bool = false,
                isDimmed: Bool = false,
                isDragging: Bool = false,
                isHighlighted: Bool = false,
                settleSeed: Int = 0) {
        self.isFaceUp = isFaceUp
        self.isSelected = isSelected
        self.isPlayable = isPlayable
        self.isDimmed = isDimmed
        self.isDragging = isDragging
        self.isHighlighted = isHighlighted
        self.settleSeed = settleSeed
    }
}

/// The card.
///
/// One view renders every card in every game. It takes a `VisibleCard`, which is
/// the redacted type — so a card the viewer is not entitled to see arrives here
/// with no face attached and there is physically nothing to draw. That is the
/// last link in the Pass & Play chain, and it is why the privacy guarantee holds
/// even for the accessibility label, which is derived from the same value.
public struct CardView: View {
    private let card: VisibleCard
    private let width: CGFloat
    private let presentation: CardPresentation
    private let cardBackID: String

    @Environment(\.deckTheme) private var theme
    @Environment(\.deckReducedMotion) private var reducedMotion

    public init(card: VisibleCard,
                width: CGFloat,
                presentation: CardPresentation = CardPresentation(),
                cardBackID: String = "cardback.deck") {
        self.card = card
        self.width = width
        self.presentation = presentation
        self.cardBackID = cardBackID
    }

    private var height: CGFloat { CardMetrics.height(forWidth: width) }
    private var corner: CGFloat { CardMetrics.corner(forWidth: width) }

    /// A card is drawn face-up only when it is turned up *and* the viewer is
    /// allowed to know what it is.
    private var showsFace: Bool {
        presentation.isFaceUp && card.isKnown
    }

    public var body: some View {
        ZStack {
            if showsFace, let model = card.card {
                CardFaceArt(card: model, width: width, theme: theme)
            } else {
                CardBackArt(styleID: cardBackID, theme: theme)
            }
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(DeckPalette.chalk)
        )
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(edgeTreatment)
        .overlay(playableMark)
        .opacity(presentation.isDimmed ? 0.45 : 1)
        .rotationEffect(settleAngle)
        .scaleEffect(scale)
        .offset(y: liftOffset)
        .deckShadow(shadow)
        .animation(DeckMotion.respectingReduceMotion(DeckMotion.cardLift, reduced: reducedMotion),
                   value: presentation)
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAddTraits(presentation.isPlayable ? [.isButton] : [])
    }

    // MARK: - Treatment

    /// Cards are objects, so their edge is a printed keyline, not a UI border.
    /// A selected card is not indicated by a border at all — it lifts, grows and
    /// casts a longer shadow, because that is what picking a card up looks like.
    private var edgeTreatment: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .strokeBorder(DeckPalette.ink.opacity(showsFace ? 0.16 : 0.28),
                          lineWidth: max(0.5, width * 0.008))
    }

    /// The move-assist treatment: a painted corner tick, not a glowing outline.
    @ViewBuilder
    private var playableMark: some View {
        if presentation.isHighlighted {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(theme.accent, lineWidth: max(1.5, width * 0.026))
                .blendMode(.normal)
        } else if presentation.isPlayable && showsFace {
            VStack {
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(theme.accent)
                        .frame(width: width * 0.22, height: max(2, width * 0.035))
                        .rotationEffect(.degrees(-38), anchor: .center)
                        .offset(x: -width * 0.02, y: width * 0.055)
                }
                Spacer()
            }
        }
    }

    private var settleAngle: Angle {
        guard presentation.settleSeed != 0 else { return .zero }
        if presentation.isDragging { return DeckMotion.settledAngle(seed: presentation.settleSeed, spread: 5) }
        return DeckMotion.settledAngle(seed: presentation.settleSeed, spread: 2.2)
    }

    private var scale: CGFloat {
        if presentation.isDragging { return 1.08 }
        if presentation.isSelected { return 1.045 }
        return 1
    }

    private var liftOffset: CGFloat {
        presentation.isSelected ? -height * CardMetrics.liftRatio : 0
    }

    private var shadow: DeckShadow {
        if presentation.isDragging { return .dragging }
        if presentation.isSelected { return .lifted }
        return .resting
    }

    // MARK: - Accessibility

    /// VoiceOver never learns more than the eyes do.
    ///
    /// A concealed card announces itself as face-down and nothing else — there
    /// is no rank or suit in this value to leak, because the `VisibleCard` this
    /// view was handed does not contain one.
    private var accessibilityLabel: String {
        guard showsFace, let model = card.card else {
            return String(localized: "card.faceDown", defaultValue: "Face-down card")
        }
        return CardNaming.spoken(model)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if presentation.isSelected {
            parts.append(String(localized: "card.selected", defaultValue: "Selected"))
        }
        if presentation.isPlayable {
            parts.append(String(localized: "card.playable", defaultValue: "Playable"))
        }
        if presentation.isDimmed && !presentation.isPlayable {
            parts.append(String(localized: "card.notPlayable", defaultValue: "Not playable"))
        }
        return parts.joined(separator: ", ")
    }
}

/// Turns a card into something VoiceOver reads well.
public enum CardNaming {
    public static func spoken(_ card: Card) -> String {
        switch card.kind {
        case let .standard(suit, rank):
            let rankName = String.deck(rank.localizationKey, or: rank.englishName)
            let suitName = String.deck(suit.localizationKey, or: suit.englishName)
            return String(format: String(localized: "card.name.format", defaultValue: "%@ of %@"),
                          rankName, suitName)
        case let .joker(colour):
            return colour == .red
                ? String(localized: "card.redJoker", defaultValue: "Red Joker")
                : String(localized: "card.blackJoker", defaultValue: "Black Joker")
        }
    }

    /// Short form for a list of cards, e.g. a hint.
    public static func shortSpoken(_ cards: [Card]) -> String {
        cards.map(spoken).joined(separator: ", ")
    }
}

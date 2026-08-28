import SwiftUI
import DeckCore

/// A game on a shelf.
///
/// The artwork does the work; the metadata sits underneath it in one quiet line.
/// Pressing it lifts the card and nudges its neighbours, which is what makes the
/// library feel like a rack of things rather than a table of rows.
public struct GameShelfCard: View {
    private let definition: GameDefinition
    private let isFavourite: Bool
    private let masteryLevel: Int
    private let onOpen: () -> Void

    @Environment(\.deckTheme) private var theme
    @Environment(\.deckReducedMotion) private var reducedMotion
    @State private var isPressed = false

    public init(definition: GameDefinition,
                isFavourite: Bool = false,
                masteryLevel: Int = 0,
                onOpen: @escaping () -> Void) {
        self.definition = definition
        self.isFavourite = isFavourite
        self.masteryLevel = masteryLevel
        self.onOpen = onOpen
    }

    public var body: some View {
        Button(action: {
            Haptics.shared.tap(.pickUp)
            onOpen()
        }) {
            VStack(alignment: .leading, spacing: DeckSpace.xs) {
                ZStack(alignment: .topTrailing) {
                    GameCoverArt(artworkID: definition.artworkID,
                                 title: definition.englishName,
                                 size: .shelf,
                                 seed: definition.id.rawValue.count)
                        .aspectRatio(0.78, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: DeckRadius.panel,
                                                    style: .continuous))
                    if isFavourite {
                        SuitShape(.heart)
                            .fill(DeckPalette.vermilion)
                            .frame(width: 16, height: 16)
                            .padding(DeckSpace.xs)
                    }
                }

                // One line of metadata, and only the parts that help somebody
                // choose: how many can play, and how long it takes.
                HStack(spacing: DeckSpace.xxs) {
                    Text(playerRangeText)
                    Text("·")
                    Text(LocalizedStringKey(definition.duration.localizationKey))
                    if masteryLevel >= 4 {
                        Text("·")
                        Text(String(localized: "mastery.mastered", defaultValue: "Mastered"))
                            .foregroundStyle(theme.accent)
                    }
                }
                .font(DeckType.footnote)
                .foregroundStyle(theme.onGroundMuted)
                .lineLimit(1)
            }
            .scaleEffect(isPressed ? 0.97 : 1)
            .rotationEffect(isPressed
                            ? DeckMotion.settledAngle(seed: definition.id.rawValue.count, spread: 1.5)
                            : .zero)
            .deckShadow(isPressed ? .lifted : .panel)
        }
        .buttonStyle(.plain)
        .animation(DeckMotion.respectingReduceMotion(DeckMotion.cardLift, reduced: reducedMotion),
                   value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(definition.englishName))
        .accessibilityValue(Text("\(playerRangeText), \(definition.duration)"))
        .accessibilityAddTraits(.isButton)
    }

    private var playerRangeText: String {
        let range = definition.playerRange
        if range.lowerBound == range.upperBound {
            return range.lowerBound == 1
                ? String(localized: "players.solo", defaultValue: "Solo")
                : String(format: String(localized: "players.exact", defaultValue: "%d players"),
                         range.lowerBound)
        }
        return String(format: String(localized: "players.range", defaultValue: "%d–%d players"),
                      range.lowerBound, range.upperBound)
    }
}

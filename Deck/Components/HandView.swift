import SwiftUI
import DeckCore

/// The player's own hand, fanned.
///
/// Spacing is computed from the card count and the space available, so a hand of
/// thirteen and a hand of three both fill the same rail and neither one runs off
/// the edge. Cards lift when chosen, tilt when dragged, and the neighbours move
/// aside — a hand should feel like something you are holding.
public struct HandView: View {
    private let cards: [VisibleCard]
    private let playable: Set<CardID>
    private let selected: Set<CardID>
    private let highlighted: Set<CardID>
    private let cardBackID: String
    private let isInteractive: Bool
    private let onTap: (CardID) -> Void
    private let onDrop: ((CardID, CGPoint) -> Void)?

    @Environment(\.deckReducedMotion) private var reducedMotion
    @State private var draggingCard: CardID?
    @State private var dragTranslation: CGSize = .zero
    @State private var hoveredIndex: Int?

    public init(cards: [VisibleCard],
                playable: Set<CardID> = [],
                selected: Set<CardID> = [],
                highlighted: Set<CardID> = [],
                cardBackID: String = "cardback.deck",
                isInteractive: Bool = true,
                onTap: @escaping (CardID) -> Void,
                onDrop: ((CardID, CGPoint) -> Void)? = nil) {
        self.cards = cards
        self.playable = playable
        self.selected = selected
        self.highlighted = highlighted
        self.cardBackID = cardBackID
        self.isInteractive = isInteractive
        self.onTap = onTap
        self.onDrop = onDrop
    }

    public var body: some View {
        GeometryReader { proxy in
            let layout = HandLayout(count: cards.count,
                                    available: proxy.size,
                                    maximumCardWidth: 118)
            ZStack {
                ForEach(Array(cards.enumerated()), id: \.element.id) { entry in
                    card(at: entry.offset, card: entry.element, layout: layout, box: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(String(localized: "hand.label", defaultValue: "Your hand")))
    }

    @ViewBuilder
    private func card(at index: Int, card: VisibleCard, layout: HandLayout, box: CGSize) -> some View {
        let isDragging = draggingCard == card.id
        let isSelected = selected.contains(card.id)
        let isPlayable = playable.contains(card.id)
        let neighbourShift = self.neighbourShift(for: index, layout: layout)

        CardView(card: card,
                 width: layout.cardWidth,
                 presentation: CardPresentation(isFaceUp: true,
                                                isSelected: isSelected,
                                                isPlayable: isPlayable && isInteractive,
                                                isDimmed: isInteractive && !playable.isEmpty && !isPlayable,
                                                isDragging: isDragging,
                                                isHighlighted: highlighted.contains(card.id),
                                                settleSeed: 0),
                 cardBackID: cardBackID)
            .rotationEffect(layout.angle(for: index), anchor: .bottom)
            .offset(x: layout.offsetX(for: index) + neighbourShift,
                    y: layout.offsetY(for: index))
            .offset(isDragging ? dragTranslation : .zero)
            .rotationEffect(isDragging ? .degrees(Double(dragTranslation.width) * 0.05) : .zero)
            .zIndex(isDragging ? 1000 : (isSelected ? Double(500 + index) : Double(index)))
            .position(x: box.width / 2, y: box.height - layout.cardHeight / 2)
            .allowsHitTesting(isInteractive)
            .onTapGesture {
                Haptics.shared.tap(isPlayable ? .pickUp : .light)
                onTap(card.id)
            }
            .gesture(dragGesture(for: card.id, layout: layout))
            .animation(DeckMotion.respectingReduceMotion(DeckMotion.cardSettle, reduced: reducedMotion),
                       value: cards.count)
            .animation(DeckMotion.respectingReduceMotion(DeckMotion.cardLift, reduced: reducedMotion),
                       value: hoveredIndex)
    }

    /// Neighbouring cards ease away from the one being handled, which is what
    /// makes the fan feel like paper rather than a row of buttons.
    private func neighbourShift(for index: Int, layout: HandLayout) -> CGFloat {
        guard let hovered = hoveredIndex, hovered != index else { return 0 }
        let distance = index - hovered
        guard abs(distance) <= 2 else { return 0 }
        let magnitude = layout.cardWidth * 0.16 / CGFloat(abs(distance))
        return distance > 0 ? magnitude : -magnitude
    }

    private func dragGesture(for id: CardID, layout: HandLayout) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard isInteractive, onDrop != nil else { return }
                if draggingCard == nil {
                    draggingCard = id
                    hoveredIndex = cards.firstIndex { $0.id == id }
                    Haptics.shared.tap(.pickUp)
                }
                dragTranslation = value.translation
            }
            .onEnded { value in
                guard let dragged = draggingCard else { return }
                draggingCard = nil
                hoveredIndex = nil
                let landing = value.location
                withAnimation(DeckMotion.respectingReduceMotion(DeckMotion.cardReturn,
                                                                reduced: reducedMotion)) {
                    dragTranslation = .zero
                }
                onDrop?(dragged, landing)
            }
    }
}

/// Works out how to fan a hand.
///
/// The rule is simple and it is what stops a big hand becoming unreadable: give
/// every card as much room as it can have, then take room away — first by
/// overlapping, then by shrinking — until the whole hand fits.
public struct HandLayout {
    public let count: Int
    public let cardWidth: CGFloat
    public let cardHeight: CGFloat
    /// Distance between the left edges of neighbouring cards.
    public let step: CGFloat
    /// Total angle the fan sweeps through.
    public let sweep: Double
    /// How far the middle of the fan sits above its ends.
    public let arc: CGFloat

    public init(count: Int, available: CGSize, maximumCardWidth: CGFloat = 118) {
        self.count = count
        guard count > 0 else {
            cardWidth = maximumCardWidth
            cardHeight = CardMetrics.height(forWidth: maximumCardWidth)
            step = 0
            sweep = 0
            arc = 0
            return
        }

        // Start from the biggest card that fits the rail's height.
        let heightLimited = CardMetrics.width(forHeight: available.height * 0.86)
        var width = min(maximumCardWidth, max(44, heightLimited))

        // Overlap as far as is still readable — a card must show its index.
        let minimumStepRatio: CGFloat = 0.24
        let comfortableStepRatio: CGFloat = 1 - CardMetrics.fanOverlap
        let usable = max(1, available.width - DeckSpace.m * 2)

        var stepValue = width * comfortableStepRatio
        if CGFloat(count - 1) * stepValue + width > usable {
            stepValue = (usable - width) / CGFloat(max(1, count - 1))
        }
        if stepValue < width * minimumStepRatio {
            // Still too wide: shrink the cards rather than hide their indices.
            let scale = max(0.55, (usable / (CGFloat(count - 1) * minimumStepRatio + 1)) / width)
            width *= scale
            stepValue = max(width * minimumStepRatio, (usable - width) / CGFloat(max(1, count - 1)))
        }

        cardWidth = width
        cardHeight = CardMetrics.height(forWidth: width)
        step = stepValue
        // A wider hand fans further, but never past a comfortable wrist angle.
        sweep = min(26, Double(count) * 2.2)
        arc = min(width * 0.28, CGFloat(count) * 1.6)
    }

    public var totalWidth: CGFloat {
        count <= 1 ? cardWidth : CGFloat(count - 1) * step + cardWidth
    }

    public func offsetX(for index: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        let centred = CGFloat(index) - CGFloat(count - 1) / 2
        return centred * step
    }

    /// Cards nearer the middle sit higher, following the arc of a real fan.
    public func offsetY(for index: Int) -> CGFloat {
        guard count > 2 else { return 0 }
        let position = Double(index) / Double(count - 1)   // 0…1
        let curve = 1 - pow((position - 0.5) * 2, 2)       // 0 at the ends, 1 in the middle
        return -arc * CGFloat(curve)
    }

    public func angle(for index: Int) -> Angle {
        guard count > 1 else { return .zero }
        let position = Double(index) / Double(count - 1) - 0.5
        return .degrees(position * sweep)
    }
}

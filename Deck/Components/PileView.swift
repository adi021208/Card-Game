import SwiftUI
import DeckCore

/// One pile on the table, drawn according to the style the game asked for.
///
/// Every pile in every game goes through here: stock, discard, tricks, the
/// board, a solitaire column, an opponent's hand. The game says *what* the pile
/// is; this decides what that looks like.
public struct PileView: View {
    private let slot: TableSlot
    private let cards: [VisibleCard]
    private let cardWidth: CGFloat
    private let faceUp: Set<CardID>
    private let playable: Set<CardID>
    private let selected: Set<CardID>
    private let highlighted: Set<CardID>
    private let cardBackID: String
    private let onTapCard: ((CardID) -> Void)?
    private let onTapEmpty: (() -> Void)?

    @Environment(\.deckTheme) private var theme
    @Environment(\.deckReducedMotion) private var reducedMotion

    public init(slot: TableSlot,
                cards: [VisibleCard],
                cardWidth: CGFloat,
                faceUp: Set<CardID>,
                playable: Set<CardID> = [],
                selected: Set<CardID> = [],
                highlighted: Set<CardID> = [],
                cardBackID: String = "cardback.deck",
                onTapCard: ((CardID) -> Void)? = nil,
                onTapEmpty: (() -> Void)? = nil) {
        self.slot = slot
        self.cards = cards
        self.cardWidth = cardWidth
        self.faceUp = faceUp
        self.playable = playable
        self.selected = selected
        self.highlighted = highlighted
        self.cardBackID = cardBackID
        self.onTapCard = onTapCard
        self.onTapEmpty = onTapEmpty
    }

    private var cardHeight: CGFloat { CardMetrics.height(forWidth: cardWidth) }

    public var body: some View {
        Group {
            if cards.isEmpty {
                emptySlot
            } else {
                contents
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(pileLabel))
    }

    // MARK: - Empty

    /// An empty pile is a drawn slot, not a dashed rectangle: a keyline with a
    /// faint device inside it, so the table still reads as a table.
    private var emptySlot: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CardMetrics.corner(forWidth: cardWidth), style: .continuous)
                .strokeBorder(theme.onGround.opacity(0.28),
                              style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            if let hint = slot.emptyHintKey {
                Text(LocalizedStringKey(hint))
                    .font(DeckType.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.onGroundMuted)
                    .padding(DeckSpace.xxs)
                    .minimumScaleFactor(0.6)
            } else if slot.zone.kind == .foundation {
                DeckGlyph(fan: 0.3)
                    .fill(theme.onGround.opacity(0.16))
                    .frame(width: cardWidth * 0.4)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .contentShape(Rectangle())
        .onTapGesture { onTapEmpty?() }
    }

    // MARK: - Contents

    @ViewBuilder
    private var contents: some View {
        switch slot.style {
        case .stack:
            stackView
        case .single:
            singleView
        case let .row(overlap):
            rowView(overlap: overlap)
        case .cascade:
            cascadeView
        case .fan:
            fanView(scale: 1)
        case .opponentFan:
            fanView(scale: 0.72)
        }
    }

    /// A stack shows its depth: a few edges behind the top card, no more.
    private var stackView: some View {
        let visibleDepth = min(4, cards.count)
        return ZStack {
            ForEach(0..<visibleDepth, id: \.self) { index in
                let isTop = index == visibleDepth - 1
                let card = cards[cards.count - visibleDepth + index]
                cardView(card,
                         settleSeed: card.id.rawValue &+ index,
                         interactive: isTop)
                    .offset(x: CGFloat(index) * 0.9, y: CGFloat(-index) * 1.1)
            }
        }
        .overlay(alignment: .bottomTrailing) { countBadge }
    }

    private var singleView: some View {
        Group {
            if let card = cards.last {
                cardView(card, settleSeed: 0, interactive: true)
            }
        }
    }

    private func rowView(overlap: Double) -> some View {
        let step = cardWidth * CGFloat(1 - overlap)
        return HStack(spacing: 0) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { entry in
                cardView(entry.element,
                         settleSeed: entry.element.id.rawValue,
                         interactive: true)
                    .zIndex(Double(entry.offset))
                    .padding(.leading, entry.offset == 0 ? 0 : step - cardWidth)
            }
        }
    }

    /// Solitaire columns: face-down cards are packed tight because there is
    /// nothing to read, face-up ones open out so their indices show.
    private var cascadeView: some View {
        ZStack(alignment: .top) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { entry in
                cardView(entry.element,
                         settleSeed: 0,
                         interactive: true)
                    .offset(y: cascadeOffset(upTo: entry.offset))
                    .zIndex(Double(entry.offset))
            }
        }
    }

    private func cascadeOffset(upTo index: Int) -> CGFloat {
        var offset: CGFloat = 0
        for position in 0..<index {
            let isUp = faceUp.contains(cards[position].id)
            offset += cardHeight * (isUp ? CardMetrics.cascadeOverlap
                                         : CardMetrics.cascadeOverlapFaceDown)
        }
        return offset
    }

    private func fanView(scale: CGFloat) -> some View {
        let width = cardWidth * scale
        let step = width * 0.34
        return ZStack {
            ForEach(Array(cards.enumerated()), id: \.element.id) { entry in
                let centred = CGFloat(entry.offset) - CGFloat(cards.count - 1) / 2
                CardView(card: entry.element,
                         width: width,
                         presentation: presentation(for: entry.element, settleSeed: 0),
                         cardBackID: cardBackID)
                    .rotationEffect(.degrees(Double(centred) * 4), anchor: .bottom)
                    .offset(x: centred * step, y: abs(centred) * 1.5)
                    .zIndex(Double(entry.offset))
            }
        }
        .frame(width: width + step * CGFloat(max(0, cards.count - 1)),
               height: CardMetrics.height(forWidth: width))
    }

    // MARK: - Pieces

    private func cardView(_ card: VisibleCard, settleSeed: Int, interactive: Bool) -> some View {
        CardView(card: card,
                 width: cardWidth,
                 presentation: presentation(for: card, settleSeed: settleSeed),
                 cardBackID: cardBackID)
            .contentShape(Rectangle())
            .onTapGesture {
                guard interactive else { return }
                Haptics.shared.tap(playable.contains(card.id) ? .pickUp : .light)
                onTapCard?(card.id)
            }
            .animation(DeckMotion.respectingReduceMotion(DeckMotion.cardSettle, reduced: reducedMotion),
                       value: cards.count)
    }

    private func presentation(for card: VisibleCard, settleSeed: Int) -> CardPresentation {
        CardPresentation(isFaceUp: faceUp.contains(card.id) || card.isKnown,
                         isSelected: selected.contains(card.id),
                         isPlayable: playable.contains(card.id),
                         isDimmed: false,
                         isDragging: false,
                         isHighlighted: highlighted.contains(card.id),
                         settleSeed: settleSeed)
    }

    /// A pile deeper than four cards says how deep it is, because the drawn
    /// edges stop being countable.
    @ViewBuilder
    private var countBadge: some View {
        if cards.count > 4 {
            Text("\(cards.count)")
                .font(DeckType.tabular(11, weight: .heavy))
                .foregroundStyle(DeckPalette.cream)
                .padding(.horizontal, DeckSpace.xxs + 2)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: DeckRadius.tight, style: .continuous)
                        .fill(DeckPalette.ink.opacity(0.82))
                )
                .offset(x: 6, y: 6)
                .accessibilityHidden(true)
        }
    }

    private var pileLabel: String {
        let known = cards.filter(\.isKnown).count
        let base: String
        if let title = slot.titleKey {
            base = String.deck(title, or: slot.zone.kind.rawValue)
        } else {
            base = slot.zone.kind.rawValue
        }
        if cards.isEmpty {
            return String(format: String(localized: "pile.empty", defaultValue: "%@, empty"), base)
        }
        if known == 0 {
            return String(format: String(localized: "pile.faceDown",
                                         defaultValue: "%@, %d face-down cards"),
                          base, cards.count)
        }
        return String(format: String(localized: "pile.count", defaultValue: "%@, %d cards"),
                      base, cards.count)
    }
}

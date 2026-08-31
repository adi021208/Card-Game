import SwiftUI
import DeckCore

/// Draws a table.
///
/// It takes a `TablePresentation` — already redacted for the viewer — and lays
/// out whatever slots the game declared. There is no game-specific code in here
/// at all: Klondike gets a grid because it asked for `.grid` anchors, Hearts
/// gets a table because it asked for `.ownHand` and `.opponent`, and a
/// sixteenth game would get whichever it asked for without this file changing.
public struct TableSurface: View {
    private let presentation: TablePresentation
    private let selection: [CardID]
    private let highlighted: Set<CardID>
    private let cardBackID: String
    private let isInteractive: Bool
    private let onTapCard: (CardID) -> Void
    private let onTapZone: (Zone) -> Void

    @Environment(\.deckTheme) private var theme

    public init(presentation: TablePresentation,
                selection: [CardID] = [],
                highlighted: Set<CardID> = [],
                cardBackID: String = "cardback.deck",
                isInteractive: Bool = true,
                onTapCard: @escaping (CardID) -> Void,
                onTapZone: @escaping (Zone) -> Void) {
        self.presentation = presentation
        self.selection = selection
        self.highlighted = highlighted
        self.cardBackID = cardBackID
        self.isInteractive = isInteractive
        self.onTapCard = onTapCard
        self.onTapZone = onTapZone
    }

    /// A game that lays its slots out on a grid is a board, not a table.
    private var isBoardLayout: Bool {
        presentation.slots.contains { if case .grid = $0.anchor { return true }; return false }
    }

    public var body: some View {
        GeometryReader { proxy in
            if isBoardLayout {
                boardLayout(in: proxy.size)
            } else {
                tableLayout(in: proxy.size)
            }
        }
    }

    // MARK: - Table layout

    private func tableLayout(in box: CGSize) -> some View {
        let ownSlot = presentation.slots.first { if case .ownHand = $0.anchor { return true }; return false }
        let opponents = presentation.slots
            .compactMap { slot -> (offset: Int, slot: TableSlot)? in
                if case let .opponent(offset) = slot.anchor { return (offset, slot) }
                return nil
            }
            .sorted { $0.offset < $1.offset }
        let centre = presentation.slots
            .compactMap { slot -> (order: Int, slot: TableSlot)? in
                if case let .centre(order) = slot.anchor { return (order, slot) }
                return nil
            }
            .sorted { $0.order < $1.order }
        let corners = presentation.slots.compactMap { slot -> (SlotAnchor.Corner, TableSlot)? in
            if case let .corner(corner) = slot.anchor { return (corner, slot) }
            return nil
        }

        // The hand rail takes a fixed share of the height; the table gets the
        // rest. On a short screen the rail shrinks before the table does,
        // because an unreadable table is worse than a tight hand.
        let railHeight = min(box.height * 0.32, 190)
        let tableHeight = box.height - railHeight
        let centreCardWidth = min(box.width / CGFloat(max(3, centre.count + 2)), 96)
        let opponentCardWidth = min(60, box.width / CGFloat(max(4, opponents.count * 2)))

        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Opponents around the far edge.
                HStack(alignment: .top, spacing: DeckSpace.m) {
                    ForEach(opponents, id: \.slot.zone) { entry in
                        opponentColumn(slot: entry.slot, cardWidth: opponentCardWidth)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DeckSpace.xs)

                Spacer(minLength: DeckSpace.s)

                // The middle of the table.
                HStack(alignment: .center, spacing: DeckSpace.m) {
                    ForEach(centre, id: \.slot.zone) { entry in
                        pile(entry.slot, cardWidth: centreCardWidth * CGFloat(entry.slot.prominence))
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: DeckSpace.s)
            }
            .frame(height: tableHeight)

            // Corner piles sit over the table rather than in the flow.
            ForEach(Array(corners.enumerated()), id: \.offset) { entry in
                pile(entry.element.1, cardWidth: centreCardWidth * 0.8)
                    .frame(maxWidth: .infinity, maxHeight: tableHeight,
                           alignment: alignment(for: entry.element.0))
                    .padding(DeckSpace.m)
            }

            // The player's own hand.
            VStack {
                Spacer(minLength: 0)
                if let ownSlot {
                    HandView(cards: presentation.board.contents(of: ownSlot.zone),
                             playable: presentation.playableCards,
                             selected: Set(selection),
                             highlighted: highlighted,
                             cardBackID: cardBackID,
                             isInteractive: isInteractive,
                             onTap: onTapCard)
                        .frame(height: railHeight)
                }
            }
        }
    }

    private func opponentColumn(slot: TableSlot, cardWidth: CGFloat) -> some View {
        let seat = presentation.seats.first { $0.seat == slot.zone.owner }
        return VStack(spacing: DeckSpace.xxs) {
            if let seat {
                SeatBadge(status: seat, isCompact: true)
            }
            PileView(slot: slot,
                     cards: presentation.board.contents(of: slot.zone),
                     cardWidth: cardWidth,
                     faceUp: presentation.board.faceUp,
                     cardBackID: cardBackID)
        }
    }

    // MARK: - Board layout

    /// Solitaire and anything else that declares a grid.
    private func boardLayout(in box: CGSize) -> some View {
        let grids = presentation.slots.compactMap { slot -> (row: Int, column: Int, slot: TableSlot)? in
            if case let .grid(row, column) = slot.anchor { return (row, column, slot) }
            return nil
        }
        let corners = presentation.slots.compactMap { slot -> (SlotAnchor.Corner, TableSlot)? in
            if case let .corner(corner) = slot.anchor { return (corner, slot) }
            return nil
        }
        let rows = Dictionary(grouping: grids, by: \.row)
        let widestRow = rows.values.map(\.count).max() ?? 1
        let gutter = DeckSpace.xs
        let available = box.width - DeckSpace.page * 2 - gutter * CGFloat(widestRow - 1)
        let cardWidth = max(38, available / CGFloat(widestRow))

        return VStack(alignment: .leading, spacing: DeckSpace.m) {
            ForEach(rows.keys.sorted(), id: \.self) { row in
                HStack(alignment: .top, spacing: gutter) {
                    ForEach((rows[row] ?? []).sorted { $0.column < $1.column }, id: \.slot.zone) { entry in
                        pile(entry.slot, cardWidth: cardWidth)
                    }
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DeckSpace.page)
        .padding(.top, DeckSpace.s)
        .overlay(alignment: .topTrailing) {
            ForEach(Array(corners.enumerated()), id: \.offset) { entry in
                pile(entry.element.1, cardWidth: cardWidth * 0.9)
                    .padding(DeckSpace.page)
            }
        }
    }

    // MARK: - Pieces

    private func pile(_ slot: TableSlot, cardWidth: CGFloat) -> some View {
        VStack(spacing: DeckSpace.xxs) {
            if let title = slot.titleKey {
                Text(LocalizedStringKey(title))
                    .font(DeckType.unit)
                    .tracking(DeckType.unitTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.onGroundMuted)
            }
            PileView(slot: slot,
                     cards: presentation.board.contents(of: slot.zone),
                     cardWidth: cardWidth,
                     faceUp: presentation.board.faceUp,
                     playable: presentation.playableCards,
                     selected: Set(selection),
                     highlighted: highlighted,
                     cardBackID: cardBackID,
                     onTapCard: isInteractive ? onTapCard : nil,
                     onTapEmpty: isInteractive && slot.acceptsDrop ? { onTapZone(slot.zone) } : nil)
        }
    }

    private func alignment(for corner: SlotAnchor.Corner) -> Alignment {
        switch corner {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
}

/// A player around the table: who they are, what they have, whether it is their
/// turn. The active player is marked with a painted underline, not a glow.
public struct SeatBadge: View {
    private let status: SeatStatus
    private let isCompact: Bool

    @Environment(\.deckTheme) private var theme

    public init(status: SeatStatus, isCompact: Bool = false) {
        self.status = status
        self.isCompact = isCompact
    }

    public var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: DeckSpace.xxs) {
                AvatarArt(avatarID: status.avatarID,
                          initials: String(status.displayName.prefix(1)).uppercased(),
                          size: isCompact ? 26 : 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(status.displayName)
                        .font(.system(size: isCompact ? 12 : 14, weight: .bold))
                        .foregroundStyle(theme.onGround)
                        .lineLimit(1)
                    HStack(spacing: DeckSpace.xxs) {
                        if let score = status.score {
                            Text("\(score)")
                                .font(DeckType.tabular(isCompact ? 11 : 13, weight: .heavy))
                                .foregroundStyle(theme.onGround)
                        }
                        if let wager = status.wager, wager > 0 {
                            Text("+\(wager)")
                                .font(DeckType.tabular(isCompact ? 10 : 12))
                                .foregroundStyle(theme.accent)
                        }
                        if let stateKey = status.stateKey {
                            Text(LocalizedStringKey(stateKey))
                                .font(.system(size: isCompact ? 10 : 11, weight: .semibold))
                                .foregroundStyle(theme.onGroundMuted)
                        }
                    }
                }
            }
            // The active player gets a painted rule, which reads without colour
            // and survives being seen out of the corner of an eye.
            PaintStroke(bow: 0.02, weight: 0.5, seed: status.seat.rawValue &+ 40)
                .fill(theme.accent)
                .frame(height: 5)
                .opacity(status.isActive ? 1 : 0)
        }
        .padding(.horizontal, DeckSpace.xs)
        .padding(.vertical, DeckSpace.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        var parts = [status.displayName]
        if let score = status.score { parts.append("\(score)") }
        parts.append(String(format: String(localized: "seat.cardCount", defaultValue: "%d cards"),
                            status.cardCount))
        if status.isActive {
            parts.append(String(localized: "seat.toPlay", defaultValue: "to play"))
        }
        if status.isDealer {
            parts.append(String(localized: "seat.dealer", defaultValue: "dealer"))
        }
        return parts.joined(separator: ", ")
    }
}

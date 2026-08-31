import SwiftUI
import DeckCore

/// The face of a card.
///
/// Drawn rather than composed from images: corner indices, a pip layout for the
/// numbers, and a stencil device for the court cards. The pip arrangement is the
/// traditional one, because a five of clubs that does not look like a five of
/// clubs is a card nobody can read at a glance.
public struct CardFaceArt: View {
    private let card: Card
    private let width: CGFloat
    private let theme: DeckTheme

    public init(card: Card, width: CGFloat, theme: DeckTheme) {
        self.card = card
        self.width = width
        self.theme = theme
    }

    private var height: CGFloat { CardMetrics.height(forWidth: width) }
    private var ink: Color {
        card.isRed ? DeckPalette.vermilion : DeckPalette.ink
    }
    private var suitKind: SuitShape.Kind? {
        guard let suit = card.suit else { return nil }
        return SuitShape.Kind(suitToken: suit.token)
    }

    public var body: some View {
        ZStack {
            DeckPalette.chalk

            if card.isJoker {
                jokerFace
            } else {
                centreArt
                corners
            }
        }
        .overlay(PaperGrain(intensity: 0.07, seed: card.id.rawValue, tint: .black))
        .accessibilityHidden(true)
    }

    // MARK: - Corners

    private var corners: some View {
        let indexWidth = width * 0.22
        return ZStack {
            VStack {
                HStack {
                    cornerIndex
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            VStack {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    cornerIndex.rotationEffect(.degrees(180))
                }
            }
        }
        .padding(width * 0.055)
        .frame(width: width, height: height)
        .environment(\.deckCornerWidth, indexWidth)
    }

    private var cornerIndex: some View {
        VStack(spacing: width * 0.008) {
            Text(card.rank?.pipLabel ?? "")
                .font(DeckType.pip(width * 0.245))
                .foregroundStyle(ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let suitKind {
                SuitShape(suitKind)
                    .fill(ink)
                    .frame(width: width * 0.135, height: width * 0.135)
            }
        }
        .fixedSize()
    }

    // MARK: - Centre

    @ViewBuilder
    private var centreArt: some View {
        if let rank = card.rank, let suitKind {
            if rank.isFaceCard {
                courtDevice(rank: rank, suit: suitKind)
            } else if rank == .ace {
                SuitMark(suitKind,
                         colour: ink,
                         offsetColour: card.isRed ? DeckPalette.coral.opacity(0.5)
                                                  : DeckPalette.cobalt.opacity(0.35),
                         wobble: 0.014,
                         seed: card.id.rawValue)
                    .frame(width: width * 0.56, height: width * 0.56)
            } else {
                pipLayout(rank: rank, suit: suitKind)
            }
        }
    }

    /// The traditional pip arrangement, laid out on the card's own grid.
    private func pipLayout(rank: Rank, suit: SuitShape.Kind) -> some View {
        let pipSize = width * 0.18
        // Columns are at 27%, 50% and 73% of the width; rows step evenly.
        let positions = Self.pipPositions(for: rank.rawValue)
        return GeometryReader { proxy in
            ForEach(Array(positions.enumerated()), id: \.offset) { entry in
                SuitShape(suit)
                    .fill(ink)
                    .frame(width: pipSize, height: pipSize)
                    .rotationEffect(.degrees(entry.element.y > 0.5 ? 180 : 0))
                    .position(x: proxy.size.width * entry.element.x,
                              y: proxy.size.height * entry.element.y)
            }
        }
        .padding(.horizontal, width * 0.16)
        .padding(.vertical, width * 0.2)
    }

    /// Court cards get a stencil device rather than a drawn figure: a stacked
    /// monogram over an oversized suit, which stays legible at hand size where a
    /// full illustration turns to mud.
    private func courtDevice(rank: Rank, suit: SuitShape.Kind) -> some View {
        ZStack {
            SuitShape(suit, wobble: 0.02, seed: card.id.rawValue)
                .fill(ink.opacity(0.14))
                .frame(width: width * 0.72, height: width * 0.72)
            RoundedRectangle(cornerRadius: width * 0.04, style: .continuous)
                .stroke(ink.opacity(0.5), lineWidth: max(1, width * 0.016))
                .frame(width: width * 0.52, height: height * 0.46)
            VStack(spacing: -width * 0.03) {
                Text(rank.token)
                    .font(DeckType.display(width * 0.46))
                    .foregroundStyle(ink)
                SuitShape(suit)
                    .fill(ink)
                    .frame(width: width * 0.18, height: width * 0.18)
            }
        }
    }

    private var jokerFace: some View {
        VStack(spacing: width * 0.04) {
            DeckGlyph(fan: 1)
                .fill(card.isRed ? DeckPalette.vermilion : DeckPalette.ink)
                .frame(width: width * 0.5, height: width * 0.5)
            Text("JOKER")
                .font(DeckType.display(width * 0.2))
                .tracking(-width * 0.006)
                .foregroundStyle(card.isRed ? DeckPalette.vermilion : DeckPalette.ink)
        }
    }

    // MARK: - Pip geometry

    /// Unit positions for the pips on a number card, in the traditional layout.
    static func pipPositions(for rank: Int) -> [CGPoint] {
        let left: CGFloat = 0.0
        let centre: CGFloat = 0.5
        let right: CGFloat = 1.0
        switch rank {
        case 2:
            return [CGPoint(x: centre, y: 0), CGPoint(x: centre, y: 1)]
        case 3:
            return [CGPoint(x: centre, y: 0), CGPoint(x: centre, y: 0.5), CGPoint(x: centre, y: 1)]
        case 4:
            return [CGPoint(x: left, y: 0), CGPoint(x: right, y: 0),
                    CGPoint(x: left, y: 1), CGPoint(x: right, y: 1)]
        case 5:
            return [CGPoint(x: left, y: 0), CGPoint(x: right, y: 0),
                    CGPoint(x: centre, y: 0.5),
                    CGPoint(x: left, y: 1), CGPoint(x: right, y: 1)]
        case 6:
            return [CGPoint(x: left, y: 0), CGPoint(x: right, y: 0),
                    CGPoint(x: left, y: 0.5), CGPoint(x: right, y: 0.5),
                    CGPoint(x: left, y: 1), CGPoint(x: right, y: 1)]
        case 7:
            return [CGPoint(x: left, y: 0), CGPoint(x: right, y: 0),
                    CGPoint(x: centre, y: 0.25),
                    CGPoint(x: left, y: 0.5), CGPoint(x: right, y: 0.5),
                    CGPoint(x: left, y: 1), CGPoint(x: right, y: 1)]
        case 8:
            return [CGPoint(x: left, y: 0), CGPoint(x: right, y: 0),
                    CGPoint(x: centre, y: 0.25),
                    CGPoint(x: left, y: 0.5), CGPoint(x: right, y: 0.5),
                    CGPoint(x: centre, y: 0.75),
                    CGPoint(x: left, y: 1), CGPoint(x: right, y: 1)]
        case 9:
            return [CGPoint(x: left, y: 0), CGPoint(x: right, y: 0),
                    CGPoint(x: left, y: 0.333), CGPoint(x: right, y: 0.333),
                    CGPoint(x: centre, y: 0.5),
                    CGPoint(x: left, y: 0.667), CGPoint(x: right, y: 0.667),
                    CGPoint(x: left, y: 1), CGPoint(x: right, y: 1)]
        case 10:
            return [CGPoint(x: left, y: 0), CGPoint(x: right, y: 0),
                    CGPoint(x: centre, y: 0.167),
                    CGPoint(x: left, y: 0.333), CGPoint(x: right, y: 0.333),
                    CGPoint(x: left, y: 0.667), CGPoint(x: right, y: 0.667),
                    CGPoint(x: centre, y: 0.833),
                    CGPoint(x: left, y: 1), CGPoint(x: right, y: 1)]
        default:
            return [CGPoint(x: centre, y: 0.5)]
        }
    }
}

private struct DeckCornerWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 20
}

extension EnvironmentValues {
    var deckCornerWidth: CGFloat {
        get { self[DeckCornerWidthKey.self] }
        set { self[DeckCornerWidthKey.self] = newValue }
    }
}

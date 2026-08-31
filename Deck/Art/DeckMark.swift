import SwiftUI

/// The DECK glyph: three cards fanned out of a stack, cut as a single stencil.
///
/// It works at sixteen points on a tab bar and at three hundred on a launch
/// screen, which is the whole reason it is a silhouette rather than an
/// illustration.
public struct DeckGlyph: Shape {
    /// How far the fan opens, 0 is a closed stack.
    public var fan: CGFloat

    public init(fan: CGFloat = 1) {
        self.fan = fan
    }

    public var animatableData: CGFloat {
        get { fan }
        set { fan = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let cardWidth = side * 0.42
        let cardHeight = cardWidth / CardMetrics.aspectRatio
        let corner = cardWidth * CardMetrics.cornerRatio * 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()

        // Three cards: two fanned out behind, one square on top.
        let angles: [CGFloat] = [-22 * fan, 22 * fan, 0]
        let offsets: [CGSize] = [
            CGSize(width: -side * 0.11 * fan, height: side * 0.02),
            CGSize(width: side * 0.11 * fan, height: side * 0.02),
            .zero
        ]
        for index in 0..<3 {
            let card = CGRect(x: -cardWidth / 2, y: -cardHeight / 2,
                              width: cardWidth, height: cardHeight)
            var cardPath = Path(roundedRect: card, cornerRadius: corner)
            let transform = CGAffineTransform.identity
                .translatedBy(x: centre.x + offsets[index].width,
                              y: centre.y + offsets[index].height)
                .rotated(by: angles[index] * .pi / 180)
            cardPath = cardPath.applying(transform)
            path.addPath(cardPath)
        }
        return path
    }
}

/// The wordmark.
///
/// DECK set in the heaviest, narrowest system face with the letters tracked
/// almost into each other, printed twice a hair out of register.
public struct DeckWordmark: View {
    private let size: CGFloat
    private let colour: Color
    private let ghost: Color?

    public init(size: CGFloat = 48, colour: Color, ghost: Color? = nil) {
        self.size = size
        self.colour = colour
        self.ghost = ghost
    }

    public var body: some View {
        Misregistered(offset: CGSize(width: size * 0.045, height: size * 0.035),
                      ghost: ghost ?? colour.opacity(0.0)) {
            Text("DECK")
                .font(DeckType.display(size))
                .tracking(-size * 0.055)
                .foregroundStyle(colour)
        }
        .accessibilityElement()
        .accessibilityLabel("DECK")
    }
}

/// The full lockup: the glyph, the wordmark and the line.
public struct DeckLockup: View {
    private let scale: CGFloat
    private let colour: Color
    private let accent: Color
    private let showsTagline: Bool

    public init(scale: CGFloat = 1, colour: Color, accent: Color, showsTagline: Bool = true) {
        self.scale = scale
        self.colour = colour
        self.accent = accent
        self.showsTagline = showsTagline
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DeckSpace.xs * scale) {
            HStack(alignment: .center, spacing: DeckSpace.s * scale) {
                DeckGlyph()
                    .fill(accent)
                    .frame(width: 44 * scale, height: 44 * scale)
                DeckWordmark(size: 52 * scale, colour: colour, ghost: accent.opacity(0.85))
            }
            if showsTagline {
                Text("ONE DECK. EVERY GAME.")
                    .font(DeckType.unit)
                    .tracking(DeckType.unitTracking * scale)
                    .foregroundStyle(colour.opacity(0.75))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("DECK. One deck, every game.")
    }
}

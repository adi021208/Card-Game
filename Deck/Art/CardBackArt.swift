import SwiftUI

/// The back of a card.
///
/// Every back in the collection is generated from the same three ingredients —
/// a ground, a border rule, and a device — so a player's chosen back always
/// still reads as a DECK card rather than as a skin bolted on top.
public struct CardBackArt: View {
    private let styleID: String
    private let theme: DeckTheme

    public init(styleID: String, theme: DeckTheme) {
        self.styleID = styleID
        self.theme = theme
    }

    private struct Recipe {
        var ground: Color
        var device: Color
        var accent: Color
        var pattern: Pattern
        var seed: Int
    }

    private enum Pattern {
        /// The house back: the glyph in a ruled frame.
        case houseMark
        /// A sprayed field behind the glyph.
        case spray
        /// A halftone gradient with a suit stencil.
        case halftone(SuitShape.Kind)
        /// A tight diagonal lattice.
        case lattice
        /// Two-colour misregistered rules.
        case press
        /// Concentric stamp rings.
        case stamp
    }

    private var recipe: Recipe {
        switch styleID {
        case "cardback.spray":
            return Recipe(ground: DeckPalette.cream, device: DeckPalette.vermilion,
                          accent: DeckPalette.ink, pattern: .spray, seed: 21)
        case "cardback.moon":
            return Recipe(ground: DeckPalette.ink, device: DeckPalette.acid,
                          accent: DeckPalette.cream, pattern: .halftone(.heart), seed: 34)
        case "cardback.royal":
            return Recipe(ground: DeckPalette.crimson, device: DeckPalette.acid,
                          accent: DeckPalette.cream, pattern: .stamp, seed: 55)
        case "cardback.stencil":
            return Recipe(ground: DeckPalette.ink, device: DeckPalette.cobalt,
                          accent: DeckPalette.cream, pattern: .halftone(.spade), seed: 13)
        case "cardback.archive":
            return Recipe(ground: DeckPalette.cream, device: DeckPalette.ink,
                          accent: DeckPalette.crimson, pattern: .lattice, seed: 8)
        case "cardback.web":
            return Recipe(ground: DeckPalette.forest, device: DeckPalette.cream,
                          accent: DeckPalette.acid, pattern: .lattice, seed: 88)
        case "cardback.speed", "cardback.motion":
            return Recipe(ground: DeckPalette.orange, device: DeckPalette.ink,
                          accent: DeckPalette.cream, pattern: .press, seed: 61)
        case "cardback.streak":
            return Recipe(ground: DeckPalette.vermilion, device: DeckPalette.acid,
                          accent: DeckPalette.ink, pattern: .spray, seed: 30)
        case "cardback.gold":
            return Recipe(ground: DeckPalette.acid, device: DeckPalette.ink,
                          accent: DeckPalette.vermilion, pattern: .stamp, seed: 50)
        case "cardback.table":
            return Recipe(ground: DeckPalette.coral, device: DeckPalette.cream,
                          accent: DeckPalette.ink, pattern: .houseMark, seed: 10)
        case "cardback.library":
            return Recipe(ground: DeckPalette.cobalt, device: DeckPalette.cream,
                          accent: DeckPalette.vermilion, pattern: .lattice, seed: 15)
        case "cardback.press":
            return Recipe(ground: DeckPalette.cream, device: DeckPalette.cobalt,
                          accent: DeckPalette.vermilion, pattern: .press, seed: 77)
        default:
            return Recipe(ground: theme.isDark ? DeckPalette.ink : DeckPalette.inkSoft,
                          device: theme.accent,
                          accent: DeckPalette.cream,
                          pattern: .houseMark, seed: 1)
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let inset = min(size.width, size.height) * 0.075
            let recipe = self.recipe
            ZStack {
                recipe.ground

                pattern(recipe: recipe, size: size, inset: inset)

                // Every back has the same ruled frame, which is what keeps the
                // set coherent.
                RoundedRectangle(cornerRadius: CardMetrics.corner(forWidth: size.width) * 0.6)
                    .stroke(recipe.accent.opacity(0.85), lineWidth: max(1, size.width * 0.022))
                    .padding(inset * 0.7)
            }
            .overlay(PaperGrain(intensity: 0.13, seed: recipe.seed, tint: .black))
            .clipShape(RoundedRectangle(cornerRadius: CardMetrics.corner(forWidth: size.width),
                                        style: .continuous))
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func pattern(recipe: Recipe, size: CGSize, inset: CGFloat) -> some View {
        switch recipe.pattern {
        case .houseMark:
            DeckGlyph()
                .fill(recipe.device)
                .frame(width: size.width * 0.52)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .spray:
            ZStack {
                SprayMark(colour: recipe.device, seed: recipe.seed, density: 0.9, spread: 0.35, drips: 1)
                    .frame(width: size.width * 0.9, height: size.height * 0.7)
                DeckGlyph(fan: 0.6)
                    .fill(recipe.accent.opacity(0.92))
                    .frame(width: size.width * 0.4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .halftone(suit):
            ZStack {
                HalftoneField(colour: recipe.device.opacity(0.55),
                              cell: max(5, size.width * 0.075),
                              direction: .topLeading)
                SuitShape(suit, wobble: 0.01, seed: recipe.seed)
                    .fill(recipe.device)
                    .frame(width: size.width * 0.46, height: size.width * 0.46)
            }

        case .lattice:
            Canvas { context, canvasSize in
                let step = max(6, canvasSize.width * 0.13)
                var path = Path()
                var x = -canvasSize.height
                while x < canvasSize.width + canvasSize.height {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + canvasSize.height, y: canvasSize.height))
                    path.move(to: CGPoint(x: x + canvasSize.height, y: 0))
                    path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    x += step
                }
                context.stroke(path, with: .color(recipe.device.opacity(0.5)),
                               style: StrokeStyle(lineWidth: max(0.8, canvasSize.width * 0.012)))
            }
            .drawingGroup()

        case .press:
            ZStack {
                Canvas { context, canvasSize in
                    let bars = 7
                    let height = canvasSize.height / CGFloat(bars * 2)
                    for index in 0..<bars {
                        let y = CGFloat(index * 2) * height
                        context.fill(Path(CGRect(x: 0, y: y, width: canvasSize.width, height: height)),
                                     with: .color(recipe.device.opacity(0.6)))
                        context.fill(Path(CGRect(x: canvasSize.width * 0.04, y: y + height * 0.35,
                                                 width: canvasSize.width, height: height)),
                                     with: .color(recipe.accent.opacity(0.35)))
                    }
                }
                .drawingGroup()
                DeckGlyph(fan: 0.35)
                    .fill(recipe.accent)
                    .frame(width: size.width * 0.42)
            }

        case .stamp:
            ZStack {
                StampOutline(form: .circle, seed: recipe.seed, breakUp: 0.12)
                    .stroke(recipe.device, lineWidth: max(1.4, size.width * 0.03))
                    .padding(inset * 1.6)
                StampOutline(form: .circle, seed: recipe.seed &+ 3, breakUp: 0.2)
                    .stroke(recipe.device.opacity(0.7), lineWidth: max(1, size.width * 0.018))
                    .padding(inset * 2.6)
                DeckGlyph(fan: 0.5)
                    .fill(recipe.device)
                    .frame(width: size.width * 0.32)
            }
        }
    }
}

import SwiftUI
import DeckCore

/// Cover art for a game.
///
/// Every game gets its own composition rather than the same template with a
/// different icon dropped in: Hearts is a painted heart with cards falling out
/// of it, Spades is a stencil cut straight through the frame, Poker is a stack
/// with chip marks sprayed over it. They share a palette, a texture and a type
/// treatment, and nothing else — which is what makes a shelf of them read as a
/// collection instead of a grid.
public struct GameCoverArt: View {
    private let artworkID: String
    private let title: String
    private let size: Size
    private let seed: Int

    public enum Size {
        /// The home hero and the game detail header.
        case hero
        /// A shelf card in the library.
        case shelf
        /// A small chip in a list or a result screen.
        case chip

        var titleSize: CGFloat {
            switch self {
            case .hero: return 68
            case .shelf: return 34
            case .chip: return 18
            }
        }

        var showsTitle: Bool { self != .chip }
        var textureIntensity: Double {
            switch self {
            case .hero: return 0.14
            case .shelf: return 0.10
            case .chip: return 0.0
            }
        }
    }

    public init(artworkID: String, title: String, size: Size = .shelf, seed: Int = 0) {
        self.artworkID = artworkID
        self.title = title
        self.size = size
        self.seed = seed
    }

    private struct Recipe {
        var ground: Color
        var mark: Color
        var accent: Color
        var type: Color
        var composition: Composition
    }

    private enum Composition {
        case suitBleed(SuitShape.Kind)
        case suitStencil(SuitShape.Kind)
        case stackAndChips
        case cascade
        case bigNumeral(String)
        case fourUp(SuitShape.Kind)
        case clash
        case cellGrid
        case webLattice
        case faceDownFan
        case meldBars
        case crown
        case twoJacks
        case motionLines
    }

    private var recipe: Recipe {
        switch artworkID {
        case "art.hearts":
            return Recipe(ground: DeckPalette.cream, mark: DeckPalette.vermilion,
                          accent: DeckPalette.ink, type: DeckPalette.ink,
                          composition: .suitBleed(.heart))
        case "art.spades":
            return Recipe(ground: DeckPalette.cobalt, mark: DeckPalette.ink,
                          accent: DeckPalette.cream, type: DeckPalette.cream,
                          composition: .suitStencil(.spade))
        case "art.poker":
            return Recipe(ground: DeckPalette.forest, mark: DeckPalette.cream,
                          accent: DeckPalette.acid, type: DeckPalette.cream,
                          composition: .stackAndChips)
        case "art.klondike":
            return Recipe(ground: DeckPalette.ink, mark: DeckPalette.cream,
                          accent: DeckPalette.orange, type: DeckPalette.cream,
                          composition: .cascade)
        case "art.crazyEights":
            return Recipe(ground: DeckPalette.acid, mark: DeckPalette.ink,
                          accent: DeckPalette.vermilion, type: DeckPalette.ink,
                          composition: .bigNumeral("8"))
        case "art.goFish":
            return Recipe(ground: DeckPalette.electric, mark: DeckPalette.cream,
                          accent: DeckPalette.acid, type: DeckPalette.cream,
                          composition: .fourUp(.diamond))
        case "art.war":
            return Recipe(ground: DeckPalette.crimson, mark: DeckPalette.cream,
                          accent: DeckPalette.ink, type: DeckPalette.cream,
                          composition: .clash)
        case "art.freeCell":
            return Recipe(ground: DeckPalette.newsprint, mark: DeckPalette.ink,
                          accent: DeckPalette.cobalt, type: DeckPalette.ink,
                          composition: .cellGrid)
        case "art.spider":
            return Recipe(ground: DeckPalette.ink, mark: DeckPalette.forest,
                          accent: DeckPalette.acid, type: DeckPalette.cream,
                          composition: .webLattice)
        case "art.cheat":
            return Recipe(ground: DeckPalette.orange, mark: DeckPalette.ink,
                          accent: DeckPalette.cream, type: DeckPalette.ink,
                          composition: .faceDownFan)
        case "art.ginRummy":
            return Recipe(ground: DeckPalette.cream, mark: DeckPalette.forest,
                          accent: DeckPalette.vermilion, type: DeckPalette.ink,
                          composition: .meldBars)
        case "art.rummy":
            return Recipe(ground: DeckPalette.coral, mark: DeckPalette.ink,
                          accent: DeckPalette.cream, type: DeckPalette.ink,
                          composition: .meldBars)
        case "art.president":
            return Recipe(ground: DeckPalette.crimson, mark: DeckPalette.acid,
                          accent: DeckPalette.cream, type: DeckPalette.cream,
                          composition: .crown)
        case "art.euchre":
            return Recipe(ground: DeckPalette.forest, mark: DeckPalette.cream,
                          accent: DeckPalette.acid, type: DeckPalette.cream,
                          composition: .twoJacks)
        case "art.speed":
            return Recipe(ground: DeckPalette.vermilion, mark: DeckPalette.cream,
                          accent: DeckPalette.acid, type: DeckPalette.cream,
                          composition: .motionLines)
        default:
            return Recipe(ground: DeckPalette.inkSoft, mark: DeckPalette.cream,
                          accent: DeckPalette.vermilion, type: DeckPalette.cream,
                          composition: .suitStencil(.club))
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            let box = proxy.size
            let recipe = self.recipe
            ZStack {
                recipe.ground
                composition(recipe: recipe, box: box)
                if size.showsTitle {
                    titleBlock(recipe: recipe, box: box)
                }
            }
            .overlay(PaperGrain(intensity: size.textureIntensity, seed: seed &+ 17, tint: .black))
            .clipped()
        }
        .accessibilityElement()
        .accessibilityLabel(Text(title))
    }

    // MARK: - Title

    private func titleBlock(recipe: Recipe, box: CGSize) -> some View {
        let fontSize = min(size.titleSize, box.width * 0.26)
        return VStack {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 0) {
                DisplayText(title.uppercased(), size: fontSize, colour: recipe.type)
                    .shadow(color: recipe.ground.opacity(0.55), radius: 1, x: 1, y: 1)
                Spacer(minLength: 0)
            }
        }
        .padding(box.width * 0.055)
    }

    // MARK: - Compositions

    @ViewBuilder
    private func composition(recipe: Recipe, box: CGSize) -> some View {
        switch recipe.composition {
        case let .suitBleed(kind):
            // The mark runs off two edges: cropping is what makes it a poster.
            ZStack(alignment: .topTrailing) {
                Color.clear
                SuitMark(kind, colour: recipe.mark,
                         offsetColour: recipe.accent.opacity(0.25),
                         wobble: 0.02, seed: seed &+ 3)
                    .frame(width: box.width * 1.05, height: box.width * 1.05)
                    .offset(x: box.width * 0.28, y: -box.width * 0.20)
                fannedCards(count: 4, box: box, colour: recipe.accent, spread: 16)
                    .offset(x: -box.width * 0.10, y: box.height * 0.16)
            }

        case let .suitStencil(kind):
            ZStack {
                HalftoneField(colour: recipe.accent.opacity(0.16),
                              cell: max(6, box.width * 0.05), direction: .topLeading)
                SuitShape(kind, wobble: 0.018, seed: seed &+ 5)
                    .fill(recipe.mark)
                    .frame(width: box.width * 0.78, height: box.width * 0.78)
                    .rotationEffect(.degrees(-6))
                    .offset(x: box.width * 0.14, y: -box.height * 0.06)
            }

        case .stackAndChips:
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: box.width * 0.03, style: .continuous)
                        .fill(recipe.mark)
                        .frame(width: box.width * 0.34,
                               height: box.width * 0.34 / CardMetrics.aspectRatio)
                        .rotationEffect(.degrees(Double(index - 1) * 11))
                        .offset(x: CGFloat(index - 1) * box.width * 0.11,
                                y: -box.height * 0.04)
                }
                SprayMark(colour: recipe.accent, seed: seed &+ 9, density: 0.7, spread: 0.5, drips: 2)
                    .frame(width: box.width * 0.5, height: box.width * 0.5)
                    .offset(x: box.width * 0.26, y: box.height * 0.12)
            }

        case .cascade:
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: box.width * 0.026, style: .continuous)
                        .fill(index % 2 == 0 ? recipe.mark : recipe.accent)
                        .frame(width: box.width * 0.26,
                               height: box.width * 0.26 / CardMetrics.aspectRatio)
                        .offset(x: box.width * (CGFloat(index) * 0.11 - 0.22),
                                y: box.height * (CGFloat(index) * 0.075 - 0.22))
                }
                .rotationEffect(.degrees(-8))
            }

        case let .bigNumeral(glyph):
            ZStack {
                SprayMark(colour: recipe.accent.opacity(0.55), seed: seed &+ 11,
                          density: 1.0, spread: 0.7, drips: 3)
                    .frame(width: box.width * 0.9, height: box.width * 0.9)
                Text(glyph)
                    .font(DeckType.numeral(box.width * 0.85))
                    .foregroundStyle(recipe.mark)
                    .rotationEffect(.degrees(-9))
                    .offset(x: box.width * 0.05, y: -box.height * 0.07)
            }

        case let .fourUp(kind):
            HStack(spacing: -box.width * 0.06) {
                ForEach(0..<4, id: \.self) { index in
                    ZStack {
                        RoundedRectangle(cornerRadius: box.width * 0.024, style: .continuous)
                            .fill(recipe.mark)
                        SuitShape(kind)
                            .fill(index % 2 == 0 ? recipe.ground : recipe.accent)
                            .padding(box.width * 0.03)
                    }
                    .frame(width: box.width * 0.22,
                           height: box.width * 0.22 / CardMetrics.aspectRatio)
                    .rotationEffect(.degrees(Double(index) * 7 - 10))
                }
            }
            .offset(y: -box.height * 0.08)

        case .clash:
            ZStack {
                // A diagonal split, with a card driving in from each side.
                Path { path in
                    path.move(to: CGPoint(x: 0, y: box.height))
                    path.addLine(to: CGPoint(x: box.width, y: 0))
                    path.addLine(to: CGPoint(x: box.width, y: box.height))
                    path.closeSubpath()
                }
                .fill(recipe.accent.opacity(0.35))
                RoundedRectangle(cornerRadius: box.width * 0.03, style: .continuous)
                    .fill(recipe.mark)
                    .frame(width: box.width * 0.3, height: box.width * 0.3 / CardMetrics.aspectRatio)
                    .rotationEffect(.degrees(-24))
                    .offset(x: -box.width * 0.16, y: -box.height * 0.04)
                RoundedRectangle(cornerRadius: box.width * 0.03, style: .continuous)
                    .fill(recipe.accent)
                    .frame(width: box.width * 0.3, height: box.width * 0.3 / CardMetrics.aspectRatio)
                    .rotationEffect(.degrees(22))
                    .offset(x: box.width * 0.18, y: -box.height * 0.12)
            }

        case .cellGrid:
            VStack(alignment: .leading, spacing: box.width * 0.03) {
                HStack(spacing: box.width * 0.03) {
                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: box.width * 0.02, style: .continuous)
                            .stroke(recipe.mark, lineWidth: max(1.5, box.width * 0.012))
                            .frame(width: box.width * 0.15,
                                   height: box.width * 0.15 / CardMetrics.aspectRatio)
                            .background(
                                RoundedRectangle(cornerRadius: box.width * 0.02, style: .continuous)
                                    .fill(index == 1 ? recipe.accent : .clear)
                            )
                    }
                }
                HStack(spacing: box.width * 0.03) {
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: box.width * 0.02, style: .continuous)
                            .fill(index % 2 == 0 ? recipe.mark : recipe.accent)
                            .frame(width: box.width * 0.11,
                                   height: box.width * (0.20 + CGFloat(index) * 0.03))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(box.width * 0.07)

        case .webLattice:
            ZStack {
                Canvas { context, canvasSize in
                    var path = Path()
                    let centre = CGPoint(x: canvasSize.width * 0.72, y: canvasSize.height * 0.24)
                    for spoke in 0..<10 {
                        let angle = Double(spoke) / 10 * 2 * .pi
                        path.move(to: centre)
                        path.addLine(to: CGPoint(x: centre.x + CGFloat(cos(angle)) * canvasSize.width,
                                                 y: centre.y + CGFloat(sin(angle)) * canvasSize.width))
                    }
                    for ring in 1...5 {
                        let radius = canvasSize.width * 0.09 * CGFloat(ring)
                        path.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                   width: radius * 2, height: radius * 2))
                    }
                    context.stroke(path, with: .color(DeckPalette.acid.opacity(0.5)),
                                   style: StrokeStyle(lineWidth: max(1, canvasSize.width * 0.006)))
                }
                .drawingGroup()
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: box.width * 0.024, style: .continuous)
                        .fill(recipe.mark)
                        .frame(width: box.width * 0.2,
                               height: box.width * 0.2 / CardMetrics.aspectRatio)
                        .offset(x: box.width * (-0.24 + CGFloat(index) * 0.055),
                                y: box.height * (0.06 + CGFloat(index) * 0.09))
                }
            }

        case .faceDownFan:
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: box.width * 0.026, style: .continuous)
                        .fill(recipe.mark)
                        .overlay(
                            RoundedRectangle(cornerRadius: box.width * 0.026, style: .continuous)
                                .strokeBorder(recipe.accent.opacity(0.6),
                                              lineWidth: max(1, box.width * 0.008))
                                .padding(box.width * 0.012)
                        )
                        .frame(width: box.width * 0.24,
                               height: box.width * 0.24 / CardMetrics.aspectRatio)
                        .rotationEffect(.degrees(Double(index) * 9 - 18))
                        .offset(x: CGFloat(index - 2) * box.width * 0.085, y: -box.height * 0.05)
                }
                StampOutline(form: .circle, seed: seed &+ 21, breakUp: 0.18)
                    .stroke(recipe.accent, lineWidth: max(2, box.width * 0.016))
                    .frame(width: box.width * 0.3, height: box.width * 0.3)
                    .rotationEffect(.degrees(-14))
                    .offset(x: box.width * 0.24, y: box.height * 0.10)
            }

        case .meldBars:
            VStack(alignment: .leading, spacing: box.width * 0.035) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: box.width * 0.02) {
                        ForEach(0..<(row == 1 ? 4 : 3), id: \.self) { column in
                            RoundedRectangle(cornerRadius: box.width * 0.018, style: .continuous)
                                .fill((row + column) % 2 == 0 ? recipe.mark : recipe.accent)
                                .frame(width: box.width * 0.115,
                                       height: box.width * 0.115 / CardMetrics.aspectRatio)
                        }
                    }
                    .rotationEffect(.degrees(row == 1 ? 2.5 : -1.5))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(box.width * 0.08)

        case .crown:
            ZStack {
                CrownShape()
                    .fill(recipe.mark)
                    .frame(width: box.width * 0.56, height: box.width * 0.42)
                    .rotationEffect(.degrees(-5))
                    .offset(x: box.width * 0.16, y: -box.height * 0.12)
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: box.width * 0.02, style: .continuous)
                        .fill(recipe.accent.opacity(1.0 - Double(index) * 0.18))
                        .frame(width: box.width * 0.17,
                               height: box.width * 0.17 / CardMetrics.aspectRatio)
                        .offset(x: box.width * (-0.26 + CGFloat(index) * 0.055),
                                y: box.height * (0.10 + CGFloat(index) * 0.045))
                }
            }

        case .twoJacks:
            ZStack {
                ForEach(0..<2, id: \.self) { index in
                    ZStack {
                        RoundedRectangle(cornerRadius: box.width * 0.028, style: .continuous)
                            .fill(recipe.mark)
                        Text("J")
                            .font(DeckType.display(box.width * 0.22))
                            .foregroundStyle(index == 0 ? DeckPalette.ink : DeckPalette.vermilion)
                    }
                    .frame(width: box.width * 0.27,
                           height: box.width * 0.27 / CardMetrics.aspectRatio)
                    .rotationEffect(.degrees(index == 0 ? -13 : 11))
                    .offset(x: index == 0 ? -box.width * 0.11 : box.width * 0.13,
                            y: index == 0 ? -box.height * 0.04 : -box.height * 0.10)
                }
                SuitShape(.club)
                    .fill(recipe.accent.opacity(0.4))
                    .frame(width: box.width * 0.3, height: box.width * 0.3)
                    .offset(x: box.width * 0.3, y: box.height * 0.16)
            }

        case .motionLines:
            ZStack {
                Canvas { context, canvasSize in
                    for index in 0..<9 {
                        let y = canvasSize.height * (0.1 + Double(index) * 0.085)
                        let length = canvasSize.width * (0.3 + Double(index % 3) * 0.22)
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: length, y: y))
                        context.stroke(path, with: .color(DeckPalette.acid.opacity(0.55)),
                                       style: StrokeStyle(lineWidth: max(2, canvasSize.width * 0.012),
                                                          lineCap: .round))
                    }
                }
                .drawingGroup()
                ForEach(0..<2, id: \.self) { index in
                    RoundedRectangle(cornerRadius: box.width * 0.028, style: .continuous)
                        .fill(recipe.mark)
                        .frame(width: box.width * 0.26,
                               height: box.width * 0.26 / CardMetrics.aspectRatio)
                        .rotationEffect(.degrees(index == 0 ? 16 : -9))
                        .offset(x: box.width * (index == 0 ? 0.20 : 0.34),
                                y: box.height * (index == 0 ? -0.10 : 0.06))
                }
            }
        }
    }

    private func fannedCards(count: Int, box: CGSize, colour: Color, spread: Double) -> some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: box.width * 0.024, style: .continuous)
                    .fill(colour.opacity(1.0 - Double(index) * 0.12))
                    .frame(width: box.width * 0.22,
                           height: box.width * 0.22 / CardMetrics.aspectRatio)
                    .rotationEffect(.degrees(Double(index) * spread / Double(count) - spread / 2))
                    .offset(x: CGFloat(index) * box.width * 0.05)
            }
        }
    }
}

/// A cut-paper crown, for President and for the mastery emblems.
public struct CrownShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let base = rect.maxY
        let top = rect.minY
        let mid = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: base))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.06, y: top + rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.28, y: mid))
        path.addLine(to: CGPoint(x: rect.midX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.28, y: mid))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: top + rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.maxX, y: base))
        path.closeSubpath()
        return path
    }
}

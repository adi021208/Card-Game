import SwiftUI
import DeckProgression

/// An illustrated portrait of one of the seven.
///
/// Built from flat shapes in two or three colours, the way a screen-printed
/// poster portrait is: a silhouette, a hair shape, two marks for the eyes, one
/// for the mouth. No gradients, no photographs, no seven-recoloured-circles.
///
/// The idle animation is deliberately small — a blink, a glance, an eyebrow.
/// The goal is that the portrait feels present, not that it performs.
public struct BossPortrait: View {
    private let boss: Boss
    private let isAnimated: Bool
    private let showsGround: Bool

    @Environment(\.deckReducedMotion) private var reducedMotion

    public init(boss: Boss, isAnimated: Bool = true, showsGround: Bool = true) {
        self.boss = boss
        self.isAnimated = isAnimated
        self.showsGround = showsGround
    }

    private var accent: Color { DeckPalette.token(boss.colourToken) }
    private var ground: Color { DeckPalette.token(boss.groundToken) }
    private var skin: Color { ground == DeckPalette.cream ? DeckPalette.ink : DeckPalette.cream }

    /// Each boss gets a different face geometry, not a different hue.
    private var traits: Traits {
        switch boss.id {
        case "hal":     return Traits(head: .oval,    hair: .parted,   eyes: .level,   mouth: .flat,    accessory: .collar)
        case "pedro":   return Traits(head: .square,  hair: .crop,     eyes: .wide,    mouth: .open,    accessory: .chain)
        case "calvin":  return Traits(head: .narrow,  hair: .receding, eyes: .narrow,  mouth: .thin,    accessory: .glasses)
        case "rohan":   return Traits(head: .round,   hair: .swept,    eyes: .level,   mouth: .flat,    accessory: .glasses)
        case "shayla":  return Traits(head: .oval,    hair: .long,     eyes: .raised,  mouth: .smirk,   accessory: .earring)
        case "honey":   return Traits(head: .round,   hair: .curls,    eyes: .wide,    mouth: .smirk,   accessory: .none)
        default:        return Traits(head: .angular, hair: .bob,      eyes: .narrow,  mouth: .thin,    accessory: .cardFan)
        }
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !isAnimated || reducedMotion)) { context in
            let beat = IdleBeat(behaviour: boss.idle,
                                time: context.date.timeIntervalSinceReferenceDate,
                                seed: boss.id.hashValue)
            GeometryReader { proxy in
                let box = min(proxy.size.width, proxy.size.height)
                ZStack {
                    if showsGround {
                        ground
                        HalftoneField(colour: accent.opacity(0.28),
                                      cell: max(5, box * 0.055),
                                      direction: .top)
                        SprayMark(colour: accent.opacity(0.5),
                                  seed: boss.id.hashValue, density: 0.6, spread: 0.4, drips: 1)
                            .frame(width: box * 0.9, height: box * 0.9)
                    }
                    face(box: box, beat: beat)
                        .offset(y: box * 0.02 * CGFloat(beat.breath))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(boss.displayName))
    }

    // MARK: - Face

    private func face(box: CGFloat, beat: IdleBeat) -> some View {
        ZStack {
            // Shoulders, so the head is not floating.
            Capsule(style: .continuous)
                .fill(accent)
                .frame(width: box * 0.86, height: box * 0.46)
                .offset(y: box * 0.42)

            traits.accessory.behindShape(box: box, colour: accent, skin: skin)

            // Head.
            traits.head.shape
                .fill(skin)
                .frame(width: box * 0.56, height: box * 0.66)
                .offset(y: -box * 0.02)

            // Hair sits over the top of the head.
            traits.hair.shape
                .fill(DeckPalette.ink.opacity(skin == DeckPalette.ink ? 0.0 : 0.92))
                .frame(width: box * 0.66, height: box * 0.44)
                .offset(y: -box * 0.24)
                .opacity(skin == DeckPalette.ink ? 0 : 1)
            // On a dark skin tone the hair reads as the accent instead.
            traits.hair.shape
                .fill(accent)
                .frame(width: box * 0.66, height: box * 0.44)
                .offset(y: -box * 0.24)
                .opacity(skin == DeckPalette.ink ? 1 : 0)

            eyes(box: box, beat: beat)
            mouth(box: box, beat: beat)
            traits.accessory.frontShape(box: box, colour: accent, skin: skin)
        }
        .frame(width: box, height: box)
    }

    private func eyes(box: CGFloat, beat: IdleBeat) -> some View {
        let eyeInk = skin == DeckPalette.ink ? DeckPalette.cream : DeckPalette.ink
        let openness = CGFloat(beat.eyeOpen)
        let glance = CGFloat(beat.glance) * box * 0.012
        return HStack(spacing: box * 0.14) {
            ForEach(0..<2, id: \.self) { index in
                // One brow lifts on the personalities that have a tell.
                let lift = (traits.eyes == .raised && index == 1) ? CGFloat(beat.brow) : 0
                traits.eyes.shape
                    .fill(eyeInk)
                    .frame(width: box * 0.10, height: box * 0.075 * max(0.08, openness))
                    .offset(x: glance, y: -box * 0.03 * lift)
            }
        }
        .offset(y: -box * 0.05)
    }

    private func mouth(box: CGFloat, beat: IdleBeat) -> some View {
        let eyeInk = skin == DeckPalette.ink ? DeckPalette.cream : DeckPalette.ink
        return traits.mouth.shape(open: CGFloat(beat.mouth))
            .stroke(eyeInk, style: StrokeStyle(lineWidth: max(2, box * 0.018),
                                               lineCap: .round, lineJoin: .round))
            .frame(width: box * 0.20, height: box * 0.08)
            .offset(y: box * 0.13)
    }

    // MARK: - Traits

    private struct Traits {
        var head: HeadShape
        var hair: HairShape
        var eyes: EyeShape
        var mouth: MouthShape
        var accessory: Accessory
    }

    private enum HeadShape {
        case oval, round, square, narrow, angular

        var shape: AnyShape {
            switch self {
            case .oval: return AnyShape(Ellipse())
            case .round: return AnyShape(Circle())
            case .square: return AnyShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            case .narrow: return AnyShape(Capsule(style: .continuous))
            case .angular: return AnyShape(AngularHead())
            }
        }
    }

    private enum HairShape {
        case parted, crop, receding, swept, long, curls, bob

        var shape: AnyShape {
            switch self {
            case .parted: return AnyShape(PartedHair())
            case .crop: return AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            case .receding: return AnyShape(RecedingHair())
            case .swept: return AnyShape(SweptHair())
            case .long: return AnyShape(LongHair())
            case .curls: return AnyShape(CurlHair())
            case .bob: return AnyShape(BobHair())
            }
        }
    }

    private enum EyeShape: Equatable {
        case level, narrow, wide, raised

        var shape: AnyShape {
            switch self {
            case .level, .raised: return AnyShape(Capsule())
            case .narrow: return AnyShape(RoundedRectangle(cornerRadius: 2))
            case .wide: return AnyShape(Ellipse())
            }
        }
    }

    private enum MouthShape {
        case flat, thin, smirk, open

        func shape(open amount: CGFloat) -> AnyShape {
            switch self {
            case .flat: return AnyShape(MouthLine(curve: 0, open: amount))
            case .thin: return AnyShape(MouthLine(curve: -0.2, open: amount * 0.4))
            case .smirk: return AnyShape(MouthLine(curve: 0.5, open: amount * 0.6, skew: 0.35))
            case .open: return AnyShape(MouthLine(curve: 0.3, open: 0.4 + amount))
            }
        }
    }

    private enum Accessory {
        case none, collar, glasses, chain, earring, cardFan

        @ViewBuilder
        func behindShape(box: CGFloat, colour: Color, skin: Color) -> some View {
            switch self {
            case .cardFan:
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: box * 0.02, style: .continuous)
                            .fill(skin)
                            .frame(width: box * 0.17, height: box * 0.17 / CardMetrics.aspectRatio)
                            .rotationEffect(.degrees(Double(index) * 14 - 14))
                            .offset(x: box * 0.30, y: box * 0.30)
                    }
                }
            default:
                EmptyView()
            }
        }

        @ViewBuilder
        func frontShape(box: CGFloat, colour: Color, skin: Color) -> some View {
            let ink = skin == DeckPalette.ink ? DeckPalette.cream : DeckPalette.ink
            switch self {
            case .glasses:
                HStack(spacing: box * 0.055) {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: box * 0.022, style: .continuous)
                            .strokeBorder(ink, lineWidth: max(2, box * 0.016))
                            .frame(width: box * 0.17, height: box * 0.13)
                    }
                }
                .offset(y: -box * 0.05)
            case .collar:
                Path { path in
                    path.move(to: CGPoint(x: box * 0.34, y: box * 0.68))
                    path.addLine(to: CGPoint(x: box * 0.5, y: box * 0.80))
                    path.addLine(to: CGPoint(x: box * 0.66, y: box * 0.68))
                }
                .stroke(skin, style: StrokeStyle(lineWidth: max(3, box * 0.024), lineJoin: .round))
            case .chain:
                Path { path in
                    path.move(to: CGPoint(x: box * 0.33, y: box * 0.66))
                    path.addQuadCurve(to: CGPoint(x: box * 0.67, y: box * 0.66),
                                      control: CGPoint(x: box * 0.5, y: box * 0.82))
                }
                .stroke(DeckPalette.acid, style: StrokeStyle(lineWidth: max(3, box * 0.022),
                                                             lineCap: .round))
            case .earring:
                Circle()
                    .fill(DeckPalette.acid)
                    .frame(width: box * 0.05, height: box * 0.05)
                    .offset(x: box * 0.24, y: box * 0.10)
            case .none, .cardFan:
                EmptyView()
            }
        }
    }

    /// The current frame of the idle animation.
    ///
    /// Everything is derived from the clock, so no state is stored and the
    /// portrait costs nothing when it is off screen.
    private struct IdleBeat {
        var eyeOpen: Double = 1
        var glance: Double = 0
        var brow: Double = 0
        var mouth: Double = 0
        var breath: Double = 0

        init(behaviour: Boss.IdleBehaviour, time: TimeInterval, seed: Int) {
            let offset = Double(abs(seed % 1000)) / 100.0
            let t = time + offset
            breath = sin(t * 0.9) * 0.35

            switch behaviour {
            case .blink:
                // A blink every four seconds or so, lasting a tenth of one.
                let phase = t.truncatingRemainder(dividingBy: 4.1)
                eyeOpen = phase < 0.12 ? max(0.05, phase / 0.12) : (phase < 0.24 ? (phase - 0.12) / 0.12 : 1)
            case .glanceAtCards:
                let phase = t.truncatingRemainder(dividingBy: 5.6)
                glance = phase < 0.8 ? -sin(phase / 0.8 * .pi) : 0
                eyeOpen = phase < 0.8 ? 0.8 : 1
            case .eyebrow:
                let phase = t.truncatingRemainder(dividingBy: 4.7)
                brow = phase < 0.7 ? sin(phase / 0.7 * .pi) : 0
            case .breathe:
                breath = sin(t * 0.75) * 0.6
            case .tapFingers:
                mouth = abs(sin(t * 3.1)) * 0.15
                breath = sin(t * 1.4) * 0.3
            case .tiltHead:
                glance = sin(t * 0.45) * 0.6
            case .smirk:
                let phase = t.truncatingRemainder(dividingBy: 6.3)
                mouth = phase < 1.4 ? sin(phase / 1.4 * .pi) * 0.5 : 0
                let blink = t.truncatingRemainder(dividingBy: 3.7)
                eyeOpen = blink < 0.1 ? 0.1 : 1
            }
        }
    }
}

// MARK: - Face component shapes

struct AngularHead: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.28))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.maxY - rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.maxY - rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.28))
        path.closeSubpath()
        return path
    }
}

struct PartedHair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX + rect.width * 0.06, y: rect.minY),
                          control: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.2))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.maxY - rect.height * 0.4))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY - rect.height * 0.4))
        path.closeSubpath()
        return path
    }
}

struct RecedingHair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX, y: rect.midY,
                                   width: rect.width * 0.3, height: rect.height * 0.5))
        path.addEllipse(in: CGRect(x: rect.maxX - rect.width * 0.3, y: rect.midY,
                                   width: rect.width * 0.3, height: rect.height * 0.5))
        return path
    }
}

struct SweptHair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.1),
                          control: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.maxY),
                          control: CGPoint(x: rect.maxX + rect.width * 0.05, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

struct LongHair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX, y: rect.minY,
                                   width: rect.width, height: rect.height * 0.9))
        path.addRect(CGRect(x: rect.minX, y: rect.midY,
                            width: rect.width * 0.16, height: rect.height * 1.3))
        path.addRect(CGRect(x: rect.maxX - rect.width * 0.16, y: rect.midY,
                            width: rect.width * 0.16, height: rect.height * 1.3))
        return path
    }
}

struct CurlHair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width * 0.16
        let positions: [(CGFloat, CGFloat)] = [(0.14, 0.55), (0.32, 0.28), (0.5, 0.16),
                                               (0.68, 0.28), (0.86, 0.55)]
        for position in positions {
            path.addEllipse(in: CGRect(x: rect.minX + rect.width * position.0 - radius,
                                       y: rect.minY + rect.height * position.1 - radius,
                                       width: radius * 2, height: radius * 2))
        }
        return path
    }
}

struct BobHair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.35))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.35),
                          control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.15))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct MouthLine: Shape {
    /// Positive curves up, negative curves down.
    var curve: CGFloat
    /// How far the mouth opens.
    var open: CGFloat
    /// Pulls one corner higher than the other.
    var skew: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let leftY = rect.midY - rect.height * skew * 0.5
        let rightY = rect.midY + rect.height * skew * 0.5
        path.move(to: CGPoint(x: rect.minX, y: leftY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rightY),
                          control: CGPoint(x: rect.midX, y: rect.midY + rect.height * curve))
        if open > 0.05 {
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: leftY),
                              control: CGPoint(x: rect.midX,
                                               y: rect.midY + rect.height * (curve + open)))
        }
        return path
    }
}

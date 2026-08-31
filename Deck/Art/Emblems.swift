import SwiftUI
import DeckCore

/// The symbol an achievement poster is built around.
///
/// Fourteen drawn marks, all from the same set of parts as everything else in
/// the app. None of them is an SF Symbol: a collectible needs to look like it
/// was made for this app and no other.
public struct EmblemMark: View {
    private let emblem: AchievementEmblem
    private let colour: Color
    private let accent: Color
    private let seed: Int

    public init(_ emblem: AchievementEmblem, colour: Color, accent: Color, seed: Int = 1) {
        self.emblem = emblem
        self.colour = colour
        self.accent = accent
        self.seed = seed
    }

    public var body: some View {
        GeometryReader { proxy in
            let box = min(proxy.size.width, proxy.size.height)
            ZStack {
                switch emblem {
                case .stamp:
                    StampOutline(form: .circle, seed: seed, breakUp: 0.14)
                        .stroke(colour, lineWidth: max(2, box * 0.05))
                    StampOutline(form: .circle, seed: seed &+ 4, breakUp: 0.22)
                        .stroke(colour.opacity(0.6), lineWidth: max(1.5, box * 0.03))
                        .padding(box * 0.14)
                    DeckGlyph(fan: 0.5).fill(accent).frame(width: box * 0.34)

                case .crown:
                    CrownShape().fill(colour).frame(width: box * 0.8, height: box * 0.6)
                    CrownShape().fill(accent.opacity(0.5))
                        .frame(width: box * 0.8, height: box * 0.6)
                        .offset(x: box * 0.03, y: box * 0.03)

                case .moon:
                    MoonShape().fill(colour).frame(width: box * 0.72, height: box * 0.72)
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: box * 0.02)
                            .fill(accent)
                            .frame(width: box * 0.16, height: box * 0.16 / CardMetrics.aspectRatio)
                            .rotationEffect(.degrees(Double(index) * 14 - 14))
                            .offset(x: box * (0.12 + Double(index) * 0.05), y: box * 0.24)
                    }

                case .flame:
                    FlameShape().fill(colour).frame(width: box * 0.6, height: box * 0.78)
                    FlameShape().fill(accent).frame(width: box * 0.34, height: box * 0.44)
                        .offset(y: box * 0.12)

                case .bolt:
                    BoltShape().fill(colour).frame(width: box * 0.5, height: box * 0.82)
                    BoltShape().fill(accent.opacity(0.55))
                        .frame(width: box * 0.5, height: box * 0.82)
                        .offset(x: box * 0.04, y: box * 0.03)

                case .royalFan:
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: box * 0.03, style: .continuous)
                            .fill(index == 2 ? accent : colour)
                            .frame(width: box * 0.28, height: box * 0.28 / CardMetrics.aspectRatio)
                            .rotationEffect(.degrees(Double(index) * 16 - 32), anchor: .bottom)
                    }

                case .spade:
                    SuitMark(.spade, colour: colour, offsetColour: accent.opacity(0.5))
                        .frame(width: box * 0.78)
                case .heart:
                    SuitMark(.heart, colour: colour, offsetColour: accent.opacity(0.5))
                        .frame(width: box * 0.78)
                case .club:
                    SuitMark(.club, colour: colour, offsetColour: accent.opacity(0.5))
                        .frame(width: box * 0.78)
                case .diamond:
                    SuitMark(.diamond, colour: colour, offsetColour: accent.opacity(0.5))
                        .frame(width: box * 0.78)

                case .clock:
                    Circle().strokeBorder(colour, lineWidth: max(2, box * 0.06))
                        .frame(width: box * 0.72, height: box * 0.72)
                    Path { path in
                        path.move(to: CGPoint(x: box / 2, y: box / 2))
                        path.addLine(to: CGPoint(x: box / 2, y: box * 0.24))
                        path.move(to: CGPoint(x: box / 2, y: box / 2))
                        path.addLine(to: CGPoint(x: box * 0.68, y: box * 0.56))
                    }
                    .stroke(accent, style: StrokeStyle(lineWidth: max(2, box * 0.05), lineCap: .round))

                case .binder:
                    RoundedRectangle(cornerRadius: box * 0.05, style: .continuous)
                        .fill(colour)
                        .frame(width: box * 0.66, height: box * 0.78)
                    VStack(spacing: box * 0.06) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule().fill(accent).frame(width: box * 0.42, height: box * 0.06)
                        }
                    }

                case .skull:
                    SkullShape().fill(colour).frame(width: box * 0.7, height: box * 0.78)
                    HStack(spacing: box * 0.1) {
                        Circle().fill(accent).frame(width: box * 0.14, height: box * 0.14)
                        Circle().fill(accent).frame(width: box * 0.14, height: box * 0.14)
                    }
                    .offset(y: -box * 0.06)

                case .star:
                    StarShape(points: 5).fill(colour).frame(width: box * 0.78, height: box * 0.78)
                    StarShape(points: 5).fill(accent.opacity(0.55))
                        .frame(width: box * 0.78, height: box * 0.78)
                        .offset(x: box * 0.03, y: box * 0.03)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct MoonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        path.addArc(center: centre, radius: radius,
                    startAngle: .degrees(60), endAngle: .degrees(300), clockwise: false)
        path.addArc(center: CGPoint(x: centre.x - radius * 0.42, y: centre.y),
                    radius: radius * 0.92,
                    startAngle: .degrees(305), endAngle: .degrees(55), clockwise: true)
        path.closeSubpath()
        return path
    }
}

struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY + rect.height * 0.1),
                      control1: CGPoint(x: rect.midX + rect.width * 0.2, y: rect.height * 0.2),
                      control2: CGPoint(x: rect.maxX, y: rect.height * 0.25))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.08),
                      control2: CGPoint(x: rect.midX + rect.width * 0.28, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.1),
                      control1: CGPoint(x: rect.midX - rect.width * 0.28, y: rect.maxY),
                      control2: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.08))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: rect.height * 0.25),
                      control2: CGPoint(x: rect.midX - rect.width * 0.2, y: rect.height * 0.2))
        path.closeSubpath()
        return path
    }
}

struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX * 0.62, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.06))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.02))
        path.addLine(to: CGPoint(x: rect.maxX * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY - rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.04, y: rect.midY - rect.height * 0.06))
        path.closeSubpath()
        return path
    }
}

struct SkullShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX, y: rect.minY,
                                   width: rect.width, height: rect.height * 0.76))
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.24,
                                       y: rect.minY + rect.height * 0.6,
                                       width: rect.width * 0.52,
                                       height: rect.height * 0.4),
                            cornerSize: CGSize(width: rect.width * 0.08, height: rect.width * 0.08))
        return path
    }
}

struct StarShape: Shape {
    var points: Int = 5
    var innerRatio: CGFloat = 0.42

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        let step = Double.pi / Double(points)
        for index in 0..<(points * 2) {
            let radius = index % 2 == 0 ? outer : inner
            let angle = Double(index) * step - .pi / 2
            let point = CGPoint(x: centre.x + CGFloat(cos(angle)) * radius,
                                y: centre.y + CGFloat(sin(angle)) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// A player avatar.
///
/// Illustrated marks rather than gradient circles: a suit stencil, a stamp, a
/// pair of eyes. The unlockable ones are recognisably from the same hand as the
/// bosses.
public struct AvatarArt: View {
    /// Corner radius as a fraction of the avatar's size. Anything that outlines
    /// or sits behind an avatar reads it from here rather than guessing a
    /// number that nearly matches.
    public static let cornerRatio: CGFloat = 0.28

    private let avatarID: String
    private let initials: String
    private let size: CGFloat

    public init(avatarID: String, initials: String = "", size: CGFloat = 44) {
        self.avatarID = avatarID
        self.initials = initials
        self.size = size
    }

    private var palette: (ground: Color, mark: Color) {
        switch avatarID {
        case "avatar.shark": return (DeckPalette.crimson, DeckPalette.cream)
        case "avatar.liar": return (DeckPalette.orange, DeckPalette.ink)
        case "avatar.president": return (DeckPalette.acid, DeckPalette.ink)
        case "avatar.expert": return (DeckPalette.forest, DeckPalette.acid)
        case "avatar.scarlet": return (DeckPalette.crimson, DeckPalette.acid)
        case "avatar.hal": return (DeckPalette.cobalt, DeckPalette.cream)
        case "avatar.pedro": return (DeckPalette.vermilion, DeckPalette.cream)
        case "avatar.calvin": return (DeckPalette.forest, DeckPalette.cream)
        case "avatar.rohan": return (DeckPalette.acid, DeckPalette.ink)
        case "avatar.shayla": return (DeckPalette.coral, DeckPalette.ink)
        case "avatar.honey": return (DeckPalette.orange, DeckPalette.ink)
        default: return (DeckPalette.cobalt, DeckPalette.cream)
        }
    }

    public var body: some View {
        let colours = palette
        ZStack {
            colours.ground
            switch avatarID {
            case "avatar.shark":
                SuitShape(.spade, wobble: 0.02, seed: 3).fill(colours.mark).padding(size * 0.2)
            case "avatar.liar":
                SuitShape(.club, wobble: 0.03, seed: 5).fill(colours.mark).padding(size * 0.2)
            case "avatar.president":
                CrownShape().fill(colours.mark).padding(size * 0.24)
            case "avatar.expert":
                StarShape(points: 5).fill(colours.mark).padding(size * 0.2)
            case "avatar.scarlet":
                SuitShape(.diamond, wobble: 0.02, seed: 9).fill(colours.mark).padding(size * 0.22)
            default:
                if initials.isEmpty {
                    DeckGlyph(fan: 0.7).fill(colours.mark).padding(size * 0.22)
                } else {
                    Text(initials)
                        .font(DeckType.display(size * 0.46))
                        .foregroundStyle(colours.mark)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * Self.cornerRatio, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * Self.cornerRatio, style: .continuous)
                .strokeBorder(DeckPalette.ink.opacity(0.25), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

import SwiftUI

/// Paper grain.
///
/// A field of very small, very faint marks — enough to stop a flat fill reading
/// as a flat fill, not enough to notice. Drawn once into a `Canvas` and cached
/// by `drawingGroup`, so it costs nothing to leave on every screen.
public struct PaperGrain: View {
    private let intensity: Double
    private let seed: Int
    private let tint: Color

    public init(intensity: Double = 0.1, seed: Int = 1, tint: Color = .black) {
        self.intensity = intensity
        self.seed = seed
        self.tint = tint
    }

    public var body: some View {
        Canvas { context, size in
            guard intensity > 0.001 else { return }
            var random = ArtRandom(seed: seed)
            // Density scales with area so a big screen is not sparser than a
            // small one.
            let count = Int(min(2400, max(240, size.width * size.height / 420)))
            for _ in 0..<count {
                let x = random.unit() * size.width
                let y = random.unit() * size.height
                let length = random.range(0.6, 2.4)
                let alpha = random.range(0.25, 1.0) * intensity
                let rect = CGRect(x: x, y: y, width: length, height: length * random.range(0.6, 1.4))
                context.fill(Path(rect), with: .color(tint.opacity(alpha)))
            }
        }
        .drawingGroup()
        .blendMode(.multiply)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A halftone dot field.
///
/// The dots grow towards one corner, which is what gives a printed gradient its
/// character. Used behind headlines and on the boss posters.
public struct HalftoneField: View {
    private let colour: Color
    private let cell: CGFloat
    private let direction: UnitPoint
    private let maximumFill: Double

    public init(colour: Color,
                cell: CGFloat = 9,
                direction: UnitPoint = .bottomTrailing,
                maximumFill: Double = 0.9) {
        self.colour = colour
        self.cell = cell
        self.direction = direction
        self.maximumFill = maximumFill
    }

    public var body: some View {
        Canvas { context, size in
            let columns = Int(size.width / cell) + 2
            let rows = Int(size.height / cell) + 2
            for row in 0..<rows {
                for column in 0..<columns {
                    let x = CGFloat(column) * cell
                    let y = CGFloat(row) * cell
                    // Distance from the light corner drives the dot size.
                    let dx = (x / max(1, size.width)) - direction.x
                    let dy = (y / max(1, size.height)) - direction.y
                    let distance = min(1, sqrt(dx * dx + dy * dy) / 1.2)
                    let fill = (1 - Double(distance)) * maximumFill
                    guard fill > 0.04 else { continue }
                    let radius = cell * 0.5 * CGFloat(fill)
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(colour))
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A spray-paint mark: a dense core that scatters as it goes out, with a few
/// heavy drips.
///
/// This is the app's most-used decorative element, so it is deliberately cheap:
/// a few hundred circles in one `Canvas` pass.
public struct SprayMark: View {
    private let colour: Color
    private let seed: Int
    private let density: Double
    private let spread: Double
    private let drips: Int

    public init(colour: Color, seed: Int = 1, density: Double = 1.0, spread: Double = 0.5, drips: Int = 2) {
        self.colour = colour
        self.seed = seed
        self.density = density
        self.spread = spread
        self.drips = drips
    }

    public var body: some View {
        Canvas { context, size in
            var random = ArtRandom(seed: seed)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let count = Int(320 * density)

            for _ in 0..<count {
                // Bias towards the centre so the mark has a core.
                let t = pow(random.unit(), 1.7)
                let angle = random.unit() * 2 * .pi
                let distance = t * Double(radius) * (0.7 + spread)
                let x = centre.x + CGFloat(cos(angle) * distance)
                let y = centre.y + CGFloat(sin(angle) * distance)
                let dotRadius = CGFloat(random.range(0.4, 2.6)) * CGFloat(1.4 - t)
                let alpha = (1.0 - t * 0.75) * random.range(0.45, 1.0)
                let rect = CGRect(x: x - dotRadius, y: y - dotRadius,
                                  width: dotRadius * 2, height: dotRadius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(colour.opacity(alpha)))
            }

            // A couple of runs, because wet paint does that.
            for _ in 0..<drips {
                let x = centre.x + CGFloat(random.signed()) * radius * 0.7
                let top = centre.y + CGFloat(random.range(0.1, 0.5)) * radius
                let length = CGFloat(random.range(0.15, 0.55)) * radius
                let width = CGFloat(random.range(1.4, 3.4))
                var path = Path()
                path.addRoundedRect(in: CGRect(x: x, y: top, width: width, height: length),
                                    cornerSize: CGSize(width: width / 2, height: width / 2))
                context.fill(path, with: .color(colour.opacity(0.7)))
                let blobRadius = width * 1.5
                context.fill(Path(ellipseIn: CGRect(x: x + width / 2 - blobRadius,
                                                    y: top + length - blobRadius,
                                                    width: blobRadius * 2,
                                                    height: blobRadius * 2)),
                             with: .color(colour.opacity(0.75)))
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Screen-print misregistration: the same content drawn twice, a hair apart, in
/// two colours. Used on the biggest type in the app.
public struct Misregistered<Content: View>: View {
    private let offset: CGSize
    private let ghost: Color
    private let content: () -> Content

    public init(offset: CGSize = CGSize(width: 3, height: 3),
                ghost: Color,
                @ViewBuilder content: @escaping () -> Content) {
        self.offset = offset
        self.ghost = ghost
        self.content = content
    }

    public var body: some View {
        ZStack {
            content()
                .foregroundStyle(ghost)
                .offset(offset)
                .accessibilityHidden(true)
            content()
        }
    }
}

/// A field of small scattered marks — ticks, crosses, dots — used to fill dead
/// space on a poster the way a printer's ornaments would.
public struct ScatterMarks: View {
    private let colour: Color
    private let seed: Int
    private let count: Int

    public init(colour: Color, seed: Int = 4, count: Int = 14) {
        self.colour = colour
        self.seed = seed
        self.count = count
    }

    public var body: some View {
        Canvas { context, size in
            var random = ArtRandom(seed: seed)
            for _ in 0..<count {
                let x = random.unit() * size.width
                let y = random.unit() * size.height
                let scale = CGFloat(random.range(4, 11))
                let alpha = random.range(0.25, 0.7)
                var path = Path()
                switch Int(random.unit() * 3) {
                case 0:
                    // Cross
                    path.move(to: CGPoint(x: x - scale, y: y - scale))
                    path.addLine(to: CGPoint(x: x + scale, y: y + scale))
                    path.move(to: CGPoint(x: x + scale, y: y - scale))
                    path.addLine(to: CGPoint(x: x - scale, y: y + scale))
                case 1:
                    // Tick
                    path.move(to: CGPoint(x: x - scale, y: y))
                    path.addLine(to: CGPoint(x: x - scale * 0.2, y: y + scale * 0.8))
                    path.addLine(to: CGPoint(x: x + scale, y: y - scale * 0.8))
                default:
                    // Dash
                    path.move(to: CGPoint(x: x - scale, y: y))
                    path.addLine(to: CGPoint(x: x + scale, y: y))
                }
                context.stroke(path,
                               with: .color(colour.opacity(alpha)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

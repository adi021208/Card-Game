import SwiftUI

/// The four suits, drawn rather than borrowed.
///
/// These are hand-built bezier paths, not SF Symbols: the app's whole identity
/// rests on the suits, and the system ones are recognisably the system's. Each
/// shape is defined in a unit square and scaled to fit, so the same path serves
/// a corner pip and a two-hundred-point poster mark.
///
/// `wobble` walks the control points off true by a fixed, seeded amount, which
/// is how the poster versions get their cut-by-hand stencil edge without any of
/// them being different from one frame to the next.
public struct SuitShape: Shape {
    public enum Kind: String, CaseIterable, Sendable {
        case heart, spade, club, diamond
    }

    public var kind: Kind
    /// 0 is a clean printed pip; 0.03 is a cut stencil; 0.06 is a spray mark.
    public var wobble: Double
    /// Changes which way the wobble goes, so two hearts on one screen differ.
    public var seed: Int

    public init(_ kind: Kind, wobble: Double = 0, seed: Int = 0) {
        self.kind = kind
        self.wobble = wobble
        self.seed = seed
    }

    public func path(in rect: CGRect) -> Path {
        // Suits are drawn in a square so they never stretch.
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        var walker = Walker(seed: seed, amount: wobble)

        func point(_ x: Double, _ y: Double) -> CGPoint {
            let jitter = walker.next()
            return CGPoint(x: origin.x + (x + jitter.dx) * side,
                           y: origin.y + (y + jitter.dy) * side)
        }

        var path = Path()
        switch kind {
        case .heart:
            path.move(to: point(0.50, 0.96))
            path.addCurve(to: point(0.03, 0.36),
                          control1: point(0.50, 0.82), control2: point(0.03, 0.62))
            path.addCurve(to: point(0.50, 0.22),
                          control1: point(0.03, 0.10), control2: point(0.28, 0.02))
            path.addCurve(to: point(0.97, 0.36),
                          control1: point(0.72, 0.02), control2: point(0.97, 0.10))
            path.addCurve(to: point(0.50, 0.96),
                          control1: point(0.97, 0.62), control2: point(0.50, 0.82))
            path.closeSubpath()

        case .spade:
            path.move(to: point(0.50, 0.04))
            path.addCurve(to: point(0.05, 0.58),
                          control1: point(0.34, 0.22), control2: point(0.05, 0.40))
            path.addCurve(to: point(0.35, 0.80),
                          control1: point(0.05, 0.74), control2: point(0.20, 0.83))
            path.addCurve(to: point(0.48, 0.70),
                          control1: point(0.42, 0.79), control2: point(0.46, 0.75))
            // The stem: a short flared tail, not a rectangle.
            path.addCurve(to: point(0.30, 0.97),
                          control1: point(0.47, 0.84), control2: point(0.40, 0.93))
            path.addLine(to: point(0.70, 0.97))
            path.addCurve(to: point(0.52, 0.70),
                          control1: point(0.60, 0.93), control2: point(0.53, 0.84))
            path.addCurve(to: point(0.65, 0.80),
                          control1: point(0.54, 0.75), control2: point(0.58, 0.79))
            path.addCurve(to: point(0.95, 0.58),
                          control1: point(0.80, 0.83), control2: point(0.95, 0.74))
            path.addCurve(to: point(0.50, 0.04),
                          control1: point(0.95, 0.40), control2: point(0.66, 0.22))
            path.closeSubpath()

        case .club:
            // Three lobes and a tail. Built from arcs so the lobes stay round
            // even when the wobble is turned up.
            let radius = 0.215
            let lobes: [(Double, Double)] = [(0.50, 0.24), (0.255, 0.565), (0.745, 0.565)]
            for lobe in lobes {
                let centre = point(lobe.0, lobe.1)
                path.addEllipse(in: CGRect(x: centre.x - radius * side,
                                           y: centre.y - radius * side,
                                           width: radius * 2 * side,
                                           height: radius * 2 * side))
            }
            var tail = Path()
            tail.move(to: point(0.50, 0.52))
            tail.addCurve(to: point(0.31, 0.97),
                          control1: point(0.50, 0.70), control2: point(0.42, 0.90))
            tail.addLine(to: point(0.69, 0.97))
            tail.addCurve(to: point(0.50, 0.52),
                          control1: point(0.58, 0.90), control2: point(0.50, 0.70))
            tail.closeSubpath()
            path.addPath(tail)

        case .diamond:
            path.move(to: point(0.50, 0.02))
            path.addCurve(to: point(0.97, 0.50),
                          control1: point(0.63, 0.20), control2: point(0.82, 0.38))
            path.addCurve(to: point(0.50, 0.98),
                          control1: point(0.82, 0.62), control2: point(0.63, 0.80))
            path.addCurve(to: point(0.03, 0.50),
                          control1: point(0.37, 0.80), control2: point(0.18, 0.62))
            path.addCurve(to: point(0.50, 0.02),
                          control1: point(0.18, 0.38), control2: point(0.37, 0.20))
            path.closeSubpath()
        }
        return path
    }

    /// Deterministic small offsets. Same seed, same shape, every time.
    private struct Walker {
        private var state: UInt64
        private let amount: Double

        init(seed: Int, amount: Double) {
            self.state = UInt64(bitPattern: Int64(seed &* 0x9E37_79B9 &+ 0x1234_5)) | 1
            self.amount = amount
        }

        mutating func next() -> (dx: Double, dy: Double) {
            guard amount > 0 else { return (0, 0) }
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            let x = Double(state % 2000) / 1000.0 - 1.0
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            let y = Double(state % 2000) / 1000.0 - 1.0
            return (x * amount, y * amount)
        }
    }
}

public extension SuitShape.Kind {
    /// Bridges the engine's suit into the drawn shape.
    init(suitToken: String) {
        switch suitToken.uppercased() {
        case "H": self = .heart
        case "S": self = .spade
        case "C": self = .club
        default: self = .diamond
        }
    }

    var isRed: Bool { self == .heart || self == .diamond }
}

/// A suit drawn as a poster mark: a filled stencil with a misregistered second
/// pass behind it, the way a two-colour screen print looks when the plates are
/// a hair out.
public struct SuitMark: View {
    private let kind: SuitShape.Kind
    private let colour: Color
    private let offsetColour: Color?
    private let wobble: Double
    private let seed: Int

    public init(_ kind: SuitShape.Kind,
                colour: Color,
                offsetColour: Color? = nil,
                wobble: Double = 0.012,
                seed: Int = 1) {
        self.kind = kind
        self.colour = colour
        self.offsetColour = offsetColour
        self.wobble = wobble
        self.seed = seed
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                if let offsetColour {
                    SuitShape(kind, wobble: wobble * 1.4, seed: seed &+ 91)
                        .fill(offsetColour)
                        .offset(x: side * 0.028, y: side * 0.022)
                }
                SuitShape(kind, wobble: wobble, seed: seed)
                    .fill(colour)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

import SwiftUI

/// Deterministic pseudo-randomness for artwork.
///
/// Every mark in DECK is generated, and every one of them has to look the same
/// on every redraw — a splatter that moves when the view invalidates is noise,
/// not art direction. This is the same generator the engine uses, kept local so
/// the art layer does not need the engine.
struct ArtRandom {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15
        if state == 0 { state = 0x9E37_79B9_7F4A_7C15 }
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0…1
    mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// -1…1
    mutating func signed() -> Double { unit() * 2 - 1 }

    mutating func range(_ lower: Double, _ upper: Double) -> Double {
        lower + unit() * (upper - lower)
    }

    mutating func chance(_ probability: Double) -> Bool { unit() < probability }
}

/// A torn paper edge.
///
/// One side of the rectangle is replaced by a run of short irregular segments.
/// Used for the poster panels, so a card of content looks like something that
/// was pulled off a pad rather than a rounded rectangle.
public struct TornEdge: Shape {
    public enum Side { case top, bottom, leading, trailing }

    public var side: Side
    /// How deep the tear bites, as a fraction of the shorter dimension.
    public var depth: CGFloat
    public var seed: Int
    /// Roughly how many teeth across the edge.
    public var teeth: Int

    public init(side: Side = .bottom, depth: CGFloat = 0.035, seed: Int = 3, teeth: Int = 26) {
        self.side = side
        self.depth = depth
        self.seed = seed
        self.teeth = teeth
    }

    public func path(in rect: CGRect) -> Path {
        var random = ArtRandom(seed: seed)
        let bite = min(rect.width, rect.height) * depth
        var path = Path()

        func tornRun(from start: CGPoint, to end: CGPoint, normal: CGVector) {
            path.move(to: start)
            let steps = max(6, teeth)
            for index in 1...steps {
                let t = CGFloat(index) / CGFloat(steps)
                let x = start.x + (end.x - start.x) * t
                let y = start.y + (end.y - start.y) * t
                let bump = CGFloat(random.unit()) * bite
                path.addLine(to: CGPoint(x: x + normal.dx * bump, y: y + normal.dy * bump))
            }
        }

        switch side {
        case .bottom:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bite))
            tornRun(from: CGPoint(x: rect.maxX, y: rect.maxY - bite),
                    to: CGPoint(x: rect.minX, y: rect.maxY - bite),
                    normal: CGVector(dx: 0, dy: 1))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        case .top:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + bite))
            tornRun(from: CGPoint(x: rect.maxX, y: rect.minY + bite),
                    to: CGPoint(x: rect.minX, y: rect.minY + bite),
                    normal: CGVector(dx: 0, dy: -1))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .leading:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + bite, y: rect.maxY))
            tornRun(from: CGPoint(x: rect.minX + bite, y: rect.maxY),
                    to: CGPoint(x: rect.minX + bite, y: rect.minY),
                    normal: CGVector(dx: -1, dy: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .trailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - bite, y: rect.maxY))
            tornRun(from: CGPoint(x: rect.maxX - bite, y: rect.maxY),
                    to: CGPoint(x: rect.maxX - bite, y: rect.minY),
                    normal: CGVector(dx: 1, dy: 0))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}

/// A painted brush stroke: a single sweep whose width swells in the middle and
/// tapers at both ends, with a ragged edge.
///
/// Used for underlines, the wipe transition, and the marks that hold a headline
/// down on the page.
public struct PaintStroke: Shape {
    /// How far the stroke bows, as a fraction of its length.
    public var bow: CGFloat
    /// Peak width as a fraction of the rect's height.
    public var weight: CGFloat
    public var seed: Int
    /// 0 draws nothing, 1 draws the whole stroke. Animatable, for the wipe.
    public var progress: CGFloat

    public init(bow: CGFloat = 0.06, weight: CGFloat = 0.7, seed: Int = 5, progress: CGFloat = 1) {
        self.bow = bow
        self.weight = weight
        self.seed = seed
        self.progress = progress
    }

    public var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        guard progress > 0.001 else { return Path() }
        var random = ArtRandom(seed: seed)
        let steps = 24
        let length = rect.width * min(1, progress)
        let midY = rect.midY
        let peak = rect.height * weight / 2

        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        for index in 0...steps {
            let t = CGFloat(index) / CGFloat(steps)
            let x = rect.minX + length * t
            // A brush is thickest a third of the way in, not in the middle.
            let taper = sin(Double(t) * .pi)
            let shaped = CGFloat(pow(taper, 0.65))
            let bowOffset = sin(Double(t) * .pi) * Double(rect.width * bow)
            let ragged = CGFloat(random.signed()) * peak * 0.16
            let halfWidth = peak * shaped
            top.append(CGPoint(x: x, y: midY - halfWidth + CGFloat(bowOffset) + ragged))
            let raggedLower = CGFloat(random.signed()) * peak * 0.16
            bottom.append(CGPoint(x: x, y: midY + halfWidth + CGFloat(bowOffset) + raggedLower))
        }

        var path = Path()
        path.move(to: top[0])
        for point in top.dropFirst() { path.addLine(to: point) }
        for point in bottom.reversed() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

/// A hand-drawn arrow, for pointing at things without an SF Symbol.
public struct InkArrow: Shape {
    public var seed: Int
    public var headSize: CGFloat

    public init(seed: Int = 7, headSize: CGFloat = 0.32) {
        self.seed = seed
        self.headSize = headSize
    }

    public func path(in rect: CGRect) -> Path {
        var random = ArtRandom(seed: seed)
        var path = Path()
        let start = CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.12)
        let end = CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.minY + rect.height * 0.18)
        let control1 = CGPoint(x: rect.minX + rect.width * (0.3 + CGFloat(random.signed()) * 0.05),
                               y: rect.maxY)
        let control2 = CGPoint(x: rect.minX + rect.width * (0.55 + CGFloat(random.signed()) * 0.05),
                               y: rect.minY + rect.height * 0.05)
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)

        // Two short strokes for the head, drawn as though the pen came back.
        let head = min(rect.width, rect.height) * headSize
        path.move(to: end)
        path.addLine(to: CGPoint(x: end.x - head * 0.95, y: end.y + head * 0.18))
        path.move(to: end)
        path.addLine(to: CGPoint(x: end.x - head * 0.22, y: end.y + head * 0.92))
        return path
    }
}

/// A rubber stamp outline: a rough circle or rounded rectangle with breaks in
/// it, the way a real stamp misses the paper.
public struct StampOutline: Shape {
    public enum Form { case circle, block }

    public var form: Form
    public var seed: Int
    /// How much of the outline is missing, 0…0.5.
    public var breakUp: Double

    public init(form: Form = .circle, seed: Int = 11, breakUp: Double = 0.16) {
        self.form = form
        self.seed = seed
        self.breakUp = breakUp
    }

    public func path(in rect: CGRect) -> Path {
        var random = ArtRandom(seed: seed)
        var path = Path()
        let segments = 64

        switch form {
        case .circle:
            let radius = min(rect.width, rect.height) / 2
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            var drawing = false
            for index in 0...segments {
                let angle = Double(index) / Double(segments) * 2 * .pi
                let jitter = 1 + random.signed() * 0.018
                let point = CGPoint(x: centre.x + CGFloat(cos(angle) * Double(radius) * jitter),
                                    y: centre.y + CGFloat(sin(angle) * Double(radius) * jitter))
                if random.chance(breakUp) {
                    drawing = false
                    continue
                }
                if drawing {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    drawing = true
                }
            }
        case .block:
            let inset = rect.insetBy(dx: rect.width * 0.02, dy: rect.height * 0.02)
            let corners = [
                CGPoint(x: inset.minX, y: inset.minY),
                CGPoint(x: inset.maxX, y: inset.minY),
                CGPoint(x: inset.maxX, y: inset.maxY),
                CGPoint(x: inset.minX, y: inset.maxY)
            ]
            for corner in corners.indices {
                let from = corners[corner]
                let to = corners[(corner + 1) % corners.count]
                let steps = 16
                var drawing = false
                for step in 0...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    let jitterX = CGFloat(random.signed()) * inset.width * 0.006
                    let jitterY = CGFloat(random.signed()) * inset.height * 0.006
                    let point = CGPoint(x: from.x + (to.x - from.x) * t + jitterX,
                                        y: from.y + (to.y - from.y) * t + jitterY)
                    if random.chance(breakUp * 0.6) {
                        drawing = false
                        continue
                    }
                    if drawing { path.addLine(to: point) } else { path.move(to: point); drawing = true }
                }
            }
        }
        return path
    }
}

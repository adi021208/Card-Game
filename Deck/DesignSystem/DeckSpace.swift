import SwiftUI

/// The spacing grid.
///
/// Everything in the app is a multiple of four. If a value here does not fit a
/// layout, the layout is wrong — the answer is never a number that is not on
/// this list. The two exceptions in the whole app are documented where they
/// occur (`CardMetrics.cornerRatio` and the hairline rule).
public enum DeckSpace {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48
    public static let xxxl: CGFloat = 64

    /// Standard page inset.
    public static let page: CGFloat = 20
    /// Space between stacked sections on a screen.
    public static let section: CGFloat = 40
}

/// Corner radii.
public enum DeckRadius {
    public static let tight: CGFloat = 4
    public static let button: CGFloat = 8
    public static let panel: CGFloat = 12
    public static let poster: CGFloat = 16
    /// Cards get their radius from `CardMetrics`, which scales it with the card.
    public static let none: CGFloat = 0
}

/// Physical card dimensions.
///
/// A playing card is 2.5 by 3.5 inches. Keeping that exact ratio everywhere is
/// what stops the cards feeling like rounded rectangles with numbers on them.
public enum CardMetrics {
    /// Width divided by height, from the real object.
    public static let aspectRatio: CGFloat = 2.5 / 3.5
    /// Corner radius as a fraction of the card's width. Derived from a real
    /// card's 3.5mm corner on a 63mm card — one of the two values in the app
    /// that is not on the spacing grid, for that reason.
    public static let cornerRatio: CGFloat = 0.055
    /// How far a selected card lifts, as a fraction of its height.
    public static let liftRatio: CGFloat = 0.16
    /// Overlap in a fanned hand, as a fraction of card width.
    public static let fanOverlap: CGFloat = 0.62
    /// Overlap in a solitaire cascade, as a fraction of card height.
    public static let cascadeOverlap: CGFloat = 0.24
    /// Overlap of a face-down cascade, tighter because there is nothing to read.
    public static let cascadeOverlapFaceDown: CGFloat = 0.11

    public static func corner(forWidth width: CGFloat) -> CGFloat {
        max(2, width * cornerRatio)
    }

    public static func height(forWidth width: CGFloat) -> CGFloat {
        width / aspectRatio
    }

    public static func width(forHeight height: CGFloat) -> CGFloat {
        height * aspectRatio
    }
}

/// Shadows. Cards are objects on a table, so their shadows are short and close.
/// There are no soft glows anywhere in the app.
public struct DeckShadow: Equatable {
    public var colour: Color
    public var radius: CGFloat
    public var x: CGFloat
    public var y: CGFloat

    public init(colour: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        self.colour = colour
        self.radius = radius
        self.x = x
        self.y = y
    }

    /// A card lying flat.
    public static let resting = DeckShadow(colour: .black.opacity(0.22), radius: 3, x: 0, y: 2)
    /// A card the player has picked out.
    public static let lifted = DeckShadow(colour: .black.opacity(0.30), radius: 10, x: 0, y: 8)
    /// A card being dragged.
    public static let dragging = DeckShadow(colour: .black.opacity(0.34), radius: 18, x: 0, y: 14)
    /// A panel or poster sitting on the ground.
    public static let panel = DeckShadow(colour: .black.opacity(0.20), radius: 6, x: 0, y: 4)
    /// No shadow.
    public static let none = DeckShadow(colour: .clear, radius: 0, x: 0, y: 0)
}

public extension View {
    func deckShadow(_ shadow: DeckShadow) -> some View {
        self.shadow(color: shadow.colour, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

import SwiftUI

/// The DECK type system.
///
/// Two families, used very differently. **Display** is the system font at its
/// heaviest weight and narrowest width, set enormous with negative tracking —
/// that is what makes a poster read as a poster without shipping a licensed
/// typeface. **Interface** is plain system type, because a settings row should
/// look like a settings row.
///
/// There is no third family and no decorative font. The personality comes from
/// scale, weight, width and tracking, not from variety.
public enum DeckType {

    // MARK: - Display

    /// Poster type: game titles, the streak number, result headlines.
    /// Compressed and black, tracked in tight so the letterforms lock together.
    public static func display(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .black).width(.compressed)
    }

    /// Slightly wider display, for two- or three-word titles that need air.
    public static func displayCondensed(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .black).width(.condensed)
    }

    /// Expanded display, used sparingly for a single word carrying a whole screen.
    public static func displayExpanded(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .heavy).width(.expanded)
    }

    /// Big numbers: streaks, scores, chip counts, timers.
    /// Rounded because a number should feel like an object, not a label.
    public static func numeral(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .black, design: .rounded)
    }

    /// Numbers that have to line up in a column.
    public static func tabular(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    // MARK: - Interface

    public static let title = Font.system(size: 22, weight: .bold)
    public static let heading = Font.system(size: 17, weight: .semibold)
    public static let body = Font.system(size: 16, weight: .regular)
    public static let bodyEmphasis = Font.system(size: 16, weight: .semibold)
    public static let caption = Font.system(size: 13, weight: .medium)
    public static let footnote = Font.system(size: 12, weight: .regular)

    /// The one small-caps treatment in the app, reserved for the label attached
    /// to a large number. Not an eyebrow above a headline.
    public static let unit = Font.system(size: 12, weight: .heavy).width(.condensed)

    /// Card corner pips.
    public static func pip(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .bold, design: .rounded)
    }

    // MARK: - Tracking

    /// Display type is set tight; the bigger it is, the tighter it goes.
    public static func displayTracking(for size: CGFloat) -> CGFloat {
        -size * 0.035
    }

    public static let unitTracking: CGFloat = 1.4
}

/// Poster type, correctly tracked and clamped so a large accessibility setting
/// does not push a headline off the screen.
public struct DisplayText: View {
    private let text: String
    private let size: CGFloat
    private let width: Width
    private let colour: Color?

    public enum Width { case compressed, condensed, expanded }

    public init(_ text: String, size: CGFloat, width: Width = .compressed, colour: Color? = nil) {
        self.text = text
        self.size = size
        self.width = width
        self.colour = colour
    }

    public var body: some View {
        Text(text)
            .font(font)
            .tracking(DeckType.displayTracking(for: size))
            .foregroundStyle(colour ?? Color.primary)
            .lineSpacing(-size * 0.14)
            .minimumScaleFactor(0.6)
            // Display type carries composition, not content, so it scales with
            // Dynamic Type only up to a point; the readable copy underneath it
            // scales all the way.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var font: Font {
        switch width {
        case .compressed: return DeckType.display(size)
        case .condensed: return DeckType.displayCondensed(size)
        case .expanded: return DeckType.displayExpanded(size)
        }
    }
}

/// A big number with its unit set underneath it, which is the only place the app
/// uses a small all-caps label.
public struct NumeralBlock: View {
    private let value: String
    private let unit: String
    private let size: CGFloat
    private let colour: Color
    private let unitColour: Color
    private let alignment: HorizontalAlignment

    public init(value: String,
                unit: String,
                size: CGFloat = 64,
                colour: Color,
                unitColour: Color? = nil,
                alignment: HorizontalAlignment = .leading) {
        self.value = value
        self.unit = unit
        self.size = size
        self.colour = colour
        self.unitColour = unitColour ?? colour.opacity(0.7)
        self.alignment = alignment
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: DeckSpace.xs) {
            Text(value)
                .font(DeckType.numeral(size))
                .tracking(-size * 0.03)
                .foregroundStyle(colour)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(unit)
                .font(DeckType.unit)
                .tracking(DeckType.unitTracking)
                .textCase(.uppercase)
                .foregroundStyle(unitColour)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(unit)")
    }
}

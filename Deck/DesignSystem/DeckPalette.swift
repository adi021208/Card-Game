import SwiftUI

/// The DECK palette.
///
/// Nine colours, all of them chosen for print rather than for screens: warm
/// blacks, paper creams, and inks that look like they came off a press. Nothing
/// here glows, and there is deliberately no violet.
public enum DeckPalette {
    // MARK: - Inks

    /// Not pure black. Pure black looks like a hole; this looks like ink.
    public static let ink = Color(red: 0.055, green: 0.051, blue: 0.047)
    public static let inkSoft = Color(red: 0.129, green: 0.122, blue: 0.114)
    public static let inkLight = Color(red: 0.239, green: 0.227, blue: 0.212)

    // MARK: - Papers

    /// The default ground. Warm, slightly uneven, like uncoated stock.
    public static let cream = Color(red: 0.949, green: 0.914, blue: 0.847)
    public static let newsprint = Color(red: 0.910, green: 0.878, blue: 0.808)
    public static let chalk = Color(red: 0.984, green: 0.969, blue: 0.937)

    // MARK: - Colours

    public static let vermilion = Color(red: 0.890, green: 0.227, blue: 0.129)
    public static let crimson = Color(red: 0.690, green: 0.063, blue: 0.188)
    public static let cobalt = Color(red: 0.106, green: 0.216, blue: 0.769)
    public static let electric = Color(red: 0.129, green: 0.396, blue: 0.965)
    public static let acid = Color(red: 0.894, green: 0.882, blue: 0.102)
    public static let coral = Color(red: 1.000, green: 0.416, blue: 0.333)
    public static let forest = Color(red: 0.059, green: 0.310, blue: 0.220)
    public static let orange = Color(red: 0.941, green: 0.475, blue: 0.118)

    /// Resolves a palette token used by the engine (bosses, cosmetics) into a colour.
    public static func token(_ name: String) -> Color {
        switch name {
        case "ink": return ink
        case "inkSoft": return inkSoft
        case "cream": return cream
        case "newsprint": return newsprint
        case "chalk": return chalk
        case "vermilion": return vermilion
        case "crimson": return crimson
        case "cobalt": return cobalt
        case "electric": return electric
        case "acid": return acid
        case "coral": return coral
        case "forest": return forest
        case "orange": return orange
        default: return vermilion
        }
    }

    /// The full set, in the order the collection screen shows them.
    public static let all: [(name: String, colour: Color)] = [
        ("ink", ink), ("cream", cream), ("vermilion", vermilion), ("cobalt", cobalt),
        ("acid", acid), ("coral", coral), ("forest", forest), ("orange", orange),
        ("crimson", crimson)
    ]
}

/// A resolved theme: the palette a screen actually draws with.
///
/// Themes change the ground, the ink and the accent, but every one of them still
/// uses the same nine colours and the same textures, so the app never stops
/// looking like itself.
public struct DeckTheme: Equatable, Sendable {
    public var id: String
    /// The page.
    public var ground: Color
    /// The layer above the page: cards, panels, posters.
    public var surface: Color
    /// Type and line work.
    public var ink: Color
    /// Secondary type.
    public var inkMuted: Color
    /// The loud one.
    public var accent: Color
    /// The second loud one, used for contrast in compositions.
    public var accentAlt: Color
    /// Warning and pressure states.
    public var alert: Color
    /// Positive states.
    public var positive: Color
    /// How much paper grain to lay over everything, 0…1.
    public var grain: Double
    /// True when the ground is dark, so components can flip their contrast.
    public var isDark: Bool

    public init(id: String,
                ground: Color,
                surface: Color,
                ink: Color,
                inkMuted: Color,
                accent: Color,
                accentAlt: Color,
                alert: Color,
                positive: Color,
                grain: Double,
                isDark: Bool) {
        self.id = id
        self.ground = ground
        self.surface = surface
        self.ink = ink
        self.inkMuted = inkMuted
        self.accent = accent
        self.accentAlt = accentAlt
        self.alert = alert
        self.positive = positive
        self.grain = grain
        self.isDark = isDark
    }

    /// Black ground, cream paper, red spray, blue stencil. The default.
    public static let streetPrint = DeckTheme(
        id: "theme.streetPrint",
        ground: DeckPalette.ink,
        surface: DeckPalette.cream,
        ink: DeckPalette.ink,
        inkMuted: DeckPalette.inkLight,
        accent: DeckPalette.vermilion,
        accentAlt: DeckPalette.cobalt,
        alert: DeckPalette.vermilion,
        positive: DeckPalette.acid,
        grain: 0.10,
        isDark: true)

    /// Warm paper, bold ink outlines, yellow accents.
    public static let sundayComic = DeckTheme(
        id: "theme.sundayComic",
        ground: DeckPalette.newsprint,
        surface: DeckPalette.chalk,
        ink: DeckPalette.ink,
        inkMuted: DeckPalette.inkLight,
        accent: DeckPalette.coral,
        accentAlt: DeckPalette.acid,
        alert: DeckPalette.vermilion,
        positive: DeckPalette.forest,
        grain: 0.14,
        isDark: false)

    /// Cream, black type, red stamps. Museum catalogue.
    public static let archive = DeckTheme(
        id: "theme.archive",
        ground: DeckPalette.cream,
        surface: DeckPalette.chalk,
        ink: DeckPalette.ink,
        inkMuted: DeckPalette.inkLight,
        accent: DeckPalette.crimson,
        accentAlt: DeckPalette.inkSoft,
        alert: DeckPalette.crimson,
        positive: DeckPalette.forest,
        grain: 0.08,
        isDark: false)

    /// A dark table with acid highlights, for playing at night.
    public static let midnight = DeckTheme(
        id: "theme.midnight",
        ground: Color(red: 0.043, green: 0.075, blue: 0.063),
        surface: DeckPalette.cream,
        ink: DeckPalette.ink,
        inkMuted: DeckPalette.inkLight,
        accent: DeckPalette.acid,
        accentAlt: DeckPalette.coral,
        alert: DeckPalette.coral,
        positive: DeckPalette.acid,
        grain: 0.12,
        isDark: true)

    public static let all: [DeckTheme] = [streetPrint, sundayComic, archive, midnight]

    public static func theme(_ id: String) -> DeckTheme {
        all.first { $0.id == id } ?? streetPrint
    }

    /// Type colour that sits on the ground rather than on a card.
    public var onGround: Color { isDark ? DeckPalette.cream : DeckPalette.ink }
    public var onGroundMuted: Color {
        isDark ? DeckPalette.cream.opacity(0.62) : DeckPalette.ink.opacity(0.58)
    }
}

private struct DeckThemeKey: EnvironmentKey {
    static let defaultValue = DeckTheme.streetPrint
}

public extension EnvironmentValues {
    var deckTheme: DeckTheme {
        get { self[DeckThemeKey.self] }
        set { self[DeckThemeKey.self] = newValue }
    }
}

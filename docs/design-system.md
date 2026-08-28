# The design system

Everything visual comes from four token files. If a value is not in one of them,
it does not go in a view.

```
Deck/DesignSystem/
  DeckPalette.swift     nine colours, four themes
  DeckTypography.swift  two families, one scale
  DeckSpace.swift       a 4pt grid, radii, card geometry, shadows
  DeckMotion.swift      durations, springs, controlled imperfection
```

## Colour

Nine colours, chosen for print rather than for screens.

| Token | What it is |
|---|---|
| `ink`, `inkSoft`, `inkLight` | Warm blacks. Not `#000` — pure black reads as a hole, this reads as ink. |
| `cream`, `newsprint`, `chalk` | Papers. The default ground is uncoated stock, not white. |
| `vermilion`, `crimson` | The reds. Vermilion is the app's accent. |
| `cobalt`, `electric` | The blues. |
| `acid`, `coral`, `forest`, `orange` | The rest of the poster palette. |

There is **no violet**, no gradient stop that fades to transparent, and no glow.
`DeckPalette.token(_:)` resolves the string tokens the engine uses (a boss's
colour, a cosmetic's palette) so `DeckProgression` never imports SwiftUI.

Four themes — Street Print, Sunday Comic, Archive, Midnight — recombine the same
nine colours. A theme changes the ground, the ink and the accent; it does not
introduce new hues.

Status is never carried by colour alone. Every state that matters also has a
mark, a weight, or a word.

## Type

Two families, used very differently.

- **Display** — the system font at `.black` weight and `.compressed` width, set
  large with tight tracking. That is what makes a poster read as a poster
  without licensing a typeface. `display`, `displayCondensed`,
  `displayExpanded`.
- **Numerals** — `.rounded` and black for the big numbers (streaks, scores,
  chips); `tabular` for anything that has to line up in a column.
- **Interface** — plain system type at `title` / `heading` / `body` /
  `bodyEmphasis` / `caption` / `footnote`. A settings row should look like a
  settings row.

There is no third family and no decorative font. All the personality comes from
scale, weight, width and tracking.

`DeckType.unit` is the one small-caps treatment in the app, and it is reserved
for the label attached to a large number — a unit, never an eyebrow above a
headline.

Everything scales with Dynamic Type. Display sizes are clamped so a poster
headline stays a poster at the largest accessibility sizes instead of
reflowing into a paragraph.

## Space

Everything is a multiple of four: `4 8 12 16 24 32 48 64`, plus `page` (20) and
`section` (40). There is no 13, no 15, no 17, no 19 anywhere in the app.

Exactly two values in the codebase are off the grid, both documented where they
occur:

- `CardMetrics.cornerRatio` (0.055) — derived from a real card's 3.5mm corner on
  a 63mm card.
- the hairline rule, which is one device pixel by definition.

`CardMetrics` keeps the real 2.5:3.5 card ratio everywhere, along with the lift
distance, the fan overlap and the two cascade overlaps. That ratio is why the
cards feel like cards and not like rounded rectangles with numbers on them.

Shadows are short and close, because a card is an object on a table. There are
no soft glows.

## Motion

Durations: `instant` 0.12, `quick` 0.22, `standard` 0.34, `deliberate` 0.55,
plus `seal` and `reveal` for the privacy handshake and `dealStep` for the
per-card stagger.

Springs are named for what they are: `cardSettle`, `cardLift`, `cardReturn`,
`deal`, `flip`, `wipe`, `panel`, `count`, `stamp`, `select`.

`DeckMotion.settledAngle(seed:)` and `settledOffset(seed:)` provide the
controlled imperfection — a card that has landed sits a degree or two off
square. It is **seeded**, so it is stable: the same card does not twitch every
time the view redraws.

`respectingReduceMotion(_:reduced:)` is the single gate. Reduced motion removes
movement; it never removes a step. The Pass & Play confirmation still has to be
tapped.

## Signature transitions

`Deck/Components/Transitions.swift` holds the ones that carry meaning:

| Transition | Means |
|---|---|
| Deck flip | you have changed game |
| Card cascade | a result is being laid out |
| Paint wipe | you have moved between major areas |
| Paper tear | something has been discarded or dismissed |
| Shuffle | the app is genuinely working, in place of a spinner |
| Stamp | this is finished — a completed day, a won game |
| Suit transform | a suit has been named or changed |

They appear where they mean something and nowhere else.

## Art

`Deck/Art/` is procedural, drawn with `Canvas` and `Shape` from a seeded
`ArtRandom`, so nothing is a shipped bitmap and nothing is a stock asset:

- `SuitShapes` — the four suits as real bezier stencils, not glyphs.
- `CardFaceArt` / `CardBackArt` — faces and the collectable backs.
- `Textures` — paper grain, torn edges, halftone, spray, misregistration.
- `Marks`, `Emblems`, `DeckMark` — the app's own marks and achievement emblems.
- `GameCoverArt` — a distinct composition per game, keyed by `artworkID`.
- `BossPortrait` — the seven, each built from its own palette and idle.

## The list of things this app does not do

Checked against §198–§199 of the brief, and against the code:

- no purple gradients — there is no violet in the palette
- no glow — shadows are short and opaque
- no floating glass containers — panels are printed, on the ground
- no all-caps eyebrow above a generic sans headline on every screen — `unit` is
  the only small-caps token and it labels numbers
- no pill soup — status is a mark or a word
- no random ONLINE / NEW / LIVE badges
- no 1px-border selection states — a selected card lifts, grows and casts a
  longer shadow, which is what picking a card up looks like
- no token drift — the grid is 4pt with two documented exceptions
- no generic empty, loading and error states — `StateViews` are composed and
  specific, and the loading state is a shuffling deck
- no particle effects standing in for design
- no glassmorphism
- no dashboard grid of equal cards

Loud visually, quiet functionally.

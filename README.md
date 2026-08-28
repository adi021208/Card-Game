# DECK

**ONE DECK. EVERY GAME.**

A card-game platform for iPhone and iPad. One card engine, one rules protocol,
one turn system, one AI framework, one Pass & Play privacy coordinator, one
progression system — and fifteen games plugged into all of it.

Adding the fiftieth game is a module. It is not a rewrite.

## The library

| | | |
|---|---|---|
| **Poker** | Texas Hold'em | real blinds, streets, side pots, showdowns |
| **Trick taking** | Hearts, Spades, Euchre | passing, nil bids, bags, bowers, going alone |
| **Rummy** | Gin Rummy, Rummy | an exact minimum-deadwood solver, knocks, undercuts, lay-offs |
| **Shedding** | Crazy Eights, President | wild eights, bombs, rank completion, the exchange |
| **Solitaire** | Klondike, FreeCell, Spider | the real lift formula, one, two and four suits |
| **Family** | Go Fish, War | books, asks that everyone hears, wars that stake three each |
| **Bluff** | Cheat | a pile nobody may look at, calls that cost you |
| **Speed** | Speed | simultaneous play, no turn order |

Every one is the real game, with the rules people argue about at a table
implemented rather than smoothed over.

## Pass & Play

The differentiating feature, and the one that would be easiest to fake.

It is not a screen that covers the cards. Permission lives in the game state:
a card carries a `Visibility`, the board is redacted for a viewer before
anything reaches the interface, and a card the viewer may not see arrives at
the renderer as `.concealed(id)` — a value with no face inside it. There is
nothing to draw and nothing for VoiceOver to read out.

Between players the app stops interaction, settles any temporary peek, removes
private information from the view hierarchy, shows **PASS TO ⟨NAME⟩**, waits for
a deliberate confirmation, and only then reveals that player's information.
Backgrounding the app re-seals it. Reduced motion removes the movement and
keeps the confirmation, because the confirmation is the guarantee.

## Everything else that is real

- **Poker** — dealer button, blinds, four streets, correct betting including
  all-ins and layered side pots, showdown with kickers, split pots and the odd
  chip. The AI estimates equity by Monte Carlo over *unseen* cards only.
- **AI** — seven personalities (Hal, Pedro, Calvin, Rohan, Shayla, Honey,
  Scarlet) sharing one `AIProfile` of behavioural dials. Difficulty changes
  decision quality — search depth, sampling budget, error rate — and never
  changes what an opponent can see. Agents receive a rules-built `Observation`
  and cannot reach the state.
- **Daily challenges** — deterministic from the date, so everyone playing the
  day gets the identical deal, boss, difficulty and objective. Difficulty runs
  −50% to +200% and is real. Three free attempts a day; a day counts once, so a
  streak cannot be farmed.
- **Bosses** — the same seven, each with a portrait, an idle, lore, a colour and
  a modifier that changes the actual configuration, explained before you start.
- **Progression** — statistics that fold by each game's own declaration,
  achievements defined as data, five mastery bands, a collection of 31 earned
  and premium pieces.
- **Persistence** — versioned, validated, migrated, written atomically. A save
  refuses to load into a different game or a different rules version rather than
  reconstructing something plausible.
- **Replay** — seed plus the ordered list of action tokens reproduces the game.

## Building

```
open Deck.xcodeproj
```

Xcode 16, iOS 17, iPhone and iPad. `DeckEngine` is a local Swift package with
five library targets and five test targets; the app target depends on all five.
There are no third-party dependencies.

```
⌘U                                    run the whole suite
swift test --package-path DeckEngine  run the engine suite alone
```

## Layout

```
Deck/                    the app: SwiftUI, design system, procedural art
DeckEngine/Sources/
  DeckCore/              cards, board, visibility, rules protocol, session,
                         privacy coordinator, seeded randomness, persistence
  DeckGames/             fifteen GameRules implementations
  DeckAI/                per-game agents over a shared profile and selector
  DeckCatalog/           the registry that binds rules to agents
  DeckProgression/       statistics, achievements, dailies, bosses, collection
DeckEngine/Tests/        five suites, one per target
docs/                    architecture, adding a game, the design system
tools/                   swiftcheck.py, make_appicon.py
```

## Documentation

- [Architecture](docs/architecture.md) — the layers, the rules protocol, how the
  privacy guarantee is enforced structurally, determinism, the save format.
- [Adding a game](docs/adding-a-game.md) — the checklist, end to end, with a
  worked example.
- [The design system](docs/design-system.md) — the four token files, the
  signature transitions, the procedural art, and the list of things this app
  deliberately does not do.

## Art direction

Bold editorial print: screen-print, spray, collage, oversized compressed type,
paper and ink texture, and imperfection that is seeded so it holds still. Nine
colours chosen for press rather than for screens. No purple gradients, no glow,
no floating glass, no pill soup, no dashboard grid.

Loud visually, quiet functionally.

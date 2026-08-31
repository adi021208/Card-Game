# Adding a game

The whole point of the architecture is that this is a checklist, not a project.
Nothing in the app target changes. Nothing in `DeckCore` changes. You write one
rules file, one agent, one catalogue entry, and one block of strings.

Working example throughout: a hypothetical **Oh Hell**.

## 1. The rules — `DeckGames/TrickTaking/OhHell.swift`

Conform to `GameRules`. The three associated types are yours to define:

```swift
public struct OhHellRules: GameRules {
    public static let gameID = GameID.ohHell
    public static let rulesVersion = 1

    public struct State: GameStateProtocol {
        public var board: Board            // required
        public var activeSeat: SeatID?     // required
        public var roundNumber: Int        // required
        public var finalResult: GameResult? // required
        // …everything else your game needs, all Codable
    }

    public enum Action: Hashable, Sendable { case bid(Int), play(CardID) }
    public struct Observation: Sendable { /* what an opponent may know */ }
}
```

### `setup(configuration:generator:)`

Build the `Board`, deal from the shuffled deck, `ensureZones` for every pile the
table will show (including empty ones, so the renderer draws their slots).
Use the `generator` you are given and nothing else — no `Int.random`, no
`Date()`, no `UUID()` anywhere in a rules file.

Deal into a hand with `facing: .hand(seat)`. That single call is what makes the
card private to that seat for the rest of the game.

### `legalActions(in:for:)` and `rejection(for:in:)`

`legalActions` is the menu; `rejection` is the door. They must agree: every
action `legalActions` returns must get `nil` from `rejection`. There is a test
in every game suite that checks this, and one in `CatalogTests` that checks it
across the whole library.

`rejection` returns a structured `IllegalMove` with a reason code and an English
fallback, never `nil`-for-"no". Add the reason to `Localizable.strings` as
`illegal.<reason>`.

### `apply(_:to:generator:)`

Mutate the state and return `[GameEvent]`. Events are how the app gets sound,
haptics and animation without knowing your game:

```swift
events.append(.cardPlayed(card: id, by: seat, to: .trick))
events.append(.trickCompleted(winner: seat, cards: cards))
events.append(.highlight(code: "ohHell.exactBid", seat: seat, value: nil))
```

`highlight` codes are yours. Achievements consume them by name.

### `advanceAutomatically(_:generator:)`

Everything that happens without a player deciding: scoring a deal, dealing the
next one, sweeping a pile. The session calls it repeatedly until it returns an
empty array, so it must reach a fixed point.

### `token(for:in:)` and `decodeAction(id:in:)`

The replay format. Build ids with `TokenID.make(seat, verb, …)` and parse them
back. `decodeAction` must round-trip every token `token(for:)` can produce —
including a poker raise to an arbitrary amount, which is why decoding is a
protocol requirement and not a search over the legal-move list.

### `observation(of:for:)`

**Exactly** what that seat is entitled to know: their own cards, public piles,
counts of other hands, and public history. Never another player's hand. There
is a test for this in every game suite.

### `presentation(of:for:seating:)`

Lay the table out. `TableBuilder` has helpers for the common shapes; go through
`state.board.redacted(for: viewer)` and never around it.

### `hint(for:seat:)`

Explain the reason. "You are void in hearts, so this is the trick to take" —
not "PLAY THIS CARD".

## 2. The agent — `DeckAI/Agents/OhHellAgent.swift`

```swift
public enum OhHellAgent {
    public static func choose(observation: OhHellRules.Observation,
                              legalActions: [OhHellRules.Action],
                              profile: AIProfile,
                              generator: inout SeededGenerator) -> OhHellRules.Action? {
        guard legalActions.count > 1 else { return legalActions.first }
        let scored = legalActions.map { ScoredMove(action: $0, score: evaluate($0, observation)) }
        return AISelector.choose(scored, profile: profile, generator: &generator)
    }
}
```

Score the moves as well as you can and let `AISelector` decide how faithfully
that evaluation is followed. That is where difficulty lives, and keeping it
there is what stops difficulty from becoming "add noise".

Read the profile properly. `aggression`, `riskTolerance` and `bluffFrequency`
should change what the agent *wants*; `memoryStrength` should gate what it is
allowed to remember about public history; `planningDepth` should change how far
it looks. An agent that ignores the profile makes seven identical opponents.

The observation is all you get. There is no back door to `State`, and adding one
would be caught by `AgentTests`.

## 3. The catalogue entry — `DeckCatalog/GameCatalog.swift`

```swift
public static func ohHell() -> GameDefinition {
    let plumbing = GameFactory.session(OhHellRules(), agent: OhHellAgent.choose)
    return GameDefinition(
        id: .ohHell,
        nameKey: "game.ohHell.name",
        englishName: "Oh Hell",
        taglineKey: "game.ohHell.tagline",
        descriptionKey: "game.ohHell.description",
        categories: [.trickTaking],
        playerRange: 3...7,
        duration: .medium,
        complexity: .medium,
        deckConfiguration: .standard52,
        variants: […],
        setupOptions: […],
        artworkID: "cover.ohHell",
        searchTerms: ["oh hell", "blackout", "nomination whist"],
        statistics: […],        // how your metrics fold
        achievements: […],      // data, not code
        tutorial: Tutorials.ohHell,
        recommendations: [.hearts, .spades],
        defaultOptions: ["targetRounds": 10],
        makeSession: plumbing.make,
        restoreSession: plumbing.restore)
}
```

Add it to `makeRegistry()`. That is the whole integration: the home screen,
search, filters, the daily-challenge picker, statistics, achievements, mastery
and the collection all read the registry, so the game appears everywhere at
once.

Solitaires use `GameFactory.soloSession(_:)` and set `supportsAIOpponents: false`,
`supportsPassAndPlay: false`, `supportsUndo: true`.

### Statistics are a declaration

```swift
StatisticDefinition(key: OhHellStatistics.exactBids,
                    titleKey: "stat.ohHell.exactBids",
                    aggregation: .total,
                    isHeadline: true)
```

`StatisticsEngine` has no idea what an exact bid is. It reads the aggregation
and folds the number. Adding a game never edits the statistics engine.

### Achievements are data

```swift
AchievementDefinition(id: "ohHell.perfectRound",
                      titleKey: "ach.ohHell.perfect",
                      descriptionKey: "ach.ohHell.perfect.desc",
                      category: .skill,
                      tracking: .highlight(code: "ohHell.exactBid", gameID: .ohHell),
                      targetOverride: 20,
                      emblem: .bolt)
```

Achievement ids must be unique across the whole library — there is a test.

## 4. Strings — `Deck/Resources/en.lproj/Localizable.strings`

Every key you invented: the name, tagline, description, variant names and
summaries, option titles, statistic titles, achievement titles and
descriptions, tutorial steps, illegal-move reasons, highlight codes and hint
messages. No user-facing English belongs in a Swift file.

## 5. Tests — `DeckEngine/Tests/DeckGamesTests/OhHellTests.swift`

Copy the shape the other games use:

- the deal is the right size and the whole deck is accounted for
- the rules that are easy to get wrong, stated as their own tests
- an illegal move returns the reason you meant it to
- the game reaches a result from a blunt play-out (`TestTable.playOut`)
- `observation(of:for:)` never names another player's card

`CatalogTests` will then automatically check that your game deals, offers legal
moves, finishes, checkpoints, restores, hands the AI a move in every seat, and
hides each hand from everybody else.

## What you do not touch

The home screen. The library grid. Navigation. The design system. The privacy
coordinator. The session. The statistics engine. The achievement engine. The
save format. If adding a game seems to require editing one of those, the
abstraction is wrong and the fix belongs there rather than in the game.

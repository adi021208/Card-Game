# Architecture

DECK is a platform, not a collection of games. One card engine, one rules
protocol, one turn system, one AI framework, one privacy coordinator, one
progression system — and fifteen games plugged into them. The fiftieth game
should be a module, not a rewrite.

## The layers

```
┌───────────────────────────────────────────────────────────┐
│  Deck (app target)                                        │
│  SwiftUI views, design system, art, sound, haptics,        │
│  navigation, StoreKit and GameKit adapters                │
└───────────────────────────────────────────────────────────┘
                          ▲   reads TablePresentation
                          │   sends ActionToken
┌───────────────────────────────────────────────────────────┐
│  DeckProgression   statistics, achievements, mastery,      │
│                    daily challenges, bosses, collection,   │
│                    entitlements, the save store            │
├───────────────────────────────────────────────────────────┤
│  DeckCatalog       the registry: fifteen GameDefinitions,  │
│                    each binding a rules type to its agent  │
├───────────────────────────────────────────────────────────┤
│  DeckAI            per-game agents over a shared           │
│                    AIProfile / AISelector                  │
├───────────────────────────────────────────────────────────┤
│  DeckGames         fifteen implementations of GameRules    │
├───────────────────────────────────────────────────────────┤
│  DeckCore          cards, board, zones, visibility,        │
│                    seeded randomness, the rules protocol,  │
│                    the session, the privacy coordinator,   │
│                    versioned persistence                   │
└───────────────────────────────────────────────────────────┘
```

Dependencies point downwards only. `DeckCore` imports nothing but Foundation —
in particular it does not import SwiftUI, so a card is a value and not a view.

## Rules laid down and kept

- **No gameplay logic in views.** A view receives a `TablePresentation` and
  emits an `ActionToken`. It cannot compute a legal move, score a hand, or
  decide who won.
- **No scoring in views.** Scores arrive in `GameResult` and in `GameEvent`.
- **No AI in UI code.** `GameSession.aiMove(for:)` is the only door, and what
  goes through it is an `Observation`, never a `State`.
- **No hard-coded library.** The home screen reads `GameRegistry`.

## The rules protocol

Every game is a reducer:

```swift
public protocol GameRules: Sendable {
    associatedtype State: GameStateProtocol
    associatedtype Action: Hashable, Sendable
    associatedtype Observation: Sendable

    func setup(configuration:generator:) -> State
    func legalActions(in:for:) -> [Action]
    func rejection(for:in:) -> IllegalMove?
    func apply(_:to:generator:) -> [GameEvent]
    func token(for:in:) -> ActionToken
    func decodeAction(id:in:) -> Action?
    func observation(of:for:) -> Observation
    func presentation(of:for:seating:) -> TablePresentation
    func advanceAutomatically(_:generator:) -> [GameEvent]
    func hint(for:seat:) -> Hint?
}
```

Three of those exist purely to keep information where it belongs:

- `observation(of:for:)` is what an AI is allowed to know.
- `presentation(of:for:seating:)` is what a *viewer* is allowed to see, and it
  goes through `Board.redacted(for:)`.
- `token(for:in:)` / `decodeAction(id:in:)` are the replay format. Seed plus the
  ordered list of token ids reproduces the game exactly.

`GameSession<Rules>` erases the associated types behind `GameSessionProtocol` so
the app can hold "a game" without knowing which one.

## Privacy is structural, not cosmetic

This is the part that would be easiest to fake and is not faked.

```
Visibility ──▶ Board.redacted(for:) ──▶ RedactedBoard ──▶ VisibleCard ──▶ CardView
  .everyone                             piles of          .known(Card)     draws a face
  .seats([…])                           VisibleCard       .concealed(id)   draws a back
  .hidden
  .temporarilyRevealed(to:restoring:)
```

A card the viewer may not see arrives at the view as `.concealed(id)`. There is
no `Card` inside that value. The renderer has no face to draw, and
`CardView.accessibilityLabel` — built from the same value — has no rank or suit
to speak. VoiceOver cannot leak what the eyes cannot see, because there is
nothing there to leak.

`PrivacyPhase.viewer` is computed, and returns `nil` for `.sealing`,
`.handoff` and `.concluded`. There is no code path that renders a hand while the
device is in transit.

## The handoff

`PrivacyCoordinator` runs the ritual and emits `PrivacyDirective`s; the
`GameCoordinator` performs them.

```
turn ends
   │
   ├─ next seat is an AI, or the same human ─▶ nothing happens
   │
   └─ next seat is a different human
        .clearInteraction     stop input, drop selections and overlays
        .settleReveals        any temporary peek goes back to hidden
        .sealCards(duration)  private information leaves the view hierarchy
        .presentHandoff(to:)  PASS TO ⟨NAME⟩, waiting for a deliberate tap
        .revealHand(seat:)    only now, and only that seat's information
        .resumePlay(seat:)
```

Reduced motion zeroes the durations. It never removes the confirmation step,
because that step is the privacy guarantee and not an animation.

Backgrounding calls `shield()`, which re-enters the sealed phase and requires
another confirmation on return.

## Determinism

`SeededGenerator` is SplitMix64. `SeedFactory` derives seeds with FNV-1a from
string components, so a daily challenge seed is a pure function of

```
challenge date + game id + rules version + challenge version
```

Two devices in different time zones that resolve to the same calendar day get
byte-identical challenges. A replay months later gets the same one again.

AI deliberation runs on `generator.branch(salt:)` — a *copy*. How long an
opponent thinks, and how much randomness it burns doing so, cannot change what
anybody is dealt. There is a test for exactly that.

## Persistence

```
save:  validate ──▶ encode ──▶ VersionedRecord{schemaVersion, revision, writtenAt}
                           ──▶ atomic write

load:  read envelope ──▶ newer than we understand?  refuse
                     ──▶ older?  migrate, then validate
                     ──▶ same?   decode, then validate
```

A `GameCheckpoint` carries the game id, the rules version, the configuration
(including the seed), the encoded state, the replay log, the turn count and the
elapsed clock. Restoring refuses a checkpoint from a different game or a
different rules version rather than reconstructing something plausible.

`RecordStore.loadAll` skips a file that will not decode, so one corrupt save
cannot take out the list it lives in.

## Events

Rules emit `GameEvent`s. The `GameCoordinator` maps them to sound and haptics
with no game-specific code anywhere in the mapping — a new game gets audio for
free by emitting the same events.

## Testing

`DeckEngine/Tests` holds five suites, one per target. They cover the session
contract, persistence and migration, every game's rules, the exact meld solver,
the poker evaluator and pot solver, the AI's legality and personality
differences, the registry, and the whole progression system. The six named
Pass & Play tests live in `DeckCoreTests/PrivacyCoordinatorTests.swift`.

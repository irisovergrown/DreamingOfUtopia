# Dreaming of Utopia — Project Context

This file loads automatically at the start of every Claude Code session in
this repo. Read it fully before writing any code. It is the persistent
memory for a project being developed across multiple machines (main PC,
laptop, work computer) and multiple Claude sessions (cloud/web and local).

> **⚠ Read `docs/HANDOFF.md` first (2026-09-12).** It is the verified, current
> handoff: what exists, how to verify it, every known gap, and the ordered next
> steps. Parts of THIS file still describe the pre-rebuild game — notably the
> "Current implementation state" entries for RulesConfig, EraData, Movement,
> CardData, CardService, Economy, Battle, MatchService, Remotes, Main,
> UIService and CameraService, plus the "Already authored" and "Not yet built"
> paragraphs. Where this file and HANDOFF.md disagree, trust HANDOFF.md (and the
> code over both). The milestone narrative from "Target architecture and
> milestones" onward is accurate.
>
> **⚠ Overriding specs (2026-09-12), in HANDOFF.md §0.4:** the Claude Design
> project (https://claude.ai/design/p/49d87599-1913-480b-86b4-a690cfca2bbd)
> overrides everything here and in the code; UI must be **real authored GUI
> instances, never built in code**, with **image slots** (asset ids) for anything
> that could be an image; and the developer has their own card-setup design —
> **ask before touching the card pipeline**.

## What this is

A Roblox board/card game inspired by Culdcept Saga (Xbox 360, OmiyaSoft) — a
Monopoly-meets-Magic:-The-Gathering hybrid. No prior Roblox version of this
concept exists. Game name: **Dreaming of Utopia**.

## Core gameplay reference (adapted from Culdcept Saga)

This is the mechanical skeleton the game is built from. Treat exact numbers
as a tunable starting point, not final balance — they're reconstructed from
community formula sheets for an older console game, not our own spec yet.

- Board loop: players ("Cepters") roll dice, move around a board, land on tiles.
- Claiming tiles: summon a creature card onto an unclaimed/enemy tile. Land
  bonus: same-element creature on matching tile gets +10 HP × tile level.
- Landing on an owned tile: pay toll, or challenge with your own creature
  (ST vs HP/defense compare) — winner takes the tile.
- Tile leveling: levels 1–5, costs scale up, raises both toll and land bonus.
- Chains: owning multiple tiles of the same element multiplies toll value
  (like Boardwalk+Park Place in Monopoly).
- Toll formula (reference): `TileValue = BaseValue × 2^(Level−1) × ChainMultiplier`;
  `Toll = TileValue × TollMod` (TollMod scales ~0.2 at Lv1 up to ~0.8 at Lv5).
- Terraforming: changing a tile's element costs scale with level; costs more
  for a fixed element than neutral.
- Lap bonus: passing the start tile grants gold, scaling with lap count,
  tile count owned, and symbol majority.
- Win condition: first player to accumulate a target amount of currency
  (working name: Total Magic / TM), typically checked on returning to start.
- Deck ("book") building: players build a customized deck of Creature /
  Spell / Item cards ahead of a match. Cards are unlocked by playing, not
  all available up front.

## Theme & setting

The element/color system uses the classic four elements — **Fire, Air,
Earth, Water** — mechanically identical to a Culdcept color (its own tiles,
chains, creature typing). This reverts an earlier pivot where retrofuturism
eras stood in as the elements themselves; that retrofuturism identity
didn't go away, it moved down a layer. Each element is now *skinned* in one
distinct retrofuturism era for visual/creature flavor only, not as the
mechanical unit — the era is flavor, the element is the mechanic.

Element → era skin mapping:

- **Fire** = **Laser Grid** — the glossy 1980s corporate future: neon
  grids, reflective glass, chrome airbrushing, robots, glass-block offices,
  high-tech luxury.
- **Air** = **Early Cyber** — Tron-grid, phosphor-green terminal,
  digital-frontier utopianism.
- **Earth** = **Cassette Futurism** — beige plastic, tape reels,
  analog-optimism (Nostromo-computer energy).
- **Water** = **Frutiger Aero** — glossy blue/green, translucent plastic,
  dew-drop/nature-tech optimism (mid-2000s "aqua" web look).

Fixed at these 4 by design decision — the era roster used to be explicitly
open-ended ("don't hardcode a fixed count"); that no longer applies now
that eras are a flavor skin on a classic 4-element mechanic rather than
being the element system itself.

Keep Y2K and Frutiger Aero (Water's skin) visually distinct: Y2K =
hard/chrome/silver; Frutiger Aero = glossy/translucent/organic. They're
adjacent aesthetics and will blend together if not deliberately separated.

Visual direction overall: nostalgic, retrofuturist, produced under the
in-fiction studio banner "Ninth Signal."

## Confirmed design decisions

- 2–4 players per match
- Both FFA and 2v2 alliance modes, player's choice
- Match length variable, scaling with board size (not fixed)
- Monetization: free-to-play, cosmetic Robux purchases only — no pay-to-win
- Card unlocks: win-based, earned from matches (not purchased, not
  daily-login)
- Starting card library: small curated set, 60–80 cards at launch
- Board content: fixed official board set only, no board editor
- Platform priority: PC/console primary, mobile secondary
- Single-player: full campaign story mode planned, but as a post-launch 1.0
  target — alpha/beta phases are PvP-core only
- Team: new dedicated team being formed for this project, starting with
  artists/modelers
- PvP matchmaking: public queues, ranked/casual, and private servers — all
  planned
- Player board piece ("Cepter token," currently a basic R6-shaped stand-in
  rig — plain blocks, spawned by `Main.server.lua`, see "Systems built so
  far" below) will eventually be a custom character/piece model, not the
  default Roblox avatar. This model is itself a cosmetic slot under the
  existing cosmetic-Robux-purchases monetization decision.
- Camera is match-wide and turn-synced, Culdcept Saga style: a single
  angled top-down/side "stage" camera that snaps to focus on whichever
  player currently has the turn. Everyone in the match sees the same
  framing at the same time — this is NOT free per-player camera control,
  and not just "look at your own Cepter." Built as `CameraService`
  (LocalScript) — see "Systems built so far" below.

## Still undecided / open

- Deeper mechanical identity per element beyond naming (what makes a Fire
  creature play differently from an Earth one, if anything)
- Actual card list/content
- Economy/balance tuning numbers

## System architecture requirements — non-negotiable

Modularity is the top priority. This project must be easy to interchange or
edit piece by piece without cascading confusion.

- One ModuleScript per system (e.g. `BoardService`, `MovementService`,
  `CardService`, `BattleService`, `EconomyService`, `TerraformService`,
  `MatchService`, `UIService`, a persistence/DataStore layer).
- Each system exposes a small, deliberate public API. Other systems call
  through that API only — never reach into another system's internals
  directly.
- Cross-system communication goes through a shared signal/event layer (the
  `Shared/Signal` module — see below), not direct cross-references, so
  systems can be swapped without hunting down every call site.
- Prefer many small, single-purpose scripts over few large ones.

## Repo layout

`src/` mirrors the Roblox Studio instance tree directly:

```
src/ReplicatedStorage/Shared/...                            -> ReplicatedStorage > Shared > ...
src/ServerScriptService/Systems/...                          -> ServerScriptService > Systems > ...
src/ServerScriptService/Main.server.lua                      -> ServerScriptService > Main (Script)
src/StarterPlayer/StarterPlayerScripts/UIService.client.lua   -> StarterPlayer > StarterPlayerScripts > UIService (LocalScript)
src/StarterPlayer/StarterPlayerScripts/CameraService.client.lua -> StarterPlayer > StarterPlayerScripts > CameraService (LocalScript)
```

Every script file's header comment states its Roblox instance type
(`Script` / `LocalScript` / `ModuleScript`), its exact Studio placement, and
its public API.

`tools/` holds one-time Studio Command Bar utility scripts — not part of the
runtime game, nothing in `src/` references them, safe to ignore or delete
once used. Currently `recreate-placeholder-board.lua` (see BoardService's
"hand-authored boards" note below) and `create-model-folders.lua` (creates
the empty `Models.Player`/`Models.Summons` folder scaffolding — see
Main.server.lua's "Model authoring" note further down).

## Getting code into Studio — two workflows

**This repo supports two different ways of working, depending on which
session you're in. Check which tools are actually available before picking
one — don't assume.**

1. **Manual copy-paste (default, always works).** The developer copies
   generated script blocks by hand into Studio's script editor across
   multiple computers — no Rojo, no live sync. When working this way:
   - State each script's type and exact placement tree up front.
   - Output each script as its own separate, individually copy-pastable
     block — never merge multiple scripts into one blob.
   - Keep scripts self-contained enough that pasting one in isolation still
     makes sense, given the modular API boundaries above.

2. **Live Roblox Studio MCP (when connected).** This repo's `.mcp.json`
   declares a `Roblox_Studio` MCP server that, when run locally on the same
   Windows machine as an open Roblox Studio instance (with Roblox's Studio
   MCP companion running), exposes tools to read/write directly into the
   live place — no copy-paste needed. This only works in a **local**
   Claude Code / Claude Desktop session on that machine; it is not reachable
   from a cloud/web session.
   - If Roblox Studio MCP tools are present this session, prefer using them
     to create/edit instances directly in the open place.
   - Still mirror whatever you create back into `src/` in this repo in the
     same layout convention above, and commit/push it — git stays the
     source of truth across machines regardless of which workflow placed
     the code in Studio.

## Current implementation state

Branch: `claude/dreaming-utopia-brief-mimfaw` (all work happens here; see
git remote branch protection notes in the session's own instructions if
running in an automated context).

Systems built so far:

- **`Shared/Signal`** (ModuleScript) — ordered, deterministic pub/sub. The
  cross-system communication layer; every service fires/listens on `Signal`
  instances instead of calling other systems' internals. **Rewritten in
  Milestone 0** and no longer fire-and-forget:
  - `Fire` is **synchronous** and runs handlers in explicit priority order
    (lower first, ties by connection order). When it returns, every handler
    has run. The old version used `task.spawn` over a `pairs()` loop, so
    handlers ran on separate threads in hash order — fine for repainting a
    label, unusable for ordered rule effects.
  - `Fold(value, ...)` threads a value through the handlers, each returning
    the next value (returning nil leaves it unchanged). This is the
    primitive behind every ordered modifier pipeline — `ModifyRoll`,
    `BeforeBattleStats`, toll modifiers. A signal that can only announce
    cannot express "then halve it."
  - Handler errors are isolated: a thrower is caught and reported, later
    handlers still run, and in `Fold` the running value survives.
  - `FireAsync` keeps the old behavior for presentation work that may
    yield. **Rules code must never use it.**
  - Because `Fire` is synchronous, a handler that yields now blocks the
    firer. That is deliberate — it makes accidental ordering dependencies
    visible instead of silently racing.
- **`Shared/Enums`** (ModuleScript) — the controlled vocabulary: `Phase`
  (the 28 match phases), `Element`, `CardType`, `ItemCategory`, `NodeType`,
  `SpeedClass`, `TerritoryCommand`, `LandingAction`, `MovementCause`,
  `BattleOutcome`, `DurationType`, `RejectReason`, `TimingHook`,
  `Visibility`. Each is a frozen name->name map whose `__index` throws on an
  unknown key, so a typo is an error rather than a silently-nil comparison.
  Element ids are canonical: Fire/Water/Air/Earth. A display label (a board
  showing Earth as "Ground") must never become a second set of ids.
- **`Shared/RulesConfig`** (ModuleScript) — every tunable rule constant and
  every rule formula, in one file. Nothing elsewhere may inline a chain
  multiplier, toll rate, hand size or development cost. Chain multipliers
  are 1.0/1.5/1.8/2.0/2.2 (capped at 5) and toll multipliers
  0.2/0.3/0.4/0.6/0.8 — **note these are the TARGET values and do not match
  what BoardService currently computes**; wiring them up is Milestone 5.
  Values genuinely uncertain against the source game are marked
  `UNVERIFIED` with what would settle them (currently lap-heal percent and
  toll rounding mode). Land value and toll are computed from **integer
  numerators over a denominator of 10**, never from the decimal tables,
  because `200 * 0.3` only lands on exactly 60 by IEEE rounding luck and a
  `floor()` over that arithmetic is one unlucky constant away from charging
  59. Pure Lua — touches no Roblox API.
- **`Shared/ActionResult`** (ModuleScript) — the structured return shape for
  every player action, replacing `success, reason`. `Ok` means the request
  was accepted and processed; what happened goes in `Payload`, **including
  losing a battle, which is a successful action with an unfavourable
  result**. `Ok = false` means refused, nothing spent, nothing moved. This
  exists because `BattleService.ChallengeTile` returns `false, nil` for
  "you lost" and `false, "reason"` for "rejected" — opposite events sharing
  a representation. Results are frozen; `fail` requires a real
  `Enums.RejectReason`.
- **`Shared/BoardDefinitions/CurrentLoop`** (ModuleScript, data) — the board
  actually in the place, expressed as graph data: 16 nodes in a one-way
  ring, one castle (tile 1), no forts, no junctions, one area. A faithful
  description of *current* behavior, not a target board — a degenerate
  graph with one exit per node walks identically to the sorted-ID loop, so
  the graph movement system can be proved against a board whose correct
  output is already known. Node ids ("T1") are separate from `StudioTileId`
  (the number in each Part's `Id` attribute) so re-authoring geometry never
  renames a graph node.
- **`Shared/EraData`** (ModuleScript) — registry of the classic four
  elements (Fire/Air/Earth/Water), each carrying a display name, a
  placeholder color, and its retrofuturism-era skin as real queryable
  fields — `EraName` (Fire=Laser Grid, Air=Early Cyber, Earth=Cassette
  Futurism, Water=Frutiger Aero) and `EraFlavor` (a one-line aesthetic
  description), see "Theme & setting". The era skin is data UI can read
  and show, not just a comment next to a color. Fixed at 4 by design
  decision, not open-ended (was, back when eras were the element system
  itself).
- **`Systems/TerritoryService`** (ModuleScript, server) — authoritative owner
  of territory state: owner, level, element, base value, keyed by **node id**.
  Replaced `BoardService` and `TerraformService` in Milestone 5 (both deleted;
  ignore any older reference to them). State seeds from the board definition
  rather than from Part attributes, which is why the Era→Element rename needed
  no attribute migration — the attribute simply stopped being read at runtime.
  Owns `GetChainSize` (area-scoped: same element, same owner, same area),
  `LevelUp` and `ChangeElement`, and the toll/value formulas from
  `RulesConfig`. A tile's *appearance* is entirely Studio-authored and this
  module never touches it.
- **`Systems/BoardGraphService`** (ModuleScript, server) — pure topology, no
  ownership and no tolls. `GetLegalExits(nodeId, cameFromNodeId)` compares
  **destinations, not edge ids**, because a two-way path is two directed edges
  and the return route has a different id.
- **`Systems/LapService`** (ModuleScript, server) — a lap means "every
  required fort TYPE, then the castle". By type, so bouncing between two Sun
  forts cannot finish a lap.
- **`Systems/ValuationService`** (ModuleScript, server) — Total Magic is
  `CM + land + symbols`, recomputed and never cached. CM is spendable cash;
  TM is what standings and victory read.
- **`Systems/VictoryService`** (ModuleScript, server) — victory in two steps.
  `RefreshGoalStates` marks the goal-reached *state*, which can be lost;
  `TryConfirmAtCastle` **re-checks TM** on arrival, so a rival who takes your
  land on the way home can put you back under the line.
- **`Systems/DeckService`** (ModuleScript, server) — the book, hand, discard
  and recycling. Cards are **instances** with their own ids, so playing one
  consumes it and instance identity is what makes secrecy possible: there is
  something to withhold.
- **`Systems/MovementService`** (ModuleScript, server) — owns each Cepter's
  (player's) board position and dice rolling (`RollDice`, `MoveCepter`,
  `GetCurrentTile`, `GetLapCount`). Moves tile-by-tile via
  `BoardService.GetNextTileId`/`GetStartTileId` — its only dependency on
  BoardService, deliberately narrow (pure read-only topology, never
  ownership/tolls; this data used to live in the now-deleted static
  `Shared/BoardData` module, moved here because only BoardService's
  CollectionService scan knows tile order once boards are hand-authored).
  Fires `CepterMoved` (per step), `CepterLanded` (move finished — the
  intended hook point for auto-triggering BattleService on landing once a
  real turn UI exists to gather player intent; nothing auto-connects to it
  yet, `Main.server.lua`'s `SummonRequest`/`ChallengeRequest` handlers
  drive BattleService from the client HUD instead), and `LapCompleted`
  (passed Start — hook point for the lap bonus once EconomyService exists).
- **`Shared/CardData`** (ModuleScript) — static registry of Creature/Spell/
  Item cards. Small placeholder set (one creature per element, one generic
  spell, one generic item) — not the real 60-80 card launch library, which
  is still open per the brief. Creature names pair the classic element with
  its retrofuturism-era skin and a nod to the traditional Paracelsian
  elemental archetype (Tape Gnome=Earth, Laser Salamander=Fire, Phosphor
  Sylph=Air, Dewdrop Undine=Water) — flavor only, no mechanical effect.
  Spell/Item cards carry an `EffectValue` magnitude (ST bonus / HP bonus)
  read by CardEffectService — the card data says how much, that module
  decides what it does.
- **`Systems/CardService`** (ModuleScript, server) — query API over
  CardData (`GetCard`, `GetAllCards`, `GetCardsByType`, `GetCardsByEra`).
  Deliberately no hand/deck/unlock state yet — that needs MatchService's
  match setup (not built, see MatchService's own header) and a persistence
  layer, neither of which exist.
- **`Systems/EconomyService`** (ModuleScript, server) — each player's Magic
  balance (brief's working-name "Total Magic"/TM). `RegisterPlayer` sets a
  starting balance; `AddMagic`/`SpendMagic` are the general transaction
  primitives; `PayToll` is the currency side of landing on an enemy tile
  (`BattleService.ChallengeTile` is the other option — pay or challenge);
  `ComputeLapBonus` implements the brief's lap-count/tiles-owned/era-majority
  formula and is auto-applied by self-subscribing to
  `MovementService.LapCompleted` (unconditional/automatic, unlike landing
  choices, so no UI/MatchService dependency needed to trigger it). Fires
  `WinTargetReached` when a balance crosses the win threshold — does NOT
  end the match itself, that's MatchService's job once it exists. Known
  simplification: `PayToll` skips crediting an owner who has since left the
  game rather than reviving their balance record.
- **`Systems/BattleService`** (ModuleScript, server) — challenge resolution:
  `SummonCreature` claims an unclaimed Property tile, `ChallengeTile`
  compares attacker ST vs the defender's effective HP (base HP +
  `BoardService.GetLandBonusHP` if the creature's era matches the tile's —
  the first thing to actually exercise that formula) and hands the tile to
  the winner. Both now spend the card's Magic `Cost` via
  `EconomyService.SpendMagic` as the last validation step, so a rejected
  claim/challenge never costs Magic. Tracks which specific creature defends
  each claimed tile itself — BoardService stays creature-agnostic (Owner/
  Level only). Deliberately does NOT do: tile-level-up costs, turn
  enforcement, or team/alliance awareness — all need MatchService (turn
  enforcement now exists, gated in `Main.server.lua`'s RemoteEvent handlers
  rather than inside BattleService itself; team/alliance still doesn't).
  Calls BoardService/CardService/EconomyService through their public APIs
  directly (layered system on top, same pattern as CardService -> CardData),
  fires `TileClaimed` / `ChallengeResolved` / `DefenderBuffed` signals.
  `QueueAttackBuff` / `ApplyDefenderHPBuff` exist so CardEffectService can
  apply Spell/Item effects without reaching into the defender table
  directly — this module stays its sole owner. A queued attack buff is
  additive and consumed (win or lose) on that player's next `ChallengeTile`;
  a defender HP buff lasts until that tile's defender record is replaced.
- **`Systems/CardEffectService`** (ModuleScript, server) — resolves a played
  card by running its declared effects. **Rewritten in Milestone 6.** It used
  to be two hardcoded behaviours, `CastSpell` (Signal Boost) and `UseItem`
  (Ninth Signal Charm), each its own branch — exactly the shape the brief
  forbids, and one that does not survive a real card list: the third card
  that boosts an attack would have been a third branch doing the same thing.
  Now a card carries an `Effects` list written in EffectPrimitives'
  vocabulary and resolving it means running each entry. Cost is charged
  **first**; if any effect fails the cost is refunded and the card is not
  consumed. That is a refund, not a rollback — effects that already
  succeeded are not undone, which is why primitives validate before they
  mutate, and the limit is documented in the module's own header.
- **`Shared/PhaseGraph`** (ModuleScript) — the legal phase transition table,
  as data. States which transitions exist; MatchOrchestrator decides when to
  take them. A move not listed cannot happen. Several rules are enforced
  structurally here rather than by convention: movement never self-loops (a
  junction leaves and returns, so remaining steps stay owned by one
  transaction), `AttackerItemChoice -> DefenderItemChoice` is the only route
  between them (Saga's sequential item order), `TollResolution ->
  Liquidation` exists because an unaffordable payment liquidates rather than
  being rejected, and Doublecast is an ordinary `SpellResolution ->
  SpellChoice` edge rather than a card-name special case.
- **`Systems/MatchLogService`** (ModuleScript, server) — append-only ordered
  event record with monotonic indices. Entries are frozen; a log a service
  can retroactively edit is not evidence. Capped at `MaxEntries`, dropping
  oldest-first and **counting the drops**, so "nothing happened before index
  400" stays distinguishable from "the first 400 were discarded".
- **`Systems/MatchOrchestrator`** (ModuleScript, server) — **the sole
  phase-transition authority**. Nothing else may change the phase. Owns
  phase, active player, turn/round counters and per-player intent
  sequencing; logs every accepted and rejected move. Intents carry a
  monotonic sequence number so a double-click or replayed packet is refused
  as `DuplicateSequence`/`StaleSequence` — and a **rejected intent does not
  consume its ordinal**, or being refused once would knock a client's
  numbering permanently out of step. Every rejection path returns before
  touching any state; the tests assert "failed AND nothing moved", not just
  that the call failed. Does **not** yet decide which actions are legal
  within a phase — that is ActionValidator's job and it does not exist yet.
- **`Systems/ActionValidator`** (ModuleScript, server) — answers both "may
  this request proceed" and "what may I do now" from one table, so the
  buttons a client offers and the requests the server accepts cannot drift.
  Each phase names its expected **Actor**, and it is deliberately not always
  the active player: `DefenderItemChoice` belongs to the **defender**, since
  the invader commits an item first. Phases with `Actor = None` are
  server-driven and refuse every request. Validates *admissibility* only
  (right phase, right actor, known intent) — affordability and targeting are
  checked where the payment happens.
- **`Systems/SnapshotService`** (ModuleScript, server) — builds the
  per-player view. A **public** portion every client receives identically
  (phase, turn, standings, hand **counts**) and a **private** `You` section
  only its recipient gets (balance, legal intents, and `Hand`, empty until
  Milestone 3). The split exists before hands do on purpose: secrecy built
  into the only path state takes to a client holds by construction, whereas
  secrecy retrofitted later is a leak hunt.
- **`Systems/BoardVisualService`** (ModuleScript, server) — everything the
  board *looks* like: tile labels, ownership material flip, element recolour,
  Cepter tokens, defender models. Split out of Main. Decides nothing;
  deleting it would leave a headless but fully correct match, which is the
  test of whether the split is real.
- **`Systems/RandomService`** (ModuleScript, server) — the only source of
  randomness in a match, so a test can pin a seed and replay deterministically.
  Deliberately **not** Roblox's `Random`: that generator's algorithm is
  unspecified, so a recorded seed is not guaranteed to reproduce the same
  match on a later engine version, and it cannot run outside Studio. This is
  a Lehmer/MINSTD generator written out in full — same seed, same sequence,
  anywhere. `NextInteger` derives from the high-order float rather than the
  weak low bits. `Shuffle` is Fisher-Yates. Clients receive rolls as
  results, never a seed they could run forward.
- **`Systems/BoardDefinitionValidator`** (ModuleScript, server) — rejects
  malformed boards at load time. Catches duplicate node ids, edges pointing
  at renamed nodes, nodes with no outgoing edge (an unrecoverable movement
  softlock), unreachable nodes, warps with missing or dangling destinations,
  Castle nodes absent from `CastleNodeIds`, and required fort types no node
  provides (which would make a lap impossible to complete). Reports **every**
  problem at once rather than stopping at the first. Pure logic — a board is
  data; whether Parts exist to render it belongs to the rendering layer.
- **`Systems/MatchService`** (ModuleScript, server) — turn order and
  match-end lifecycle. `RegisterPlayer`/`RemovePlayer` maintain a rotation
  (array of userIds in join order); `IsPlayersTurn` / `HasRolledThisTurn` /
  `MarkRolled` / `EndTurn` are the primitives `Main.server.lua` checks
  before letting a RemoteEvent request through to Movement/Battle/Economy —
  those systems stay turn-agnostic themselves, the gating lives in Main.
  Self-subscribes to `EconomyService.WinTargetReached` in `Init` to freeze
  turns and fire `MatchEnded` with the winner. `GetTeam`/`AreAllies` exist
  as the seam a real 2v2 alliance flow will use later, but every player is
  currently their own team (pure FFA) — no pairing logic exists yet.
  Deliberately does NOT do: match setup/a lobby (there's no "start match"
  step or minimum player count — the match is implicitly in progress from
  the first registered player onward, same always-on-world style the rest
  of the project uses) or rematch/return-to-lobby after `MatchEnded`.
- **`Systems/StatusService`** (ModuleScript, server) — the status registry
  and the ordered hook dispatcher. `Apply(spec)` creates a status;
  `RunHook(hook, context, value)` folds every matching status through a
  timing hook in **priority order** (ties by application order) and logs the
  resolved sequence; `FireHook` is the no-value form for hooks that act by
  side effect; `TickDurations(durationType, scopeUserId)` expires them.
  Handler errors are isolated — one bad card cannot strand a turn. Stacking
  is a declared policy (Replace / Stack / Ignore / RefreshDuration), and
  `ReplacementGroup` evicts across *different* kinds, which is what stops a
  player being both forced to roll a 6 and unable to roll. `ScopeUserId`
  names whose turns a status counts down on when that is neither the caster
  nor the target — a poison on an opponent's creature is owned by the caster
  and targets a node, so without it, it belongs to nobody's turn.
  Knows nothing about what any status *does*.
- **`Systems/StatusDefinitions`** (ModuleScript, server) — what each kind
  does, keyed by kind, in one file. Behaviour has to be code (a hook is a
  function), but it lives here once rather than on cards: a card that poisons
  says `{ Kind = "Poison", Turns = 3 }` and reuses this. Adding a status is
  an entry here plus the cards that apply it — no service changes, because
  StatusService dispatches whatever it finds. Currently ForcedRoll, Haste,
  Slow, RollClamp, Poison, Paralysis, AttackBoost, GlobalAttackShift.
- **`Systems/EffectPrimitives`** (ModuleScript, server) — the closed
  vocabulary a card's effects are written in, and the reason there is no
  module-per-card. Each primitive declares its target KIND; the resolver
  turns that into a concrete id, so primitives never parse player input.
  Every one returns an ActionResult and a primitive that cannot act must
  **fail** rather than silently doing nothing, because the caller refunds on
  failure — a spell that quietly fizzles while taking the Magic is worse than
  one that is refused.
- **`Shared/Remotes`** (ModuleScript) — the only client-server bridge so
  far. Creates (server) / waits for (client) a fixed set of RemoteEvents
  under `ReplicatedStorage > Remotes`, returned as a name-keyed table so
  both sides reference the same instances instead of magic strings:
  `RollRequest`, `SummonRequest(cardId)`, `ChallengeRequest(cardId)`,
  `PayTollRequest`, `EndTurnRequest`, `TerraformRequest(targetEra)`,
  `CastSpellRequest(cardId)`, `UseItemRequest(cardId, tileId)`
  (client -> server), `StateUpdated(snapshot)`, `ActionResult(message)`
  (server -> client). Request handlers must read the acting player from
  `OnServerEvent`'s own first argument — never a client-supplied one — to
  stay authoritative.
- **`Main.server.lua`** (Script, bootstrap/composition root) — requires
  BoardService, MovementService, CardService, EconomyService, BattleService,
  MatchService, TerraformService, CardEffectService, and Remotes. Does NOT
  spawn tiles — scans `CollectionService:GetTagged("Tile")` itself (same tag
  BoardService
  scans, kept as a separate scan on purpose: BoardService stays
  instance-agnostic/pure data, this is a visual-only concern) to find the
  hand-placed tile Parts and attach a BillboardGui label to each; wires
  signals to visuals (label text, ownership Material flip to Neon, era
  recolor, a per-player "Cepter token" cloned from a **developer-authored
  model** rather than built in code — see "Model authoring" below —
  parented under a `Cepters` folder, named `"Cepter_"..userId` (the exact
  name CameraService looks up), moved with `Model:PivotTo` on every
  `MovementService.CepterMoved`). Also clones the matching creature model
  onto a claimed tile under a `Defenders` folder, driven by the same
  `TileOwnerChanged` signal — real per-card art now, not a generic
  placeholder marker, as long as the developer has placed one (falls back
  to a `warn()` and no visual if a card has no matching Summons model yet).
  Registers/cleans up Cepters, Magic balances, and turn rotation on
  PlayerAdded/PlayerRemoving. `warn()`s if no tagged tiles are found at
  boot (helps catch a forgotten tag/attribute during hand-authoring).

  **Model authoring** (Cepter tokens + creature summons — this is the
  developer's job now, not code-generated, per an explicit decision to stop
  procedurally building placeholder geometry): place real Models under
  `ReplicatedStorage > Models > Player` and `ReplicatedStorage > Models >
  Summons` (in Studio directly, or via a plugin — `tools/create-model-folders.lua`
  is a one-time Command Bar script that creates just the empty folder
  scaffolding, not the models themselves). Contract Main.server.lua
  actually reads:
    - `Models.Player.PlayerTemplate` (Model) — a real R6 Character with a
      `Humanoid` and a part literally named `HumanoidRootPart`. Cloned once
      per joining player; `PrimaryPart` is set to that HumanoidRootPart on
      clone. CameraService depends on that exact child name/part existing
      to find its focus target's live position.
    - `Models.Summons.<any name>` (Model) — one per creature card, matched
      to `CardData` by a number **Attribute** named `CardId` set on the
      Model itself (the Model's own instance *Name* can be anything
      readable — the attribute is the actual lookup key). Same
      attribute-driven pattern `BoardService` already uses for tile data,
      kept consistent on purpose.
  Every cloned model has all its `BasePart` descendants force-`Anchored`
  (movement here is teleport/PivotTo, never physics-simulated, same as the
  rest of the board) and is positioned via `Model:PivotTo`, not by setting
  a single Part's `.Position` — this is what let the switch away from the
  old block-rig/Neon-marker placeholders happen without needing a
  Motor6D/joint rig of its own; PivotTo works on any Model regardless of
  its internal joint structure. The 8 `*Request` RemoteEvents are
  handled here, each gated by `MatchService.IsPlayersTurn` (roll also
  checks `HasRolledThisTurn`) before calling into
  Movement/Battle/Economy/Terraform/CardEffect — `sendStateToPlayer`/
  `refreshAllPlayerStates` push a per-player state snapshot (including
  turn/match info, and the current turn's userId for CameraService) over
  `StateUpdated` whenever anything relevant changes (movement, balance,
  tile ownership/level/era, turn, match end).
- **`StarterPlayer/UIService.client.lua`** (LocalScript) — first slice of
  UIService: a deliberately plain HUD (`ScreenGui`/`Frame`, standard Roblox
  gray panel, default `SourceSans` font, no custom color theme, no card art
  or animation — kept intentionally undecorated rather than styled) with a
  turn indicator, Magic balance line, current-tile info, a card-id
  `TextBox`, a target-tile `TextBox` (`TargetTileBox` — the project's first
  explicit target input, used by Use Item only; every other action just
  acts on the tile you're standing on), an era-id `TextBox` (raw
  `EraData.Eras` keys, listed in the legend), and Roll/Summon/Challenge/
  Pay Toll/End Turn/Cast Spell/Use Item/Terraform buttons that fire the
  matching Remote. Action button text dims to gray when it
  isn't the local player's turn (visual cue only — the server is the
  actual enforcement). Reads `CardData`/`EraData` directly for the legend
  (safe — pure static Shared data, no security concern). Only talks to the
  server through `Shared.Remotes`; cannot and does not require server
  ModuleScripts.
- **`StarterPlayer/CameraService.client.lua`** (LocalScript) — the
  match-wide turn-synced "stage" camera from the design decisions above.
  Takes the camera fully `Scriptable` (no free-roam gameplay exists to lose
  by not using the default follow-avatar camera) and, on every
  `StateUpdated` push where `CurrentTurnUserId` changed, finds that
  player's `"Cepter_"..userId` token Model under Workspace (plain
  replication, visible to every client automatically — no camera-specific
  networking), then its `HumanoidRootPart` child specifically, and tweens
  to an angled offset framing it. Also subscribes to that part's own
  `Position` changes while focused on it, so the camera keeps following
  live as the active player rolls/moves during their turn, not just once
  at turn-start. Entirely decoupled from board geometry/data — only ever
  reads a Cepter token's live Position, never tile data — so it needed
  zero changes for the hand-authored-boards switch above, and only a
  one-line lookup change (Part -> Model.HumanoidRootPart) for the real-R6
  Cepter switch.
  Two non-obvious Roblox behaviors this had to work around, found by
  actually testing in Studio (both easy to hit again if this pattern gets
  reused elsewhere): (1) `Workspace.CurrentCamera` can be swapped for a
  brand-new Camera instance around character spawn, so a reference grabbed
  once at script start can go stale — re-acquired on every
  `CurrentCamera` property change, not just once. (2) Roblox's own default
  camera control script (present in every place, not something this
  project added) keeps re-asserting `CameraType = Custom` on its own even
  after this script sets `Scriptable`, which snapped the view back to
  following the character — fixed by re-claiming `Scriptable` every
  `RenderStepped` frame instead of only reacting to changes. Token lookup
  also uses `WaitForChild` with a timeout, not a one-shot `FindFirstChild`
  — the server fires `StateUpdated` right after creating a new Cepter
  token, but instance replication and RemoteEvent delivery aren't
  guaranteed to arrive in that order, so the token can genuinely not exist
  on the client yet for a brief moment.

Already authored in the live place (Studio-side content, not code, so it
lives in the .rbxl rather than this repo — verified present 2026-09-08): a
16-tile board (ids 1-16, one Start + 15 Property, all tagged and
attributed), `Models.Player.PlayerTemplate`, and a `Models.Summons` stand-in
for all four creature cards (single Parts carrying `CardId` 1-4). The game
is playable end to end today. These are greybox placeholders — real art
still to come — but the "no models authored yet" gap is closed.

Not yet built: match setup/lobby and 2v2 alliance mode (see MatchService's
header for what's deferred there), persistence/DataStore layer, terraforming
an owned tile (see TerraformService's header), tile level-up (BoardService
exposes `LevelUp` but nothing costs Magic for it or calls it — a core
Culdcept mechanic still missing), any deck/hand/draw model (CardService is
a pure static query API, so every player can play any card any number of
times — UIService asks you to type a card id, which is why the HUD looks
like a debug panel), and the rest of UIService (card hand, deck builder,
actual visual design).

## Target architecture and milestones

The project is being rebuilt against a Culdcept Saga fidelity brief. The
mechanical target is Saga's *rules and timing model*; the creative identity
(names, art, era skins, lore) stays original. The demand is not more
features — it is that every phase, choice, rule exception, timing window and
resource change has a named owner, an input contract, a resolution order and
a test.

**Milestone 1 is complete.** A turn now runs `TurnStart -> Draw ->
SpellChoice -> RollReady -> DiceResolution -> Movement -> LandingResolution
-> LandingActionChoice -> TurnEnd -> VictoryCheck -> (RoundEnd) -> TurnStart`,
driven by MatchOrchestrator. Draw and SpellChoice are *traversed, not
skipped*: there is no book until Milestone 3, but the phases are real,
logged, and already in the right place for it.

The eight action-shaped RemoteEvents collapsed into one intent-shaped
`SubmitIntent(intent, sequence, expectedPhase, payload)`. One channel means
one validation path — every request passes orchestrator admissibility, then
expected-phase agreement, then ActionValidator, before reaching a service.
The old shape had a hand-written turn check per remote and they had already
drifted: `EndTurnRequest` was the one handler that forgot to check whose turn
it was. `expectedPhase` turns a race into a clean rejection: a player who
clicks a screen the server has moved past gets `StaleSequence` rather than an
action applied in the wrong phase.

**Milestone 2 is complete.** Movement is a resumable transaction over a board
graph: `BeginMove` returns Completed or AwaitingChoice, and the remaining
steps live in the transaction until `ChooseExit` resumes it. `BoardGraphService`
owns topology only. The reversal rule compares **destinations, not edge ids**,
because a two-way path is two directed edges and the return route has a
different id. `LapService` makes a lap mean "every required fort TYPE, then the
castle" — by type, so bouncing between two Sun forts cannot finish a lap.
`TestBoard01` carries a T-junction, dead end, two fort types, a mandatory warp
and a landing warp. **A warp relocates without consuming a step.**

**Milestone 3 is complete.** `DeckService` gives each player a shuffled
50-card book, a 6-card hand, a discard, and recycling. Cards are **instances**
with their own ids, so playing one consumes it — a card id can no longer be
summoned repeatedly. Instance identity is also what makes secrecy possible:
there is something to withhold.

**Card presentation (decided 2026-09-09, developer's design).** Exactly one
hand is on screen at a time — the **active player's**, in a Culdcept-style row
along the bottom. Its owner sees the faces; every other player sees the same
number of backs in the same place, and the visible hand follows the turn. You
never see your own cards on someone else's turn.

The secrecy is server-side, not a client-side flip: `SnapshotService.HandView`
puts card identities in the table **only** when the recipient owns them, so an
opponent's snapshot has no `Cards` field at all. `Count` is public because hand
size is public in Culdcept; contents are not. Cards render as rounded
rectangles with text — no art yet.

**Milestone 4 is complete.** A battle is a nested state machine:
`BeginInvasion -> AwaitingAttackerItem -> AwaitingDefenderItem -> Resolved`.
The invader commits first and the defender chooses knowing what was committed;
that order is enforced structurally, since the defender's function refuses to
run until the attacker's has.

**The HP defect is fixed.** A defender keeps `BaseMHP` / `BonusMHP` /
`CurrentHP`, and the land bonus is computed fresh each battle from the tile's
CURRENT element and level. Nothing about the land is ever written into the
creature, so a terraform or level change is simply picked up next battle —
which is what will let M5 lift the unclaimed-only terraform restriction.
Temporary battle HP (land bonus, armour) absorbs damage **before** persistent
health; the pool is identical either way, but it decides how much damage a
survivor carries. UNVERIFIED against the source game.

Speed classes rank First > Normal > Last, higher strikes first, invader wins a
tie — one comparison that reproduces the brief's whole matrix including a
faster *defender*. A lethal first strike ends the battle.

Keywords read from card data, never card names: First, Last, Critical,
Penetration, Neutralize, Reflect, Regenerate, Support. Scrolls bypass the land
bonus and ordinary Neutralize/Reflect.

`MatchOrchestrator.SubmitIntent` gained an `entitledUserId` parameter because
of this milestone: during `DefenderItemChoice` the **defender** submits, not
the turn holder, and hard-coding "active player" made that impossible. The
hand spotlight follows the same rule — whoever is currently entitled to decide
sees their own cards.

**Deferred out of M4, delivered in M6:** poison and paralysis. The brief listed
them here, but they are statuses with durations outliving a battle and
faking them as battle-local flags would have passed a test while modelling the
wrong thing. They now live in `StatusDefinitions`.

`BothDestroyed` is handled but still unreachable with the current keywords —
Reflect zeroes incoming damage and so spares the reflector.

**Milestone 5 is complete.** `TerritoryService` replaces BoardService and
TerraformService, keyed by **node id** — one name for a place on the board
instead of two. State seeds from the board definition, not from Part
attributes, which is why the Era→Element rename needed no attribute migration:
the attribute simply stopped being read at runtime.

**Current Magic and Total Magic are now separate quantities.** CM is spendable
cash (EconomyService); TM is CM + land + symbols (ValuationService) and is what
standings and victory read. This is the whole strategic loop — verified live:
developing a territory from level 1 to 3 cost **300 CM** and raised land value
by **450**, so TM went **up 150** while cash went down. With one balance that
reads as pure loss.

**Victory is two steps.** Reaching the TM goal is a visible *state*, not a win;
it must be confirmed by reaching or crossing a castle, where TM is
**re-checked** — so a rival who takes your land on the way home can put you
back under the line and arriving wins nothing.

Chains are **area-scoped** (same element, same owner, same area). An
unaffordable toll now enters **liquidation** rather than being refused:
`RequirePayment` takes what is available and records a debt, territories are
sold at `RulesConfig.Liquidation.SaleRate`, and a player with debt and no land
is bankrupt.

Terraforming works on **your own occupied land** — the unclaimed-only rule was
a workaround for the M4 HP defect, and fixing that removed its reason.

**Milestone 6 is complete for statuses and card effects. Special nodes are
NOT done and are deliberately deferred — see the end of this section.**

`StatusService` is the piece the previous five milestones kept deferring things
into. A status is a record with a kind, a target, a duration and a priority;
`RunHook` folds every matching one through a timing hook in priority order and
**logs the resolved order**, which is what makes "why was my roll a 6"
answerable after the fact. Behaviour lives in `StatusDefinitions`, keyed by
kind, so a second poison card reuses the definition rather than describing
poisoning again.

Ordering is the whole point, and it is enforced by priority rather than by
luck: `ForcedRoll` runs at −100 so a haste applies **on top of** the forced
value instead of being overwritten by it, and `RollClamp` runs at +1000 so it
bounds whatever the others produced. A forced roll consumes itself in its own
handler (`status.Consumed`), so it is spent by the roll it forces and cannot
leak into a later turn. `ForcedRoll` and `Paralysis` share a
`ReplacementGroup`, so you cannot be simultaneously forced to roll a 6 and
unable to roll.

`EffectPrimitives` is the closed vocabulary a card's effects are written in —
GainMagic, LoseMagic, Draw, ForceRoll, ApplyStatus, ApplyCreatureStatus,
ApplyGlobalStatus, BoostNextAttack, BuffDefenderHP, Teleport. A card carries an
`Effects` list; `CardEffectService` looks each verb up and runs it. **No module
per card and no `if card.Name ==` chain.** Adding a card that draws three needs
no code at all. `EffectSpec` walks the whole library and asserts every declared
primitive exists, so a typo in CardData fails a test rather than a live match.

Cost is charged **first** — a spell that resolves before it is paid for can be
cast without the Magic — and if any effect fails the cost is refunded and the
card is **not consumed**. This is a refund, not a rollback: effects that already
succeeded are not undone, which is why primitives validate before they mutate.
Documented as a limit in CardEffectService's own header.

**`SpellChoice` now stops.** It was traversed through M1–M5 because there was
nothing to cast. Declining is a real choice (`SkipSpell`) rather than the
absence of one, for the same reason `No Item` is a button: otherwise the server
has already moved to `RollReady` before the client can offer anything.

Two battle special cases became ordinary statuses. `BattleService.QueueAttackBuff`'s
private `_attackBuffs` table is now `AttackBoost` resolved through
`BeforeBattleStats`, and both combatants run the same fold — which is how
`GlobalAttackShift` reaches the defender without needing to know a battle has
sides. Poison damages through `BattleService.DamageDefender` rather than writing
`CurrentHP` directly, because that service is the sole owner of defender state
and a private write also skips the signal the board repaints on.

`ScopeUserId` exists because a poison cast by Alice onto Bob's creature is
owned by Alice and targets a *node*: without it the status belongs to nobody's
turn and never expires. Whoever applies a status knows whose turns it counts
down on; StatusService cannot work it out.

**UNVERIFIED against the source game:** poison ticks at the *end* of the
afflicted creature's owner's turn. Saga may tick at the start instead, which
differs by one tick when the poison lands mid-round. Marked in
`StatusDefinitions.Poison`.

**The status set spell cards will actually use is `docs/status-backlog.md`**
(recorded 2026-09-11, the developer's own list, canonical). M6 built only enough
statuses to prove the engine worked. Five of the seven are done or half-done;
the two genuinely missing ones — **Silenced** and **Invulnerable/shielded** —
need a *dispatch site* rather than just a definition: `Enums.TimingHook`
declares `BeforeSpell` and `OnDamage`, and **nothing calls either**, so a
definition hanging off them is dead code until some service folds through them.
Do not invent statuses outside that list.

**Deferred out of M6 and still missing:** `NodeEffectService` and special nodes
— shrine, Fortune Teller, Fountain, Temple/symbols, Board Action. Neither
CurrentLoop nor TestBoard01 has any, so there is nothing to exercise them
against; they need a board authored for them first.

Milestones, in order: **M0 safety net and schemas** (done), **M1 match/turn
state machine** (done), **M2 graph movement** (done), **M3 book/hand/card
lifecycle** (done), **M4 landing and battle** (done), **M5 territory and full
economy** (done), **M6 card/status engine** (done; special nodes deferred),
M7 content and presentation, M8 secondary-system skeletons. Build a complete
local match before matchmaking, campaign or monetization; those get interfaces
early and skeletal implementations.

Four inversions define the work: a phase state machine replaces implicit turn
state; a board graph replaces the sorted-ID loop; ordered value-transforming
effect hooks replace fire-and-forget signals; owned, consumed card instances
replace a static registry players index by typing a number.

## Getting code into Studio — Rojo (decided 2026-09-08)

`default.project.json` syncs the repo into Studio. This replaced hand
copy-paste and MCP retransmission after Milestone 0, where twelve
retransmissions through the MCP bridge left three files silently drifted
between repo and place — caught only by checksumming every script.

Rojo **deletes instances under a managed path that aren't in the repo**, so
the project tree is scoped deliberately. It manages `ReplicatedStorage >
Shared`, `ServerScriptService > Main / Systems / Tests`, and `StarterPlayer >
StarterPlayerScripts`. It does **not** manage `Workspace` (the authored
board), `ReplicatedStorage > Models` (Cepter and creature models),
`ReplicatedStorage > Remotes` (runtime-created), or `ServerStorage > README`.
Never widen a `$path` to a whole service that contains authored content — see
README.md for why.

MCP is still used, but for what Rojo cannot do: inspecting the live tree,
reading Studio-authored board/model data, running the suite in a playtest,
and driving verification through RemoteEvents.

## Open decisions resolved (2026-09-08)

- **Element vs Era naming.** The brief says element; the code says `Era`
  everywhere, including the attribute on all 16 board Parts. Decision: new
  code uses `Element`, and the tile-attribute migration is scripted as part
  of replacing BoardService in Milestone 2 — not as a separate churn pass
  over authored board data.
- **Milestone 2 test board.** Generated: graph data hand-written, throwaway
  greybox Parts spawned into their own folder. The authored board is left
  untouched and the test board is disposable.
- **Card content.** Placeholder library of roughly 20-25 original-named
  cards, chosen to exercise every mechanic the Milestone 4 battle tests need
  (Weapon/Armor/Tool/Scroll/Support/First/Last/Critical/Penetration/
  Neutralize/Reflect/Regenerate/poison/paralysis). Explicitly disposable test
  content, not a balance proposal or the 60-80 launch library.

## Testing

Specs live in `ServerScriptService > Tests > Specs`, run by
`Tests.TestRunner`. A spec is `{ Name, Tests = { {description, fn}, ... } }` —
an ordered array, not a keyed table, so report lines do not shuffle between
runs.

**Run them in a playtest, not in Edit.** Roblox caches `require` per Edit
session, so a module edited after being required once returns the stale table
for the rest of that session and the suite silently tests old code. Start a
playtest and run against the Server datamodel:

```lua
local Tests = game.ServerScriptService.Tests
print(require(Tests.TestRunner).runAll(Tests.Specs))
```

**The MCP `execute_luau` sandbox is not the running game.** Its calls share a
module cache with each other but *not* with `Main.server.lua` — verified by
Main's signals showing zero handlers from inside it. So the suite tests
services in isolation and cannot corrupt a live match, but equally cannot
verify Main's wiring, the HUD, or a real turn. For that, fire a RemoteEvent
from the **Client** datamodel: remotes cross the network layer rather than
the module cache, so they reach the real server.

`CharacterizationSpec` deliberately pins the CURRENT formulas, several of
which are provably wrong against the target (chain multiplier is linear
+0.5/tile; toll multipliers are 0.2/0.35/0.5/0.65/0.8; terraform costs
50 + 30/level). Each such test names what it becomes. When Milestone 5
changes the formulas, exactly these tests should fail — the gap between
"expected to fail" and "actually failed" is the blast radius.

Two Luau constraints found the hard way, both in `Enums`:
- A metatable must be attached **before** `table.freeze`; `setmetatable` on a
  frozen table throws.
- `table.freeze` **refuses** a table whose metatable is protected with
  `__metatable`, so an enum cannot have both. Freezing is the stronger
  guarantee and subsumes it.

## Working style — how to respond (manual copy-paste sessions)

1. Every script states its type up front — `Script`, `LocalScript`, or
   `ModuleScript` — and whether it's standalone or part of the shared
   modular system.
2. Every script comes with an exact placement tree (e.g.
   `ServerScriptService > Systems > BoardService (ModuleScript)`), not a
   vague location.
3. Output code in clearly separated, individually copy-pastable blocks.
4. Keep scripts self-contained enough that pasting one at a time in
   isolation still makes sense, given the modular API boundaries above.
5. Don't assume file-sync tooling is present unless a session confirms
   Roblox Studio MCP tools are actually connected (see workflow 2 above).

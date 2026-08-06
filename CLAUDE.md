# Dreaming of Utopia — Project Context

This file loads automatically at the start of every Claude Code session in
this repo. Read it fully before writing any code. It is the persistent
memory for a project being developed across multiple machines (main PC,
laptop, work computer) and multiple Claude sessions (cloud/web and local).

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

Instead of classical elements (Fire/Water/Earth/Air), the "element/color"
system is built from retrofuturism eras — different "perceptions of the
future," a.k.a. utopias. Each era functions mechanically like a Culdcept
color (has its own tiles, chains, creature aesthetic).

Confirmed eras so far:

- **Cassette Futurism** — beige plastic, tape reels, analog-optimism
  (Nostromo-computer energy) [REPLACED EARTH]
- **Laser Grid** — the glossy 1980s corporate future: neon grids, reflective
  glass, chrome airbrushing, robots, glass-block offices, high-tech luxury.
  [REPLACED FIRE]
- **Early Cyber** — Tron-grid, phosphor-green terminal, digital-frontier
  utopianism [REPLACED AIR]
- **Frutiger Aero** — glossy blue/green, translucent plastic, dew-drop/
  nature-tech optimism (mid-2000s "aqua" web look) [REPLACED WATER]
- More eras may be added later — **keep the system open to expansion**,
  don't hardcode a fixed count of 4.

Keep Y2K and Frutiger Aero visually distinct: Y2K = hard/chrome/silver;
Frutiger Aero = glossy/translucent/organic. They're adjacent eras and will
blend together if not deliberately separated.

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
- Player board piece ("Cepter token," currently a placeholder ball spawned
  by `Main.server.lua`) will be a custom character/piece model, not the
  default Roblox avatar. This model is itself a cosmetic slot under the
  existing cosmetic-Robux-purchases monetization decision.
- Camera is match-wide and turn-synced, Culdcept Saga style: a single
  angled top-down/side "stage" camera that snaps to focus on whichever
  player currently has the turn. Everyone in the match sees the same
  framing at the same time — this is NOT free per-player camera control,
  and not just "look at your own Cepter." Built as `CameraService`
  (LocalScript) — see "Systems built so far" below.

## Still undecided / open

- Deeper mechanical identity per era beyond naming (what makes a Cyber
  creature play differently from a Cassette Futurism one, if anything)
- Actual card list/content
- Economy/balance tuning numbers
- Whether more than 4 eras ship at launch

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
once used. Currently just `recreate-placeholder-board.lua` (see BoardService's
"hand-authored boards" note below).

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

- **`Shared/Signal`** (ModuleScript) — lightweight pub/sub event object.
  The cross-system communication layer; every service fires/listens on
  `Signal` instances instead of calling other systems' internals.
- **`Shared/EraData`** (ModuleScript) — registry of retrofuturism eras
  (display name + placeholder color per era). Open-ended by design — add an
  entry, every system that reads it picks up the new era automatically.
- **`Systems/BoardService`** (ModuleScript, server) — authoritative owner
  of the board itself, now **hand-authored**: tiles are Parts placed
  directly in Workspace by the developer (own board designs, not
  code-generated), tagged `"Tile"` via `CollectionService`, with attributes
  set in Studio's Properties panel: `Id` (number, required — order in the
  movement loop; does NOT need to be contiguous, only uniquely orderable,
  since `GetNextTileId` sorts once at `Init` and walks that order rather
  than doing `id + 1` arithmetic), `TileType` (`"Start"` or `"Property"`,
  required), `Era` (must match an `EraData.Eras` key, or blank for
  neutral/Start, optional), `BaseValue` (optional, defaults to 0 for Start
  / 100 for Property). `Init` scans `CollectionService:GetTagged("Tile")`
  and builds the runtime tile registry from those attributes — a tile
  missing `Id` is skipped with a `warn()`. Everything about a tile's
  *appearance* (its Part's Position/Color/Material/model) is entirely
  Studio-authored and BoardService never touches or needs it — Owner/
  Level/Era are the only mutable runtime state it tracks, mutated only
  through its public API (`SetOwner`, `LevelUp`, `SetEra`), never touched
  directly by other systems. Implements the toll/value formulas from the
  gameplay reference (`GetTileValue`, `GetToll`, `GetChainMultiplier`,
  `GetLandBonusHP`). Fires `TileOwnerChanged` / `TileLeveledUp` /
  `EraChanged` signals. `tools/recreate-placeholder-board.lua` is a
  one-time Studio Command Bar script (not part of the runtime game) that
  recreates the old procedural 16-tile loop as real tagged/attributed
  Parts — a working starting point to hand-edit from, not required.
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
  Item cards. Small placeholder set (one creature per confirmed era, one
  generic spell, one generic item) — not the real 60-80 card launch
  library, which is still open per the brief.
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
  fires `TileClaimed` / `ChallengeResolved` signals.
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
- **`Systems/TerraformService`** (ModuleScript, server) — changes a
  Property tile's era for Magic (`TerraformTile`), cost scaling with the
  tile's level and with a surcharge for committing to a specific era over
  reverting to neutral (`GetTerraformCost`). Restricted to **unclaimed**
  tiles only — an owned tile's defender has a `CurrentHP` cached at summon
  time (base HP + land bonus if era matched then); changing era afterward
  would leave that stale since BattleService doesn't recompute it on a
  later era change. Fixing that needs deliberately touching BattleService's
  defender state, not as a side effect of this module, so it's deferred —
  terraform before claiming, not after. Calls `BoardService.SetEra`/
  `EconomyService.SpendMagic` directly (layered on top, same pattern as
  other Systems-on-Systems dependencies).
- **`Shared/Remotes`** (ModuleScript) — the only client-server bridge so
  far. Creates (server) / waits for (client) a fixed set of RemoteEvents
  under `ReplicatedStorage > Remotes`, returned as a name-keyed table so
  both sides reference the same instances instead of magic strings:
  `RollRequest`, `SummonRequest(cardId)`, `ChallengeRequest(cardId)`,
  `PayTollRequest`, `EndTurnRequest`, `TerraformRequest(targetEra)`
  (client -> server), `StateUpdated(snapshot)`, `ActionResult(message)`
  (server -> client). Request handlers must read the acting player from
  `OnServerEvent`'s own first argument — never a client-supplied one — to
  stay authoritative.
- **`Main.server.lua`** (Script, bootstrap/composition root) — requires
  BoardService, MovementService, CardService, EconomyService, BattleService,
  MatchService, TerraformService, and Remotes. Does NOT spawn tiles — scans
  `CollectionService:GetTagged("Tile")` itself (same tag BoardService
  scans, kept as a separate scan on purpose: BoardService stays
  instance-agnostic/pure data, this is a visual-only concern) to find the
  hand-placed tile Parts and attach a BillboardGui label to each; wires
  signals to visuals (label text, ownership Material flip to Neon, era
  recolor, a per-player ball "Cepter token" parented under a `Cepters`
  folder that walks the board using each tile Part's own `.Position`);
  registers/cleans up Cepters, Magic balances, and turn rotation on
  PlayerAdded/PlayerRemoving. `warn()`s if no tagged tiles are found at
  boot (helps catch a forgotten tag/attribute during hand-authoring). The 6
  `*Request` RemoteEvents are handled here, each gated by
  `MatchService.IsPlayersTurn` (roll also checks `HasRolledThisTurn`)
  before calling into Movement/Battle/Economy/Terraform —
  `sendStateToPlayer`/`refreshAllPlayerStates` push a per-player state
  snapshot (including turn/match info, and the current turn's userId for
  CameraService) over `StateUpdated` whenever anything relevant changes
  (movement, balance, tile ownership/level/era, turn, match end).
- **`StarterPlayer/UIService.client.lua`** (LocalScript) — first slice of
  UIService: a plain monospace "terminal" HUD (`ScreenGui`/`Frame`, no card
  art or animation) with a turn indicator, Magic balance line, current-tile
  info, a card-id `TextBox`, an era-id `TextBox` (raw `EraData.Eras` keys,
  listed in the legend), and Roll/Summon/Challenge/Pay Toll/End Turn/
  Terraform buttons that fire the matching Remote. Action buttons dim when
  it isn't the local player's turn (visual cue only — the server is the
  actual enforcement). Reads `CardData`/`EraData` directly for the legend
  (safe — pure static Shared data, no security concern). Only talks to the
  server through `Shared.Remotes`; cannot and does not require server
  ModuleScripts.
- **`StarterPlayer/CameraService.client.lua`** (LocalScript) — the
  match-wide turn-synced "stage" camera from the design decisions above.
  Takes the camera fully `Scriptable` (no free-roam gameplay exists to lose
  by not using the default follow-avatar camera) and, on every
  `StateUpdated` push where `CurrentTurnUserId` changed, finds that
  player's `"Cepter_"..userId` token under Workspace (plain replication,
  visible to every client automatically — no camera-specific networking)
  and tweens to an angled offset framing it. Also subscribes to that
  token's own `Position` changes while focused on it, so the camera keeps
  following live as the active player rolls/moves during their turn, not
  just once at turn-start. Entirely decoupled from board geometry/data —
  only ever reads a Cepter token's live Position, never tile data — so it
  needed zero changes for the hand-authored-boards switch above.

Not yet built: match setup/lobby and 2v2 alliance mode (see MatchService's
header for what's deferred there), persistence/DataStore layer, terraforming
an owned tile (see TerraformService's header), custom Cepter token model
(still a plain ball), and the rest of UIService (card hand, deck builder).

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

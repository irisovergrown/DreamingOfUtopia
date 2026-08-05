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
  and not just "look at your own Cepter." Implies a future client-side
  system (e.g. `CameraService`, LocalScript) that reacts to match-wide turn
  state — depends on MatchService (turn order) existing first, so it can't
  be built until that system exists.

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
src/ReplicatedStorage/Shared/...        -> ReplicatedStorage > Shared > ...
src/ServerScriptService/Systems/...     -> ServerScriptService > Systems > ...
src/ServerScriptService/Main.server.lua -> ServerScriptService > Main (Script)
```

Every script file's header comment states its Roblox instance type
(`Script` / `LocalScript` / `ModuleScript`), its exact Studio placement, and
its public API.

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
- **`Shared/BoardData`** (ModuleScript) — static greybox board layout: a
  placeholder 16-tile perimeter loop (5x5 grid border), tiles cycling
  through the 4 confirmed eras plus one Start tile. Not final board content
  — just enough geometry to exercise the system end to end. Board rendering
  and movement code should key off `Tile.Id` / `GetNextTileId`, never
  assume this exact geometry, since real board content (a full board *set*)
  comes later.
- **`Systems/BoardService`** (ModuleScript, server) — authoritative owner
  of tile runtime state (owner, level 1-5). Implements the toll/value
  formulas from the gameplay reference (`GetTileValue`, `GetToll`,
  `GetChainMultiplier`, `GetLandBonusHP`). Fires `TileOwnerChanged` /
  `TileLeveledUp` signals; other systems must go through its public API,
  never touch tile state directly.
- **`Systems/MovementService`** (ModuleScript, server) — owns each Cepter's
  (player's) board position and dice rolling (`RollDice`, `MoveCepter`,
  `GetCurrentTile`, `GetLapCount`). Moves tile-by-tile via
  `BoardData.GetNextTileId`, deliberately has no knowledge of tile
  ownership/tolls. Fires `CepterMoved` (per step), `CepterLanded` (move
  finished — this is the hook point for BoardService/BattleService to react
  to landing), and `LapCompleted` (passed Start — hook point for the lap
  bonus once EconomyService exists).
- **`Main.server.lua`** (Script, bootstrap/composition root) — requires
  BoardService and MovementService, builds the physical board onto the
  baseplate from BoardData/EraData, wires their signals to visuals (tile
  labels/material, and a per-player ball "Cepter token" that walks the
  board), and registers/cleans up Cepters on PlayerAdded/PlayerRemoving.
  Includes a **temporary** `/roll` chat command so movement is testable
  without real turn input — replace once MatchService/UIService exist.

Not yet built: CardService (creature/spell/item data + deck building),
BattleService (challenge resolution), EconomyService (gold/TM tracking, win
condition), TerraformService, MatchService (turn order, match setup, FFA/2v2
modes), UIService, persistence/DataStore layer.

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

# Dreaming of Utopia

Roblox board/card game (Culdcept-style). See `CLAUDE.md` for the full
project brief and design context — it loads automatically for Claude Code
sessions in this repo.

## Working locally with Roblox Studio (optional)

`.mcp.json` declares a `Roblox_Studio` MCP server for direct, live editing
of an open Roblox Studio place from a **local** Claude Code / Claude
Desktop session on the same Windows machine as Studio (requires Roblox's
Studio MCP companion running — launched via `%LOCALAPPDATA%\Roblox\mcp.bat`).
This only works locally; cloud/web sessions fall back to the manual
copy-paste workflow described in `CLAUDE.md`.

## Repo layout

This repo is the source of truth for scripts that get **copy-pasted by hand**
into Roblox Studio (no Rojo sync). The `src/` folder mirrors the Studio
instance tree directly:

```
src/ReplicatedStorage/Shared/...                                -> ReplicatedStorage > Shared > ...
src/ServerScriptService/Systems/...                              -> ServerScriptService > Systems > ...
src/ServerScriptService/Main.server.lua                          -> ServerScriptService > Main (Script)
src/StarterPlayer/StarterPlayerScripts/UIService.client.lua       -> StarterPlayer > StarterPlayerScripts > UIService (LocalScript)
src/StarterPlayer/StarterPlayerScripts/CameraService.client.lua   -> StarterPlayer > StarterPlayerScripts > CameraService (LocalScript)
```

Each file's header comment states its Roblox instance type (`Script` /
`LocalScript` / `ModuleScript`), its exact Studio placement, and its public
API. When pasting into Studio: create the instance at the stated path, set
its ClassName/type as stated, paste the body (the file minus the type may
already be code — headers are plain `--[[ ]]` comments and paste in fine as-is).

`tools/` holds one-time Studio Command Bar utility scripts, not part of the
runtime game — currently `recreate-placeholder-board.lua`, which recreates
the old procedural 16-tile loop as real tagged/attributed Parts (a starting
point for hand-editing, see "Board authoring" below).

## Board authoring

The board is hand-authored, not code-generated: place Parts in Workspace,
tag each `"Tile"` (CollectionService), and set attributes in Studio's
Properties panel — `Id` (number, required), `TileType` (`"Start"` or
`"Property"`, required), `Era` (an `EraData.Eras` key, optional/blank =
neutral), `BaseValue` (optional). `BoardService` builds its tile registry
by scanning those tags/attributes at `Init`; `Main.server.lua` never spawns
tiles. Run `tools/recreate-placeholder-board.lua` once from Studio's
Command Bar for a working starting layout to edit from.

## Current systems

- `Shared/Signal` — cross-system pub/sub event object
- `Shared/EraData` — retrofuturism era registry (colors, display names)
- `Systems/BoardService` — hand-authored board registry (scans
  CollectionService-tagged tiles), ownership/level/era state, tile value &
  toll formulas
- `Systems/MovementService` — Cepter board position, dice rolling, move/lap
  signals (topology via `BoardService.GetNextTileId`/`GetStartTileId`)
- `Shared/CardData` — static Creature/Spell/Item card registry (placeholder set)
- `Systems/CardService` — query API over CardData
- `Systems/EconomyService` — Magic balances, lap bonus (auto-applied),
  toll payment, win-target detection
- `Systems/BattleService` — claim/challenge resolution (ST vs effective HP),
  spends Magic Cost via EconomyService, tracks which creature defends each
  claimed tile
- `Systems/MatchService` — turn order rotation, match-end on win target,
  FFA-only team stubs for a future 2v2 alliance mode
- `Systems/TerraformService` — changes an unclaimed Property tile's era for
  Magic, cost scales with level + a surcharge for a specific (non-neutral) era
- `Shared/Remotes` — client-server RemoteEvent bridge (Roll/Summon/Challenge/
  PayToll/EndTurn/Terraform requests, StateUpdated/ActionResult pushes)
- `Main.server.lua` — bootstrap: finds hand-placed tiles (doesn't spawn
  them), spawns a basic R6-shaped stand-in rig per player (plain blocks,
  not final art) and a single colored marker per claimed tile for its
  defending creature, wires Board/Movement/Battle/Economy/Match signals to
  visuals and per-player state pushes over Remotes, gates the 6 action
  RemoteEvents on MatchService's turn checks
- `StarterPlayer/UIService.client.lua` — deliberately plain HUD (standard
  Roblox gray panel, default font, no color theme — turn indicator,
  balance, tile info, card-id + era-id inputs, Roll/Summon/Challenge/Pay
  Toll/End Turn/Terraform buttons, dimmed when it isn't your turn)
- `StarterPlayer/CameraService.client.lua` — match-wide, turn-synced stage
  camera; snaps to and follows whichever player currently has the turn,
  same framing for everyone, computed independently per-client from synced
  turn state (no camera-specific networking)

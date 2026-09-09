# Dreaming of Utopia

Roblox board/card game (Culdcept-style). See `CLAUDE.md` for the full
project brief and design context — it loads automatically for Claude Code
sessions in this repo.

## Syncing code into Studio (Rojo)

`default.project.json` maps this repo into the Studio tree. With Rojo
running, editing a file here updates Studio live — no copy-paste, no
retransmission, and no drift between the repo and the place.

One-time setup, per machine:

```bash
rojo plugin install
```

```bash
rojo serve
```

Install the CLI first if you don't have it — grab a release binary from
<https://github.com/rojo-rbx/rojo/releases>, or manage the version with
[Aftman](https://github.com/LPGhatguy/aftman) (`aftman add rojo-rbx/rojo`).
`rojo plugin install` installs the Studio plugin itself, so there's no
marketplace step. Then in Studio: **Plugins → Rojo → Connect**.

### What Rojo manages — and deliberately does not

Rojo **deletes instances under a managed path that aren't in the repo**, so
the project file is scoped narrowly on purpose. It manages exactly:

| Studio location | Repo path |
|---|---|
| `ReplicatedStorage > Shared` | `src/ReplicatedStorage/Shared` |
| `ServerScriptService > Main` | `src/ServerScriptService/Main.server.lua` |
| `ServerScriptService > Systems` | `src/ServerScriptService/Systems` |
| `ServerScriptService > Tests` | `src/ServerScriptService/Tests` |
| `StarterPlayer > StarterPlayerScripts` | `src/StarterPlayer/StarterPlayerScripts` |

It does **not** manage — and therefore cannot touch or delete:

- **`Workspace`** — the hand-authored board and its tagged tile Parts.
- **`ReplicatedStorage > Models`** — the Cepter token and creature models.
- **`ReplicatedStorage > Remotes`** — created at runtime by `Shared.Remotes`.
- **`ServerStorage > README`** — the git-independent context snapshot.

That split is the whole safety property: scripts live in git and sync one
way into Studio, while everything you author by hand in Studio stays yours
and is never overwritten. Widening a `$path` to a whole service (e.g.
`Workspace`) would put authored content under Rojo's control and it would
be deleted on the next sync. Don't.

## Working locally with Roblox Studio MCP (optional)

`.mcp.json` declares a `Roblox_Studio` MCP server for direct, live editing
of an open Roblox Studio place from a **local** Claude Code / Claude
Desktop session on the same Windows machine as Studio (requires Roblox's
Studio MCP companion running — launched via `%LOCALAPPDATA%\Roblox\mcp.bat`).
This only works locally; cloud/web sessions fall back to the manual
copy-paste workflow described in `CLAUDE.md`.

With Rojo handling script sync, MCP is now for the things Rojo can't do:
inspecting the live tree, reading Studio-authored board/model data, running
the test suite in a playtest, and driving verification.

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
runtime game — `recreate-placeholder-board.lua`, which recreates the old
procedural 16-tile loop as real tagged/attributed Parts (a starting point
for hand-editing, see "Board authoring" below), and
`create-model-folders.lua`, which creates the empty `Models.Player`/
`Models.Summons` folder scaffolding (see "Model authoring" below).

## Model authoring

Cepter tokens and creature summons are real, developer-authored models —
not code-generated. Place them under:

- `ReplicatedStorage > Models > Player > PlayerTemplate` (Model) — a real
  R6 Character with a `Humanoid` and a part named `HumanoidRootPart`.
  Cloned once per joining player.
- `ReplicatedStorage > Models > Summons > <any name>` (Model) — one per
  creature card, matched to `CardData` by a number Attribute named
  `CardId` set on the Model itself.

`Main.server.lua` clones whichever model matches and positions it with
`Model:PivotTo` — it never builds character/creature geometry in code. If a
template is missing it just skips that token/marker with a `warn()`.

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
- `Shared/EraData` — classic four-element registry (Fire/Air/Earth/Water),
  each skinned in a retrofuturism era for flavor (colors, display names)
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
  them), clones a developer-authored Cepter token per player and a
  matching creature model per claimed tile's defender (see "Model
  authoring" above — it never builds this geometry in code), wires
  Board/Movement/Battle/Economy/Match signals to visuals and per-player
  state pushes over Remotes, gates the 6 action RemoteEvents on
  MatchService's turn checks
- `StarterPlayer/UIService.client.lua` — deliberately plain HUD (standard
  Roblox gray panel, default font, no color theme — turn indicator,
  balance, tile info, card-id + era-id inputs, Roll/Summon/Challenge/Pay
  Toll/End Turn/Terraform buttons, dimmed when it isn't your turn)
- `StarterPlayer/CameraService.client.lua` — match-wide, turn-synced stage
  camera; snaps to and follows whichever player currently has the turn,
  same framing for everyone, computed independently per-client from synced
  turn state (no camera-specific networking)

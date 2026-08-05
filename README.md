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
src/ReplicatedStorage/Shared/...       -> ReplicatedStorage > Shared > ...
src/ServerScriptService/Systems/...    -> ServerScriptService > Systems > ...
src/ServerScriptService/Main.server.lua -> ServerScriptService > Main (Script)
```

Each file's header comment states its Roblox instance type (`Script` /
`LocalScript` / `ModuleScript`), its exact Studio placement, and its public
API. When pasting into Studio: create the instance at the stated path, set
its ClassName/type as stated, paste the body (the file minus the type may
already be code — headers are plain `--[[ ]]` comments and paste in fine as-is).

## Current systems

- `Shared/Signal` — cross-system pub/sub event object
- `Shared/EraData` — retrofuturism era registry (colors, display names)
- `Shared/BoardData` — static greybox board layout (16-tile perimeter loop)
- `Systems/BoardService` — authoritative tile ownership/level state, tile
  value & toll formulas
- `Systems/MovementService` — Cepter board position, dice rolling, move/lap signals
- `Main.server.lua` — bootstrap: builds the board on the baseplate, spawns
  Cepter tokens, wires BoardService/MovementService signals to visuals,
  temporary `/roll` chat command for testing movement

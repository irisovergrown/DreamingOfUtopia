# DREAMING OF UTOPIA — FULL HANDOFF

Snapshot: 2026-09-12. Git HEAD at time of writing: `0267f05` on branch
`claude/dreaming-utopia-brief-mimfaw`.

This document is written for an AI (or person) arriving with **no memory of
any previous session**. Read it top to bottom before touching anything. It
says what exists, how to verify it, what is broken or missing, and exactly
what to do next.

It lives in two places:

- `docs/HANDOFF.md` in the git repo — **the source copy**.
- `ServerStorage > README` in the Studio place — a mirror, pasted in so a
  session with only Studio access can still read it.

If the two disagree, git wins. If this document disagrees with the CODE, the
code wins — and fix this document.

---

## 0. READ THIS FIRST

### 0.1 Trust order

1. **The code** in `src/` (and the live place, which is verified identical to
   it — see 3.4).
2. **This document.** Every factual claim here was checked against code or
   the live place on 2026-09-12 unless it says otherwise.
3. **`CLAUDE.md`** — auto-loaded by Claude Code in the repo. Its milestone
   narrative (the "Target architecture and milestones" section onward) is
   accurate. **Several of its earlier sections are stale** and describe the
   pre-rebuild game. See 9.10 for the exact list. Do not act on those
   sections.
4. **`README.md`** — mostly stale below its Rojo section. See 9.10.

### 0.2 The five rules that are not negotiable

These come from the developer's governing brief (see 2.1). Breaking any of
them is a regression regardless of what else improves.

1. **Never overwrite developer-authored models or board geometry.** Workspace,
   `ReplicatedStorage > Models`, and `ServerStorage > README` are
   hand-authored. Rojo is deliberately scoped so it cannot touch them. Never
   widen `default.project.json` to a whole service.
2. **Git is the source of truth.** Anything changed live in Studio must be
   mirrored back to `src/` and committed.
3. **Do not fabricate test results.** Always distinguish: static checks (read
   the code), automated tests (the spec suite), and verified live playtests
   (driving the real server). Say which one you did.
4. **The server validates; the client requests and displays.** No rule
   decision on the client, ever.
5. **Uncertain rules go behind `RulesConfig` marked `UNVERIFIED`**, with what
   would settle them, and you ask the developer for a gameplay check. Never
   bury a guess inline.

And one creative rule: reproduce Culdcept Saga's **rules and timing**, never
its names, art, card text, or assets. All content is original.

### 0.3 If you only have ten minutes

- The game is 7 of 9 milestones through a Culdcept-faithful rebuild. A full
  local turn works end to end on the live server.
- 329 automated tests pass (last run 2026-09-10, no code changed since).
- All 52 scripts in Studio are byte-identical to git (checked 2026-09-12).
- Next work is **not** M7 art yet. Section 10 lists a short set of core-rule
  gaps and a robustness hole (disconnects, no turn timeouts) that should be
  closed first, then M7.
- Ask the developer before: widening Rojo scope, deleting anything they
  authored, renaming a status or keyword that cards reference, or starting a
  milestone. They like to confirm the plan at each milestone start.

---

## 1. THE PROJECT

### 1.1 What it is

**Dreaming of Utopia** — a Roblox board/card strategy game, "Monopoly meets
Magic: The Gathering", in the lineage of **Culdcept Saga** (Xbox 360,
OmiyaSoft). No Roblox game does this. Produced under the in-fiction studio
banner **"Ninth Signal"**.

Players ("Cepters") roll dice and move around a board graph, claim territories
by summoning creature cards onto them, charge each other tolls, fight battles
for land, and win by reaching a Total Magic goal **and confirming it at a
castle**.

### 1.2 Elements and their visual skins

Four classic elements are the mechanic. Each is *skinned* in one
retrofuturism era — flavour only, never the mechanical unit.

- **Fire = Laser Grid** — glossy 1980s corporate future: neon grids, chrome,
  reflective glass.
- **Air = Early Cyber** — Tron grid, phosphor-green terminals.
- **Earth = Cassette Futurism** — beige plastic, tape reels, analog optimism.
- **Water = Frutiger Aero** — glossy translucent blue/green, dew-drop
  nature-tech.

Fixed at four. Element ids are canonical `Fire`/`Water`/`Air`/`Earth`; a
display label must never become a second set of ids. Keep Frutiger Aero
(glossy/organic) visually distinct from Y2K (hard/chrome).

### 1.3 Confirmed design decisions (do not re-litigate)

- 2–4 players. FFA and 2v2 alliance modes (2v2 not built).
- Match length scales with board size.
- Free to play, **cosmetic-only** Robux purchases. No pay-to-win.
- Card unlocks earned by **winning matches** — not bought, not daily login.
- Launch library: curated 60–80 cards.
- Fixed official boards only, no board editor.
- PC/console primary, mobile secondary.
- Single-player campaign is post-launch (1.0). Alpha/beta is PvP core only.
- Cepter token becomes a custom piece model (a cosmetic slot), not the Roblox
  avatar.
- **Camera is match-wide and turn-synced**: one angled stage camera framing
  whoever holds the turn, identical for everyone. Not per-player free camera.
- **Card presentation** (developer's design, 2026-09-09): cards are simple
  rounded rectangles with text for now, laid out in a Culdcept-style row along
  the bottom. **Exactly one hand is on screen at a time** — the hand of
  whoever is currently entitled to decide. Its owner sees faces; everyone else
  sees the same number of card backs in the same place. You never see your
  own cards on someone else's turn.
- **Canonical status set** for spell cards: `docs/status-backlog.md`
  (2026-09-11). Do not invent statuses outside it.
- UI direction: see `docs/ui-master-prompt.md` (settled 2026-09-11) — neutral
  "Ninth Signal" house style, printed-and-industrial materials, lean
  persistent HUD with full-focus takeovers, hybrid diegetic lobby. It is a
  brief written to be pasted into Claude Design.

### 1.4 Still genuinely open

- Mechanical identity per element beyond typing and land bonus.
- The real card list and all balance numbers.

---

## 2. THE GOVERNING BRIEF AND HOW WORK IS RUN

### 2.1 Where the brief is

The developer's "Claude Master Implementation Package" governs all rules work.

⚠ **It is not in the repo.** It exists only at
`C:\Users\ldyou\Downloads\Dreaming-of-Utopia-Claude-Master-Package.md` on the
developer's main PC (767 lines). A session on any other machine cannot read
it. Recommended: ask the developer whether to commit it to `docs/` (it is
their document; do not commit it without asking).

Its structure, so you know what to look up: §1 outcome, §2 vocabulary, §3
match state machine, §4 board and movement, §5 landing action matrix, §6
territory commands, §7 economy/tolls/victory, §8 books and card engine, §9
battle flow, §10 special nodes and symbols, §11 status and timing framework,
§12 Roblox architecture, §13 presentation behaviour, §14 original repo audit,
§15 milestones, §16 acceptance tests, §17 working protocol, §18 first
response. §18 (audit and plan before coding) has **already been done and
approved** — do not redo it.

### 2.2 Milestone protocol the developer expects

- At the **start** of a milestone: state the files you will change and the
  acceptance tests that will prove it. The developer usually confirms.
- At the **end**: report verified results, clearly separating automated from
  live verification, and list remaining limitations honestly.
- Resolve genuine open questions **before** building, not mid-way. The
  developer explicitly prefers "all needed questions first".
- Commit per milestone with a descriptive message, push, update `CLAUDE.md`.
- Keep the roadmap artifact current (see 11).

### 2.3 Brief milestones

- M0 Safety net and schemas — **done**
- M1 Match and turn state machine — **done** (turn timeouts missing, see 9.3)
- M2 Graph movement — **done**
- M3 Book, hand, card lifecycle — **done**
- M4 Landing and battle — **done**
- M5 Territory and full economy — **done** (3 of 5 territory commands
  missing, see 9.2)
- M6 Card, status, special-node engine — **done for statuses and effects**;
  special nodes and symbols **not built** (see 9.1)
- M7 Content and production presentation — **next**
- M8 Secondary-system skeletons — not started

---

## 3. ENVIRONMENT AND TOOLING

### 3.1 Machine and repo

- Windows 11. Shells available to an agent: Git Bash and PowerShell 5.1.
- **No Python** and **no local Lua/Luau interpreter**. Syntax is only checked
  by Studio. Do not plan on running Lua outside Studio.
- Repo: `D:\random projects\DreamingOfUtopia`
- Remote: `https://github.com/irisovergrown/DreamingOfUtopia`
- Branch: `claude/dreaming-utopia-brief-mimfaw` — all work happens here.
- Git warns "LF will be replaced by CRLF" on commit. Harmless; expected.

### 3.2 Repo layout

```
CLAUDE.md                 auto-loaded project memory (partly stale, 9.10)
README.md                 Rojo setup (accurate) + stale sections below
default.project.json      Rojo project, deliberately narrow scope
rokit.toml                pins rojo-rbx/rojo@7.7.0
.mcp.json                 Roblox_Studio MCP server launcher
docs/HANDOFF.md           this file
docs/status-backlog.md    canonical status set for spell cards
docs/ui-master-prompt.md  UI/visual brief for Claude Design
tools/                    one-time Studio Command Bar scripts (not runtime)
src/ReplicatedStorage/Shared/...           -> ReplicatedStorage > Shared
src/ServerScriptService/Main.server.lua    -> ServerScriptService > Main
src/ServerScriptService/Systems/...        -> ServerScriptService > Systems
src/ServerScriptService/Tests/...          -> ServerScriptService > Tests
src/StarterPlayer/StarterPlayerScripts/... -> StarterPlayerScripts
```

Every script's header comment states its instance type, exact Studio
placement, and public API. Keep that convention.

### 3.3 Roblox Studio and MCP

- Place: **"Dreaming of Utopia [ALPHA]"**, placeId `84614866720426`.
- MCP server `Roblox_Studio` (declared in `.mcp.json`) only works in a
  **local** session on the same Windows machine as Studio.
- **Every MCP call needs a `studio_id`, and it changes whenever Studio
  restarts.** Always call `list_roblox_studios` first.
- `execute_luau` takes `datamodel_type`: `Edit`, or during a playtest
  `Server` / `Client`.
- **HttpService is disabled in the place.** Studio cannot fetch GitHub. Every
  fetch fails, which looks like "file missing". Use the checksum method (3.5)
  to compare Studio with git.

### 3.4 Rojo

- Pinned 7.7.0 via Rokit. `rokit install` once per machine, then from the repo
  root: `rojo serve`. Serves on **localhost:34872**. In Studio: Plugins →
  Rojo → Connect.
- Rojo **manages** exactly: `ReplicatedStorage > Shared`,
  `ServerScriptService > Main / Systems / Tests`,
  `StarterPlayer > StarterPlayerScripts`.
- Rojo **does not manage**: `Workspace` (the authored board),
  `ReplicatedStorage > Models`, `ReplicatedStorage > Remotes` (created at
  runtime), `ServerStorage > README` (this file's mirror). That split is the
  safety property. Rojo deletes unknown instances under paths it manages.
- If `rojo serve` exits with code 4 right after printing "listening", another
  Rojo server already holds the port. On 2026-09-12 **two `rojo.exe`
  processes were running**. Check with `tasklist | grep -i rojo` before
  starting another.
- Known Rojo behaviour seen in M5: it propagated a file **rename** but not
  plain **deletions** until the plugin reconnected. After deleting a module,
  confirm it is gone from Studio.
- After a Studio restart the plugin must be reconnected. A half-synced tree
  once caused confusing test failures; when results look impossible, checksum
  first (3.5).
- **State on 2026-09-12: all 52 synced scripts in Studio match git exactly.**

### 3.5 Verifying Studio matches git (checksum method)

Hash every script on both sides with the same normalisation (CRLF→LF, strip
trailing whitespace per line, strip trailing newlines), rolling hash
`h = (h*31 + byte) % 1000000007`, and diff the two sorted lists.

Studio side (`execute_luau`, `Edit`):

```lua
local function norm(s)
	s = s:gsub("\r\n", "\n")
	local lines = {}
	for line in (s .. "\n"):gmatch("(.-)\n") do
		table.insert(lines, (line:gsub("%s+$", "")))
	end
	return (table.concat(lines, "\n"):gsub("\n+$", ""))
end
local function hash(s)
	local h = 0
	for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 1000000007 end
	return h
end
local results = {}
local function walk(inst, prefix)
	for _, child in ipairs(inst:GetChildren()) do
		local key = prefix .. child.Name
		if child:IsA("LuaSourceContainer") then
			table.insert(results, key .. "=" .. hash(norm(child.Source)))
		end
		if #child:GetChildren() > 0 then walk(child, key .. "/") end
	end
end
local SSS = game:GetService("ServerScriptService")
walk(game.ReplicatedStorage.Shared, "Shared/")
walk(SSS.Systems, "Systems/")
walk(SSS.Tests, "Tests/")
walk(game.StarterPlayer.StarterPlayerScripts, "StarterPlayerScripts/")
table.insert(results, "Main=" .. hash(norm(SSS.Main.Source)))
table.sort(results)
return #results .. " scripts\n" .. table.concat(results, "\n")
```

Repo side (PowerShell):

```powershell
$root = "D:\random projects\DreamingOfUtopia\src"
$map = @(
  @{ Dir = "$root\ReplicatedStorage\Shared"; Prefix = "Shared/" },
  @{ Dir = "$root\ServerScriptService\Systems"; Prefix = "Systems/" },
  @{ Dir = "$root\ServerScriptService\Tests"; Prefix = "Tests/" },
  @{ Dir = "$root\StarterPlayer\StarterPlayerScripts"; Prefix = "StarterPlayerScripts/" }
)
function Get-Norm([string]$t) {
  $t = $t.TrimStart([char]0xFEFF) -replace "`r`n", "`n"
  (($t -split "`n" | ForEach-Object { $_.TrimEnd() }) -join "`n").TrimEnd("`n")
}
function Get-Hash([string]$t) {
  [long]$h = 0
  foreach ($b in [Text.Encoding]::UTF8.GetBytes($t)) { $h = ($h * 31 + $b) % 1000000007 }
  $h
}
$out = New-Object System.Collections.Generic.List[string]
foreach ($m in $map) {
  Get-ChildItem $m.Dir -Recurse -Filter *.lua | ForEach-Object {
    $rel = $_.FullName.Substring($m.Dir.Length + 1) -replace '\\', '/'
    $name = $rel -replace '\.server\.lua$|\.client\.lua$|\.lua$', ''
    $out.Add("$($m.Prefix)$name=$(Get-Hash (Get-Norm ([IO.File]::ReadAllText($_.FullName))))")
  }
}
$out.Add("Main=$(Get-Hash (Get-Norm ([IO.File]::ReadAllText("$root\ServerScriptService\Main.server.lua"))))")
$out | Sort-Object { $_ } -Culture ([Globalization.CultureInfo]::InvariantCulture)
```

Byte or line counts alone mislead: the checkout uses CRLF.

---

## 4. TESTING AND VERIFICATION — HOW, AND THE TRAPS

### 4.1 Running the suite

Specs: `ServerScriptService > Tests > Specs`, runner `Tests.TestRunner`. A
spec is `{ Name, Tests = { { description, fn }, ... } }` — an ordered array so
report lines never shuffle. Assertion methods: `Equal`, `NotEqual`, `True`,
`False`, `Nil`, `NotNil`, `Near`, `DeepEqual`, `Throws`, `DoesNotThrow`,
`Contains`. A spec that fails to **load** counts as a failure.

**Run only inside a playtest, against the Server datamodel:**

1. `start_stop_play` with `is_start = true`
2. `execute_luau`, `datamodel_type = "Server"`:

```lua
local Tests = game.ServerScriptService.Tests
return require(Tests.TestRunner).runAll(Tests.Specs)
```

### 4.2 Traps that each cost real time

- **Edit-mode `require` is cached for the whole session.** A module required
  once returns the stale table after any edit, so the suite silently tests old
  code. Never run tests in Edit.
- **Edits made during a playtest do not reach the running playtest.** Rojo
  writes into the Edit datamodel. After changing code, **stop and restart**
  the playtest, then run the suite. (Found 2026-09-10: a one-line fix appeared
  not to work until the playtest was restarted.)
- **`execute_luau` has its own module cache**, shared between its own calls
  but **separate from the running game**. Requiring `BattleService` there gives
  you a different instance from the one `Main.server.lua` uses. Consequences:
  the suite cannot corrupt a live match, but you **cannot inspect live match
  state** (balances, defenders, statuses) through `require` either.
- To reach the **real** server, fire a RemoteEvent from the **Client**
  datamodel. Remotes cross the network layer, so the real `OnServerEvent`
  handler runs. See 4.3.
- Expected noise in the console during a suite run: three "deliberate
  failure" errors from SignalSpec and StatusSpec. They test error isolation.
- No Python, no local Lua: there is no way to syntax-check Luau except by
  loading it in Studio.

### 4.3 Driving a live turn

Snapshots are only pushed on change, so a fresh listener may receive nothing.
Read the HUD's own labels from `Client` (`PlayerGui` descendants) to learn the
phase and the hand's instance ids (buttons named `Card_<instanceId>`).

Then submit intents:

```lua
local RS = game:GetService("ReplicatedStorage")
local Remotes = require(RS.Shared.Remotes)
local Enums = require(RS.Shared.Enums)
-- intent, sequence, the phase you believe the server is in, payload
Remotes.SubmitIntent:FireServer(Enums.Intent.CastSpell, 9001,
	Enums.Phase.SpellChoice, { InstanceId = "c33" })
```

Listen on `Remotes.ActionResult.OnClientEvent` and
`Remotes.StateUpdated.OnClientEvent`, and `task.wait(~0.7)` between intents.

⚠ Use **high sequence numbers** (9000+). The server only requires them to
increase. This leaves the real HUD's own counter behind, so the HUD's next
clicks are refused as stale. **Restart the playtest afterwards.**

A single-player playtest can never test a two-player battle: the defender is
a different player. Use Studio's Test → Clients and Servers with 2 players.

### 4.4 Current verified state

Automated (playtest, 2026-09-10) — **329 passed, 0 failed, 5,585 assertions**:

| Spec | Tests |
|---|---|
| ActionResult | 10 |
| ActionValidator | 18 |
| Battle | 35 |
| BoardDefinitionValidator | 21 |
| Characterization (defects closed) | 11 |
| DeckService | 20 |
| CardEffects (EffectSpec) | 15 |
| MatchOrchestrator | 26 |
| Movement (graph) | 24 |
| PhaseGraph | 22 |
| RandomService | 15 |
| RulesConfig | 22 |
| Signal | 19 |
| SnapshotService | 17 |
| Status | 24 |
| Territory & economy | 30 |

Only documentation changed after that run (commit `0267f05`), and the
2026-09-12 checksum confirms Studio matches git.

Live-verified through the real server (single player):

- M1: phase flow, intent rejection paths.
- M2: movement on the ring.
- M3: draw, hand display with backs for non-owners.
- M5: developing a territory L1→L3 cost 300 CM and raised land value by 450,
  so TM rose by 150 while cash fell.
- M6 (2026-09-10): `SpellChoice` stops and offers Cast / No Spell; casting
  Signal Boost charged 500→485, consumed the card, and showed
  `AttackBoost(20)` in the public snapshot; Call Sign Six turned a natural
  roll of 2 into 6 and removed itself; Dead Air refused the roll
  ("You cannot roll this turn") and ended the turn without moving the token.

**Never live-verified:** a two-player battle (attacker→defender item
handoff), poison ticking on a real board creature and repainting its label,
liquidation and bankruptcy in a real match, castle victory confirmation in a
real match.

---

## 5. ARCHITECTURE

### 5.1 The four inversions the rebuild made

1. A **phase state machine** replaced implicit turn state.
2. A **board graph** replaced a sorted-id loop.
3. **Ordered, value-transforming effect hooks** replaced fire-and-forget
   signals.
4. **Owned, consumed card instances** replaced a static registry players
   indexed by typing a number.

### 5.2 Request path (one door in)

Client sends exactly one remote:
`SubmitIntent(intent, sequence, expectedPhase, payload)`.

In `Main.server.lua` every request passes, in order:

1. `MatchOrchestrator.SubmitIntent(userId, intent, sequence, entitledUserId)`
   — right player for this phase, sequence strictly increasing, match running.
   The entitled user is the active player, **except** in phases whose actor is
   `Defender`, where it is `BattleService.GetDefenderUserId()`. A rejected
   intent does not consume its sequence number.
2. `expectedPhase` must equal the current phase, or it is stale.
3. `ActionValidator` — intent is legal in this phase for this actor.
4. The intent handler, which calls services. Affordability and targeting are
   validated where the payment happens.

The acting player always comes from `OnServerEvent`'s first argument, never
the payload. Every rejection path returns before mutating anything; tests
assert "failed AND nothing changed".

Server → client: `StateUpdated(snapshot)` and `ActionResult(result)`.

### 5.3 Snapshots and secrecy

`SnapshotService.Build(userId)` returns a **public** part (phase, turn,
round, active player, standings with hand **counts** and public statuses) and
a private `You` part (CM, legal intents, own hand, book/discard counts,
pending junction route). `CurrentTile` describes where the recipient stands.

Hidden information is enforced by **omission**: an opponent's snapshot has no
card identities in it at all. Never add a "hidden" flag and trust the client.

`You.LegalIntents` comes from the same `ActionValidator` table the server
validates against, so enabled buttons and accepted requests cannot drift.

### 5.4 Signal

`Shared/Signal`: `Fire` is **synchronous** and runs handlers in priority order
(lower first, ties by connection order). `Fold(value, ...)` threads a value
through handlers (nil return leaves it unchanged) — the basis of every
modifier pipeline. Handler errors are isolated. `FireAsync` exists for
presentation only; **rules code must never use it**. A yielding handler blocks
the firer, deliberately.

`Connect(handler, priority, label)` — Main labels its connections.

### 5.5 RulesConfig

Every rule constant and formula lives in `Shared/RulesConfig`. Nothing else
may inline a multiplier, rate, size or cost. Land value and toll are computed
from **integer numerators over 10**, never decimals, because floating
`200 * 0.3` only reaches 60 by luck and `floor()` on it can charge 59.

### 5.6 ActionResult

`Ok = true` means accepted and processed — **including losing a battle**,
which is a successful action with a bad result. `Ok = false` means refused,
nothing spent, nothing moved; it requires a real `Enums.RejectReason`. Results
are frozen.

### 5.7 Enums

Frozen name→name maps whose `__index` throws on unknown keys. Two Luau
constraints learned the hard way: attach a metatable **before**
`table.freeze`; and `table.freeze` refuses a table with a protected
`__metatable`, so enums use freezing only.

Key vocabularies (verbatim):

- **Phase (28):** WaitingForPlayers, MatchSetup, TurnStart, Draw,
  HandOverflowDiscard, SpellChoice, SpellTargetChoice, SpellResolution,
  RollReady, DiceResolution, Movement, JunctionChoice, PassEffectChoice,
  LandingResolution, LandingActionChoice, SummonChoice, BattleSetup,
  AttackerItemChoice, DefenderItemChoice, BattleResolution, TollResolution,
  TerritoryCommandChoice, TerritoryCommandResolution, TurnEnd, RoundEnd,
  Liquidation, VictoryCheck, MatchComplete
- **Intent (15):** DiscardToHandLimit, CastSpell, SkipSpell,
  ChooseSpellTarget, Roll, ChooseJunction, ChoosePassEffect,
  ChooseLandingAction, ChooseSummon, ChooseBattleItem,
  ChooseTerritoryCommand, PayToll, ChooseLiquidation, ConfirmResult, EndTurn
- **RejectReason:** WrongPhase, NotYourTurn, NotAParticipant, StaleSequence,
  DuplicateSequence, UnknownMatch, MatchEnded, InsufficientMagic,
  InvalidTarget, InvalidCard, CardNotInHand, IllegalAction, RuleViolation,
  Timeout
- **TimingHook:** BeforeDraw, AfterDraw, BeforeSpell, BeforeRoll, ModifyRoll,
  OnNodeExited, OnNodeEntered, OnLand, BeforeBattleStats, BeforeItem,
  BeforeAttack, OnDamage, AfterAttack, BattleEnd, OnLap, TurnEnd, RoundEnd
- **NodeType:** Territory, Castle, Fort, Shrine, FortuneTeller, LandingWarp,
  MandatoryWarp, Temple, Fountain, BoardAction
- **TerritoryCommand:** LevelLand, ChangeElement, MoveCreature,
  ExchangeCreature, TerritoryAbility
- **MovementCause:** Roll, ForcedMove, Transport, Recall, CreatureMove
- **SpeedClass:** First, Normal, Last. **ItemCategory:** Weapon, Armor,
  Tool, Scroll.
- Also: Element, CardType, LandingAction, BattleOutcome, DurationType
  (Instant, Turns, Rounds, Permanent, UntilBattleEnd, UntilNextRoll),
  StatusTarget (Player, Creature, Territory, Area, Global), StackingPolicy
  (Replace, Stack, Ignore, RefreshDuration), Actor (ActivePlayer, Defender,
  AnyParticipant, None), Visibility.

### 5.8 Module map

Shared (`ReplicatedStorage > Shared`):

- `ActionResult` — structured action results (5.6).
- `BoardDefinitions/CurrentLoop` — the live board as graph data (7.1).
- `BoardDefinitions/TestBoard01` — proving board, data only (7.2).
- `CardData` — the 28 placeholder cards (7.4).
- `ElementData` — the four elements with display name, colour, `EraName`,
  `EraFlavor`. (Renamed from `EraData` in M5; old docs still say EraData.)
- `Enums` — vocabularies (5.7).
- `PhaseGraph` — legal phase transitions as data. Movement never self-loops;
  `AttackerItemChoice → DefenderItemChoice` is the only route between them;
  `TollResolution → Liquidation` exists; Doublecast is an ordinary
  `SpellResolution → SpellChoice` edge.
- `Remotes` — creates/waits for `SubmitIntent`, `StateUpdated`,
  `ActionResult` under `ReplicatedStorage > Remotes`.
- `RulesConfig` — every constant and formula (6.1).
- `Signal` — ordered sync pub/sub with `Fold` (5.4).

Server systems (`ServerScriptService > Systems`), with line counts:

- `ActionValidator` (259) — phase → expected actor + legal intents; used for
  both validation and `LegalIntents`.
- `BattleService` (749) — summon, invasion state machine, strike resolution
  (`resolveStrike`), defender state, `DamageDefender`, `ApplyDefenderHPBuff`.
  Folds `BeforeBattleStats` for both combatants.
- `BoardDefinitionValidator` (362) — rejects malformed boards, reports every
  error at once.
- `BoardGraphService` (280) — topology only. `GetLegalExits(node, cameFrom)`
  compares **destinations, not edge ids**.
- `BoardVisualService` (369) — tile labels, ownership/element visuals, Cepter
  tokens, defender models. Decides nothing; deleting it would leave a correct
  headless match.
- `CardEffectService` (189) — resolves a card's `Effects` list via
  EffectPrimitives. Charges cost first; refunds and does not consume on any
  failure (refund, not rollback).
- `CardService` (70) — query API over CardData.
- `DeckService` (305) — book, hand, discard, recycle; card instances with ids.
- `EconomyService` (252) — Current Magic, `RequirePayment` (takes what exists,
  records debt), tolls, liquidation, bankruptcy, lap bonus on
  `LapService.LapCompleted`.
- `EffectPrimitives` (239) — the effect verbs: GainMagic, LoseMagic, Draw,
  ForceRoll, ApplyStatus, ApplyCreatureStatus, ApplyGlobalStatus,
  BoostNextAttack, BuffDefenderHP, Teleport. Each declares a target kind
  (Caster, ChosenPlayer, ChosenTerritory, CurrentTerritory, Global).
- `LapService` (152) — fort types visited, lap completion at castle.
- `MatchLogService` (165) — append-only frozen log, capped, counts drops.
- `MatchOrchestrator` (367) — **sole phase authority**; participants, active
  player, turn/round counters, intent sequencing.
- `MatchService` (203) — ⚠ **dead code.** The pre-rebuild turn service. Nothing
  requires it. Candidate for deletion (ask first).
- `MovementService` (428) — resumable movement transactions, junction pause,
  transports, `RollDice` folded through `ModifyRoll`, `CanRoll` via
  `BeforeRoll`, `TeleportTo`.
- `RandomService` (140) — deterministic Lehmer/MINSTD RNG, seedable,
  Fisher-Yates shuffle. Deliberately not Roblox `Random`.
- `SnapshotService` (284) — per-player snapshots (5.3).
- `StatusDefinitions` (265) — behaviour per status kind.
- `StatusService` (359) — status registry, ordered hook dispatch, durations.
- `TerritoryService` (283) — owner/level/element keyed by node id; chains,
  land value, toll, development, element change.
- `ValuationService` (116) — Total Magic = CM + land + symbols (symbols
  always 0, see 9.1).
- `VictoryService` (142) — goal-reached state, castle confirmation re-checks
  TM.

Composition root: `ServerScriptService > Main` (Script). Init order is
explicit: MatchLog → Orchestrator → board load (errors loudly if invalid) →
Territory → Lap → **Status** → Movement → Economy → Valuation → Victory → Deck
→ Battle → EffectPrimitives → CardEffect → BoardVisual → Snapshot. It holds
the turn driver and all intent handlers.

Client (`StarterPlayerScripts`):

- `UIService` (LocalScript) — deliberately plain debug HUD (6.8).
- `CameraService` (LocalScript) — turn-synced stage camera (6.9).

Tests: `Tests/TestRunner` and 16 specs (4.4).

Tools (`tools/`, run once from the Studio Command Bar, not part of the game):
`create-model-folders.lua`, `recreate-placeholder-board.lua` (pre-rebuild
era; the board already exists).

---

## 6. THE GAME AS IMPLEMENTED

### 6.1 Numbers (from RulesConfig)

- Starting Magic **500**. TM goal **3000**. Players 2–4 (`MinPlayers` and
  `MaxPlayers` are declared; min is not enforced, see 9.3).
- Book **50** (min 30, max 60), **max 4 copies** per card. Hand max **6**,
  opening hand **5** (so the first turn's draw fills to 6 exactly).
- Roll range 1–6 by default (board definitions may override).
- Land levels 1–5. Default base value 100.
- Land value = `Base × 2^(Level−1) × Chain`. Base 100 gives 100, 200, 400,
  800, 1600 before chains.
- Chain multipliers **1.0 / 1.5 / 1.8 / 2.0 / 2.2** (chain size capped at 5).
  Chains are **area-scoped**: same element, same owner, same area.
- Toll = land value × **0.2 / 0.3 / 0.4 / 0.6 / 0.8** by level.
- Development cost = cumulative **unchained** value increase.
- Terrain change cost = **100 per level + 200 surcharge** if the land is
  already elemental.
- Land bonus HP = **10 × level** for a creature whose element matches the
  land. Temporary, battle only.
- Critical multiplier **1.5**.
- Liquidation sale rate **0.5** of land value. (UNVERIFIED)
- Lap bonus = `magic + floor(magic × (lap − 1) / 10) + 20 × ownedTerritories
  + floor(symbolValue × 10 / 100)`, where `magic` is the board's default
  starting Magic. Applied by EconomyService on `LapService.LapCompleted`.
  Symbol value is always 0 today (9.1).
- Rounding mode `floor`. (UNVERIFIED)
- Lap heal **50% of MHP**. (UNVERIFIED **and not applied anywhere**, 9.2)
- `SupportSTPerAdjacent = 10`. (Declared, **not applied anywhere**, 9.2)

### 6.2 The turn, as the server runs it

`TurnStart → Draw` (draw 1). If the hand is over 6 →
`HandOverflowDiscard` until legal.

`SpellChoice` **stops and waits**. `CastSpell` (payload `InstanceId`, optional
`TargetUserId`, `TargetNodeId`) resolves the card and passes
`SpellResolution → SpellChoice`, so the player may keep casting.
`SkipSpell` advances to `RollReady`.

`Roll`: if `MovementService.CanRoll` is false (paralysis), the server passes
`DiceResolution → Movement → LandingResolution` without moving and ends the
turn. Otherwise it rolls, folds through `ModifyRoll`, and reports
"Rolled N (natural M)" when a status changed the result.

`DiceResolution → Movement`. Movement may pause in `JunctionChoice`;
`ChooseJunction` (payload `EdgeId`) resumes with remaining steps. A warp
relocates **without consuming a step**. Entering or crossing the castle
triggers the victory check (6.6).

`LandingResolution`, then the landing matrix:

- Non-territory node (castle etc.): nothing to do, turn ends.
- **Unowned** territory: `ChooseSummon` claims it (card consumed, turn ends).
- **Your own** territory: `ChooseTerritoryCommand` — `LevelLand` (payload
  `Level`) or `ChangeElement` (payload `Element`). Also `EndTurn`.
- **Enemy** territory: `PayToll`, or `ChooseSummon` to invade.

Toll: `PayToll` always charges. If short, the shortfall becomes debt and the
phase moves to `Liquidation`, where `ChooseLiquidation` sells territories at
the sale rate until the debt is paid, or the player is declared bankrupt.

Invasion: `BattleSetup → AttackerItemChoice` (invader `ChooseBattleItem`,
payload `InstanceId` or empty for No Item) `→ DefenderItemChoice` (the
**defender** submits) `→ BattleResolution`. If a toll is owed after the
battle, `TollResolution` charges it. Turn ends.

`TurnEnd`: fire `TurnEnd` hook for the ending player (with `GetCreature` and
`DamageCreature` lookups), tick `Turns` durations scoped to that player.
`VictoryCheck`: refresh goal states for everyone; if a win is confirmed →
`MatchComplete`. Otherwise advance to the next player; if the rotation
wrapped → `RoundEnd` (fire `RoundEnd` hook, tick `Rounds` durations) →
`TurnStart`.

Match start: the **first player to join** triggers
`WaitingForPlayers → MatchSetup` and gets the first turn immediately. Later
joiners are added to the rotation mid-match.

Player leaving: Cepter, deck and economy records are removed, **all their
territories are released** (so chains shrink), and if they were the active
player the turn advances. See 9.3 for the gap.

### 6.3 Who may act in each phase (ActionValidator)

- HandOverflowDiscard — active player — DiscardToHandLimit
- SpellChoice — active — CastSpell, SkipSpell
- SpellTargetChoice — active — ChooseSpellTarget (no handler, 9.4)
- RollReady — active — Roll
- JunctionChoice — active — ChooseJunction
- PassEffectChoice — active — ChoosePassEffect (no handler, 9.4)
- LandingActionChoice — active — the landing matrix intents
- SummonChoice — active — ChooseSummon
- AttackerItemChoice — active — ChooseBattleItem
- **DefenderItemChoice — Defender** — ChooseBattleItem
- TollResolution — active — PayToll
- Liquidation — active — ChooseLiquidation
- TerritoryCommandChoice — active — ChooseTerritoryCommand, EndTurn
- Every other phase — actor None; server-driven; all requests refused.

Intent handlers that exist in Main: CastSpell, SkipSpell, Roll,
ChooseJunction, DiscardToHandLimit, ChooseSummon, ChooseBattleItem, PayToll,
ChooseTerritoryCommand, ChooseLiquidation, EndTurn.

### 6.4 Battle

- The invader commits an item first; the defender chooses **knowing** what
  was committed. Enforced structurally.
- Speed ranks First 3 / Normal 2 / Last 1; higher strikes first; **invader
  wins ties**. A lethal first strike ends the battle (no counter).
- Creature state keeps `BaseST`, `BonusST`, `BaseMHP`, `BonusMHP`,
  `CurrentHP`. The land bonus is **computed fresh per battle** from the land's
  current element and level and never written into the creature — which is
  why terraforming owned land is safe.
- Temporary HP (land bonus, armour) absorbs damage before persistent HP.
  (UNVERIFIED against the source game.)
- Keywords, read from card data, never names: First, Last, Critical,
  Penetration (ignores land bonus), Neutralize (first ordinary strike → 0),
  Reflect (→ 0 and returned), Regenerate (survivor restored to full at battle
  end), Support (a creature may be used as the battle item).
- Scrolls deal fixed damage, bypass the land bonus and ordinary
  Neutralize/Reflect.
- Outcomes: invader wins (land transfers, no toll), invader dies (defender
  keeps land, toll owed), both survive (attacker returns card, toll owed),
  both destroyed (vacant, no toll — **currently unreachable** with existing
  keywords).
- ST modifiers from statuses: `battleSTBonus` folds `BeforeBattleStats` for
  attacker and defender alike.

### 6.5 Economy and valuation

- **Current Magic (CM)** is spendable cash (EconomyService).
- **Total Magic (TM)** = CM + land value + symbol value (ValuationService),
  always recomputed. Standings and victory read TM.
- Developing land lowers CM but raises TM when the value gained exceeds the
  cost. That trade is the core strategic loop.

### 6.6 Victory

Two steps. Reaching the TM goal sets a visible, **losable** goal-reached
state. The win is confirmed only on **entering or crossing a castle**, where
TM is **re-checked**. A rival who takes your land on the way home can put you
back below the line.

### 6.7 Statuses and effects

`StatusService.Apply(spec)`: `Kind`, `TargetType`, `TargetId`,
`OwnerPlayerId`, `ScopeUserId`, `SourceCardId`, `DurationType`,
`RemainingDuration`, `Priority`, `Value`, `Visibility`, `StackingPolicy`.

`RunHook(hook, context, value)` folds every matching status in **priority
order** (lower first, then application order) and logs the resolved order.
`FireHook` is the no-value form. `status.Consumed = true` inside a handler
removes it immediately. `ReplacementGroup` evicts different kinds on the same
target. `ScopeUserId` says whose turns a status counts down on when that is
neither caster nor target (poison on an enemy creature).

Hooks that are actually **dispatched** today: `ModifyRoll` and `BeforeRoll`
(MovementService), `BeforeBattleStats` (BattleService), `TurnEnd` and
`RoundEnd` (Main). **All other hooks are declared but never fired** — a
definition on them does nothing.

Defined statuses:

- `ForcedRoll` — priority −100, replaces the roll, consumed. Group
  `RollOverride`.
- `Haste` / `Slow` — priority 0, ± to the roll, RefreshDuration.
- `RollClamp` — priority 1000, global, clamps to the legal range.
- `Poison` — creature, ticks on `TurnEnd` of the creature's **owner**, floors
  at 1 (cannot kill), damages through `BattleService.DamageDefender`.
  Tick timing UNVERIFIED.
- `Paralysis` — `BeforeRoll` returns false. Group `RollOverride`.
- `AttackBoost` — `BeforeBattleStats`, attacker only, consumed, stacks.
- `GlobalAttackShift` — every combatant's ST, lasts a round.

Card resolution: `CardEffectService.Resolve` → validate instance and cost →
**spend first** → resolve each effect's target → run the primitive → on any
failure refund and keep the card → on success consume and log.

The **canonical set of statuses to build next** is `docs/status-backlog.md`.
Summary: Haste/slow done; Poison done, Regen missing; Strength up/down half
(persistent up/down missing); Immobilised done as `Paralysis` (rename
decision); **Silenced** and **Invulnerable/shielded** missing and need
`BeforeSpell` / `OnDamage` to be dispatched first; Debt exists in
EconomyService and should stay there, only surfaced in the UI.

### 6.8 The HUD (UIService)

Plain Roblox panel, default font, no theming — deliberately ugly until the
rules settled. Labels: phase, Magic, tile, standings, legend. Inputs:
`ElementBox`, `LevelBox`, `SpellTargetBox` (typed node id or user id; the
client sends it as both and the server uses whichever the effect declares).

Buttons (enabled only when their intent is in `You.LegalIntents`): Cast, No
Spell, Roll, Summon, Pay Toll, Level Up, Terraform, End Turn, Discard, Use
Item, No Item. Junction route buttons appear on demand. The hand row shows
the spotlit player's cards as rounded rectangles (faces for the owner, backs
for others); clicking a card selects its instance id.

### 6.9 The camera (CameraService)

Scriptable camera, re-claimed every `RenderStepped` (Roblox's default camera
script keeps resetting `CameraType`), re-acquires `CurrentCamera` when it is
swapped, and follows `Workspace > Cepters > Cepter_<userId>` →
`HumanoidRootPart` for the snapshot's `ActivePlayerId`. Token lookup uses
`WaitForChild` with a timeout because the token can replicate after the
snapshot arrives. (Its header comment still says `CurrentTurnUserId`; the code
correctly reads `ActivePlayerId`.)

---

## 7. CONTENT IN THE PLACE

### 7.1 The live board

- `Workspace > Board` holds **16 Parts** `Tile_1`…`Tile_16`, all tagged
  `Tile`. `Tile_1` has `TileType = "Start"` and sits at a **corner of the
  ring** (−20, 1, −20; ring centroid is the origin). There is no separate
  castle model in Workspace.
- Graph data: `Shared/BoardDefinitions/CurrentLoop` — nodes `T1`…`T16` in a
  one-way ring, castle `T1`, **no forts, no junctions, no special nodes**, one
  area. Node ids are separate from each Part's `Id` attribute (`StudioTileId`)
  so re-authoring geometry never renames a node. Territory state seeds from
  this data, not from Part attributes.
- `Main` loads `CurrentLoop`. Swapping that one `require` for `TestBoard01`
  loads the proving board instead.

### 7.2 TestBoard01

Data only. Castle, P1, FortSun, a T-junction `JT`, P2, `Bridge` (mandatory
warp) → P4, FortMoon, `Pool` (landing warp), a spur `S1` ↔ `DeadEnd`. Two
required fort types. Used by MovementSpec. Its header mentions
`tools/generate-test-board.lua`, **which does not exist** — there are no Parts
for this board.

### 7.3 Models

- `ReplicatedStorage > Models > Player > PlayerTemplate` — R6 Model with
  `Humanoid` and `HumanoidRootPart`. Cloned per player as `Cepter_<userId>`.
- `ReplicatedStorage > Models > Summons` — **4** models, matched by a number
  attribute `CardId`: Tape Gnome (1), Laser Salamander (2), Phosphor Sylph
  (3), Dewdrop Undine (4). The other 24 cards have no model; summoning them
  logs a warning and shows no visual. This is by design — presentation never
  halts a match — but is Studio work for the developer.
- All cloned models are force-anchored and positioned with `Model:PivotTo`.
- These are developer-authored. **Never generate or overwrite them in code.**

### 7.4 Card library (28 placeholder cards)

Disposable test content, not a balance proposal. **Ids 1–6 are load-bearing
for tests — never renumber.** Names are original.

- 1 Tape Gnome — Creature, Earth, 30, ST40/HP60
- 2 Laser Salamander — Creature, Fire, 40, ST60/HP50
- 3 Phosphor Sylph — Creature, Air, 25, ST35/HP45
- 4 Dewdrop Undine — Creature, Water, 20, ST30/HP55
- 5 Signal Boost — Spell, 15, BoostNextAttack 20
- 6 Ninth Signal Charm — Item/Tool, 10, BuffDefenderHP 25 (ChosenTerritory)
- 7 Chrome Vulcan — Creature, Fire, 30, ST50/HP40, First
- 8 Grid Phoenix — Creature, Fire, 45, ST40/HP60, Regenerate
- 9 Packet Wraith — Creature, Air, 25, ST45/HP30, Penetration
- 10 Daemon Courier — Creature, Air, 30, ST30/HP50, Support
- 11 Ferrite Golem — Creature, Earth, 45, ST30/HP80, Last
- 12 Spool Warden — Creature, Earth, 35, ST35/HP55, Neutralize
- 13 Aero Nereid — Creature, Water, 35, ST45/HP45, Reflect
- 14 Bloom Leviathan — Creature, Water, 60, ST70/HP70
- 15 Signal Drone — Creature, neutral, 10, ST25/HP25
- 16 Null Sentinel — Creature, neutral, 40, ST20/HP70, Neutralize
- 17 Cathode Lance — Item/Weapon, 20, +30 ST
- 18 Mylar Plating — Item/Armor, 20, +30 HP
- 19 Static Scroll — Item/Scroll, 25, 40 damage ignoring land
- 20 Ribbon Cutter — Item/Weapon, 25, +20 ST, Critical
- 21 Call Sign One — Spell, 20, ForceRoll 1 (ChosenPlayer)
- 22 Call Sign Six — Spell, 20, ForceRoll 6 (ChosenPlayer)
- 23 Rewind Tape — Spell, 15, Draw 2
- 24 Corroded Tape — Spell, 25, Poison 10 for 3 turns (ChosenTerritory)
- 25 Dead Air — Spell, 30, Paralysis 1 turn (ChosenPlayer)
- 26 Overclock — Spell, 20, Haste +2 for 2 turns (Caster)
- 27 Signal Flood — Spell, 40, GlobalAttackShift +10 for 1 round
- 28 Homeward Signal — Spell, 35, Teleport to castle (Recall, not a crossing)

Items 17–20 have no `Effects` list: their battle effect is applied inside
BattleService from `ItemCategory`/`EffectValue`. A `ChosenPlayer` target with
no `TargetUserId` defaults to the caster.

---

## 8. HISTORY IN BRIEF

Pre-rebuild (to 2026-09-08): a working but approximate prototype —
sorted-id tile loop, one balance, one-comparison battles, typed card ids,
eight action remotes, hand copy-paste into Studio. Hand-authored board and
models were added in this era and are kept.

2026-09-08: the developer's master brief arrived. Audit and migration plan
approved. Rojo adopted after MCP retransmission left three files silently
drifted (caught only by checksumming).

- **M0** `a07adc0` — Enums, RulesConfig (integer maths), ActionResult,
  rewritten Signal, RandomService, BoardDefinitionValidator, TestRunner,
  CharacterizationSpec pinning the wrong formulas.
- **M1** `343910e`…`a53d804` — PhaseGraph, MatchLogService,
  MatchOrchestrator, ActionValidator, SnapshotService, one `SubmitIntent`
  remote, Main split into BoardVisualService.
- **M2** `dff8915` — graph movement transactions, LapService, TestBoard01.
- Camera fix `5479c47` — CameraService still read a renamed snapshot field;
  also a latch that permanently skipped a not-yet-replicated token.
- **M3** `362dc45` — DeckService, instances, hidden hands, spotlight display.
- **M4** `48669c6` — battle state machine, speed classes, keywords, the HP
  defect fix.
- **M5** `2453460` — TerritoryService (replaced BoardService and
  TerraformService), ValuationService, VictoryService, liquidation, Era→Element
  rename.
- **M6** `53c0dd9` — StatusService, StatusDefinitions, EffectPrimitives,
  data-driven CardEffectService, `SpellChoice` stops, poison/paralysis, status
  spells 24–28.
- Docs `0267f05` — canonical status backlog.

Bugs worth remembering because the patterns recur:

- `ipairs({ nil, card })` stops immediately — collapsed the whole speed
  matrix once. Use explicit ordered checks when an entry may be nil.
- `local t = { f = function() return t end }` captures a nil global — the
  name is not in scope inside its own constructor. Declare `local t = {}`
  first.
- `{ Key = nil }` creates no key — override tables with nil values do
  nothing.
- A test runner that reported ALL PASS while specs failed to load. Load
  failures now count.
- A validator that crashed on its own error path (dangling warp enqueued into
  a reachability walk).
- Test arithmetic errors are common — warps do not consume steps; ties are
  broken by userId; `>=` still satisfies at exactly the goal. Check the test
  before the code.

---

## 9. KNOWN GAPS, DEFECTS AND UNVERIFIED RULES

Everything here was confirmed by reading code on 2026-09-12 unless marked.

### 9.1 Special nodes and symbols — not built (M6 remainder)

- `NodeType` declares Shrine, FortuneTeller, Temple, Fountain, BoardAction.
  **No code references any of them.** There is no `NodeEffectService`.
- `ValuationService.GetSymbolValue` **always returns 0**. No Temple, no
  symbol market, no symbol plurality in the lap bonus.
- Neither board has any special node, so a board must be authored for them
  first (board geometry is the developer's; the graph data can be written).
- Brief §10 specifies a shared node interface, light/dark shrines, Fortune
  Teller search, Fountain hand replacement, Board Action topology change,
  Temple buy/sell/skip while crossing (cap 50), symbol pricing from same
  element land value per area, symbols in TM and liquidation, and strict
  plurality lap bonuses.

### 9.2 Declared but not implemented

- **Territory commands** `MoveCreature`, `ExchangeCreature`,
  `TerritoryAbility` — enum only; Main handles only `LevelLand` and
  `ChangeElement`. Commands also only target the land you stand on; the brief
  allows crossed land, and anywhere from a castle.
- **Lap heal** — `RulesConfig.Lap.HealPercentOfMHP` is unused; completing a
  lap heals nobody. `LapService`'s own header notes this.
- **Support adjacency bonus** — `RulesConfig.Land.SupportSTPerAdjacent` is
  unused. (The Support keyword's creature-as-item rule does work.)
- **Doublecast** — a phase-graph edge and comments only. No card, no handler.
- **`ChooseSpellTarget` / `SpellTargetChoice`** and
  **`ChoosePassEffect` / `PassEffectChoice`** — validator entries, no
  handlers. Spell targets currently travel inline in the `CastSpell` payload.
- **`ConfirmResult`, `ChooseLandingAction`** intents — no handlers.
- **Timing hooks** other than ModifyRoll, BeforeRoll, BeforeBattleStats,
  TurnEnd, RoundEnd — never dispatched. Notably `BeforeSpell` (needed for
  Silenced), `OnDamage` (needed for Invulnerable/shielded), `OnLap`,
  `OnNodeEntered` via statuses, `BattleEnd`.
- **Item and land restrictions** on cards (which creatures may use which
  items, which lands a creature may be summoned onto) — brief M4 lists them;
  not modelled.

### 9.3 Robustness — the biggest real risk

- **No turn timeouts.** `RejectReason.Timeout` exists, nothing uses it. An
  idle player stalls the match forever. (Brief M1 and §16 require timeouts.)
- **Defender disconnect mid-battle** — by code reading, not tested:
  `onPlayerRemoving` only advances the turn when the **active** player
  leaves. If the defender leaves during `DefenderItemChoice`, the entitled
  submitter no longer exists and the match appears to be stuck. The same
  reasoning applies to any phase whose actor is not the active player.
- **No rejoin/recovery.** A returning player is treated as a brand-new
  joiner.
- **No lobby / match start.** The first player to join starts the match
  alone; `MinPlayers` is not enforced; late joiners enter mid-match.
- **Simultaneous requests** — sequence numbers prevent a single client double
  acting; a deliberate two-client race test (§16 Robustness) does not exist.
- Brief §16 Robustness asks for tests of disconnect during every actionable
  phase, fresh-snapshot recovery, animation failure isolation, and no
  double-spend under simultaneous requests. None exist yet.

### 9.4 Never verified with a real second player

The attacker → defender item handoff, defender hand spotlight, toll after a
lost invasion, and land transfer have unit tests only.

### 9.5 Unreachable or questionable

- `BothDestroyed` outcome is handled but unreachable with current keywords.
- Once `OnDamage` is dispatched, **Neutralize and Reflect** (currently keyword
  branches inside `resolveStrike`) become a second damage-modification system
  with no defined order against statuses. Plan to re-express them as statuses
  applied at battle start, the way `AttackBoost` replaced a private table.
- **Name collision:** a future `Regen` status vs the existing `Regenerate`
  battle keyword. Decide the names before shipping either.

### 9.6 UNVERIFIED rules (need a Culdcept Saga gameplay check)

- Toll rounding mode (`floor`), which only matters for fractional chains.
- Liquidation sale rate (0.5).
- Lap heal percentage (0.5) — and it is not applied at all yet.
- Temporary battle HP absorbing damage before persistent HP.
- Poison ticking at the **end** of the owner's turn rather than the start.
- Whether scrolls bypass a shield (for when shields exist).

### 9.7 Presentation gaps (M7 territory)

- The HUD is a debug panel; spell targets are typed ids.
- No battle view, no dice animation, no junction camera framing, no target
  highlighting, no disabled-button reasons, no TM goal/lap/fort progress UI.
- **Requested by the developer, not built:** an opening camera fly-around of
  the map at match start, then following each player on their turn.
- 24 of 28 cards have no creature/visual model (developer's Studio work).
- Poison's board-label repaint is wired (`DamageDefender` fires
  `DefenderBuffed`) but has not been watched live.

### 9.8 Dead code

- `Systems/MatchService` — nothing requires it.
- `CardService.GetCardsByElement(era)` — parameter still named `era`.

### 9.9 Governing brief is local-only

See 2.1.

### 9.10 Stale documentation (fix, don't trust)

`CLAUDE.md`:

- "System architecture requirements" example list names `BoardService`,
  `TerraformService`, `MatchService`.
- "Repo layout" / `tools/` description refers to BoardService.
- "Current implementation state" — these entries describe **pre-rebuild**
  behaviour and are wrong: `Shared/RulesConfig` (says targets do not match
  BoardService), `Shared/EraData` (now ElementData), `Systems/MovementService`,
  `Shared/CardData` (says one creature per element), `Systems/CardService`,
  `Systems/EconomyService`, `Systems/BattleService`, `Shared/Remotes` (lists
  eight remotes), `Main.server.lua` (lists BoardService/MatchService and
  per-remote turn gating), `StarterPlayer/UIService` (card-id and era boxes),
  `Systems/MatchService` (not used), and the two paragraphs starting
  "Already authored in the live place" and "Not yet built".
- `CameraService` entry says `CurrentTurnUserId`.
- "Open decisions resolved" — the Element/Era plan predates its completion.
- "Testing" — the CharacterizationSpec paragraph describes formulas that M5
  already fixed.
- Accurate: everything from "Target architecture and milestones" through the
  M6 section, the Rojo section, and the Testing run instructions.

`README.md`: the Rojo section is accurate. "Repo layout" (claims no Rojo),
"Board authoring" (BoardService/Era attributes), and "Current systems" are
pre-rebuild.

Script headers: `CameraService` (field name), `TestBoard01` (nonexistent
tool).

`docs/ui-master-prompt.md` lists only the eight implemented statuses; the
canonical target set is `docs/status-backlog.md`.

The roadmap artifact (section 11) says the castle sits in the middle of the
ring; the live geometry shows the Start tile at a ring corner with no separate
castle model.

---

## 10. WHAT TO DO NEXT

Ordered. Each item says where and how you will know it is done. Confirm the
plan for a milestone-sized chunk with the developer before starting it.

### Step 1 — Housekeeping (small, prevents the next session being misled)

1. Ask whether to commit the master brief into `docs/`.
2. Rewrite the stale `CLAUDE.md` sections listed in 9.10 so they match
   section 5 of this document. Fix `README.md` below its Rojo section.
3. Fix the `CameraService` and `TestBoard01` header comments.
4. Ask, then delete `Systems/MatchService`. Confirm it disappears from Studio
   (Rojo has been unreliable about deletions).
5. Done when: no doc references BoardService, TerraformService, EraData, the
   eight remotes, or MatchService as live; suite still 329 green; checksums
   match.

### Step 2 — Robustness (brief M1 + §16; do this before M7)

1. **Turn timeouts** per actionable phase, values in `RulesConfig`. On expiry
   take the safe default (skip spell, no item, pay toll, end turn, discard the
   last card), log it, refuse late requests with `RejectReason.Timeout`.
2. **Disconnect in every actionable phase**, especially a non-active entitled
   actor (defender). Resolve a pending battle safely (for example: defender
   chooses No Item), never strand the phase.
3. Deterministic tests for both, plus a two-requests-at-once no-double-spend
   test.
4. **Live two-client verification** (Studio Test → Clients and Servers, 2
   players): a full invasion including defender item choice, toll after a
   failed invasion, and land transfer after a successful one.
5. Done when: specs cover timeout and disconnect for every phase with an
   actor; a two-client battle has been driven live and reported as such.

### Step 3 — Remaining core rules (finish M5/M6 before content)

In roughly this order, each with focused specs:

1. **Lap heal** on lap completion using `HealPercentOfMHP` (keep UNVERIFIED).
2. **Support adjacency** ST bonus, if the developer confirms the rule.
3. **Status backlog** in the order given in `docs/status-backlog.md`:
   persistent strength up/down (free — hook already dispatched); Regen (with a
   heal counterpart to `DamageDefender`, capped at MHP; settle the naming
   collision first); rename Paralysis → Immobilised (ask first); Silenced
   (dispatch `BeforeSpell` in the cast path, drop `CastSpell` from legal
   intents while silenced, **keep `SkipSpell` reachable**); Invulnerable /
   shielded (dispatch `OnDamage` in `BattleService.resolveStrike`, and plan the
   Neutralize/Reflect migration with it); surface Debt in the snapshot.
4. **Territory commands** MoveCreature, ExchangeCreature, TerritoryAbility,
   and the wider targeting rules.
5. **Doublecast** — one card that opens exactly one extra `SpellChoice`
   window, with the §16 test.
6. **Item and land restrictions** on cards.
7. **Special nodes and symbols** behind a `NodeEffectService` interface (brief
   §10). Needs a board with those nodes: write the graph data, then ask the
   developer to author or approve geometry. Do not build Parts in their board.

### Step 4 — Milestone 7: content and presentation

1. **UI** from `docs/ui-master-prompt.md`. The developer is producing designs
   in Claude Design; implement from those, Tier 1 first (match HUD your turn /
   not your turn, card anatomy, battle takeover, tile inspector and
   development, landing decision, lobby hub, book builder). Obey its "failure
   mode" section — no generic generated-software look. Keep the client
   display-only.
2. **Camera**: opening fly-around of the board at match start, then
   turn-follow; junction framing; battle framing.
3. Dice presentation that animates a result the server already decided.
4. **Card library**: 60–80 original cards with balance, written as data over
   existing primitives and the canonical statuses. Keep ids 1–6.
5. Creature and token art are the developer's; code references models by the
   `CardId` attribute only.
6. Audio hooks, tutorial, accessibility (brief M7).

### Step 5 — Milestone 8: secondary-system skeletons

Persistence schema with versioning, collection inventory, book builder,
reward interface (unlocks from wins), AI action-provider interface, team
policy for 2v2 (symbol and lap comparisons by team), lobby configuration,
private match setup, matchmaking adapter. **No ranked rating, live
matchmaking or campaign content until the local core passes every §16
fidelity test.**

### Questions only the developer can answer

- Commit the master brief to the repo?
- Delete `MatchService`?
- Rename `Paralysis` → `Immobilised`? `Regen` vs `Regenerate` naming?
- Strength statuses attach to the **player** or to the **creature**?
- Support adjacency bonus: keep the rule?
- Shields vs scrolls?
- Saga gameplay checks for every item in 9.6.
- Castle placement on the live board, and whether to author a board with
  forts, junctions and special nodes.
- Turn timeout durations.

---

## 11. WORKING WITH THIS DEVELOPER

- Wants Culdcept Saga **fidelity** in rules and timing, with an original
  identity. Explain rule choices in those terms.
- Works milestone by milestone and likes to "lock in" a plan first. Resolve
  questions up front with a short list of concrete choices.
- Values honest reporting: what was verified automatically, what live, what
  not at all. Do not round "unit-tested" up to "works".
- Works across several machines. Git plus this README are how context moves.
- Keeps a published **roadmap artifact** at
  `https://claude.ai/code/artifact/36a9d2d2-4529-4fa3-bbe5-d43e8692eb4a`
  (private to their account unless shared). Update it after each milestone;
  it currently reflects M6 complete.
- Authors boards and models in Studio themselves. Code must adapt to their
  content, never replace it.
- Has asked for: the camera fly-around intro, the one-hand-on-screen card
  display, and the seven-status backlog. All recorded above.

---

## 12. KEEPING THIS DOCUMENT CURRENT

Update `docs/HANDOFF.md` at the end of every milestone or significant
decision, commit it, then mirror it into Studio:

- `ServerStorage > README` is a **Script** whose entire source is one
  long-bracket comment, so it never executes. It is not managed by Rojo.
- Wrap the document in a leveled long-bracket comment (two dashes, an opening
  square bracket, eight equals signs, another opening square bracket) and
  close it with the mirror image. Before writing, grep the document for a
  closing square bracket followed by an equals sign; if one exists, raise the
  number of equals signs. This paragraph deliberately spells the brackets out
  in words, because writing them literally would end the comment early.
- Write it with `execute_luau` (Edit datamodel) by setting `Source`, then read
  back its length and checksum it against the file.
- Update the snapshot date and git HEAD at the top.

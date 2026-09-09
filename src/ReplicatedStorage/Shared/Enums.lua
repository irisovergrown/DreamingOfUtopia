--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > Enums (ModuleScript)

	Purpose:
		The project's controlled vocabulary. Every phase name, element id,
		node type, rejection reason and timing hook lives here exactly once,
		so a typo is a runtime error instead of a silently-false comparison.

		Each enum is a frozen table mapping a name to itself, so
		`Enums.Phase.RollReady` is the string "RollReady" and
		`Enums.Phase.RolReady` throws rather than evaluating to nil and
		making an `if` quietly take the wrong branch. Freezing also means no
		system can add a phase at runtime — the set of legal states is fixed
		at load and reviewable in one file.

		Element ids are the canonical internal identifiers. The four are
		Fire/Water/Air/Earth. Display labels (including any board that shows
		Earth as "Ground") are a presentation concern and must never become
		a second set of ids — see ElementData for display names and the
		retrofuturism era skins.

	Usage:
		local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
		if phase == Enums.Phase.SpellChoice then ... end
		Enums.isValid(Enums.Element, "Fire") -- true

	Public API:
		Enums.<EnumName>.<Value>      -- the value's own name as a string
		Enums.isValid(enumTable, value) -> boolean
		Enums.values(enumTable) -> sorted array of the enum's values
]]

local Enums = {}

-- Builds a frozen name->name map. Indexing a name that doesn't exist throws
-- instead of returning nil, which is the entire point of using this over
-- bare string literals.
--
-- Two Luau constraints shape this, both found the hard way:
--   1. The metatable must be attached BEFORE freezing. A frozen table is
--      readonly, and setmetatable on one throws.
--   2. table.freeze REFUSES a table whose metatable is protected with
--      __metatable, so the enum cannot have both. Freezing is the stronger
--      guarantee and subsumes the other: setmetatable on a frozen table
--      already throws, so the metatable cannot be swapped out anyway.
local function makeEnum(name, values)
	local enum = {}
	for _, value in ipairs(values) do
		enum[value] = value
	end

	setmetatable(enum, {
		__index = function(_, key)
			error(string.format("'%s' is not a valid %s value", tostring(key), name), 2)
		end,
	})

	return table.freeze(enum)
end

-- The authoritative match phases. Not every turn visits every phase, but a
-- request arriving in the wrong one is rejected without changing state.
Enums.Phase = makeEnum("Phase", {
	"WaitingForPlayers",
	"MatchSetup",
	"TurnStart",
	"Draw",
	"HandOverflowDiscard",
	"SpellChoice",
	"SpellTargetChoice",
	"SpellResolution",
	"RollReady",
	"DiceResolution",
	"Movement",
	"JunctionChoice",
	"PassEffectChoice",
	"LandingResolution",
	"LandingActionChoice",
	"SummonChoice",
	"BattleSetup",
	"AttackerItemChoice",
	"DefenderItemChoice",
	"BattleResolution",
	"TollResolution",
	"TerritoryCommandChoice",
	"TerritoryCommandResolution",
	"TurnEnd",
	"RoundEnd",
	"Liquidation",
	"VictoryCheck",
	"MatchComplete",
})

-- Canonical element ids. Fixed at four by design decision.
Enums.Element = makeEnum("Element", {
	"Fire",
	"Water",
	"Air",
	"Earth",
})

Enums.CardType = makeEnum("CardType", {
	"Creature",
	"Spell",
	"Item",
})

-- Item subcategories. A creature's ItemLimits are expressed in these terms,
-- and a Scroll is an Item (never a Spell) despite reading like magic.
Enums.ItemCategory = makeEnum("ItemCategory", {
	"Weapon",
	"Armor",
	"Tool",
	"Scroll",
})

Enums.NodeType = makeEnum("NodeType", {
	"Territory",
	"Castle",
	"Fort",
	"Shrine",
	"FortuneTeller",
	"LandingWarp",
	"MandatoryWarp",
	"Temple",
	"Fountain",
	"BoardAction",
})

-- Attack order classes. Item-granted speed may override intrinsic speed.
Enums.SpeedClass = makeEnum("SpeedClass", {
	"First",
	"Normal",
	"Last",
})

Enums.TerritoryCommand = makeEnum("TerritoryCommand", {
	"LevelLand",
	"ChangeElement",
	"MoveCreature",
	"ExchangeCreature",
	"TerritoryAbility",
})

Enums.LandingAction = makeEnum("LandingAction", {
	"Summon",
	"Invade",
	"PayToll",
	"TerritoryCommand",
	"Skip",
})

-- Why a token is moving. Castle pass/lap/victory effects are NOT universal
-- across these: a Recall is not equivalent to walking across the castle, so
-- the cause has to travel with the movement transaction.
Enums.MovementCause = makeEnum("MovementCause", {
	"Roll",
	"ForcedMove",
	"Transport",
	"Recall",
	"CreatureMove",
})

-- Exactly one of these results from any battle.
Enums.BattleOutcome = makeEnum("BattleOutcome", {
	"AttackerTakesTerritory",
	"DefenderHolds",
	"BothSurvive",
	"BothDestroyed",
})

Enums.DurationType = makeEnum("DurationType", {
	"Instant",
	"Turns",
	"Rounds",
	"Permanent",
	"UntilBattleEnd",
	"UntilNextRoll",
})

-- Typed rejection codes. Clients render these; tests assert on them. A
-- rejection must never mutate state, so these are the complete set of ways
-- an intent can be refused before anything is paid or moved.
Enums.RejectReason = makeEnum("RejectReason", {
	"WrongPhase",
	"NotYourTurn",
	"NotAParticipant",
	"StaleSequence",
	"DuplicateSequence",
	"UnknownMatch",
	"MatchEnded",
	"InsufficientMagic",
	"InvalidTarget",
	"InvalidCard",
	"CardNotInHand",
	"IllegalAction",
	"RuleViolation",
	"Timeout",
})

-- Named points where statuses and card effects may intervene. Multiple
-- effects on one hook are ordered by explicit priority, then stable source
-- order, and the resolved order is logged.
Enums.TimingHook = makeEnum("TimingHook", {
	"BeforeDraw",
	"AfterDraw",
	"BeforeSpell",
	"BeforeRoll",
	"ModifyRoll",
	"OnNodeExited",
	"OnNodeEntered",
	"OnLand",
	"BeforeBattleStats",
	"BeforeItem",
	"BeforeAttack",
	"OnDamage",
	"AfterAttack",
	"BattleEnd",
	"OnLap",
	"TurnEnd",
	"RoundEnd",
})

-- What a client may ask the server to do. Requests are intent-shaped: the
-- client states what it wants, never what the outcome is. Each intent is
-- legal in a specific set of phases (see ActionValidator).
Enums.Intent = makeEnum("Intent", {
	"DiscardToHandLimit",
	"CastSpell",
	"SkipSpell",
	"ChooseSpellTarget",
	"Roll",
	"ChooseJunction",
	"ChoosePassEffect",
	"ChooseLandingAction",
	"ChooseSummon",
	"ChooseBattleItem",
	"ChooseTerritoryCommand",
	"PayToll",
	"ChooseLiquidation",
	"ConfirmResult",
	"EndTurn",
})

-- Who is expected to act in a given phase. Not everything is the active
-- player: the defender chooses a battle item after the invader has committed,
-- and most phases are server-driven with no player input at all.
Enums.Actor = makeEnum("Actor", {
	"ActivePlayer",
	"Defender",
	"AnyParticipant",
	"None",
})

-- Whether a status/hand/book detail is visible to opponents.
Enums.Visibility = makeEnum("Visibility", {
	"Public",
	"OwnerOnly",
	"Hidden",
})

-- rawget, because the enum metatables throw on unknown keys by design.
function Enums.isValid(enumTable, value)
	if type(enumTable) ~= "table" or type(value) ~= "string" then
		return false
	end
	return rawget(enumTable, value) ~= nil
end

-- Sorted so iteration order is deterministic; enum tables are hash maps and
-- pairs() order is not stable enough to build tests or logs on.
function Enums.values(enumTable)
	local values = {}
	for value in pairs(enumTable) do
		table.insert(values, value)
	end
	table.sort(values)
	return values
end

return Enums

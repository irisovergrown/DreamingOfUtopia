--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > PhaseGraph (ModuleScript)

	Purpose:
		The legal transition table for the match state machine, as data.

		This is deliberately a separate module from MatchOrchestrator. The
		orchestrator decides WHEN to move and performs the side effects; this
		file states WHICH moves exist at all. Keeping them apart means the
		legal shape of a turn is reviewable in one screen without reading any
		control flow, and testable without constructing a match.

		Every transition the game can make is listed here. A move that is not
		listed cannot happen — MatchOrchestrator asks this module first and
		rejects anything else, so an unforeseen path fails loudly at the seam
		instead of silently corrupting a turn three phases later.

	Reading the table:
		Each key is a phase; its array lists every phase reachable from it.
		Order within an array is not significant.

	Notes on specific edges, since several are non-obvious:
		- Draw -> HandOverflowDiscard only when the draw pushed the hand over
		  the cap; otherwise Draw goes straight to SpellChoice. Both edges are
		  legal, and the orchestrator picks based on hand size.
		- SpellResolution -> SpellChoice is the Doublecast allowance. It is a
		  normal edge rather than a special case so any effect that grants an
		  extra spell action reuses it.
		- Movement -> Movement does NOT exist. A junction or pass effect
		  interrupts movement into its own phase and returns; movement never
		  re-enters itself, which keeps "remaining steps" owned by one
		  transaction rather than being reset by a self-loop.
		- LandingResolution -> TurnEnd covers landing somewhere with no legal
		  action at all (an allied territory, or a node whose effect is
		  purely mandatory).
		- TollResolution -> Liquidation is the "cannot afford it" path. The
		  brief is explicit that an unaffordable mandatory payment enters
		  liquidation rather than being rejected, so this edge must exist.
		- Liquidation -> MatchComplete is bankruptcy/elimination ending the
		  match outright.
		- VictoryCheck -> TurnStart is the ordinary case; -> RoundEnd when
		  the rotation wrapped; -> MatchComplete when someone has won.
		- MatchComplete is terminal and has no outgoing edges. That is
		  asserted by a test, not just by omission.

	Public API:
		PhaseGraph.Transitions -> frozen map of phase -> array of phases
		PhaseGraph.canTransition(from, to) -> boolean
		PhaseGraph.getNextPhases(from) -> array (a copy; safe to mutate)
		PhaseGraph.isTerminal(phase) -> boolean
		PhaseGraph.InitialPhase -> the phase a fresh match starts in
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)

local Phase = Enums.Phase

local PhaseGraph = {}

PhaseGraph.InitialPhase = Phase.WaitingForPlayers

local Transitions = {
	[Phase.WaitingForPlayers] = { Phase.MatchSetup },
	[Phase.MatchSetup] = { Phase.TurnStart },

	[Phase.TurnStart] = { Phase.Draw },
	[Phase.Draw] = { Phase.HandOverflowDiscard, Phase.SpellChoice },
	[Phase.HandOverflowDiscard] = { Phase.SpellChoice },

	[Phase.SpellChoice] = { Phase.SpellTargetChoice, Phase.SpellResolution, Phase.RollReady },
	[Phase.SpellTargetChoice] = { Phase.SpellResolution, Phase.SpellChoice },
	[Phase.SpellResolution] = { Phase.SpellChoice, Phase.RollReady },

	[Phase.RollReady] = { Phase.DiceResolution },
	[Phase.DiceResolution] = { Phase.Movement },

	[Phase.Movement] = { Phase.JunctionChoice, Phase.PassEffectChoice, Phase.LandingResolution },
	[Phase.JunctionChoice] = { Phase.Movement },
	[Phase.PassEffectChoice] = { Phase.Movement },

	[Phase.LandingResolution] = {
		Phase.LandingActionChoice,
		Phase.TollResolution,
		Phase.TurnEnd,
	},

	[Phase.LandingActionChoice] = {
		Phase.SummonChoice,
		Phase.BattleSetup,
		Phase.TollResolution,
		Phase.TerritoryCommandChoice,
		Phase.TurnEnd,
	},

	[Phase.SummonChoice] = { Phase.TurnEnd, Phase.LandingActionChoice },

	[Phase.BattleSetup] = { Phase.AttackerItemChoice },
	-- Sequential by design: the invader commits first, then the defender
	-- chooses knowing what was committed. There is no edge that lets the
	-- defender choose first.
	[Phase.AttackerItemChoice] = { Phase.DefenderItemChoice },
	[Phase.DefenderItemChoice] = { Phase.BattleResolution },
	[Phase.BattleResolution] = { Phase.TollResolution, Phase.TurnEnd },

	[Phase.TollResolution] = { Phase.Liquidation, Phase.TurnEnd },
	[Phase.Liquidation] = { Phase.TollResolution, Phase.TurnEnd, Phase.MatchComplete },

	[Phase.TerritoryCommandChoice] = { Phase.TerritoryCommandResolution, Phase.TurnEnd },
	[Phase.TerritoryCommandResolution] = { Phase.TurnEnd },

	[Phase.TurnEnd] = { Phase.VictoryCheck },
	[Phase.VictoryCheck] = { Phase.TurnStart, Phase.RoundEnd, Phase.MatchComplete },
	[Phase.RoundEnd] = { Phase.TurnStart },

	-- Terminal.
	[Phase.MatchComplete] = {},
}

-- Freeze each destination array as well as the outer table, so a caller that
-- mutates what getNextPhases hands back cannot quietly rewrite the rules for
-- everyone. getNextPhases returns a copy for exactly that reason.
for _, destinations in pairs(Transitions) do
	table.freeze(destinations)
end
PhaseGraph.Transitions = table.freeze(Transitions)

-- Built once rather than scanned per call: this is asked on every intent.
local transitionSet = {}
for from, destinations in pairs(Transitions) do
	local set = {}
	for _, to in ipairs(destinations) do
		set[to] = true
	end
	transitionSet[from] = set
end

function PhaseGraph.canTransition(from, to)
	local set = transitionSet[from]
	if set == nil then
		return false
	end
	return set[to] == true
end

function PhaseGraph.getNextPhases(from)
	local destinations = Transitions[from]
	if destinations == nil then
		return {}
	end
	local copy = {}
	for index, phase in ipairs(destinations) do
		copy[index] = phase
	end
	return copy
end

function PhaseGraph.isTerminal(phase)
	local destinations = Transitions[phase]
	return destinations ~= nil and #destinations == 0
end

return PhaseGraph

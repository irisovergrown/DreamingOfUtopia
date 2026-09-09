--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > PhaseGraphSpec (ModuleScript)

	The structural guarantees the state machine rests on. These are properties
	of the graph itself, provable without constructing a match: every phase is
	accounted for, nothing is stranded, and the turn sequence the brief
	specifies is actually walkable.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local PhaseGraph = require(ReplicatedStorage.Shared.PhaseGraph)

local Phase = Enums.Phase

-- Walks a named sequence, asserting each step is a legal transition.
local function walk(t, sequence)
	for index = 1, #sequence - 1 do
		local from, to = sequence[index], sequence[index + 1]
		t:True(
			PhaseGraph.canTransition(from, to),
			string.format("step %d: %s -> %s should be legal", index, from, to)
		)
	end
end

return {
	Name = "PhaseGraph",
	Tests = {
		{ "every phase in the enum has a transition entry", function(t)
			-- A phase with no entry cannot be reasoned about: canTransition
			-- returns false for everything, so reaching it strands the match.
			for _, phase in ipairs(Enums.values(Phase)) do
				t:NotNil(PhaseGraph.Transitions[phase], "no entry for phase " .. phase)
			end
		end },

		{ "every destination is a real phase", function(t)
			-- Guards against a typo'd destination that would be unreachable
			-- and silently never taken.
			for from, destinations in pairs(PhaseGraph.Transitions) do
				for _, to in ipairs(destinations) do
					t:True(Enums.isValid(Phase, to), string.format("%s -> '%s' is not a real phase", from, tostring(to)))
				end
			end
		end },

		{ "no phase transitions to itself", function(t)
			-- Movement in particular must not self-loop: a junction or pass
			-- effect leaves and returns, and a self-edge would invite
			-- re-entering movement with the step count reset.
			for from, destinations in pairs(PhaseGraph.Transitions) do
				for _, to in ipairs(destinations) do
					t:NotEqual(to, from, "self-loop on " .. from)
				end
			end
		end },

		{ "MatchComplete is the only terminal phase", function(t)
			for _, phase in ipairs(Enums.values(Phase)) do
				if phase == Phase.MatchComplete then
					t:True(PhaseGraph.isTerminal(phase), "MatchComplete should be terminal")
				else
					t:False(PhaseGraph.isTerminal(phase), phase .. " should not be a dead end")
				end
			end
		end },

		{ "every phase is reachable from the initial phase", function(t)
			-- An unreachable phase is dead code that looks like a feature.
			local seen = { [PhaseGraph.InitialPhase] = true }
			local queue = { PhaseGraph.InitialPhase }
			while #queue > 0 do
				local phase = table.remove(queue)
				for _, next_ in ipairs(PhaseGraph.Transitions[phase] or {}) do
					if not seen[next_] then
						seen[next_] = true
						table.insert(queue, next_)
					end
				end
			end

			for _, phase in ipairs(Enums.values(Phase)) do
				t:True(seen[phase] == true, "phase " .. phase .. " is unreachable from " .. PhaseGraph.InitialPhase)
			end
		end },

		{ "an ordinary turn walks end to end", function(t)
			-- The brief's normal turn sequence: start, draw, skip the spell,
			-- roll, move, land, take one action, end.
			walk(t, {
				Phase.TurnStart,
				Phase.Draw,
				Phase.SpellChoice,
				Phase.RollReady,
				Phase.DiceResolution,
				Phase.Movement,
				Phase.LandingResolution,
				Phase.LandingActionChoice,
				Phase.SummonChoice,
				Phase.TurnEnd,
				Phase.VictoryCheck,
				Phase.TurnStart,
			})
		end },

		{ "a turn with hand overflow walks end to end", function(t)
			walk(t, {
				Phase.TurnStart,
				Phase.Draw,
				Phase.HandOverflowDiscard,
				Phase.SpellChoice,
				Phase.RollReady,
			})
		end },

		{ "a targeted spell walks end to end", function(t)
			walk(t, {
				Phase.SpellChoice,
				Phase.SpellTargetChoice,
				Phase.SpellResolution,
				Phase.RollReady,
			})
		end },

		{ "Doublecast can re-open the spell window exactly as a normal edge", function(t)
			-- Represented as a spell-action allowance, not a card-name case.
			t:True(PhaseGraph.canTransition(Phase.SpellResolution, Phase.SpellChoice))
			walk(t, {
				Phase.SpellChoice,
				Phase.SpellResolution,
				Phase.SpellChoice,
				Phase.SpellResolution,
				Phase.RollReady,
			})
		end },

		{ "a junction interrupts movement and returns to it", function(t)
			walk(t, {
				Phase.Movement,
				Phase.JunctionChoice,
				Phase.Movement,
				Phase.LandingResolution,
			})
		end },

		{ "a pass effect interrupts movement and returns to it", function(t)
			walk(t, {
				Phase.Movement,
				Phase.PassEffectChoice,
				Phase.Movement,
			})
		end },

		{ "an invasion walks through sequential item choice to a toll", function(t)
			walk(t, {
				Phase.LandingActionChoice,
				Phase.BattleSetup,
				Phase.AttackerItemChoice,
				Phase.DefenderItemChoice,
				Phase.BattleResolution,
				Phase.TollResolution,
				Phase.TurnEnd,
			})
		end },

		{ "the defender can never choose an item before the invader", function(t)
			-- Saga's sequential decision order, enforced structurally rather
			-- than by convention in the battle code.
			t:False(PhaseGraph.canTransition(Phase.BattleSetup, Phase.DefenderItemChoice), "battle cannot skip to the defender")
			t:False(PhaseGraph.canTransition(Phase.DefenderItemChoice, Phase.AttackerItemChoice), "order cannot reverse")
		end },

		{ "an unaffordable toll enters liquidation rather than being rejected", function(t)
			walk(t, {
				Phase.TollResolution,
				Phase.Liquidation,
				Phase.TollResolution,
				Phase.TurnEnd,
			})
		end },

		{ "liquidation can end the match through bankruptcy", function(t)
			t:True(PhaseGraph.canTransition(Phase.Liquidation, Phase.MatchComplete))
		end },

		{ "a territory command walks end to end", function(t)
			walk(t, {
				Phase.LandingActionChoice,
				Phase.TerritoryCommandChoice,
				Phase.TerritoryCommandResolution,
				Phase.TurnEnd,
			})
		end },

		{ "victory is checked after every turn, and can end the match", function(t)
			t:True(PhaseGraph.canTransition(Phase.TurnEnd, Phase.VictoryCheck), "turn end always checks")
			t:DeepEqual(PhaseGraph.getNextPhases(Phase.TurnEnd), { Phase.VictoryCheck }, "and does nothing else")
			t:True(PhaseGraph.canTransition(Phase.VictoryCheck, Phase.MatchComplete))
			t:True(PhaseGraph.canTransition(Phase.VictoryCheck, Phase.RoundEnd))
			t:True(PhaseGraph.canTransition(Phase.VictoryCheck, Phase.TurnStart))
		end },

		{ "a match starts in WaitingForPlayers and must pass through setup", function(t)
			t:Equal(PhaseGraph.InitialPhase, Phase.WaitingForPlayers)
			t:DeepEqual(PhaseGraph.getNextPhases(Phase.WaitingForPlayers), { Phase.MatchSetup })
			t:DeepEqual(PhaseGraph.getNextPhases(Phase.MatchSetup), { Phase.TurnStart })
		end },

		{ "illegal jumps are rejected", function(t)
			t:False(PhaseGraph.canTransition(Phase.TurnStart, Phase.RollReady), "cannot skip the draw and spell phases")
			t:False(PhaseGraph.canTransition(Phase.Draw, Phase.Movement), "cannot skip to movement")
			t:False(PhaseGraph.canTransition(Phase.MatchComplete, Phase.TurnStart), "a finished match cannot resume")
			t:False(PhaseGraph.canTransition(Phase.LandingResolution, Phase.BattleSetup), "battle is entered through the action choice")
		end },

		{ "unknown phases are rejected rather than throwing", function(t)
			t:False(PhaseGraph.canTransition("NotAPhase", Phase.TurnStart))
			t:False(PhaseGraph.canTransition(Phase.TurnStart, "NotAPhase"))
			t:DeepEqual(PhaseGraph.getNextPhases("NotAPhase"), {})
			t:False(PhaseGraph.isTerminal("NotAPhase"))
		end },

		{ "the table cannot be rewritten at runtime", function(t)
			-- The set of legal moves is fixed at load and reviewable in one
			-- file; nothing may extend it dynamically.
			t:Throws(function()
				PhaseGraph.Transitions[Phase.TurnStart] = { Phase.MatchComplete }
			end)
			t:Throws(function()
				table.insert(PhaseGraph.Transitions[Phase.TurnStart], Phase.MatchComplete)
			end)
		end },

		{ "getNextPhases hands back a copy", function(t)
			local first = PhaseGraph.getNextPhases(Phase.Movement)
			table.insert(first, Phase.MatchComplete)
			t:Equal(#PhaseGraph.getNextPhases(Phase.Movement), #first - 1, "mutating the copy did not affect the graph")
		end },
	},
}

--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > ActionValidatorSpec (ModuleScript)

	The brief's "only legal actions are selectable" and "wrong-phase,
	wrong-player requests make no state change" criteria. The last test is the
	structural one: what the client is told it may do is derived from the same
	table the server validates against, so the two cannot drift.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local PhaseGraph = require(ReplicatedStorage.Shared.PhaseGraph)
local ActionValidator = require(ServerScriptService.Systems.ActionValidator)

local Phase = Enums.Phase
local Intent = Enums.Intent
local Actor = Enums.Actor

local ALICE, BOB, CHARLIE = 101, 202, 303

local function context(phase, overrides)
	local ctx = {
		Phase = phase,
		ActivePlayerId = ALICE,
		DefenderId = BOB,
		RequesterId = ALICE,
		Participants = { [ALICE] = true, [BOB] = true },
	}
	for key, value in pairs(overrides or {}) do
		ctx[key] = value
	end
	return ctx
end

return {
	Name = "ActionValidator",
	Tests = {
		{ "the active player may roll during RollReady", function(t)
			local result = ActionValidator.validate(context(Phase.RollReady), Intent.Roll)
			t:True(result.Ok)
			t:Equal(result.Payload.Actor, Actor.ActivePlayer)
		end },

		{ "rolling outside RollReady is refused as WrongPhase", function(t)
			for _, phase in ipairs({ Phase.SpellChoice, Phase.Movement, Phase.TurnEnd, Phase.LandingActionChoice }) do
				local result = ActionValidator.validate(context(phase), Intent.Roll)
				t:False(result.Ok, "roll should be illegal in " .. phase)
				t:Equal(result.Code, Enums.RejectReason.WrongPhase, phase)
			end
		end },

		{ "a non-active player is refused as NotYourTurn", function(t)
			local result = ActionValidator.validate(context(Phase.RollReady, { RequesterId = BOB }), Intent.Roll)
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.NotYourTurn)
		end },

		{ "a non-participant is refused as NotAParticipant, not NotYourTurn", function(t)
			-- A spectator should be told they are not in the match, rather
			-- than the misleading "wait your turn".
			local result = ActionValidator.validate(context(Phase.RollReady, { RequesterId = CHARLIE }), Intent.Roll)
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.NotAParticipant)
		end },

		{ "DefenderItemChoice belongs to the defender, not the active player", function(t)
			-- The asymmetry Actor exists for. The invader has already
			-- committed; this window is the defender's.
			t:Equal(ActionValidator.getExpectedActor(Phase.DefenderItemChoice), Actor.Defender)

			local defender = ActionValidator.validate(
				context(Phase.DefenderItemChoice, { RequesterId = BOB }),
				Intent.ChooseBattleItem
			)
			t:True(defender.Ok, "the defender may choose")

			local attacker = ActionValidator.validate(
				context(Phase.DefenderItemChoice, { RequesterId = ALICE }),
				Intent.ChooseBattleItem
			)
			t:False(attacker.Ok, "the invader may not choose for the defender")
		end },

		{ "AttackerItemChoice belongs to the active player", function(t)
			t:Equal(ActionValidator.getExpectedActor(Phase.AttackerItemChoice), Actor.ActivePlayer)
			t:True(ActionValidator.validate(context(Phase.AttackerItemChoice), Intent.ChooseBattleItem).Ok)
			t:False(ActionValidator.validate(
				context(Phase.AttackerItemChoice, { RequesterId = BOB }),
				Intent.ChooseBattleItem
			).Ok)
		end },

		{ "server-driven phases accept nothing from anyone", function(t)
			-- Most of the machine resolves without input; saying so explicitly
			-- means a stray request during resolution cannot slip through.
			local serverDriven = {
				Phase.TurnStart, Phase.Draw, Phase.SpellResolution, Phase.DiceResolution,
				Phase.Movement, Phase.LandingResolution, Phase.BattleSetup,
				Phase.BattleResolution, Phase.TerritoryCommandResolution,
				Phase.TurnEnd, Phase.VictoryCheck, Phase.RoundEnd,
				Phase.MatchSetup, Phase.WaitingForPlayers, Phase.MatchComplete,
			}
			for _, phase in ipairs(serverDriven) do
				t:Equal(ActionValidator.getExpectedActor(phase), Actor.None, phase)
				t:Equal(#ActionValidator.getLegalIntents(phase), 0, phase .. " should offer nothing")

				local result = ActionValidator.validate(context(phase), Intent.Roll)
				t:False(result.Ok, phase .. " accepted a request")
				t:Equal(result.Code, Enums.RejectReason.WrongPhase, phase)
			end
		end },

		{ "a phase with no entitled actor refuses rather than throwing", function(t)
			-- e.g. DefenderItemChoice reached with no defender recorded.
			-- Built literally rather than through the context helper: an
			-- override of `DefenderId = nil` creates no key in a Lua table
			-- literal, so the helper would silently leave the real defender
			-- in place and this would test nothing.
			local result = ActionValidator.validate({
				Phase = Phase.DefenderItemChoice,
				ActivePlayerId = ALICE,
				DefenderId = nil,
				RequesterId = BOB,
				Participants = { [ALICE] = true, [BOB] = true },
			}, Intent.ChooseBattleItem)

			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.IllegalAction)
		end },

		{ "unknown phases and intents are refused, not thrown on", function(t)
			t:Equal(ActionValidator.validate(context("Nowhere"), Intent.Roll).Code, Enums.RejectReason.IllegalAction)
			t:Equal(ActionValidator.validate(context(Phase.RollReady), "Fly").Code, Enums.RejectReason.IllegalAction)
			t:Equal(ActionValidator.validate(nil, Intent.Roll).Code, Enums.RejectReason.IllegalAction)
		end },

		{ "the landing action window offers exactly the post-move choices", function(t)
			local intents = ActionValidator.getLegalIntents(Phase.LandingActionChoice)
			t:Contains(intents, Intent.ChooseSummon)
			t:Contains(intents, Intent.PayToll)
			t:Contains(intents, Intent.ChooseTerritoryCommand)
			t:Contains(intents, Intent.EndTurn)
			-- Rolling again after moving is the mistake this prevents.
			t:False(ActionValidator.isIntentLegalInPhase(Phase.LandingActionChoice, Intent.Roll))
		end },

		{ "every legal intent is a real intent", function(t)
			for _, phase in ipairs(Enums.values(Phase)) do
				for _, intent in ipairs(ActionValidator.getLegalIntents(phase)) do
					t:True(Enums.isValid(Intent, intent), string.format("%s offers unknown intent '%s'", phase, tostring(intent)))
				end
			end
		end },

		{ "every phase that accepts input offers at least one intent", function(t)
			-- An actor with nothing to do would stall the match: the phase
			-- waits for a player who has no legal move to make.
			for _, phase in ipairs(Enums.values(Phase)) do
				if ActionValidator.getExpectedActor(phase) ~= Actor.None then
					t:True(#ActionValidator.getLegalIntents(phase) > 0, phase .. " expects an actor but offers no intent")
				end
			end
		end },

		{ "every phase that offers intents also names an actor", function(t)
			-- The inverse stall: intents nobody is entitled to send.
			for _, phase in ipairs(Enums.values(Phase)) do
				if #ActionValidator.getLegalIntents(phase) > 0 then
					t:NotEqual(ActionValidator.getExpectedActor(phase), Actor.None, phase .. " offers intents with no actor")
				end
			end
		end },

		{ "every input phase is reachable in the phase graph", function(t)
			-- A phase that waits for a player but can never be entered is a
			-- feature that will never fire.
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
				if ActionValidator.getExpectedActor(phase) ~= Actor.None then
					t:True(seen[phase] == true, phase .. " accepts input but is unreachable")
				end
			end
		end },

		{ "the client's offered actions match what the server accepts", function(t)
			-- The structural guarantee: buttons and validation come from one
			-- table, so a client cannot offer an action the server refuses.
			for _, phase in ipairs(Enums.values(Phase)) do
				local ctx = context(phase)
				local offered = ActionValidator.getLegalIntentsForPlayer(ctx, ALICE)
				for _, intent in ipairs(offered) do
					t:True(
						ActionValidator.validate(ctx, intent).Ok,
						string.format("%s offered %s to the active player but would refuse it", phase, intent)
					)
				end
			end
		end },

		{ "a player offered nothing is refused everything", function(t)
			for _, phase in ipairs(Enums.values(Phase)) do
				local ctx = context(phase, { RequesterId = BOB })
				if #ActionValidator.getLegalIntentsForPlayer(ctx, BOB) == 0 then
					for _, intent in ipairs(ActionValidator.getLegalIntents(phase)) do
						t:False(
							ActionValidator.validate(ctx, intent).Ok,
							string.format("%s offered Bob nothing but accepted %s", phase, intent)
						)
					end
				end
			end
		end },

		{ "the defender is offered their battle window and the attacker is not", function(t)
			local ctx = context(Phase.DefenderItemChoice)
			t:Contains(ActionValidator.getLegalIntentsForPlayer(ctx, BOB), Intent.ChooseBattleItem)
			t:Equal(#ActionValidator.getLegalIntentsForPlayer(ctx, ALICE), 0, "the attacker waits")
		end },

		{ "getLegalIntents hands back a copy", function(t)
			local first = ActionValidator.getLegalIntents(Phase.RollReady)
			table.insert(first, Intent.EndTurn)
			t:Equal(#ActionValidator.getLegalIntents(Phase.RollReady), #first - 1)
		end },
	},
}

--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > MatchOrchestratorSpec (ModuleScript)

	Covers the Milestone 1 "turn flow" and "robustness" acceptance criteria
	that exist yet: wrong-phase, wrong-player, duplicate and stale requests
	make no state change, and the phase machine only moves where PhaseGraph
	allows.

	The recurring assertion is not "the call failed" but "the call failed AND
	nothing moved". A rejection that quietly advances a counter is the bug
	worth catching, and it is invisible if you only check the return value.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local MatchLogService = require(ServerScriptService.Systems.MatchLogService)
local MatchOrchestrator = require(ServerScriptService.Systems.MatchOrchestrator)

local Phase = Enums.Phase
local ALICE, BOB = 101, 202

-- Fresh orchestrator and log for each test; these are module singletons, so
-- without this the specs would leak state into each other.
local function reset()
	MatchLogService.Init()
	MatchOrchestrator.Init()
end

-- Drives the machine to TurnStart and hands the turn to `userId`.
local function beginTurnFor(userId)
	MatchOrchestrator.TransitionTo(Phase.MatchSetup, "test")
	MatchOrchestrator.TransitionTo(Phase.TurnStart, "test")
	MatchOrchestrator.BeginTurn(userId)
end

-- Snapshot of everything a rejection must leave alone.
local function stateOf()
	return {
		Phase = MatchOrchestrator.GetPhase(),
		Active = MatchOrchestrator.GetActivePlayerId(),
		Turn = MatchOrchestrator.GetTurnNumber(),
		Round = MatchOrchestrator.GetRoundNumber(),
		AliceSeq = MatchOrchestrator.PeekSequence(ALICE),
		BobSeq = MatchOrchestrator.PeekSequence(BOB),
	}
end

return {
	Name = "MatchOrchestrator",
	Tests = {
		{ "a fresh match starts in WaitingForPlayers with nothing counted", function(t)
			reset()
			t:Equal(MatchOrchestrator.GetPhase(), Phase.WaitingForPlayers)
			t:Nil(MatchOrchestrator.GetActivePlayerId())
			t:Equal(MatchOrchestrator.GetTurnNumber(), 0)
			t:Equal(MatchOrchestrator.GetRoundNumber(), 0)
			t:False(MatchOrchestrator.IsMatchComplete())
		end },

		{ "a legal transition moves the phase and reports the move", function(t)
			reset()
			local result = MatchOrchestrator.TransitionTo(Phase.MatchSetup, "test")
			t:True(result.Ok)
			t:Equal(result.Payload.From, Phase.WaitingForPlayers)
			t:Equal(result.Payload.To, Phase.MatchSetup)
			t:Equal(MatchOrchestrator.GetPhase(), Phase.MatchSetup)
		end },

		{ "an illegal transition is refused and changes nothing", function(t)
			reset()
			local before = stateOf()

			local result = MatchOrchestrator.TransitionTo(Phase.Movement, "illegal jump")
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.WrongPhase)
			t:DeepEqual(stateOf(), before, "state after a refused transition")
		end },

		{ "a transition to a non-phase is refused and changes nothing", function(t)
			reset()
			local before = stateOf()

			local result = MatchOrchestrator.TransitionTo("Elsewhere", "typo")
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.IllegalAction)
			t:DeepEqual(stateOf(), before)
		end },

		{ "PhaseChanged fires with the from/to pair", function(t)
			reset()
			local seen
			local connection = MatchOrchestrator.PhaseChanged:Connect(function(from, to, reason)
				seen = { From = from, To = to, Reason = reason }
			end)

			MatchOrchestrator.TransitionTo(Phase.MatchSetup, "because")
			connection.Disconnect()

			t:DeepEqual(seen, { From = Phase.WaitingForPlayers, To = Phase.MatchSetup, Reason = "because" })
		end },

		{ "PhaseChanged does not fire for a refused transition", function(t)
			reset()
			local fired = false
			local connection = MatchOrchestrator.PhaseChanged:Connect(function() fired = true end)

			MatchOrchestrator.TransitionTo(Phase.Movement, "illegal")
			connection.Disconnect()

			t:False(fired, "a refused transition must not announce itself")
		end },

		{ "BeginTurn assigns the active player and counts the turn", function(t)
			reset()
			beginTurnFor(ALICE)

			t:Equal(MatchOrchestrator.GetActivePlayerId(), ALICE)
			t:Equal(MatchOrchestrator.GetTurnNumber(), 1)
			t:True(MatchOrchestrator.IsActivePlayer(ALICE))
			t:False(MatchOrchestrator.IsActivePlayer(BOB))
		end },

		{ "BeginTurn outside TurnStart is refused and changes nothing", function(t)
			reset()
			local before = stateOf()

			local result = MatchOrchestrator.BeginTurn(ALICE)
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.WrongPhase)
			t:DeepEqual(stateOf(), before, "no turn was counted")
		end },

		{ "entering RoundEnd counts the round", function(t)
			reset()
			beginTurnFor(ALICE)
			t:Equal(MatchOrchestrator.GetRoundNumber(), 0)

			for _, phase in ipairs({ Phase.Draw, Phase.SpellChoice, Phase.RollReady, Phase.DiceResolution, Phase.Movement, Phase.LandingResolution, Phase.TurnEnd, Phase.VictoryCheck, Phase.RoundEnd }) do
				t:True(MatchOrchestrator.TransitionTo(phase, "test").Ok, "could not reach " .. phase)
			end

			t:Equal(MatchOrchestrator.GetRoundNumber(), 1)
		end },

		{ "an intent from the active player with a fresh sequence is accepted", function(t)
			reset()
			beginTurnFor(ALICE)

			local result = MatchOrchestrator.SubmitIntent(ALICE, "Roll", 1)
			t:True(result.Ok)
			t:Equal(MatchOrchestrator.PeekSequence(ALICE), 1)
		end },

		{ "an intent from a non-active player is refused and consumes nothing", function(t)
			reset()
			beginTurnFor(ALICE)
			local before = stateOf()

			local result = MatchOrchestrator.SubmitIntent(BOB, "Roll", 1)
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.NotYourTurn)
			t:DeepEqual(stateOf(), before, "Bob's rejected intent moved nothing")
		end },

		{ "a replayed sequence is refused exactly once as a duplicate", function(t)
			-- The double-click / laggy-retry case. Accepting it twice would
			-- double-spend whatever the intent pays for.
			reset()
			beginTurnFor(ALICE)

			t:True(MatchOrchestrator.SubmitIntent(ALICE, "Roll", 1).Ok, "first submission")

			local replay = MatchOrchestrator.SubmitIntent(ALICE, "Roll", 1)
			t:False(replay.Ok)
			t:Equal(replay.Code, Enums.RejectReason.DuplicateSequence)
			t:Equal(MatchOrchestrator.PeekSequence(ALICE), 1, "sequence did not advance")
		end },

		{ "a stale sequence is refused", function(t)
			reset()
			beginTurnFor(ALICE)
			MatchOrchestrator.SubmitIntent(ALICE, "Roll", 5)

			local stale = MatchOrchestrator.SubmitIntent(ALICE, "Roll", 3)
			t:False(stale.Ok)
			t:Equal(stale.Code, Enums.RejectReason.StaleSequence)
			t:Equal(MatchOrchestrator.PeekSequence(ALICE), 5, "sequence unchanged by a stale request")
		end },

		{ "a rejected intent does not consume its ordinal", function(t)
			-- Otherwise being refused once would knock the client's numbering
			-- permanently out of step with the server's.
			reset()
			beginTurnFor(ALICE)

			MatchOrchestrator.SubmitIntent(BOB, "Roll", 1)
			t:Equal(MatchOrchestrator.PeekSequence(BOB), 0, "Bob consumed nothing")

			beginTurnFor(BOB)
			t:True(MatchOrchestrator.SubmitIntent(BOB, "Roll", 1).Ok, "sequence 1 is still available to Bob")
		end },

		{ "sequences advance per player, not globally", function(t)
			reset()
			beginTurnFor(ALICE)
			MatchOrchestrator.SubmitIntent(ALICE, "Roll", 7)

			beginTurnFor(BOB)
			t:True(MatchOrchestrator.SubmitIntent(BOB, "Roll", 1).Ok, "Bob is not held to Alice's counter")
			t:Equal(MatchOrchestrator.PeekSequence(ALICE), 7)
			t:Equal(MatchOrchestrator.PeekSequence(BOB), 1)
		end },

		{ "a non-integer sequence is refused", function(t)
			reset()
			beginTurnFor(ALICE)

			t:Equal(MatchOrchestrator.SubmitIntent(ALICE, "Roll", 1.5).Code, Enums.RejectReason.IllegalAction)
			t:Equal(MatchOrchestrator.SubmitIntent(ALICE, "Roll", "1").Code, Enums.RejectReason.IllegalAction)
			t:Equal(MatchOrchestrator.PeekSequence(ALICE), 0)
		end },

		{ "an unnamed intent is refused", function(t)
			reset()
			beginTurnFor(ALICE)
			t:Equal(MatchOrchestrator.SubmitIntent(ALICE, "", 1).Code, Enums.RejectReason.IllegalAction)
			t:Equal(MatchOrchestrator.SubmitIntent(ALICE, nil, 1).Code, Enums.RejectReason.IllegalAction)
		end },

		{ "every intent is refused once the match is complete", function(t)
			reset()
			beginTurnFor(ALICE)
			for _, phase in ipairs({ Phase.Draw, Phase.SpellChoice, Phase.RollReady, Phase.DiceResolution, Phase.Movement, Phase.LandingResolution, Phase.TurnEnd, Phase.VictoryCheck, Phase.MatchComplete }) do
				MatchOrchestrator.TransitionTo(phase, "test")
			end
			t:True(MatchOrchestrator.IsMatchComplete())

			local result = MatchOrchestrator.SubmitIntent(ALICE, "Roll", 1)
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.MatchEnded)
		end },

		{ "a completed match cannot transition anywhere", function(t)
			reset()
			beginTurnFor(ALICE)
			for _, phase in ipairs({ Phase.Draw, Phase.SpellChoice, Phase.RollReady, Phase.DiceResolution, Phase.Movement, Phase.LandingResolution, Phase.TurnEnd, Phase.VictoryCheck, Phase.MatchComplete }) do
				MatchOrchestrator.TransitionTo(phase, "test")
			end

			t:False(MatchOrchestrator.TransitionTo(Phase.TurnStart, "resume?").Ok)
			t:Equal(MatchOrchestrator.GetPhase(), Phase.MatchComplete)
		end },

		{ "accepted and rejected moves are both logged", function(t)
			-- The brief requires transitions to be legal, deterministic AND
			-- logged; a refusal that leaves no trace is undiagnosable.
			reset()
			MatchOrchestrator.TransitionTo(Phase.MatchSetup, "good")
			MatchOrchestrator.TransitionTo(Phase.Movement, "bad")

			local types = {}
			for _, entry in ipairs(MatchLogService.GetEntries()) do
				types[entry.Type] = (types[entry.Type] or 0) + 1
			end

			t:Equal(types.PhaseChanged, 1, "the accepted move")
			t:Equal(types.PhaseTransitionRejected, 1, "the refused move")
		end },

		{ "log entries carry the phase and turn they happened in", function(t)
			reset()
			beginTurnFor(ALICE)

			local entries = MatchLogService.GetEntries()
			local turnBegan
			for _, entry in ipairs(entries) do
				if entry.Type == "TurnBegan" then
					turnBegan = entry
				end
			end

			t:NotNil(turnBegan, "TurnBegan was logged")
			t:Equal(turnBegan.Phase, Phase.TurnStart)
			t:Equal(turnBegan.Turn, 1)
		end },

		{ "log indices are monotonic and never reused", function(t)
			reset()
			MatchOrchestrator.TransitionTo(Phase.MatchSetup, "a")
			MatchOrchestrator.TransitionTo(Phase.TurnStart, "b")

			local previous = 0
			for _, entry in ipairs(MatchLogService.GetEntries()) do
				t:True(entry.Index > previous, "index " .. entry.Index .. " did not increase")
				previous = entry.Index
			end
		end },

		{ "log entries cannot be edited after the fact", function(t)
			reset()
			MatchOrchestrator.TransitionTo(Phase.MatchSetup, "a")
			local entry = MatchLogService.GetEntries()[1]
			t:Throws(function() entry.Type = "Rewritten" end)
		end },

		{ "the log drops oldest-first and reports how many it dropped", function(t)
			-- Silently losing history would make the log misleading rather
			-- than merely incomplete.
			MatchLogService.Init()
			local realMax = MatchLogService.MaxEntries
			MatchLogService.MaxEntries = 5

			for index = 1, 12 do
				MatchLogService.Append("Filler", { N = index })
			end

			local stats = MatchLogService.GetStats()
			t:Equal(stats.Count, 5, "retained")
			t:Equal(stats.Dropped, 7, "dropped")
			t:Equal(MatchLogService.GetEntries()[1].Payload.N, 8, "oldest surviving entry")

			MatchLogService.MaxEntries = realMax
			MatchLogService.Init()
		end },

		{ "GetEntries(fromIndex) filters by absolute index, not position", function(t)
			reset()
			MatchOrchestrator.TransitionTo(Phase.MatchSetup, "a")
			MatchOrchestrator.TransitionTo(Phase.TurnStart, "b")

			local all = MatchLogService.GetEntries()
			local lastIndex = all[#all].Index
			local tail = MatchLogService.GetEntries(lastIndex)

			t:Equal(#tail, 1, "only the final entry")
			t:Equal(tail[1].Index, lastIndex)
		end },

		{ "Init clears phase, counters and sequences together", function(t)
			reset()
			beginTurnFor(ALICE)
			MatchOrchestrator.SubmitIntent(ALICE, "Roll", 4)

			MatchOrchestrator.Init()

			t:Equal(MatchOrchestrator.GetPhase(), Phase.WaitingForPlayers)
			t:Nil(MatchOrchestrator.GetActivePlayerId())
			t:Equal(MatchOrchestrator.GetTurnNumber(), 0)
			t:Equal(MatchOrchestrator.GetRoundNumber(), 0)
			t:Equal(MatchOrchestrator.PeekSequence(ALICE), 0, "a new match does not inherit sequences")
		end },
	},
}

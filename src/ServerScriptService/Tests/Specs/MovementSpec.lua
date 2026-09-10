--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > MovementSpec (ModuleScript)

	The brief's "Movement" acceptance criteria, run against TestBoard01, which
	exists precisely so each one has a real feature to exercise.

	Steps are forced rather than rolled throughout: the point of most of these
	is exact arrival, and a random roll would make the assertion about the
	generator instead of the resolver.

	The board, for reference:
		Castle -> P1 -> FortSun -> JT -> P2 -> Bridge ==> P4 -> FortMoon -> Pool -> Castle
		                            |                (warp)
		                            +-> S1 <-> DeadEnd
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ActionResult = require(ReplicatedStorage.Shared.ActionResult)
local TestBoard01 = require(ReplicatedStorage.Shared.BoardDefinitions.TestBoard01)
local CurrentLoop = require(ReplicatedStorage.Shared.BoardDefinitions.CurrentLoop)
local BoardGraphService = require(ServerScriptService.Systems.BoardGraphService)
local LapService = require(ServerScriptService.Systems.LapService)
local MovementService = require(ServerScriptService.Systems.MovementService)
local RandomService = require(ServerScriptService.Systems.RandomService)

local PLAYER = 4242

local function loadBoard(definition, seed)
	ActionResult.assertOk(BoardGraphService.Load(definition), "load board")
	LapService.Init({ Graph = BoardGraphService })
	MovementService.Init({
		Graph = BoardGraphService,
		Lap = LapService,
		Random = RandomService.new(seed or 1),
	})
	MovementService.RegisterCepter(PLAYER)
end

-- Walks `steps`, resolving any junction by taking the named edge.
local function moveTaking(steps, edgeId)
	local result = MovementService.BeginMove(PLAYER, steps)
	while result.Ok and result.Payload.Status == "AwaitingChoice" do
		result = MovementService.ChooseExit(PLAYER, edgeId)
	end
	return result
end

local function at()
	return MovementService.GetCurrentNodeId(PLAYER)
end

return {
	Name = "Movement (graph)",
	Tests = {
		{ "the test board loads and validates", function(t)
			loadBoard(TestBoard01)
			t:True(BoardGraphService.IsLoaded())
			t:Equal(BoardGraphService.GetBoardId(), "TestBoard01")
			t:Equal(BoardGraphService.GetStartNodeId(), "Castle")
			t:Equal(at(), "Castle", "a fresh Cepter starts at the castle")
		end },

		{ "forced steps produce exact arrival", function(t)
			-- The brief's "forced roll values produce exact steps".
			loadBoard(TestBoard01)
			t:True(MovementService.BeginMove(PLAYER, 1).Ok)
			t:Equal(at(), "P1", "one step")

			loadBoard(TestBoard01)
			t:True(MovementService.BeginMove(PLAYER, 2).Ok)
			t:Equal(at(), "FortSun", "two steps")
		end },

		{ "a junction pauses the move instead of guessing", function(t)
			loadBoard(TestBoard01)
			local result = MovementService.BeginMove(PLAYER, 5)

			t:True(result.Ok)
			t:Equal(result.Payload.Status, "AwaitingChoice")
			t:Equal(result.Payload.NodeId, "JT", "paused at the junction")
			t:Equal(#result.Payload.Options, 2, "both routes offered")
			t:True(MovementService.IsAwaitingChoice(PLAYER))
		end },

		{ "a junction preserves the remaining steps across the pause", function(t)
			-- The property the old for-loop could not have: the move survives
			-- being interrupted.
			loadBoard(TestBoard01)
			local paused = MovementService.BeginMove(PLAYER, 5)

			-- Three steps used to reach JT (P1, FortSun, JT), two left.
			t:Equal(paused.Payload.RemainingSteps, 2, "steps left when paused")

			local finished = MovementService.ChooseExit(PLAYER, "E04")
			t:True(finished.Ok)
			t:Equal(finished.Payload.Status, "Completed")
			-- Two more steps: P2, then Bridge -- which warps to P4.
			t:Equal(at(), "P4", "resumed and spent exactly the remaining steps")
		end },

		{ "choosing the other branch goes the other way", function(t)
			loadBoard(TestBoard01)
			MovementService.BeginMove(PLAYER, 4)
			local result = MovementService.ChooseExit(PLAYER, "E05")

			t:True(result.Ok)
			t:Equal(at(), "S1", "took the spur")
		end },

		{ "an edge that was not offered is refused, and the move survives", function(t)
			loadBoard(TestBoard01)
			MovementService.BeginMove(PLAYER, 5)

			local refused = MovementService.ChooseExit(PLAYER, "E13")
			t:False(refused.Ok, "an unoffered route is refused")
			t:True(MovementService.IsAwaitingChoice(PLAYER), "the move still awaits a real choice")

			t:True(MovementService.ChooseExit(PLAYER, "E04").Ok, "and can still be resumed")
		end },

		{ "immediate reversal is unavailable at a normal junction", function(t)
			-- Arriving at JT from the spur, only the main route is legal.
			loadBoard(TestBoard01)
			local exits = BoardGraphService.GetLegalExits("JT", "S1")

			t:Equal(#exits, 1, "one legal exit, not two")
			t:Equal(exits[1].To, "P2", "and it is the forward one")
		end },

		{ "a dead end reverses automatically", function(t)
			-- DeadEnd's only edge leads back to S1, so the no-reversal rule
			-- has to yield or the token would be stuck forever.
			loadBoard(TestBoard01)
			local exits = BoardGraphService.GetLegalExits("DeadEnd", "S1")

			t:Equal(#exits, 1)
			t:Equal(exits[1].To, "S1", "the way back is the only way on")

			-- Walked: JT(choose spur) -> S1 -> DeadEnd -> back to S1.
			loadBoard(TestBoard01)
			MovementService.BeginMove(PLAYER, 6)
			MovementService.ChooseExit(PLAYER, "E05")
			t:Equal(at(), "S1", "bounced off the dead end without stalling")
		end },

		{ "a mandatory warp fires when merely crossed", function(t)
			loadBoard(TestBoard01)
			-- Six steps: P1, FortSun, JT(choose main), P2, Bridge->warps to P4,
			-- then one more step to FortMoon.
			local result = moveTaking(6, "E04")

			t:True(result.Ok)
			t:Equal(at(), "FortMoon", "crossed the bridge and kept going")
			t:Contains(result.Payload.Path, "P4", "the warp destination is in the path")
		end },

		{ "a mandatory warp preserves the remaining movement", function(t)
			loadBoard(TestBoard01)
			-- Five steps lands exactly on Bridge, which warps to P4 with zero
			-- steps left, so the move ends at the destination.
			local result = moveTaking(5, "E04")

			t:True(result.Ok)
			t:Equal(at(), "P4", "warped and stopped, not warped and drifted")
			t:Equal(result.Payload.RemainingSteps, 0)
		end },

		{ "a landing warp does NOT fire when crossed", function(t)
			-- Pool warps to P1, but only on landing. Crossing it must leave
			-- the token continuing to the castle.
			--
			-- Step count, since a warp relocates WITHOUT spending a step:
			--   1 P1, 2 FortSun, 3 JT, 4 P2, 5 Bridge->P4, 6 FortMoon,
			--   7 Pool, 8 Castle. The whole main loop is eight, not nine.
			loadBoard(TestBoard01)
			local result = moveTaking(8, "E04")

			t:True(result.Ok)
			t:Equal(at(), "Castle", "crossed Pool without being teleported")
			t:Contains(result.Payload.Path, "Pool", "and did pass through it")
		end },

		{ "a landing warp DOES fire when landed on", function(t)
			loadBoard(TestBoard01)
			-- Seven steps ends exactly on Pool, which then relocates to P1.
			local result = moveTaking(7, "E04")

			t:True(result.Ok)
			t:Equal(at(), "P1", "landing on Pool warped to its destination")
		end },

		{ "a fort is credited once per lap, not once per visit", function(t)
			loadBoard(TestBoard01)
			t:DeepEqual(LapService.GetVisitedFortTypes(PLAYER), {}, "nothing visited yet")

			MovementService.BeginMove(PLAYER, 2) -- onto FortSun
			t:DeepEqual(LapService.GetVisitedFortTypes(PLAYER), { "Sun" })

			-- Re-crediting the same type is a no-op, not a second credit.
			t:False(LapService.CreditFort(PLAYER, "Sun"), "second visit credits nothing")
			t:DeepEqual(LapService.GetVisitedFortTypes(PLAYER), { "Sun" })
		end },

		{ "crossing the castle without every fort does not complete a lap", function(t)
			loadBoard(TestBoard01)
			-- Take the spur, which never reaches either fort... except FortSun
			-- sits before the junction, so Sun is credited but Moon is not.
			moveTaking(9, "E05")

			t:Equal(LapService.GetLapCount(PLAYER), 0, "no lap without both forts")
			t:DeepEqual(LapService.GetMissingFortTypes(PLAYER), { "Moon" })
		end },

		{ "crossing the castle with every fort completes the lap and resets it", function(t)
			loadBoard(TestBoard01)
			local completed = 0
			local connection = LapService.LapCompleted:Connect(function()
				completed += 1
			end)

			moveTaking(9, "E04") -- the full main loop, both forts, onto Castle
			connection.Disconnect()

			t:Equal(completed, 1, "LapCompleted fired once")
			t:Equal(LapService.GetLapCount(PLAYER), 1)
			t:DeepEqual(LapService.GetVisitedFortTypes(PLAYER), {}, "fort flags reset for the next lap")
		end },

		{ "a lap completes mid-move and movement continues", function(t)
			-- Nine steps: the eighth crosses the castle and completes the lap,
			-- the ninth carries on to P1. Crossing must not swallow the
			-- remaining movement.
			loadBoard(TestBoard01)
			moveTaking(9, "E04")

			t:Equal(LapService.GetLapCount(PLAYER), 1, "the lap still completed")
			t:Equal(at(), "P1", "and the last step was still spent")
		end },

		{ "a move in progress cannot be restarted", function(t)
			loadBoard(TestBoard01)
			MovementService.BeginMove(PLAYER, 5) -- pauses at JT

			local second = MovementService.BeginMove(PLAYER, 3)
			t:False(second.Ok, "a second move is refused while one is pending")
			t:True(MovementService.IsAwaitingChoice(PLAYER), "the original move is untouched")
		end },

		{ "zero and negative steps are refused", function(t)
			loadBoard(TestBoard01)
			t:False(MovementService.BeginMove(PLAYER, 0).Ok)
			t:False(MovementService.BeginMove(PLAYER, -2).Ok)
			t:False(MovementService.BeginMove(PLAYER, 1.5).Ok)
			t:Equal(at(), "Castle", "none of them moved the token")
		end },

		{ "step events fire in order for one step", function(t)
			loadBoard(TestBoard01)
			local order = {}
			local c1 = MovementService.NodeExited:Connect(function() table.insert(order, "exit") end)
			local c2 = MovementService.EdgeTraversed:Connect(function() table.insert(order, "edge") end)
			local c3 = MovementService.NodeEntered:Connect(function() table.insert(order, "enter") end)

			MovementService.BeginMove(PLAYER, 1)
			c1.Disconnect(); c2.Disconnect(); c3.Disconnect()

			t:DeepEqual(order, { "exit", "edge", "enter" })
		end },

		{ "the roll range comes from the board, not a hardcoded d6", function(t)
			loadBoard(TestBoard01)
			local min, max = BoardGraphService.GetRollRange()
			t:Equal(min, 1)
			t:Equal(max, 6)

			for _ = 1, 200 do
				local total = MovementService.RollDice(1)
				t:True(total >= min and total <= max, "roll " .. total .. " outside the board's range")
			end
		end },

		{ "teleport relocates without walking or crediting", function(t)
			-- A recall is not the same as walking across the board, so it must
			-- not pick up forts on the way -- there is no way.
			loadBoard(TestBoard01)
			local result = MovementService.TeleportTo(PLAYER, "FortMoon")

			t:True(result.Ok)
			t:Equal(at(), "FortMoon")
			t:DeepEqual(LapService.GetVisitedFortTypes(PLAYER), {}, "no forts credited by teleporting")
		end },

		{ "the 16-tile ring still walks exactly as it always did", function(t)
			-- The migration check: the graph must reproduce the old sorted-ring
			-- behaviour before it can be trusted on a board with branches.
			loadBoard(CurrentLoop)
			t:Equal(at(), "T1", "starts at the castle")

			MovementService.BeginMove(PLAYER, 1)
			t:Equal(at(), "T2")

			MovementService.BeginMove(PLAYER, 14)
			t:Equal(at(), "T16", "walked the ring without ever branching")

			MovementService.BeginMove(PLAYER, 1)
			t:Equal(at(), "T1", "and wrapped back round")
		end },

		{ "the ring exposes tile ids for callers that still use them", function(t)
			loadBoard(CurrentLoop)
			t:Equal(MovementService.GetCurrentTile(PLAYER), 1)

			MovementService.BeginMove(PLAYER, 3)
			t:Equal(MovementService.GetCurrentTile(PLAYER), 4, "node T4 reports tile 4")
		end },

		{ "a lap on the ring needs only the castle, since it has no forts", function(t)
			loadBoard(CurrentLoop)
			t:DeepEqual(BoardGraphService.GetRequiredFortTypes(), {}, "no forts on this board")

			MovementService.BeginMove(PLAYER, 16)
			t:Equal(at(), "T1")
			t:Equal(LapService.GetLapCount(PLAYER), 1, "a full circuit is one lap")
		end },
	},
}

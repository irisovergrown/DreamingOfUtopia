--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > VictoryService (ModuleScript)

	Purpose:
		Deciding when the match is actually won.

		The current rule is wrong twice over: it reads Current Magic instead
		of Total Magic, and it ends the match the instant the number is hit.
		Both matter. Reading CM means a player who spends their winnings on
		land gets further from victory while getting richer, and ending
		immediately removes the part of Culdcept everyone remembers — the long
		walk home while the board tries to stop you.

		So victory is two steps:

			1. GOAL REACHED. TM meets the target. This is a visible state, not
			   a win. It can be lost again.
			2. CONFIRMED AT THE CASTLE. The player reaches or crosses a castle
			   with lap requirements satisfied, and TM is re-checked THERE.

		Re-checking at the castle is the rule that gives the state its teeth:
		a rival who takes one of your territories on the way home can put you
		back under the line, and arriving no longer wins. Without the
		re-check, "goal reached" would be a formality rather than a target on
		your back.

	Public API:
		VictoryService.Init(deps)         -- deps.Valuation, deps.Lap, deps.Graph
		VictoryService.SetGoal(totalMagicGoal)
		VictoryService.GetGoal() -> number
		VictoryService.HasReachedGoal(userId) -> boolean
		VictoryService.IsGoalReachedState(userId) -> boolean
		VictoryService.RefreshGoalStates(userIds)
		VictoryService.TryConfirmAtCastle(userId, nodeId) -> boolean
		VictoryService.GetWinner() -> userId or nil
		VictoryService.IsMatchWon() -> boolean

	Signals:
		VictoryService.GoalReached:Connect(function(userId, totalMagic) end)
		VictoryService.GoalLost:Connect(function(userId, totalMagic) end)
		VictoryService.MatchWon:Connect(function(userId, totalMagic) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RulesConfig = require(ReplicatedStorage.Shared.RulesConfig)
local Signal = require(ReplicatedStorage.Shared.Signal)

local VictoryService = {}

VictoryService.GoalReached = Signal.new("Victory.GoalReached")
VictoryService.GoalLost = Signal.new("Victory.GoalLost")
VictoryService.MatchWon = Signal.new("Victory.MatchWon")

local _valuation, _lap, _graph
local _goal = RulesConfig.Match.DefaultTMGoal
local _goalReached = {}
local _winnerId = nil

function VictoryService.Init(deps)
	deps = deps or {}
	_valuation = deps.Valuation
	_lap = deps.Lap
	_graph = deps.Graph

	_goal = RulesConfig.Match.DefaultTMGoal
	_goalReached = {}
	_winnerId = nil
end

function VictoryService.SetGoal(totalMagicGoal)
	_goal = totalMagicGoal or RulesConfig.Match.DefaultTMGoal
end

function VictoryService.GetGoal()
	return _goal
end

function VictoryService.HasReachedGoal(userId)
	return _valuation ~= nil and _valuation.GetTotalMagic(userId) >= _goal
end

function VictoryService.IsGoalReachedState(userId)
	return _goalReached[userId] == true
end

-- Called whenever anything that can move TM has moved: a payment, a capture,
-- a level-up, an element change. The state is recomputed for EVERY player,
-- not just the one who acted, because one player's capture changes another
-- player's chain and therefore another player's total.
function VictoryService.RefreshGoalStates(userIds)
	for _, userId in ipairs(userIds or {}) do
		local reached = VictoryService.HasReachedGoal(userId)
		local was = _goalReached[userId] == true

		if reached and not was then
			_goalReached[userId] = true
			VictoryService.GoalReached:Fire(userId, _valuation.GetTotalMagic(userId))
		elseif not reached and was then
			-- Falling back under the line is a real event: the player was
			-- walking home to win and no longer can.
			_goalReached[userId] = nil
			VictoryService.GoalLost:Fire(userId, _valuation.GetTotalMagic(userId))
		end
	end
end

-- The confirmation. Returns true only if this arrival actually wins.
function VictoryService.TryConfirmAtCastle(userId, nodeId)
	if _winnerId ~= nil then
		return false
	end
	if _graph == nil or not _graph.IsCastle(nodeId) then
		return false
	end
	-- Lap requirements gate the castle for victory exactly as they do for a
	-- lap: arriving without the required forts is just an arrival.
	if _lap ~= nil and not _lap.HasAllRequiredForts(userId) then
		return false
	end
	-- Re-checked HERE, not trusted from when the goal was first reached.
	if not VictoryService.HasReachedGoal(userId) then
		return false
	end

	_winnerId = userId
	VictoryService.MatchWon:Fire(userId, _valuation.GetTotalMagic(userId))
	return true
end

function VictoryService.GetWinner()
	return _winnerId
end

function VictoryService.IsMatchWon()
	return _winnerId ~= nil
end

return VictoryService

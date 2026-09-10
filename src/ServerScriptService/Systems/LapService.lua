--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > LapService (ModuleScript)

	Purpose:
		Fort progress and lap completion.

		A lap is not "went round the board". It is: visit every required fort
		TYPE, then reach or cross the castle. Both halves matter, and the
		current code has neither — it counts a lap the moment a token touches
		the start tile, which would let a player collect lap bonuses without
		ever leaving the castle's neighbourhood on a board with a short cycle.

		Fort progress is tracked by TYPE, not by node. A board may have several
		physical Sun forts; visiting two of them is one fort type visited, not
		two. Crediting per node instead would let a player complete a lap by
		bouncing between duplicates of the same fort, which is exactly the
		degenerate route the type rule exists to close.

		Completing a lap resets the fort flags, so the next lap has to earn
		them again.

	Not done here (Milestone 4):
		Lap healing. The brief restores a configured percentage of MHP to a
		player's creatures on lap completion, but persistent creature HP does
		not exist yet — today's defender HP fuses the temporary land bonus into
		one number. Healing that would bake the bonus in permanently. The
		percentage is already in RulesConfig.Lap.HealPercentOfMHP, unused, and
		LapCompleted is the hook it will attach to.

	Public API:
		LapService.Init(deps)                 -- deps.Graph
		LapService.RegisterPlayer(userId)
		LapService.RemovePlayer(userId)
		LapService.CreditFort(userId, fortType) -> boolean  -- true if newly credited
		LapService.GetVisitedFortTypes(userId) -> sorted array
		LapService.HasAllRequiredForts(userId) -> boolean
		LapService.GetMissingFortTypes(userId) -> sorted array
		LapService.GetLapCount(userId) -> number
		LapService.TryCompleteLap(userId) -> boolean  -- true if a lap completed
		LapService.ResetForts(userId)

	Signals:
		LapService.FortVisited:Connect(function(userId, fortType) end)
		LapService.LapCompleted:Connect(function(userId, lapNumber) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

local LapService = {}

LapService.FortVisited = Signal.new("Lap.FortVisited")
LapService.LapCompleted = Signal.new("Lap.LapCompleted")

local _graph = nil
-- userId -> { LapCount = number, VisitedFortTypes = { [type] = true } }
local _state = {}

function LapService.Init(deps)
	_graph = (deps or {}).Graph
	_state = {}
end

local function stateFor(userId)
	local state = _state[userId]
	if state == nil then
		state = { LapCount = 0, VisitedFortTypes = {} }
		_state[userId] = state
	end
	return state
end

function LapService.RegisterPlayer(userId)
	_state[userId] = { LapCount = 0, VisitedFortTypes = {} }
end

function LapService.RemovePlayer(userId)
	_state[userId] = nil
end

-- Returns whether this was a NEW credit. A second visit to the same fort type
-- within one lap is not an error, it simply does nothing — and the caller
-- wants to know which it was so it can avoid announcing a non-event.
function LapService.CreditFort(userId, fortType)
	if fortType == nil then
		return false
	end

	local state = stateFor(userId)
	if state.VisitedFortTypes[fortType] then
		return false
	end

	state.VisitedFortTypes[fortType] = true
	LapService.FortVisited:Fire(userId, fortType)
	return true
end

function LapService.GetVisitedFortTypes(userId)
	local result = {}
	for fortType in pairs(stateFor(userId).VisitedFortTypes) do
		table.insert(result, fortType)
	end
	table.sort(result)
	return result
end

function LapService.GetMissingFortTypes(userId)
	local visited = stateFor(userId).VisitedFortTypes
	local missing = {}
	for _, fortType in ipairs(_graph and _graph.GetRequiredFortTypes() or {}) do
		if not visited[fortType] then
			table.insert(missing, fortType)
		end
	end
	table.sort(missing)
	return missing
end

function LapService.HasAllRequiredForts(userId)
	return #LapService.GetMissingFortTypes(userId) == 0
end

function LapService.GetLapCount(userId)
	return stateFor(userId).LapCount
end

function LapService.ResetForts(userId)
	stateFor(userId).VisitedFortTypes = {}
end

-- Called when a token reaches OR crosses a castle. Completing is conditional:
-- reaching the castle without every required fort is simply an ordinary
-- arrival, not a failure and not a lap.
function LapService.TryCompleteLap(userId)
	if not LapService.HasAllRequiredForts(userId) then
		return false
	end

	local state = stateFor(userId)
	state.LapCount += 1
	state.VisitedFortTypes = {}

	LapService.LapCompleted:Fire(userId, state.LapCount)
	return true
end

return LapService

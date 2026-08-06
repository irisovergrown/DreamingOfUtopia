--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > MovementService (ModuleScript)

	Purpose:
		Owns each Cepter's (player's) position on the board loop and dice
		rolling. Moves a Cepter tile-by-tile via BoardService.GetNextTileId
		so callers can react per-step (animation) or just to the final
		landing. Deliberately doesn't know about tile ownership, tolls, or
		claiming — BoardService/BattleService react to CepterLanded for
		that, per the project's cross-system signal rule.

		Depends on BoardService for exactly two read-only topology queries
		(GetNextTileId, GetStartTileId) — deliberately NOT a broader
		dependency; this module still never touches ownership, tolls, or
		any other BoardService state. That topology used to live in the
		static Shared/BoardData module; now that boards are hand-authored
		(CollectionService-tagged Parts, see BoardService's header),
		BoardService is the only thing that actually knows tile order at
		runtime, so this had to move here with it.

	Public API:
		MovementService.RegisterCepter(player)
		MovementService.RemoveCepter(player)
		MovementService.RollDice(diceCount) -> total, rolls (array)
		MovementService.MoveCepter(player, spaces) -> finalTileId or nil
		MovementService.GetCurrentTile(player) -> tileId or nil
		MovementService.GetLapCount(player) -> number

	Signals (ReplicatedStorage.Shared.Signal instances):
		MovementService.CepterMoved:Connect(function(player, fromTileId, toTileId) end)
		MovementService.CepterLanded:Connect(function(player, finalTileId) end)
		MovementService.LapCompleted:Connect(function(player, lapCount) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Signal = require(ReplicatedStorage.Shared.Signal)
local BoardService = require(ServerScriptService.Systems.BoardService)

local MovementService = {}

MovementService.CepterMoved = Signal.new()
MovementService.CepterLanded = Signal.new()
MovementService.LapCompleted = Signal.new()

-- Seconds paused between each tile-step during a move — placeholder pacing
-- so CepterMoved reads as stepwise movement instead of an instant jump.
-- Tune once real movement animation/tweening exists.
local STEP_DELAY = 0.25

local _rng = Random.new()

-- player.UserId -> { CurrentTileId = number, LapCount = number }
local _cepterState = {}

function MovementService.RegisterCepter(player)
	_cepterState[player.UserId] = {
		CurrentTileId = BoardService.GetStartTileId(),
		LapCount = 0,
	}
end

function MovementService.RemoveCepter(player)
	_cepterState[player.UserId] = nil
end

function MovementService.GetCurrentTile(player)
	local state = _cepterState[player.UserId]
	return state and state.CurrentTileId
end

function MovementService.GetLapCount(player)
	local state = _cepterState[player.UserId]
	return state and state.LapCount or 0
end

function MovementService.RollDice(diceCount)
	diceCount = diceCount or 1

	local rolls = {}
	local total = 0
	for i = 1, diceCount do
		local roll = _rng:NextInteger(1, 6)
		rolls[i] = roll
		total += roll
	end

	return total, rolls
end

function MovementService.MoveCepter(player, spaces)
	local state = _cepterState[player.UserId]
	if state == nil then
		return nil
	end

	local startTileId = BoardService.GetStartTileId()

	for _ = 1, spaces do
		local fromTileId = state.CurrentTileId
		local toTileId = BoardService.GetNextTileId(fromTileId)
		state.CurrentTileId = toTileId

		MovementService.CepterMoved:Fire(player, fromTileId, toTileId)

		if toTileId == startTileId then
			state.LapCount += 1
			MovementService.LapCompleted:Fire(player, state.LapCount)
		end

		task.wait(STEP_DELAY)
	end

	MovementService.CepterLanded:Fire(player, state.CurrentTileId)
	return state.CurrentTileId
end

return MovementService

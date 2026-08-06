--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > MatchService (ModuleScript)

	Purpose:
		Turn order and match-end lifecycle. Registered players rotate in
		join order; only the current turn holder may roll (once per turn —
		EndTurn resets that) or take a Battle/Economy action. Main.server.lua
		enforces this by checking IsPlayersTurn/HasRolledThisTurn in its
		RemoteEvent handlers before calling MovementService/BattleService/
		EconomyService — those systems stay turn-agnostic themselves, same
		as documented in their own headers.

		Ends the match by subscribing to EconomyService.WinTargetReached:
		freezes turns (IsPlayersTurn returns false for everyone) and fires
		MatchEnded with the winner.

		Deliberately NOT built here:
		- Match setup / a lobby (choosing board size, waiting for a minimum
		  player count, an explicit "start match" step). There's no lobby
		  UI, so the "match" is implicitly in progress from the first
		  registered player onward — same always-on-world style the rest of
		  the project has used so far. A real MatchService covering this
		  would need that UI first.
		- 2v2 alliance mode. GetTeam/AreAllies exist as the seam a real
		  team-select flow will use later, but every player is currently
		  their own team (pure FFA) — no pairing logic exists yet. Adding
		  it won't require GetTeam/AreAllies' signatures to change.
		- Rematch / returning to a lobby after MatchEnded fires.

	Public API:
		MatchService.Init()
		MatchService.RegisterPlayer(player)
		MatchService.RemovePlayer(player)
		MatchService.GetCurrentTurnPlayer() -> Player or nil
		MatchService.IsPlayersTurn(player) -> boolean
		MatchService.HasRolledThisTurn() -> boolean
		MatchService.MarkRolled()
		MatchService.EndTurn(player) -> success, reason
		MatchService.GetTeam(player) -> teamId (FFA only: player's own userId)
		MatchService.AreAllies(playerA, playerB) -> boolean
		MatchService.IsMatchEnded() -> boolean
		MatchService.GetWinner() -> userId or nil

	Signals (ReplicatedStorage.Shared.Signal instances):
		MatchService.TurnChanged:Connect(function(currentTurnUserId) end)
		MatchService.MatchEnded:Connect(function(winnerUserId) end)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Signal = require(ReplicatedStorage.Shared.Signal)
local EconomyService = require(ServerScriptService.Systems.EconomyService)

local MatchService = {}

MatchService.TurnChanged = Signal.new()
MatchService.MatchEnded = Signal.new()

-- Array of userIds, in join/turn order.
local _turnOrder = {}
local _currentTurnIndex = 1
local _hasRolledThisTurn = false
local _matchEnded = false
local _winnerId = nil

local function getUserId(playerOrUserId)
	if playerOrUserId == nil then
		return nil
	end
	if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		return playerOrUserId.UserId
	end
	return playerOrUserId
end

function MatchService.Init()
	_turnOrder = {}
	_currentTurnIndex = 1
	_hasRolledThisTurn = false
	_matchEnded = false
	_winnerId = nil

	EconomyService.WinTargetReached:Connect(function(userId, _balance)
		if _matchEnded then
			return
		end
		_matchEnded = true
		_winnerId = userId
		MatchService.MatchEnded:Fire(userId)
	end)
end

function MatchService.RegisterPlayer(player)
	table.insert(_turnOrder, getUserId(player))
end

function MatchService.RemovePlayer(player)
	local userId = getUserId(player)
	local removedIndex = nil
	for i, id in ipairs(_turnOrder) do
		if id == userId then
			removedIndex = i
			break
		end
	end
	if removedIndex == nil then
		return
	end

	table.remove(_turnOrder, removedIndex)

	if #_turnOrder == 0 then
		_currentTurnIndex = 1
		return
	end

	if removedIndex < _currentTurnIndex then
		_currentTurnIndex -= 1
	end
	if _currentTurnIndex > #_turnOrder then
		_currentTurnIndex = 1
	end
end

function MatchService.GetCurrentTurnPlayer()
	local userId = _turnOrder[_currentTurnIndex]
	if userId == nil then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

function MatchService.IsPlayersTurn(player)
	if _matchEnded then
		return false
	end
	local currentPlayer = MatchService.GetCurrentTurnPlayer()
	return currentPlayer ~= nil and currentPlayer == player
end

function MatchService.HasRolledThisTurn()
	return _hasRolledThisTurn
end

function MatchService.MarkRolled()
	_hasRolledThisTurn = true
end

function MatchService.EndTurn(player)
	if _matchEnded then
		return false, "Match has ended"
	end
	if not MatchService.IsPlayersTurn(player) then
		return false, "Not your turn"
	end

	_currentTurnIndex = (_currentTurnIndex % #_turnOrder) + 1
	_hasRolledThisTurn = false

	MatchService.TurnChanged:Fire(_turnOrder[_currentTurnIndex])
	return true, nil
end

-- FFA only for now — see header. Every player is their own team.
function MatchService.GetTeam(player)
	return getUserId(player)
end

function MatchService.AreAllies(playerA, playerB)
	return MatchService.GetTeam(playerA) == MatchService.GetTeam(playerB)
end

function MatchService.IsMatchEnded()
	return _matchEnded
end

function MatchService.GetWinner()
	return _winnerId
end

return MatchService

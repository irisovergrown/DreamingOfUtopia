--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > EconomyService (ModuleScript)

	Purpose:
		Owns each player's Magic balance (the brief's working-name "Total
		Magic"/TM currency), the lap bonus (auto-applied by self-subscribing
		to MovementService.LapCompleted — this is unconditional/automatic
		per the gameplay reference, unlike landing-on-a-tile choices, so it
		doesn't need to wait for a UI/MatchService to gather player intent
		the way BattleService's landing actions do), toll payment, and win
		target detection.

		All formula constants below are placeholders reconstructed from the
		brief's gameplay reference, same as BoardService's — tune later.

		Deliberately NOT built here: actually ending a match / declaring a
		winner (fires WinTargetReached and stops there — MatchService will
		consume that once it exists), and tile/balance cleanup when an
		owning player disconnects mid-match (PayToll just skips crediting a
		departed owner rather than erroring — a known simplification until
		MatchService owns match-lifecycle/player-leave handling).

	Public API:
		EconomyService.Init()
		EconomyService.RegisterPlayer(player)
		EconomyService.RemovePlayer(player)
		EconomyService.GetBalance(player) -> number or nil
		EconomyService.AddMagic(player, amount) -> newBalance or nil
		EconomyService.SpendMagic(player, amount) -> success, newBalanceOrReason
		EconomyService.ComputeLapBonus(player) -> number
		EconomyService.PayToll(player, tileId) -> success, reason

	Signals (ReplicatedStorage.Shared.Signal instances):
		EconomyService.BalanceChanged:Connect(function(userId, newBalance) end)
		EconomyService.WinTargetReached:Connect(function(userId, balance) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Signal = require(ReplicatedStorage.Shared.Signal)
local BoardService = require(ServerScriptService.Systems.BoardService)
local MovementService = require(ServerScriptService.Systems.MovementService)

local EconomyService = {}

EconomyService.BalanceChanged = Signal.new()
EconomyService.WinTargetReached = Signal.new()

local STARTING_MAGIC = 500
local WIN_TARGET_MAGIC = 3000

-- Lap bonus formula pieces (brief: "scaling with lap count, tile count
-- owned, and symbol [era] majority") — placeholder weights, not final balance.
local BASE_LAP_BONUS = 50
local TILE_OWNED_BONUS_PER_TILE = 10
local LAP_COUNT_BONUS_PER_LAP = 20
local ERA_MAJORITY_BONUS = 100

-- userId -> number
local _balances = {}

local function getUserId(playerOrUserId)
	if playerOrUserId == nil then
		return nil
	end
	if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		return playerOrUserId.UserId
	end
	return playerOrUserId
end

-- era -> { [ownerUserId] = tileCount }, Property tiles only.
local function getEraOwnershipCounts()
	local counts = {}
	for _, tile in ipairs(BoardService.GetAllTiles()) do
		if tile.TileType == "Property" and tile.Owner ~= nil and tile.Era ~= nil then
			counts[tile.Era] = counts[tile.Era] or {}
			counts[tile.Era][tile.Owner] = (counts[tile.Era][tile.Owner] or 0) + 1
		end
	end
	return counts
end

-- Number of eras where userId strictly owns more Property tiles than any
-- other single player (ties count as no majority — simplest tunable rule).
local function countMajorityEras(userId, eraOwnershipCounts)
	local majorityCount = 0
	for _, ownerCounts in pairs(eraOwnershipCounts) do
		local playerCount = ownerCounts[userId] or 0
		if playerCount > 0 then
			local isMajority = true
			for otherUserId, otherCount in pairs(ownerCounts) do
				if otherUserId ~= userId and otherCount >= playerCount then
					isMajority = false
					break
				end
			end
			if isMajority then
				majorityCount += 1
			end
		end
	end
	return majorityCount
end

function EconomyService.Init()
	_balances = {}

	MovementService.LapCompleted:Connect(function(player, _lapCount)
		local bonus = EconomyService.ComputeLapBonus(player)
		EconomyService.AddMagic(player, bonus)

		local balance = EconomyService.GetBalance(player)
		if balance ~= nil and balance >= WIN_TARGET_MAGIC then
			EconomyService.WinTargetReached:Fire(getUserId(player), balance)
		end
	end)
end

function EconomyService.RegisterPlayer(player)
	local userId = getUserId(player)
	_balances[userId] = STARTING_MAGIC
	EconomyService.BalanceChanged:Fire(userId, _balances[userId])
end

function EconomyService.RemovePlayer(player)
	_balances[getUserId(player)] = nil
end

function EconomyService.GetBalance(playerOrUserId)
	return _balances[getUserId(playerOrUserId)]
end

function EconomyService.AddMagic(playerOrUserId, amount)
	local userId = getUserId(playerOrUserId)
	if _balances[userId] == nil then
		return nil
	end

	_balances[userId] += amount
	EconomyService.BalanceChanged:Fire(userId, _balances[userId])
	return _balances[userId]
end

function EconomyService.SpendMagic(playerOrUserId, amount)
	local userId = getUserId(playerOrUserId)
	local balance = _balances[userId]
	if balance == nil then
		return false, "Player not registered with EconomyService"
	end
	if balance < amount then
		return false, "Not enough Magic"
	end

	_balances[userId] = balance - amount
	EconomyService.BalanceChanged:Fire(userId, _balances[userId])
	return true, _balances[userId]
end

function EconomyService.ComputeLapBonus(player)
	local userId = getUserId(player)
	local lapCount = MovementService.GetLapCount(player)

	local ownedCount = 0
	for _, tile in ipairs(BoardService.GetAllTiles()) do
		if tile.TileType == "Property" and tile.Owner == userId then
			ownedCount += 1
		end
	end

	local majorityEraCount = countMajorityEras(userId, getEraOwnershipCounts())

	return BASE_LAP_BONUS
		+ ownedCount * TILE_OWNED_BONUS_PER_TILE
		+ lapCount * LAP_COUNT_BONUS_PER_LAP
		+ majorityEraCount * ERA_MAJORITY_BONUS
end

function EconomyService.PayToll(player, tileId)
	local tile = BoardService.GetTile(tileId)
	if tile == nil or tile.TileType ~= "Property" or tile.Owner == nil then
		return false, "Tile has no toll to pay"
	end

	local payerUserId = getUserId(player)
	if tile.Owner == payerUserId then
		return false, "You own this tile"
	end

	local toll = BoardService.GetToll(tileId)
	local success, reason = EconomyService.SpendMagic(payerUserId, toll)
	if not success then
		return false, reason
	end

	-- If the owner has since left the game their balance record is gone —
	-- skip crediting rather than reviving a record for an absent player.
	if _balances[tile.Owner] ~= nil then
		EconomyService.AddMagic(tile.Owner, toll)
	end

	return true, nil
end

return EconomyService

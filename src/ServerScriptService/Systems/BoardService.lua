--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > BoardService (ModuleScript)

	Purpose:
		Authoritative owner of tile runtime state (who owns each tile, its
		level) and the tile value / toll math. Combines the static layout
		from ReplicatedStorage.Shared.BoardData with server-only state that
		must never be trusted to the client.

		Other systems (MovementService, BattleService, EconomyService, ...)
		only touch tiles through this module's public API below, and react
		to state changes via the exposed Signals instead of polling —
		per the project's cross-system communication rule.

		All formula constants are placeholders reconstructed from Culdcept
		Saga community notes, per the brief: tune later, don't treat as final.

	Public API:
		BoardService.Init()
		BoardService.GetTile(tileId) -> table snapshot or nil
		BoardService.GetAllTiles() -> array of table snapshots
		BoardService.SetOwner(tileId, player)         -- player or nil to clear
		BoardService.LevelUp(tileId)      -> newLevel or nil if already max
		BoardService.GetChainMultiplier(userId, era)
		BoardService.GetTileValue(tileId)
		BoardService.GetToll(tileId)
		BoardService.GetLandBonusHP(tileId)            -- caller checks era match

	Signals (ReplicatedStorage.Shared.Signal instances):
		BoardService.TileOwnerChanged:Connect(function(tileId, newOwnerUserId) end)
		BoardService.TileLeveledUp:Connect(function(tileId, newLevel) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)
local BoardData = require(ReplicatedStorage.Shared.BoardData)

local BoardService = {}

BoardService.TileOwnerChanged = Signal.new()
BoardService.TileLeveledUp = Signal.new()

local MAX_TILE_LEVEL = 5

-- TollMod per level, ~0.2 at Lv1 scaling to ~0.8 at Lv5 (brief's reference range).
local TOLL_MOD_BY_LEVEL = { 0.2, 0.35, 0.5, 0.65, 0.8 }

-- +50% toll value per additional same-era tile the same player owns beyond the first.
local CHAIN_BONUS_PER_EXTRA_TILE = 0.5

-- +10 HP per tile level for a matching-era creature landing on its own tile.
local LAND_BONUS_HP_PER_LEVEL = 10

-- tileId -> { Owner = userId or nil, Level = number }
local _tileState = {}

local function getUserId(playerOrUserId)
	if playerOrUserId == nil then
		return nil
	end
	if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		return playerOrUserId.UserId
	end
	return playerOrUserId
end

function BoardService.Init()
	_tileState = {}
	for _, tile in ipairs(BoardData.Tiles) do
		_tileState[tile.Id] = {
			Owner = nil,
			Level = 1,
		}
	end
end

function BoardService.GetTile(tileId)
	local static = nil
	for _, tile in ipairs(BoardData.Tiles) do
		if tile.Id == tileId then
			static = tile
			break
		end
	end

	local state = _tileState[tileId]
	if static == nil or state == nil then
		return nil
	end

	return {
		Id = static.Id,
		GridPosition = static.GridPosition,
		Era = static.Era,
		BaseValue = static.BaseValue,
		TileType = static.TileType,
		Owner = state.Owner,
		Level = state.Level,
	}
end

function BoardService.GetAllTiles()
	local snapshots = {}
	for _, tile in ipairs(BoardData.Tiles) do
		table.insert(snapshots, BoardService.GetTile(tile.Id))
	end
	return snapshots
end

function BoardService.SetOwner(tileId, playerOrUserId)
	local state = _tileState[tileId]
	if state == nil then
		return
	end

	state.Owner = getUserId(playerOrUserId)
	BoardService.TileOwnerChanged:Fire(tileId, state.Owner)
end

function BoardService.LevelUp(tileId)
	local state = _tileState[tileId]
	if state == nil or state.Level >= MAX_TILE_LEVEL then
		return nil
	end

	state.Level += 1
	BoardService.TileLeveledUp:Fire(tileId, state.Level)
	return state.Level
end

function BoardService.GetChainMultiplier(playerOrUserId, era)
	local userId = getUserId(playerOrUserId)
	if userId == nil or era == nil then
		return 1
	end

	local ownedSameEraCount = 0
	for _, tile in ipairs(BoardData.Tiles) do
		local state = _tileState[tile.Id]
		if state.Owner == userId and tile.Era == era then
			ownedSameEraCount += 1
		end
	end

	if ownedSameEraCount <= 1 then
		return 1
	end
	return 1 + CHAIN_BONUS_PER_EXTRA_TILE * (ownedSameEraCount - 1)
end

function BoardService.GetTileValue(tileId)
	local tile = BoardService.GetTile(tileId)
	if tile == nil or tile.TileType ~= "Property" then
		return 0
	end

	local chainMultiplier = BoardService.GetChainMultiplier(tile.Owner, tile.Era)
	return tile.BaseValue * (2 ^ (tile.Level - 1)) * chainMultiplier
end

function BoardService.GetToll(tileId)
	local tile = BoardService.GetTile(tileId)
	if tile == nil then
		return 0
	end

	local tollMod = TOLL_MOD_BY_LEVEL[tile.Level] or TOLL_MOD_BY_LEVEL[1]
	return BoardService.GetTileValue(tileId) * tollMod
end

function BoardService.GetLandBonusHP(tileId)
	local tile = BoardService.GetTile(tileId)
	if tile == nil then
		return 0
	end
	return LAND_BONUS_HP_PER_LEVEL * tile.Level
end

return BoardService

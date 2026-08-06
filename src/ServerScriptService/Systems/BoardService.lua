--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > BoardService (ModuleScript)

	Purpose:
		Authoritative owner of the board itself: which tiles exist, their
		order, and their runtime state (owner, level, era). The board is
		now HAND-AUTHORED — tiles are Parts placed directly in Workspace by
		the developer, not code-generated. Init() builds the tile registry
		by scanning CollectionService for parts tagged "Tile" and reading
		attributes off each one:
			Id        (number, REQUIRED)  order in the movement loop — does
			                               not need to be contiguous, only
			                               uniquely orderable (sorted once
			                               at Init); tile adjacency is NOT
			                               inferable from spatial position,
			                               so this can't be skipped.
			TileType  (string, REQUIRED)  "Start" or "Property"
			Era       (string, optional)  must match an EraData.Eras key,
			                               or leave blank for neutral/Start
			BaseValue (number, optional)  defaults to 0 for Start, 100 for
			                               Property if unset
		A tile missing Id is skipped with a warning — everything else about
		a tile (its Part's Position, color, model) is Studio-authored and
		this module never touches or needs it; Main.server.lua does its own
		separate tag scan for that, keeping visual and logic concerns split.

		Other systems (MovementService, BattleService, EconomyService, ...)
		only touch tiles through this module's public API below, and react
		to state changes via the exposed Signals instead of polling — per
		the project's cross-system communication rule. MovementService
		depends on GetNextTileId specifically (pure topology, not
		ownership/tolls) — see its own header for why that's an
		intentionally narrow exception to staying decoupled from BoardService.

		All formula constants are placeholders reconstructed from Culdcept
		Saga community notes, per the brief: tune later, don't treat as final.

	Public API:
		BoardService.Init()
		BoardService.GetTile(tileId) -> table snapshot or nil
		BoardService.GetAllTiles() -> array of table snapshots, in Id order
		BoardService.GetNextTileId(tileId) -> tileId or nil, wraps around the loop
		BoardService.GetStartTileId() -> tileId of the tile tagged TileType="Start"
		BoardService.SetOwner(tileId, player)         -- player or nil to clear
		BoardService.LevelUp(tileId)      -> newLevel or nil if already max
		BoardService.SetEra(tileId, era)              -- era or nil for neutral
		BoardService.GetChainMultiplier(userId, era)
		BoardService.GetTileValue(tileId)
		BoardService.GetToll(tileId)
		BoardService.GetLandBonusHP(tileId)            -- caller checks era match

	Signals (ReplicatedStorage.Shared.Signal instances):
		BoardService.TileOwnerChanged:Connect(function(tileId, newOwnerUserId) end)
		BoardService.TileLeveledUp:Connect(function(tileId, newLevel) end)
		BoardService.EraChanged:Connect(function(tileId, newEra) end)
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

local BoardService = {}

BoardService.TileOwnerChanged = Signal.new()
BoardService.TileLeveledUp = Signal.new()
BoardService.EraChanged = Signal.new()

local TILE_TAG = "Tile"
local MAX_TILE_LEVEL = 5
local DEFAULT_PROPERTY_BASE_VALUE = 100

-- TollMod per level, ~0.2 at Lv1 scaling to ~0.8 at Lv5 (brief's reference range).
local TOLL_MOD_BY_LEVEL = { 0.2, 0.35, 0.5, 0.65, 0.8 }

-- +50% toll value per additional same-era tile the same player owns beyond the first.
local CHAIN_BONUS_PER_EXTRA_TILE = 0.5

-- +10 HP per tile level for a matching-era creature landing on its own tile.
local LAND_BONUS_HP_PER_LEVEL = 10

-- tileId -> { Owner, Level, Era, TileType, BaseValue } — the full tile record now
-- lives here, populated once from hand-placed Parts' attributes at Init.
local _tileState = {}
-- Sorted array of tileIds, defines movement order for GetNextTileId/GetAllTiles.
local _tileOrder = {}

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
	_tileOrder = {}

	for _, part in ipairs(CollectionService:GetTagged(TILE_TAG)) do
		local id = part:GetAttribute("Id")
		if id == nil then
			warn("[BoardService] " .. part:GetFullName() .. " is tagged Tile but has no Id attribute, skipping")
		else
			local tileType = part:GetAttribute("TileType") or "Property"
			local era = part:GetAttribute("Era")
			if era == "" then
				era = nil
			end
			local baseValue = part:GetAttribute("BaseValue")
			if baseValue == nil then
				baseValue = tileType == "Start" and 0 or DEFAULT_PROPERTY_BASE_VALUE
			end

			_tileState[id] = {
				Owner = nil,
				Level = 1,
				Era = era,
				TileType = tileType,
				BaseValue = baseValue,
			}
			table.insert(_tileOrder, id)
		end
	end

	table.sort(_tileOrder)
end

function BoardService.GetTile(tileId)
	local state = _tileState[tileId]
	if state == nil then
		return nil
	end

	return {
		Id = tileId,
		Era = state.Era,
		BaseValue = state.BaseValue,
		TileType = state.TileType,
		Owner = state.Owner,
		Level = state.Level,
	}
end

function BoardService.GetAllTiles()
	local snapshots = {}
	for _, tileId in ipairs(_tileOrder) do
		table.insert(snapshots, BoardService.GetTile(tileId))
	end
	return snapshots
end

function BoardService.GetNextTileId(tileId)
	for i, id in ipairs(_tileOrder) do
		if id == tileId then
			local nextIndex = (i % #_tileOrder) + 1
			return _tileOrder[nextIndex]
		end
	end
	return nil
end

function BoardService.GetStartTileId()
	for _, tileId in ipairs(_tileOrder) do
		if _tileState[tileId].TileType == "Start" then
			return tileId
		end
	end
	return _tileOrder[1]
end

function BoardService.SetEra(tileId, era)
	local state = _tileState[tileId]
	if state == nil then
		return
	end

	state.Era = era
	BoardService.EraChanged:Fire(tileId, era)
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
	for _, tileId in ipairs(_tileOrder) do
		local state = _tileState[tileId]
		if state.Owner == userId and state.Era == era then
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

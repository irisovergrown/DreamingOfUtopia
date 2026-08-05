--[[
	Script — server, standalone bootstrap / composition root.

	Studio placement:
		ServerScriptService > Main (Script)

	Purpose:
		First thing that runs when the place starts. Initializes
		BoardService and physically builds the greybox board (BoardData)
		onto the baseplate so the layout is visible and testable in Studio.
		This is the wiring layer — it requires systems and connects their
		Signals, but game systems still never require each other directly.

		Nothing here is meant to be final visual art — plain colored parts
		and a BillboardGui label, just enough to see the board loop and
		verify BoardService state changes render.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local BoardData = require(ReplicatedStorage.Shared.BoardData)
local EraData = require(ReplicatedStorage.Shared.EraData)
local BoardService = require(ServerScriptService.Systems.BoardService)

BoardService.Init()

local boardFolder = Instance.new("Folder")
boardFolder.Name = "Board"
boardFolder.Parent = Workspace

-- Grid is 0..4 on both axes (see BoardData) — center it on the origin.
local GRID_CENTER = 2
local TILE_HEIGHT = 2

local tileParts = {}

local function createTilePart(tile)
	local era = EraData.GetEra(tile.Era)

	local part = Instance.new("Part")
	part.Name = "Tile_" .. tile.Id
	part.Anchored = true
	part.Size = Vector3.new(BoardData.TileSize, TILE_HEIGHT, BoardData.TileSize)
	part.Position = Vector3.new(
		(tile.GridPosition.X - GRID_CENTER) * BoardData.TileSpacing,
		TILE_HEIGHT / 2,
		(tile.GridPosition.Z - GRID_CENTER) * BoardData.TileSpacing
	)
	part.Color = era.Color
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = boardFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TileLabel"
	billboard.Size = UDim2.fromOffset(160, 40)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.Code
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard

	tileParts[tile.Id] = part

	return part, label
end

local tileLabels = {}

for _, tile in ipairs(BoardData.Tiles) do
	local part, label = createTilePart(tile)
	tileLabels[tile.Id] = label
end

local function refreshTileLabel(tileId)
	local tile = BoardService.GetTile(tileId)
	local label = tileLabels[tileId]
	if tile == nil or label == nil then
		return
	end

	if tile.TileType == "Start" then
		label.Text = string.format("#%d — Start", tile.Id)
		return
	end

	local era = EraData.GetEra(tile.Era)
	local ownerText = tile.Owner and ("Owner " .. tostring(tile.Owner)) or "Unclaimed"
	label.Text = string.format("#%d — %s — Lv%d — %s", tile.Id, era.DisplayName, tile.Level, ownerText)
end

for _, tile in ipairs(BoardData.Tiles) do
	refreshTileLabel(tile.Id)
end

-- React to BoardService state changes instead of polling — the cross-system
-- signal pattern MovementService/BattleService will also use once they exist.
BoardService.TileOwnerChanged:Connect(function(tileId, newOwnerUserId)
	local part = tileParts[tileId]
	if part ~= nil then
		part.Material = newOwnerUserId and Enum.Material.Neon or Enum.Material.SmoothPlastic
	end
	refreshTileLabel(tileId)
end)

BoardService.TileLeveledUp:Connect(function(tileId, _newLevel)
	refreshTileLabel(tileId)
end)

print("[DreamingOfUtopia] Board initialized:", #BoardData.Tiles, "tiles")

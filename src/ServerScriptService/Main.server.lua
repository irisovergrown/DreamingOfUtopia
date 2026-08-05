--[[
	Script — server, standalone bootstrap / composition root.

	Studio placement:
		ServerScriptService > Main (Script)

	Purpose:
		First thing that runs when the place starts. Initializes
		BoardService and physically builds the greybox board (BoardData)
		onto the baseplate so the layout is visible and testable in Studio.
		Also registers each joining player with MovementService and gives
		them a simple ball "Cepter token" that walks the board on move, and
		requires CardService so its card registry loads at boot.
		This is the wiring layer — it requires systems and connects their
		Signals, but game systems still never require each other directly.

		Nothing here is meant to be final visual art — plain colored parts
		and a BillboardGui label, just enough to see the board loop and
		verify BoardService/MovementService/BattleService state changes render.

		Includes temporary "/roll", "/summon <cardId>", and
		"/challenge <cardId>" chat commands so movement and battles are
		testable without a real UI/MatchService yet — no turn enforcement,
		no cost/toll payment (no EconomyService yet). Replace with
		UIService-driven input once those systems exist.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local BoardData = require(ReplicatedStorage.Shared.BoardData)
local EraData = require(ReplicatedStorage.Shared.EraData)
local BoardService = require(ServerScriptService.Systems.BoardService)
local MovementService = require(ServerScriptService.Systems.MovementService)
local CardService = require(ServerScriptService.Systems.CardService)
local BattleService = require(ServerScriptService.Systems.BattleService)

BoardService.Init()
BattleService.Init()

local boardFolder = Instance.new("Folder")
boardFolder.Name = "Board"
boardFolder.Parent = Workspace

-- Grid is 0..4 on both axes (see BoardData) — center it on the origin.
local GRID_CENTER = 2
local TILE_HEIGHT = 2
local CEPTER_TOKEN_HEIGHT = 3

local function gridToWorldPosition(gridPosition, yOffset)
	return Vector3.new(
		(gridPosition.X - GRID_CENTER) * BoardData.TileSpacing,
		yOffset,
		(gridPosition.Z - GRID_CENTER) * BoardData.TileSpacing
	)
end

local tileParts = {}
local tileGridById = {}

local function createTilePart(tile)
	local era = EraData.GetEra(tile.Era)

	local part = Instance.new("Part")
	part.Name = "Tile_" .. tile.Id
	part.Anchored = true
	part.Size = Vector3.new(BoardData.TileSize, TILE_HEIGHT, BoardData.TileSize)
	part.Position = gridToWorldPosition(tile.GridPosition, TILE_HEIGHT / 2)
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
	tileGridById[tile.Id] = tile.GridPosition
end

local function getTileWorldPosition(tileId, yOffset)
	local gridPosition = tileGridById[tileId]
	if gridPosition == nil then
		return Vector3.new(0, yOffset, 0)
	end
	return gridToWorldPosition(gridPosition, yOffset)
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

	local defenderText = ""
	local defender = BattleService.GetDefender(tileId)
	if defender ~= nil then
		local card = CardService.GetCard(defender.CardId)
		if card ~= nil then
			defenderText = string.format(" — %s (%dHP)", card.Name, defender.CurrentHP)
		end
	end

	label.Text = string.format("#%d — %s — Lv%d — %s%s", tile.Id, era.DisplayName, tile.Level, ownerText, defenderText)
end

for _, tile in ipairs(BoardData.Tiles) do
	refreshTileLabel(tile.Id)
end

-- React to BoardService state changes instead of polling — the same
-- cross-system signal pattern MovementService and BattleService use.
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

-- Cepter tokens: one ball per player, walking the board as MovementService moves them.
local cepterTokens = {}

local function createCepterToken(player)
	local token = Instance.new("Part")
	token.Name = "Cepter_" .. player.UserId
	token.Shape = Enum.PartType.Ball
	token.Size = Vector3.new(3, 3, 3)
	token.Anchored = true
	token.CanCollide = false
	token.Color = BrickColor.Random().Color
	token.Position = getTileWorldPosition(MovementService.GetCurrentTile(player), CEPTER_TOKEN_HEIGHT)
	token.Parent = boardFolder

	cepterTokens[player.UserId] = token
end

local function onPlayerAdded(player)
	MovementService.RegisterCepter(player)
	createCepterToken(player)

	-- Temporary manual test harness — replace with UIService-driven input
	-- once MatchService/UIService exist.
	player.Chatted:Connect(function(message)
		if message:lower() == "/roll" then
			local total = MovementService.RollDice(1)
			print(string.format("[DreamingOfUtopia] %s rolled %d", player.Name, total))
			MovementService.MoveCepter(player, total)
			return
		end

		local summonCardIdText = message:match("^/summon%s+(%d+)$")
		if summonCardIdText ~= nil then
			local tileId = MovementService.GetCurrentTile(player)
			local success, reason = BattleService.SummonCreature(player, tonumber(summonCardIdText), tileId)
			print(string.format(
				"[DreamingOfUtopia] %s summon on tile #%d: %s",
				player.Name,
				tileId,
				success and "claimed" or ("failed (" .. tostring(reason) .. ")")
			))
			return
		end

		local challengeCardIdText = message:match("^/challenge%s+(%d+)$")
		if challengeCardIdText ~= nil then
			local tileId = MovementService.GetCurrentTile(player)
			local attackerWon, reason = BattleService.ChallengeTile(player, tonumber(challengeCardIdText), tileId)
			if reason ~= nil then
				print(string.format("[DreamingOfUtopia] %s challenge on tile #%d failed (%s)", player.Name, tileId, reason))
			else
				print(string.format(
					"[DreamingOfUtopia] %s challenge on tile #%d: %s",
					player.Name,
					tileId,
					attackerWon and "won, tile claimed" or "lost, defender holds"
				))
			end
		end
	end)
end

local function onPlayerRemoving(player)
	MovementService.RemoveCepter(player)
	local token = cepterTokens[player.UserId]
	if token ~= nil then
		token:Destroy()
		cepterTokens[player.UserId] = nil
	end
end

MovementService.CepterMoved:Connect(function(player, _fromTileId, toTileId)
	local token = cepterTokens[player.UserId]
	if token ~= nil then
		token.Position = getTileWorldPosition(toTileId, CEPTER_TOKEN_HEIGHT)
	end
end)

MovementService.CepterLanded:Connect(function(player, tileId)
	print(string.format("[DreamingOfUtopia] %s landed on tile #%d", player.Name, tileId))
end)

MovementService.LapCompleted:Connect(function(player, lapCount)
	print(string.format("[DreamingOfUtopia] %s completed lap %d", player.Name, lapCount))
end)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

print("[DreamingOfUtopia] Board initialized:", #BoardData.Tiles, "tiles")
print("[DreamingOfUtopia] Cards loaded:", #CardService.GetAllCards())

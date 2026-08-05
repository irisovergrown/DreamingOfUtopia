--[[
	Script — server, standalone bootstrap / composition root.

	Studio placement:
		ServerScriptService > Main (Script)

	Purpose:
		First thing that runs when the place starts. Initializes
		BoardService and physically builds the greybox board (BoardData)
		onto the baseplate so the layout is visible and testable in Studio.
		Also registers each joining player with MovementService (board
		position) and EconomyService (Magic balance), and gives them a
		simple ball "Cepter token" that walks the board on move.
		This is the wiring layer — it requires systems and connects their
		Signals, but game systems still never require each other directly.

		Nothing here is meant to be final visual art — plain colored parts
		and a BillboardGui label, just enough to see the board loop and
		verify Board/Movement/Battle/Economy state changes render.

		Player input/output now goes through ReplicatedStorage.Shared.Remotes
		to the client HUD (StarterPlayerScripts > UIService) instead of chat
		commands and the output window — Roll/Summon/Challenge/PayToll
		requests come in via RemoteEvents below, and state pushes back out
		via StateUpdated/ActionResult. Still no turn enforcement or team/
		alliance awareness — that needs MatchService, which doesn't exist yet.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local BoardData = require(ReplicatedStorage.Shared.BoardData)
local EraData = require(ReplicatedStorage.Shared.EraData)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local BoardService = require(ServerScriptService.Systems.BoardService)
local MovementService = require(ServerScriptService.Systems.MovementService)
local CardService = require(ServerScriptService.Systems.CardService)
local EconomyService = require(ServerScriptService.Systems.EconomyService)
local BattleService = require(ServerScriptService.Systems.BattleService)

BoardService.Init()
EconomyService.Init()
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

-- Per-player HUD state snapshot, pushed to the client over Remotes.StateUpdated.
local function buildStateSnapshot(player)
	local tileId = MovementService.GetCurrentTile(player)
	local tile = tileId and BoardService.GetTile(tileId)
	local defender = tileId and BattleService.GetDefender(tileId)
	local defenderCard = defender and CardService.GetCard(defender.CardId)

	return {
		Balance = EconomyService.GetBalance(player),
		TileId = tileId,
		TileType = tile and tile.TileType,
		TileEra = tile and tile.Era,
		TileLevel = tile and tile.Level,
		TileOwner = tile and tile.Owner,
		DefenderName = defenderCard and defenderCard.Name,
		DefenderHP = defender and defender.CurrentHP,
		Toll = (tile and tile.TileType == "Property" and tile.Owner ~= nil) and BoardService.GetToll(tileId) or 0,
	}
end

local function sendStateToPlayer(player)
	Remotes.StateUpdated:FireClient(player, buildStateSnapshot(player))
end

local function refreshAllPlayerStates()
	for _, player in ipairs(Players:GetPlayers()) do
		sendStateToPlayer(player)
	end
end

-- React to BoardService state changes instead of polling — the same
-- cross-system signal pattern MovementService and BattleService use.
BoardService.TileOwnerChanged:Connect(function(tileId, newOwnerUserId)
	local part = tileParts[tileId]
	if part ~= nil then
		part.Material = newOwnerUserId and Enum.Material.Neon or Enum.Material.SmoothPlastic
	end
	refreshTileLabel(tileId)
	refreshAllPlayerStates()
end)

BoardService.TileLeveledUp:Connect(function(tileId, _newLevel)
	refreshTileLabel(tileId)
	refreshAllPlayerStates()
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
	EconomyService.RegisterPlayer(player)
	createCepterToken(player)
	sendStateToPlayer(player)
end

local function onPlayerRemoving(player)
	MovementService.RemoveCepter(player)
	EconomyService.RemovePlayer(player)
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
	sendStateToPlayer(player)
end)

MovementService.CepterLanded:Connect(function(player, tileId)
	print(string.format("[DreamingOfUtopia] %s landed on tile #%d", player.Name, tileId))
end)

MovementService.LapCompleted:Connect(function(player, lapCount)
	print(string.format("[DreamingOfUtopia] %s completed lap %d", player.Name, lapCount))
end)

EconomyService.BalanceChanged:Connect(function(userId, _newBalance)
	local player = Players:GetPlayerByUserId(userId)
	if player ~= nil then
		sendStateToPlayer(player)
	end
end)

-- Player action requests from the client HUD (StarterPlayerScripts > UIService).
-- `player` always comes from OnServerEvent's own argument, never from the
-- client — cannot be spoofed, this is what keeps these calls authoritative.
Remotes.RollRequest.OnServerEvent:Connect(function(player)
	local total = MovementService.RollDice(1)
	print(string.format("[DreamingOfUtopia] %s rolled %d", player.Name, total))
	Remotes.ActionResult:FireClient(player, string.format("Rolled %d", total))
	MovementService.MoveCepter(player, total)
end)

Remotes.SummonRequest.OnServerEvent:Connect(function(player, cardId)
	if typeof(cardId) ~= "number" then
		Remotes.ActionResult:FireClient(player, "Invalid card id")
		return
	end

	local tileId = MovementService.GetCurrentTile(player)
	local success, reason = BattleService.SummonCreature(player, cardId, tileId)
	Remotes.ActionResult:FireClient(player, success and ("Claimed tile #" .. tileId) or ("Summon failed: " .. tostring(reason)))
end)

Remotes.ChallengeRequest.OnServerEvent:Connect(function(player, cardId)
	if typeof(cardId) ~= "number" then
		Remotes.ActionResult:FireClient(player, "Invalid card id")
		return
	end

	local tileId = MovementService.GetCurrentTile(player)
	local attackerWon, reason = BattleService.ChallengeTile(player, cardId, tileId)
	local message
	if reason ~= nil then
		message = "Challenge failed: " .. reason
	else
		message = attackerWon and ("Won! Claimed tile #" .. tileId) or "Lost the challenge"
	end
	Remotes.ActionResult:FireClient(player, message)
end)

Remotes.PayTollRequest.OnServerEvent:Connect(function(player)
	local tileId = MovementService.GetCurrentTile(player)
	local success, reason = EconomyService.PayToll(player, tileId)
	Remotes.ActionResult:FireClient(player, success and "Toll paid" or ("Pay toll failed: " .. tostring(reason)))
end)

EconomyService.WinTargetReached:Connect(function(userId, balance)
	print(string.format(
		"[DreamingOfUtopia] Player %d reached the win target with %d Magic! (MatchService will handle real match end later)",
		userId,
		balance
	))
end)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

print("[DreamingOfUtopia] Board initialized:", #BoardData.Tiles, "tiles")
print("[DreamingOfUtopia] Cards loaded:", #CardService.GetAllCards())

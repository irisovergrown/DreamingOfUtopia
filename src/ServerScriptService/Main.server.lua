--[[
	Script — server, standalone bootstrap / composition root.

	Studio placement:
		ServerScriptService > Main (Script)

	Purpose:
		First thing that runs when the place starts. Initializes
		BoardService, which builds its tile registry from hand-placed,
		CollectionService-tagged Parts already sitting in Workspace (see
		BoardService's header for the tagging/attribute scheme) — this
		script does NOT spawn tiles, it just finds the ones already there
		and attaches a BillboardGui label to each. Also registers each
		joining player with MovementService (board position) and
		EconomyService (Magic balance), and gives them a simple ball
		"Cepter token" that walks the board on move.
		This is the wiring layer — it requires systems and connects their
		Signals, but game systems still never require each other directly.

		A tile Part's own color/material/model are entirely Studio-authored
		by the developer (own board designs, not code-generated) — the only
		visuals this script adds are the BillboardGui label and the
		ownership Material flip (Neon) / era recolor reactions below, which
		are universal gameplay-state indicators, not part of a tile's design.

		Player input/output goes through ReplicatedStorage.Shared.Remotes to
		the client HUD (StarterPlayerScripts > UIService) — Roll/Summon/
		Challenge/PayToll/EndTurn/Terraform requests come in via RemoteEvents
		below, gated by MatchService.IsPlayersTurn (and HasRolledThisTurn for
		rolling) before touching Movement/Battle/Economy/Terraform, and state
		pushes back out via StateUpdated/ActionResult. Still no 2v2 alliance
		awareness or a real match-setup lobby — see MatchService's header.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local EraData = require(ReplicatedStorage.Shared.EraData)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local BoardService = require(ServerScriptService.Systems.BoardService)
local MovementService = require(ServerScriptService.Systems.MovementService)
local CardService = require(ServerScriptService.Systems.CardService)
local EconomyService = require(ServerScriptService.Systems.EconomyService)
local BattleService = require(ServerScriptService.Systems.BattleService)
local MatchService = require(ServerScriptService.Systems.MatchService)
local TerraformService = require(ServerScriptService.Systems.TerraformService)

BoardService.Init()
EconomyService.Init()
BattleService.Init()
MatchService.Init()

local TILE_TAG = "Tile"
local CEPTER_TOKEN_RADIUS = 1.5

local cepterFolder = Instance.new("Folder")
cepterFolder.Name = "Cepters"
cepterFolder.Parent = Workspace

-- tileId -> Part, built from the same "Tile" tag BoardService itself scans.
-- Kept separate from BoardService on purpose — it stays instance-agnostic
-- (pure data/logic); this is a visual-only concern that belongs to Main.
local tileParts = {}
local tileLabels = {}

local function attachTileLabel(tileId, part)
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

	tileLabels[tileId] = label
end

local taggedTileParts = CollectionService:GetTagged(TILE_TAG)
if #taggedTileParts == 0 then
	warn("[DreamingOfUtopia] No Parts tagged '" .. TILE_TAG .. "' found in Workspace — hand-place and tag a board before playing (see BoardService's header).")
end

for _, part in ipairs(taggedTileParts) do
	local tileId = part:GetAttribute("Id")
	if tileId ~= nil then
		tileParts[tileId] = part
		attachTileLabel(tileId, part)
	end
end

-- A point `radius` studs above the tile Part's own top surface — works
-- regardless of a hand-placed tile's size or elevation.
local function getTileWorldPosition(tileId, radius)
	local part = tileParts[tileId]
	if part == nil then
		return Vector3.new(0, radius, 0)
	end
	return part.Position + Vector3.new(0, part.Size.Y / 2 + radius, 0)
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

for tileId, _ in pairs(tileParts) do
	refreshTileLabel(tileId)
end

-- Per-player HUD state snapshot, pushed to the client over Remotes.StateUpdated.
local function buildStateSnapshot(player)
	local tileId = MovementService.GetCurrentTile(player)
	local tile = tileId and BoardService.GetTile(tileId)
	local defender = tileId and BattleService.GetDefender(tileId)
	local defenderCard = defender and CardService.GetCard(defender.CardId)

	local currentTurnPlayer = MatchService.GetCurrentTurnPlayer()
	local winnerUserId = MatchService.GetWinner()
	local winnerPlayer = winnerUserId and Players:GetPlayerByUserId(winnerUserId)

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
		IsYourTurn = MatchService.IsPlayersTurn(player),
		CurrentTurnUserId = currentTurnPlayer and currentTurnPlayer.UserId,
		CurrentTurnName = currentTurnPlayer and currentTurnPlayer.Name,
		HasRolled = MatchService.HasRolledThisTurn(),
		MatchEnded = MatchService.IsMatchEnded(),
		WinnerName = winnerPlayer and winnerPlayer.Name or (winnerUserId and tostring(winnerUserId)),
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

BoardService.EraChanged:Connect(function(tileId, newEra)
	local part = tileParts[tileId]
	if part ~= nil then
		part.Color = EraData.GetEra(newEra).Color
	end
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
	token.Position = getTileWorldPosition(MovementService.GetCurrentTile(player), CEPTER_TOKEN_RADIUS)
	token.Parent = cepterFolder

	cepterTokens[player.UserId] = token
end

local function onPlayerAdded(player)
	MovementService.RegisterCepter(player)
	EconomyService.RegisterPlayer(player)
	MatchService.RegisterPlayer(player)
	createCepterToken(player)
	sendStateToPlayer(player)
end

local function onPlayerRemoving(player)
	MovementService.RemoveCepter(player)
	EconomyService.RemovePlayer(player)
	MatchService.RemovePlayer(player)
	local token = cepterTokens[player.UserId]
	if token ~= nil then
		token:Destroy()
		cepterTokens[player.UserId] = nil
	end
	refreshAllPlayerStates()
end

MovementService.CepterMoved:Connect(function(player, _fromTileId, toTileId)
	local token = cepterTokens[player.UserId]
	if token ~= nil then
		token.Position = getTileWorldPosition(toTileId, CEPTER_TOKEN_RADIUS)
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
-- Every action is gated by MatchService.IsPlayersTurn — Movement/Battle/
-- Economy stay turn-agnostic themselves, the check lives here.
Remotes.RollRequest.OnServerEvent:Connect(function(player)
	if not MatchService.IsPlayersTurn(player) then
		Remotes.ActionResult:FireClient(player, "Not your turn")
		return
	end
	if MatchService.HasRolledThisTurn() then
		Remotes.ActionResult:FireClient(player, "Already rolled this turn")
		return
	end

	local total = MovementService.RollDice(1)
	print(string.format("[DreamingOfUtopia] %s rolled %d", player.Name, total))
	Remotes.ActionResult:FireClient(player, string.format("Rolled %d", total))
	MatchService.MarkRolled()
	MovementService.MoveCepter(player, total)
end)

Remotes.SummonRequest.OnServerEvent:Connect(function(player, cardId)
	if not MatchService.IsPlayersTurn(player) then
		Remotes.ActionResult:FireClient(player, "Not your turn")
		return
	end
	if typeof(cardId) ~= "number" then
		Remotes.ActionResult:FireClient(player, "Invalid card id")
		return
	end

	local tileId = MovementService.GetCurrentTile(player)
	local success, reason = BattleService.SummonCreature(player, cardId, tileId)
	Remotes.ActionResult:FireClient(player, success and ("Claimed tile #" .. tileId) or ("Summon failed: " .. tostring(reason)))
end)

Remotes.ChallengeRequest.OnServerEvent:Connect(function(player, cardId)
	if not MatchService.IsPlayersTurn(player) then
		Remotes.ActionResult:FireClient(player, "Not your turn")
		return
	end
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
	if not MatchService.IsPlayersTurn(player) then
		Remotes.ActionResult:FireClient(player, "Not your turn")
		return
	end

	local tileId = MovementService.GetCurrentTile(player)
	local success, reason = EconomyService.PayToll(player, tileId)
	Remotes.ActionResult:FireClient(player, success and "Toll paid" or ("Pay toll failed: " .. tostring(reason)))
end)

Remotes.EndTurnRequest.OnServerEvent:Connect(function(player)
	local success, reason = MatchService.EndTurn(player)
	Remotes.ActionResult:FireClient(player, success and "Turn ended" or ("End turn failed: " .. tostring(reason)))
end)

Remotes.TerraformRequest.OnServerEvent:Connect(function(player, targetEra)
	if not MatchService.IsPlayersTurn(player) then
		Remotes.ActionResult:FireClient(player, "Not your turn")
		return
	end
	if typeof(targetEra) ~= "string" then
		Remotes.ActionResult:FireClient(player, "Invalid era")
		return
	end

	local normalizedEra = targetEra ~= "" and targetEra or nil
	local tileId = MovementService.GetCurrentTile(player)
	local cost = TerraformService.GetTerraformCost(tileId, normalizedEra)
	local success, reason = TerraformService.TerraformTile(player, tileId, normalizedEra)
	local message
	if success then
		message = string.format("Terraformed to %s (-%d Magic)", EraData.GetEra(normalizedEra).DisplayName, cost)
	else
		message = "Terraform failed: " .. tostring(reason)
	end
	Remotes.ActionResult:FireClient(player, message)
end)

EconomyService.WinTargetReached:Connect(function(userId, balance)
	print(string.format("[DreamingOfUtopia] Player %d reached the win target with %d Magic!", userId, balance))
end)

MatchService.TurnChanged:Connect(function(currentTurnUserId)
	local currentPlayer = Players:GetPlayerByUserId(currentTurnUserId)
	print(string.format("[DreamingOfUtopia] Turn changed to %s", currentPlayer and currentPlayer.Name or tostring(currentTurnUserId)))
	refreshAllPlayerStates()
end)

MatchService.MatchEnded:Connect(function(winnerUserId)
	local winnerPlayer = Players:GetPlayerByUserId(winnerUserId)
	print(string.format("[DreamingOfUtopia] Match ended! Winner: %s", winnerPlayer and winnerPlayer.Name or tostring(winnerUserId)))
	refreshAllPlayerStates()
end)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

print("[DreamingOfUtopia] Board initialized:", #BoardService.GetAllTiles(), "tiles")
print("[DreamingOfUtopia] Cards loaded:", #CardService.GetAllCards())

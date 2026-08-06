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
		EconomyService (Magic balance), and gives them a Cepter token by
		cloning a developer-authored model rather than building one from
		Instance.new() — see "Model authoring" below. Also spawns a clone
		of the matching creature model on a tile whenever it's defended, so
		a claimed tile visibly has "something" guarding it instead of just
		a label.
		This is the wiring layer — it requires systems and connects their
		Signals, but game systems still never require each other directly.

		Model authoring (Cepter tokens + creature summons):
			This script does NOT build character/creature geometry in code —
			those are real models the developer places in Studio (by hand or
			via plugins), under:
				ReplicatedStorage > Models > Player > PlayerTemplate (Model)
					A single R6 Character with a Humanoid and a part named
					"HumanoidRootPart" — cloned once per joining player.
					PrimaryPart is set to that HumanoidRootPart on clone.
					CameraService depends on that exact child name to find
					its focus target's position, so it must be present.
				ReplicatedStorage > Models > Summons > <any name> (Model)
					One Model per creature card, matched to CardData by a
					number Attribute named "CardId" set on the Model itself
					(the Model's own Name can be anything readable) — same
					attribute-driven lookup pattern BoardService already
					uses for tile data, kept consistent on purpose.
			If a template/model is missing, the corresponding token/marker
			is simply skipped with a warn() — nothing else breaks.

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

-- Developer-authored model folders — see this file's header
-- ("Model authoring") for the exact naming/attribute contract.
local MODELS_FOLDER = ReplicatedStorage:WaitForChild("Models", 10)
local PLAYER_MODELS_FOLDER = MODELS_FOLDER and MODELS_FOLDER:WaitForChild("Player", 10)
local SUMMON_MODELS_FOLDER = MODELS_FOLDER and MODELS_FOLDER:WaitForChild("Summons", 10)

if MODELS_FOLDER == nil then
	warn("[DreamingOfUtopia] Main: ReplicatedStorage.Models not found — create Models > Player and Models > Summons and place your Cepter/creature models there (see this file's header comment).")
end

local PLAYER_TEMPLATE_NAME = "PlayerTemplate"

-- How far above the tile surface the Cepter token's pivot (its
-- HumanoidRootPart) sits — tunable to match whatever proportions the
-- authored PlayerTemplate model actually has.
local CEPTER_ROOT_HEIGHT = 3

local cepterFolder = Instance.new("Folder")
cepterFolder.Name = "Cepters"
cepterFolder.Parent = Workspace

local defenderFolder = Instance.new("Folder")
defenderFolder.Name = "Defenders"
defenderFolder.Parent = Workspace

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

-- Cloned models are teleport-positioned (PivotTo), never simulated —
-- anchoring every part keeps them from falling/reacting to physics,
-- matching the fully-anchored/teleport-based movement the rest of the
-- board already uses.
local function anchorAllParts(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

-- Finds the Models.Summons Model whose "CardId" Attribute matches — see
-- this file's header ("Model authoring") for the naming/attribute contract.
local function findSummonModel(cardId)
	if SUMMON_MODELS_FOLDER == nil then
		return nil
	end
	for _, model in ipairs(SUMMON_MODELS_FOLDER:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("CardId") == cardId then
			return model
		end
	end
	return nil
end

-- tileId -> the cloned creature Model marking that tile's defender.
local defenderMarkers = {}

local function updateDefenderMarker(tileId, newOwnerUserId)
	local existing = defenderMarkers[tileId]
	if existing ~= nil then
		existing:Destroy()
		defenderMarkers[tileId] = nil
	end

	if newOwnerUserId == nil then
		return
	end

	local defender = BattleService.GetDefender(tileId)
	local card = defender and CardService.GetCard(defender.CardId)
	if card == nil then
		return
	end

	local summonTemplate = findSummonModel(card.Id)
	if summonTemplate == nil then
		warn(string.format("[DreamingOfUtopia] Main: no Models.Summons model with CardId=%d (%s) — place one there (see this file's header).", card.Id, card.Name))
		return
	end

	local marker = summonTemplate:Clone()
	marker.Name = "Defender_" .. tileId
	anchorAllParts(marker)
	marker.Parent = defenderFolder

	local _, size = marker:GetBoundingBox()
	marker:PivotTo(CFrame.new(getTileWorldPosition(tileId, size.Y / 2)))

	defenderMarkers[tileId] = marker
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
	updateDefenderMarker(tileId, newOwnerUserId)
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

-- Cepter tokens: one clone of Models.Player.PlayerTemplate per player,
-- walking the board as MovementService moves them. `cepterTokens` holds
-- each player's cloned Model, named "Cepter_"..userId — the exact name/
-- BasePart-child contract CameraService looks up (its HumanoidRootPart
-- child specifically, for position tracking).
local cepterTokens = {}

local function createCepterToken(player)
	if PLAYER_MODELS_FOLDER == nil then
		return
	end

	local template = PLAYER_MODELS_FOLDER:FindFirstChild(PLAYER_TEMPLATE_NAME)
	if template == nil or not template:IsA("Model") then
		warn("[DreamingOfUtopia] Main: no '" .. PLAYER_TEMPLATE_NAME .. "' Model found under Models.Player — see this file's header.")
		return
	end

	local model = template:Clone()
	model.Name = "Cepter_" .. player.UserId

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart == nil or not humanoidRootPart:IsA("BasePart") then
		warn("[DreamingOfUtopia] Main: '" .. PLAYER_TEMPLATE_NAME .. "' has no HumanoidRootPart — CameraService and movement both depend on it.")
		model:Destroy()
		return
	end

	model.PrimaryPart = humanoidRootPart
	anchorAllParts(model)
	model.Parent = cepterFolder
	model:PivotTo(CFrame.new(getTileWorldPosition(MovementService.GetCurrentTile(player), CEPTER_ROOT_HEIGHT)))

	cepterTokens[player.UserId] = model
end

local function moveCepterToken(player, tileId)
	local model = cepterTokens[player.UserId]
	if model == nil then
		return
	end
	model:PivotTo(CFrame.new(getTileWorldPosition(tileId, CEPTER_ROOT_HEIGHT)))
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
	moveCepterToken(player, toTileId)
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

--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > BoardVisualService (ModuleScript)

	Purpose:
		Everything the board LOOKS like: tile labels, the ownership material
		flip, element recolouring, Cepter tokens and defender models.

		Split out of Main.server.lua, which had grown to 574 lines doing three
		unrelated jobs — composition root, visual presentation, and remote
		handling. Presentation is the largest of the three and the one least
		related to rules, so it moves first.

		Nothing here decides anything. It subscribes to the services that own
		state and reacts. Deleting this module would leave a headless but
		fully correct match, which is the test of whether the split is real:
		the brief requires a server result to stay valid even if every
		animation is skipped.

		A tile Part's own colour, material and model are Studio-authored by
		the developer. The only visuals added here are the BillboardGui label
		and the ownership/element indicators, which are gameplay-state
		readouts rather than part of a tile's design.

	Model authoring (unchanged from Main's original contract):
		ReplicatedStorage > Models > Player > PlayerTemplate (Model)
			An R6 character with a Humanoid and a part named HumanoidRootPart.
			Cloned per player; PrimaryPart is set to that part on clone.
			CameraService looks up that exact child name to follow a token.
		ReplicatedStorage > Models > Summons > <any name> (Model or Part)
			One per creature card, matched to CardData by a number Attribute
			named "CardId" on the instance itself. Its own Name may be
			anything readable — the attribute is the lookup key.

		A missing template is a warn() and a skipped visual, never an error:
		presentation must not be able to stop a match.

	Public API:
		BoardVisualService.Init(services)
		BoardVisualService.CreateCepterToken(player)
		BoardVisualService.RemoveCepterToken(player)
		BoardVisualService.RefreshAllTiles()
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ElementData = require(ReplicatedStorage.Shared.ElementData)

local BoardVisualService = {}

local TILE_TAG = "Tile"
local PLAYER_TEMPLATE_NAME = "PlayerTemplate"

-- How far above a tile's top surface a Cepter token's pivot sits. Tunable to
-- whatever proportions the authored PlayerTemplate actually has.
local CEPTER_ROOT_HEIGHT = 3

local _territory, _battle, _card, _movement, _graph
local _cepterFolder, _defenderFolder
local _modelsFolder, _playerModels, _summonModels

local _tileParts = {}
local _tileLabels = {}
local _cepterTokens = {}
local _defenderMarkers = {}

local function ensureFolder(name)
	local existing = Workspace:FindFirstChild(name)
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = Workspace
	return folder
end

local function attachTileLabel(nodeId, part)
	local existing = part:FindFirstChild("TileLabel")
	if existing then
		existing:Destroy()
	end

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

	_tileLabels[nodeId] = label
end

-- A point `radius` studs above the tile's own top surface, so this works
-- regardless of a hand-placed tile's size or elevation.
local function nodeWorldPosition(nodeId, radius)
	local part = _tileParts[nodeId]
	if part == nil then
		return Vector3.new(0, radius, 0)
	end
	return part.Position + Vector3.new(0, part.Size.Y / 2 + radius, 0)
end

-- Cloned models are teleport-positioned via PivotTo and never simulated, so
-- anchoring every part keeps them from falling. Handles a Model and a lone
-- BasePart used directly as a summon.
local function anchorAll(instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

local function findSummonModel(cardId)
	if _summonModels == nil then
		return nil
	end
	for _, instance in ipairs(_summonModels:GetChildren()) do
		if (instance:IsA("Model") or instance:IsA("BasePart")) and instance:GetAttribute("CardId") == cardId then
			return instance
		end
	end
	return nil
end

-- GetBoundingBox exists on Model but not BasePart; a lone Part's own Size is
-- already the height needed.
local function instanceHeight(instance)
	if instance:IsA("BasePart") then
		return instance.Size.Y
	end
	local _, size = instance:GetBoundingBox()
	return size.Y
end

-- Everything here is keyed by NODE ID since Milestone 5, the same key the
-- graph and TerritoryService use. The Part that draws a node is found through
-- its StudioNodeId, so the numeric attribute is a rendering detail rather than
-- a second identity for a place on the board.
local function refreshTileLabel(nodeId)
	local label = _tileLabels[nodeId]
	if label == nil then
		return
	end

	-- Castles, forts and warps are not territories, so they have no ownership
	-- or level to show — just what they are.
	local territory = _territory.GetTerritory(nodeId)
	if territory == nil then
		local node = _graph and _graph.GetNode(nodeId)
		label.Text = string.format("%s — %s", nodeId, node and node.Type or "?")
		return
	end

	local element = ElementData.GetElement(territory.Element)
	local ownerText = territory.Owner and ("Owner " .. tostring(territory.Owner)) or "Unclaimed"

	local defenderText = ""
	local defender = _battle.GetDefender(nodeId)
	if defender ~= nil then
		local card = _card.GetCard(defender.CardId)
		if card ~= nil then
			defenderText = string.format(" — %s (%dHP)", card.Name, defender.CurrentHP)
		end
	end

	label.Text = string.format(
		"%s — %s — Lv%d — %s%s",
		nodeId,
		element and element.DisplayName or "Neutral",
		territory.Level,
		ownerText,
		defenderText
	)
end

local function updateDefenderMarker(nodeId, newOwnerUserId)
	local existing = _defenderMarkers[nodeId]
	if existing ~= nil then
		existing:Destroy()
		_defenderMarkers[nodeId] = nil
	end

	if newOwnerUserId == nil then
		return
	end

	local defender = _battle.GetDefender(nodeId)
	local card = defender and _card.GetCard(defender.CardId)
	if card == nil then
		return
	end

	local template = findSummonModel(card.Id)
	if template == nil then
		warn(string.format(
			"[DreamingOfUtopia] BoardVisualService: no Models.Summons instance with CardId=%d (%s)",
			card.Id, card.Name
		))
		return
	end

	local marker = template:Clone()
	marker.Name = "Defender_" .. nodeId
	anchorAll(marker)
	marker.Parent = _defenderFolder
	marker:PivotTo(CFrame.new(nodeWorldPosition(nodeId, instanceHeight(marker) / 2)))

	_defenderMarkers[nodeId] = marker
end

function BoardVisualService.RefreshAllTiles()
	for nodeId in pairs(_tileParts) do
		refreshTileLabel(nodeId)
	end
end

function BoardVisualService.CreateCepterToken(player)
	if _playerModels == nil then
		return
	end

	local template = _playerModels:FindFirstChild(PLAYER_TEMPLATE_NAME)
	if template == nil or not template:IsA("Model") then
		warn("[DreamingOfUtopia] BoardVisualService: no '" .. PLAYER_TEMPLATE_NAME .. "' Model under Models.Player")
		return
	end

	local model = template:Clone()
	model.Name = "Cepter_" .. player.UserId

	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		warn("[DreamingOfUtopia] BoardVisualService: PlayerTemplate has no HumanoidRootPart; CameraService depends on it")
		model:Destroy()
		return
	end

	model.PrimaryPart = root
	anchorAll(model)
	model.Parent = _cepterFolder
	model:PivotTo(CFrame.new(nodeWorldPosition(_movement.GetCurrentNodeId(player), CEPTER_ROOT_HEIGHT)))

	_cepterTokens[player.UserId] = model
end

function BoardVisualService.RemoveCepterToken(player)
	local token = _cepterTokens[player.UserId]
	if token ~= nil then
		token:Destroy()
		_cepterTokens[player.UserId] = nil
	end
end

local function moveCepterToken(player, nodeId)
	local model = _cepterTokens[player.UserId]
	if model ~= nil then
		model:PivotTo(CFrame.new(nodeWorldPosition(nodeId, CEPTER_ROOT_HEIGHT)))
	end
end

function BoardVisualService.Init(services)
	_territory = services.Territory
	_battle = services.Battle
	_card = services.Card
	_movement = services.Movement
	_graph = services.Graph

	_tileParts = {}
	_tileLabels = {}
	_cepterTokens = {}
	_defenderMarkers = {}

	_cepterFolder = ensureFolder("Cepters")
	_defenderFolder = ensureFolder("Defenders")
	_cepterFolder:ClearAllChildren()
	_defenderFolder:ClearAllChildren()

	_modelsFolder = ReplicatedStorage:WaitForChild("Models", 10)
	_playerModels = _modelsFolder and _modelsFolder:WaitForChild("Player", 10)
	_summonModels = _modelsFolder and _modelsFolder:WaitForChild("Summons", 10)

	if _modelsFolder == nil then
		warn("[DreamingOfUtopia] BoardVisualService: ReplicatedStorage.Models not found — Cepter and creature visuals will be skipped")
	end

	-- Parts are found by tag and then resolved to graph nodes through their
	-- StudioNodeId. A tagged Part whose id is not in the loaded board is
	-- skipped with a warning rather than silently ignored — it almost always
	-- means the board definition and the Studio geometry have drifted.
	local tagged = CollectionService:GetTagged(TILE_TAG)
	if #tagged == 0 then
		warn("[DreamingOfUtopia] BoardVisualService: no Parts tagged '" .. TILE_TAG .. "' in Workspace")
	end
	for _, part in ipairs(tagged) do
		local studioNodeId = part:GetAttribute("Id")
		local nodeId = studioNodeId ~= nil and _graph and _graph.GetNodeIdByStudioNodeId(studioNodeId) or nil
		if nodeId ~= nil then
			_tileParts[nodeId] = part
			attachTileLabel(nodeId, part)
		elseif studioNodeId ~= nil then
			warn(string.format(
				"[DreamingOfUtopia] BoardVisualService: Part with Id=%s has no node in board '%s'",
				tostring(studioNodeId), tostring(_graph and _graph.GetBoardId())
			))
		end
	end

	_territory.OwnerChanged:Connect(function(nodeId, newOwnerUserId)
		local part = _tileParts[nodeId]
		if part ~= nil then
			part.Material = newOwnerUserId and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
		refreshTileLabel(nodeId)
		updateDefenderMarker(nodeId, newOwnerUserId)
	end, 0, "BoardVisual.OwnerChanged")

	_territory.LevelChanged:Connect(function(nodeId)
		refreshTileLabel(nodeId)
	end, 0, "BoardVisual.LevelChanged")

	_territory.ElementChanged:Connect(function(nodeId, newElement)
		local part = _tileParts[nodeId]
		if part ~= nil then
			local element = ElementData.GetElement(newElement)
			part.Color = element and element.Color or ElementData.Neutral.Color
		end
		refreshTileLabel(nodeId)
	end, 0, "BoardVisual.ElementChanged")

	_battle.DefenderBuffed:Connect(function(nodeId)
		refreshTileLabel(nodeId)
	end, 0, "BoardVisual.DefenderBuffed")

	-- Movement is graph-based since Milestone 2 and reports node ids, so the
	-- token follows NodeEntered and translates back to the Part that draws
	-- that node. Movement no longer sleeps between steps either, so this fires
	-- for every node of a move in one frame; the client animates from the
	-- path in the movement result rather than from these.
	_movement.NodeEntered:Connect(function(userId, nodeId)
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil then
			moveCepterToken(player, nodeId)
		end
	end, 0, "BoardVisual.NodeEntered")

	BoardVisualService.RefreshAllTiles()
end

return BoardVisualService

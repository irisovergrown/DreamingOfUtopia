--[[
	LocalScript — client, standalone (first slice of a future UIService).

	Studio placement:
		StarterPlayer > StarterPlayerScripts > UIService (LocalScript)

	Purpose:
		A plain HUD driven entirely by the server's snapshot.

		The important change from the previous version is what decides which
		buttons work. It used to dim them from an IsYourTurn flag — a guess
		the client made about what the server would accept, which was already
		wrong for actions that are illegal for reasons other than turn order.
		Now the snapshot carries `You.LegalIntents`, produced by the same
		ActionValidator table the server validates against, so a button is
		enabled exactly when the request behind it would be accepted.

		Deliberately plain: standard Roblox panel, default font, no theming,
		no card art. A real UIService replaces this once there is a hand and
		a deck to show.

	Sequence numbers:
		Each request carries an incrementing ordinal and the phase the client
		believed it was in. The server refuses anything at or below the last
		accepted ordinal, so a double-click cannot act twice, and refuses a
		request whose expected phase has moved on, so clicking a stale screen
		is a clean rejection rather than an action applied in the wrong phase.
		A rejected request does not consume its ordinal, so being refused
		never knocks this counter out of step with the server's.

	Server contract (ReplicatedStorage > Shared > Remotes):
		Client -> Server: SubmitIntent(intent, sequence, expectedPhase, payload)
		Server -> Client: StateUpdated(snapshot), ActionResult(result)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CardData = require(ReplicatedStorage.Shared.CardData)
local ElementData = require(ReplicatedStorage.Shared.EraData)

local Intent = Enums.Intent
local localPlayer = Players.LocalPlayer

local FONT = Enum.Font.SourceSans
local TEXT_COLOR = Color3.fromRGB(0, 0, 0)
local DIM_TEXT_COLOR = Color3.fromRGB(150, 150, 150)
local PANEL_COLOR = Color3.fromRGB(242, 242, 242)
local INPUT_COLOR = Color3.fromRGB(255, 255, 255)
local BUTTON_COLOR = Color3.fromRGB(225, 225, 225)
local BUTTON_DIM_COLOR = Color3.fromRGB(240, 240, 240)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "UIServiceHud"
screenGui.ResetOnSpawn = false
screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromOffset(400, 500)
frame.Position = UDim2.fromOffset(20, 20)
frame.BackgroundColor3 = PANEL_COLOR
frame.BorderSizePixel = 1
frame.Parent = screenGui

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = frame

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 4)
layout.Parent = frame

local function createLabel(name, order, height, textSize)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, height)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextSize = textSize
	label.TextColor3 = TEXT_COLOR
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Text = ""
	label.Parent = frame
	return label
end

local phaseLabel = createLabel("PhaseLabel", 1, 20, 16)
local magicLabel = createLabel("MagicLabel", 2, 20, 18)
local tileLabel = createLabel("TileLabel", 3, 60, 14)
local standingsLabel = createLabel("StandingsLabel", 4, 76, 13)
local legendLabel = createLabel("LegendLabel", 5, 84, 12)

local function createTextBox(name, order, placeholder)
	local box = Instance.new("TextBox")
	box.Name = name
	box.LayoutOrder = order
	box.Size = UDim2.new(1, 0, 0, 26)
	box.BackgroundColor3 = INPUT_COLOR
	box.TextColor3 = TEXT_COLOR
	box.Font = FONT
	box.TextSize = 14
	box.PlaceholderText = placeholder
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Parent = frame
	return box
end

local cardIdBox = createTextBox("CardIdBox", 6, "card id")
local elementBox = createTextBox("ElementBox", 7, "element id (blank = neutral)")

local buttonRow = Instance.new("Frame")
buttonRow.Name = "ButtonRow"
buttonRow.LayoutOrder = 8
buttonRow.Size = UDim2.new(1, 0, 0, 28)
buttonRow.BackgroundTransparency = 1
buttonRow.Parent = frame

local buttonRowLayout = Instance.new("UIListLayout")
buttonRowLayout.FillDirection = Enum.FillDirection.Horizontal
buttonRowLayout.Padding = UDim.new(0, 6)
buttonRowLayout.Parent = buttonRow

-- Route buttons, built on demand when movement pauses at a branch. There is
-- no fixed set of them: how many routes a junction offers is a property of
-- the board, so the row is rebuilt from each snapshot rather than declared.
local routeRow = Instance.new("Frame")
routeRow.Name = "RouteRow"
routeRow.LayoutOrder = 9
routeRow.Size = UDim2.new(1, 0, 0, 28)
routeRow.BackgroundTransparency = 1
routeRow.Visible = false
routeRow.Parent = frame

local routeRowLayout = Instance.new("UIListLayout")
routeRowLayout.FillDirection = Enum.FillDirection.Horizontal
routeRowLayout.Padding = UDim.new(0, 6)
routeRowLayout.Parent = routeRow

local resultLabel = createLabel("ResultLabel", 10, 54, 14)

-- === Intent dispatch ========================================================

local sequence = 0
local currentPhase = nil
local legalIntents = {}

local function isLegal(intent)
	for _, candidate in ipairs(legalIntents) do
		if candidate == intent then
			return true
		end
	end
	return false
end

local function submit(intent, payload)
	if not isLegal(intent) then
		-- The server would refuse this anyway; saying so locally avoids a
		-- pointless round trip and gives an immediate reason.
		resultLabel.Text = intent .. " is not available right now"
		return
	end
	sequence += 1
	Remotes.SubmitIntent:FireServer(intent, sequence, currentPhase, payload)
end

-- Buttons declare which intent they send and how to build its payload; the
-- table below is the only place a button and an intent are paired.
local buttonDefinitions = {
	{ Name = "RollButton", Text = "Roll", Intent = Intent.Roll },
	{
		Name = "SummonButton",
		Text = "Summon",
		Intent = Intent.ChooseSummon,
		Payload = function()
			local cardId = tonumber(cardIdBox.Text)
			if cardId == nil then
				return nil, "enter a card id first"
			end
			return { CardId = cardId }
		end,
	},
	{ Name = "PayTollButton", Text = "Pay Toll", Intent = Intent.PayToll },
	{
		Name = "TerraformButton",
		Text = "Terraform",
		Intent = Intent.ChooseTerritoryCommand,
		Payload = function()
			return { Element = elementBox.Text }
		end,
	},
	{ Name = "EndTurnButton", Text = "End Turn", Intent = Intent.EndTurn },
}

local buttons = {}
for order, definition in ipairs(buttonDefinitions) do
	local button = Instance.new("TextButton")
	button.Name = definition.Name
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(74, 28)
	button.BackgroundColor3 = BUTTON_COLOR
	button.TextColor3 = TEXT_COLOR
	button.Font = FONT
	button.TextSize = 13
	button.Text = definition.Text
	button.Parent = buttonRow

	button.Activated:Connect(function()
		local payload, problem
		if definition.Payload then
			payload, problem = definition.Payload()
			if problem then
				resultLabel.Text = problem
				return
			end
		end
		submit(definition.Intent, payload)
	end)

	buttons[definition.Intent] = button
end

-- === Card legend ============================================================

local legendLines = {}
for _, card in ipairs(CardData.Cards) do
	local elementText = card.Era and ElementData.GetEra(card.Era).DisplayName or "Neutral"
	if card.CardType == "Creature" then
		table.insert(legendLines, string.format(
			"%d %s [%s] ST%d/HP%d Cost%d",
			card.Id, card.Name, elementText, card.ST, card.HP, card.Cost
		))
	end
end

local elementIds = {}
for elementId in pairs(ElementData.Eras) do
	table.insert(elementIds, elementId)
end
table.sort(elementIds)
table.insert(legendLines, "Elements: " .. table.concat(elementIds, ", "))
legendLabel.Text = table.concat(legendLines, "\n")

-- === Rendering ==============================================================

local function formatTile(tile)
	if tile == nil then
		return "Tile: —"
	end

	local elementText = tile.Element and ElementData.GetEra(tile.Element).DisplayName or "Neutral"
	local lines = { string.format("Tile #%d — %s — Lv%d", tile.TileId, elementText, tile.Level or 1) }

	if tile.TileType == "Property" then
		table.insert(lines, tile.Owner and ("Owner " .. tostring(tile.Owner)) or "Unclaimed")
		if tile.DefenderName then
			table.insert(lines, string.format("Defender: %s (%dHP)", tile.DefenderName, tile.DefenderHP))
		end
		if tile.Toll and tile.Toll > 0 then
			table.insert(lines, "Toll: " .. tile.Toll)
		end
	end
	return table.concat(lines, "\n")
end

local function formatStandings(snapshot)
	local lines = {}
	for _, standing in ipairs(snapshot.Standings) do
		table.insert(lines, string.format(
			"%s%d — %d Magic, %d land, %d cards",
			standing.IsActive and "> " or "  ",
			standing.UserId,
			standing.CurrentMagic,
			standing.TerritoriesOwned,
			standing.HandCount
		))
	end
	return table.concat(lines, "\n")
end

local function renderRouteChoice(pending)
	for _, child in ipairs(routeRow:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	if pending == nil then
		routeRow.Visible = false
		return
	end

	routeRow.Visible = true
	for order, option in ipairs(pending.Options) do
		local button = Instance.new("TextButton")
		button.Name = "Route_" .. option.EdgeId
		button.LayoutOrder = order
		button.Size = UDim2.fromOffset(104, 28)
		button.BackgroundColor3 = BUTTON_COLOR
		button.TextColor3 = TEXT_COLOR
		button.Font = FONT
		button.TextSize = 13
		button.Text = "→ " .. option.To
		button.Parent = routeRow

		button.Activated:Connect(function()
			submit(Intent.ChooseJunction, { EdgeId = option.EdgeId })
		end)
	end
end

Remotes.StateUpdated.OnClientEvent:Connect(function(snapshot)
	currentPhase = snapshot.Phase
	legalIntents = snapshot.You.LegalIntents or {}
	renderRouteChoice(snapshot.You.PendingRoute)

	if snapshot.MatchComplete then
		phaseLabel.Text = "Match over"
	else
		phaseLabel.Text = string.format(
			"%s — turn %d, round %d%s",
			snapshot.Phase, snapshot.Turn, snapshot.Round,
			snapshot.You.IsYourTurn and "  (yours)" or ""
		)
	end

	magicLabel.Text = "Magic: " .. snapshot.You.CurrentMagic
	tileLabel.Text = formatTile(snapshot.CurrentTile)
	standingsLabel.Text = formatStandings(snapshot)

	-- Enabled state comes straight from the server's legal-intent list, so
	-- the buttons cannot offer something the server would refuse.
	for intent, button in pairs(buttons) do
		local enabled = isLegal(intent)
		button.TextColor3 = enabled and TEXT_COLOR or DIM_TEXT_COLOR
		button.BackgroundColor3 = enabled and BUTTON_COLOR or BUTTON_DIM_COLOR
		button.AutoButtonColor = enabled
	end
end)

Remotes.ActionResult.OnClientEvent:Connect(function(result)
	if result.Ok then
		resultLabel.Text = result.Message or "ok"
	else
		resultLabel.Text = string.format("%s (%s)", result.Message or "refused", result.Code or "?")
	end
end)

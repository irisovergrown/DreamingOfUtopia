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
local ElementData = require(ReplicatedStorage.Shared.ElementData)

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

local elementBox = createTextBox("ElementBox", 6, "element id (blank = neutral)")
local levelBox = createTextBox("LevelBox", 7, "develop to level (2-5)")

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
local selectedInstanceId = nil

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
			if selectedInstanceId == nil then
				return nil, "select a card from your hand first"
			end
			return { InstanceId = selectedInstanceId }
		end,
	},
	{ Name = "PayTollButton", Text = "Pay Toll", Intent = Intent.PayToll },
	-- The two territory commands that change land itself. Both send the same
	-- intent and are told apart by Command, so adding the remaining three
	-- (move creature, exchange creature, territory ability) needs no new
	-- remote and no new intent.
	{
		Name = "LevelUpButton",
		Text = "Level Up",
		Intent = Intent.ChooseTerritoryCommand,
		Payload = function()
			local level = tonumber(levelBox.Text)
			if level == nil then
				return nil, "enter the level to develop to (2-5)"
			end
			return { Command = Enums.TerritoryCommand.LevelLand, Level = level }
		end,
	},
	{
		Name = "TerraformButton",
		Text = "Terraform",
		Intent = Intent.ChooseTerritoryCommand,
		Payload = function()
			return { Command = Enums.TerritoryCommand.ChangeElement, Element = elementBox.Text }
		end,
	},
	{ Name = "EndTurnButton", Text = "End Turn", Intent = Intent.EndTurn },
	{
		Name = "DiscardButton",
		Text = "Discard",
		Intent = Intent.DiscardToHandLimit,
		Payload = function()
			if selectedInstanceId == nil then
				return nil, "select the card to discard"
			end
			return { InstanceId = selectedInstanceId }
		end,
	},
	-- Two buttons for one intent: committing an item and declining are the
	-- same decision, and declining has to be a real choice rather than the
	-- absence of one.
	{
		Name = "UseItemButton",
		Text = "Use Item",
		Intent = Intent.ChooseBattleItem,
		Payload = function()
			if selectedInstanceId == nil then
				return nil, "select an item from your hand"
			end
			return { InstanceId = selectedInstanceId }
		end,
	},
	{
		Name = "NoItemButton",
		Text = "No Item",
		Intent = Intent.ChooseBattleItem,
		Payload = function()
			return {}
		end,
	},
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

	-- Keyed by name, not by intent: "Use Item" and "No Item" send the same
	-- intent, and keying by intent would let one silently replace the other.
	buttons[definition.Name] = { Button = button, Intent = definition.Intent }
end

-- === The hand ===============================================================
--
-- Culdcept puts the hand along the bottom of the screen, and only one hand is
-- ever shown: the ACTIVE player's. Its owner sees the faces; everyone else
-- sees the same number of backs in the same place, so the turn is legible from
-- any seat without leaking anything.
--
-- The secrecy is not enforced here. The server simply does not put card
-- identities in a snapshot for anyone but the owner, so this code renders
-- backs because it has nothing else to render.

local HAND_CARD_WIDTH = 96
local HAND_CARD_HEIGHT = 132
local CARD_BACK_COLOR = Color3.fromRGB(52, 62, 82)
local CARD_FACE_COLOR = Color3.fromRGB(252, 252, 250)
local CARD_SELECTED_COLOR = Color3.fromRGB(214, 236, 248)

local handGui = Instance.new("Frame")
handGui.Name = "Hand"
handGui.AnchorPoint = Vector2.new(0.5, 1)
handGui.Position = UDim2.new(0.5, 0, 1, -16)
handGui.Size = UDim2.fromOffset(HAND_CARD_WIDTH * 6 + 8 * 5, HAND_CARD_HEIGHT + 22)
handGui.BackgroundTransparency = 1
handGui.Parent = screenGui

local handLabel = Instance.new("TextLabel")
handLabel.Name = "HandOwner"
handLabel.Size = UDim2.new(1, 0, 0, 18)
handLabel.BackgroundTransparency = 1
handLabel.Font = FONT
handLabel.TextSize = 14
handLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
handLabel.TextStrokeTransparency = 0.4
handLabel.Text = ""
handLabel.Parent = handGui

local handRow = Instance.new("Frame")
handRow.Name = "Row"
handRow.Position = UDim2.fromOffset(0, 22)
handRow.Size = UDim2.new(1, 0, 0, HAND_CARD_HEIGHT)
handRow.BackgroundTransparency = 1
handRow.Parent = handGui

local handRowLayout = Instance.new("UIListLayout")
handRowLayout.FillDirection = Enum.FillDirection.Horizontal
handRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
handRowLayout.Padding = UDim.new(0, 8)
handRowLayout.Parent = handRow

local cardsById = {}

local function styleCardSelection()
	for instanceId, card in pairs(cardsById) do
		card.BackgroundColor3 = instanceId == selectedInstanceId and CARD_SELECTED_COLOR or CARD_FACE_COLOR
	end
end

local function buildCardFace(instance, order)
	local card = CardData.Cards[1]
	for _, definition in ipairs(CardData.Cards) do
		if definition.Id == instance.CardId then
			card = definition
			break
		end
	end

	local button = Instance.new("TextButton")
	button.Name = "Card_" .. instance.InstanceId
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(HAND_CARD_WIDTH, HAND_CARD_HEIGHT)
	button.BackgroundColor3 = CARD_FACE_COLOR
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false
	button.Parent = handRow

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = card.Element and ElementData.GetElement(card.Element).Color or Color3.fromRGB(170, 170, 170)
	stroke.Thickness = 2
	stroke.Parent = button

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 7)
	pad.PaddingRight = UDim.new(0, 7)
	pad.Parent = button

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = FONT
	text.TextSize = 12
	text.TextColor3 = TEXT_COLOR
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.TextWrapped = true
	text.RichText = true

	local statLine
	if card.CardType == "Creature" then
		statLine = string.format("ST %d  HP %d", card.ST, card.HP)
	else
		statLine = card.ItemCategory or card.CardType
	end

	text.Text = string.format(
		"<b>%s</b>\n%s\n\n%s\n\n<i>%s</i>",
		card.Name,
		card.Element and ElementData.GetElement(card.Element).DisplayName or "Neutral",
		statLine,
		card.RulesText or ""
	)
	text.Parent = button

	local cost = Instance.new("TextLabel")
	cost.AnchorPoint = Vector2.new(1, 1)
	cost.Position = UDim2.fromScale(1, 1)
	cost.Size = UDim2.fromOffset(34, 16)
	cost.BackgroundTransparency = 1
	cost.Font = FONT
	cost.TextSize = 13
	cost.TextXAlignment = Enum.TextXAlignment.Right
	cost.TextColor3 = Color3.fromRGB(90, 90, 110)
	cost.Text = tostring(card.Cost) .. "G"
	cost.Parent = button

	button.Activated:Connect(function()
		selectedInstanceId = instance.InstanceId
		styleCardSelection()
		resultLabel.Text = "Selected " .. card.Name
	end)

	cardsById[instance.InstanceId] = button
	return button
end

local function buildCardBack(order)
	local back = Instance.new("Frame")
	back.Name = "CardBack"
	back.LayoutOrder = order
	back.Size = UDim2.fromOffset(HAND_CARD_WIDTH, HAND_CARD_HEIGHT)
	back.BackgroundColor3 = CARD_BACK_COLOR
	back.BorderSizePixel = 0
	back.Parent = handRow

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = back

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(96, 110, 140)
	stroke.Thickness = 2
	stroke.Parent = back

	local mark = Instance.new("TextLabel")
	mark.Size = UDim2.fromScale(1, 1)
	mark.BackgroundTransparency = 1
	mark.Font = FONT
	mark.TextSize = 22
	mark.TextColor3 = Color3.fromRGB(120, 136, 170)
	mark.Text = "IX"
	mark.Parent = back

	return back
end

local function renderHand(handView, yourUserId)
	for _, child in ipairs(handRow:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	cardsById = {}

	if handView == nil then
		handGui.Visible = false
		return
	end
	handGui.Visible = true

	if handView.IsFaceUp then
		handLabel.Text = string.format("Your hand — %d/%d", handView.Count, 6)
		-- A selection is only meaningful while the cards it referred to are
		-- still shown, so it is dropped whenever the hand is rebuilt from a
		-- snapshot that no longer contains it.
		local stillHeld = false
		for order, instance in ipairs(handView.Cards or {}) do
			buildCardFace(instance, order)
			if instance.InstanceId == selectedInstanceId then
				stillHeld = true
			end
		end
		if not stillHeld then
			selectedInstanceId = nil
		end
		styleCardSelection()
	else
		handLabel.Text = string.format("Player %d's hand — %d cards", handView.OwnerUserId, handView.Count)
		selectedInstanceId = nil
		for order = 1, handView.Count do
			buildCardBack(order)
		end
	end
end

-- === Zone counts ============================================================
-- The card-id legend this replaced only existed so a player could look up a
-- number to type. Cards are selected from hand now, so the useful thing to
-- show in that space is where a player's cards actually are.

local elementIds = {}
for elementId in pairs(ElementData.Elements) do
	table.insert(elementIds, elementId)
end
table.sort(elementIds)

local function renderZones(you)
	legendLabel.Text = string.format(
		"Book %d   ·   Discard %d\nElements: %s",
		you.BookCount or 0,
		you.DiscardCount or 0,
		table.concat(elementIds, ", ")
	)
end

-- === Rendering ==============================================================

-- Node ids are strings since Milestone 5, so this formats %s rather than %d.
-- A castle or fort is a legitimate place to be standing and simply has no
-- ownership to report, rather than being an absent tile.
local function formatTile(view)
	if view == nil then
		return "Location: —"
	end

	if view.NodeType ~= "Territory" then
		return string.format("%s — %s", view.NodeId, view.NodeType or "?")
	end

	local elementText = view.Element and ElementData.GetElement(view.Element).DisplayName or "Neutral"
	local lines = {
		string.format("%s — %s — Lv%d", view.NodeId, elementText, view.Level or 1),
	}

	table.insert(lines, view.Owner and ("Owner " .. tostring(view.Owner)) or "Unclaimed")
	if view.LandValue then
		table.insert(lines, "Value: " .. view.LandValue)
	end
	if view.DefenderName then
		table.insert(lines, string.format("Defender: %s (%dHP)", view.DefenderName, view.DefenderHP))
	end
	if view.Toll and view.Toll > 0 then
		table.insert(lines, "Toll: " .. view.Toll)
	end

	return table.concat(lines, "\n")
end

local function formatStandings(snapshot)
	local lines = {}
	for _, standing in ipairs(snapshot.Standings) do
		-- TM first: it is what the standings are ordered by and what wins.
		-- A goal-reached player is flagged, because everyone needs to know
		-- who is walking home to win.
		table.insert(lines, string.format(
			"%s%d — TM %d  (CM %d, land %d)  %d tiles, %d cards%s",
			standing.IsActive and "> " or "  ",
			standing.UserId,
			standing.TotalMagic or 0,
			standing.CurrentMagic,
			standing.LandValue or 0,
			standing.TerritoriesOwned,
			standing.HandCount,
			standing.GoalReached and "  [GOAL]" or ""
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
	renderHand(snapshot.HandView, snapshot.You.UserId)
	renderZones(snapshot.You)

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
	for _, entry in pairs(buttons) do
		local enabled = isLegal(entry.Intent)
		entry.Button.TextColor3 = enabled and TEXT_COLOR or DIM_TEXT_COLOR
		entry.Button.BackgroundColor3 = enabled and BUTTON_COLOR or BUTTON_DIM_COLOR
		entry.Button.AutoButtonColor = enabled
	end
end)

Remotes.ActionResult.OnClientEvent:Connect(function(result)
	if result.Ok then
		resultLabel.Text = result.Message or "ok"
	else
		resultLabel.Text = string.format("%s (%s)", result.Message or "refused", result.Code or "?")
	end
end)

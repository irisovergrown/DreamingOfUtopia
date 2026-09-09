--[[
	LocalScript — client, standalone (first slice of a future UIService).

	Studio placement:
		StarterPlayer > StarterPlayerScripts > UIService (LocalScript)

	Purpose:
		Plain HUD (standard Roblox gray panel, default font, no theming)
		replacing the temporary /roll /summon /challenge /paytoll chat
		commands with buttons, and replacing "check the server output
		window" with an on-screen balance/tile readout and action-result
		line. Deliberately plain on purpose — no card art, no animations,
		no custom color theme, just default-looking labels/boxes/buttons.
		A real UIService (card hand, deck builder, actual visual design)
		replaces this once more systems (MatchService especially) exist to
		give it more to show.

		Talks to the server only through ReplicatedStorage.Shared.Remotes —
		never requires server ModuleScripts directly (can't; they live in
		ServerScriptService, which the client cannot see). CardData/EraData
		are Shared (ReplicatedStorage), so this reads them directly for the
		card legend — pure static data, no security concern.

		Turn indicator + End Turn button reflect MatchService's turn state
		(pushed via StateUpdated) — action buttons dim when it isn't your
		turn, though they're still clickable; the server is what actually
		enforces turn order, this is just a visual cue.

		Terraform takes a raw era id typed into EraBox (e.g. "Fire",
		matching an EraData.Eras key — see the legend) rather than a picker;
		blank means neutral. Only works on unclaimed tiles — see
		TerraformService's header for why owned tiles aren't supported yet.

		Cast Spell / Use Item call CardEffectService (see its header for what
		Signal Boost/Ninth Signal Charm actually do). Cast Spell only needs a
		card id — it's a self-buff queued for your next Challenge. Use Item
		needs TargetTileBox too, the project's first explicit tile-id target:
		it must be a tile you're currently defending.

	Server contract (see ReplicatedStorage > Shared > Remotes):
		Client -> Server: RollRequest, SummonRequest(cardId), ChallengeRequest(cardId), PayTollRequest, EndTurnRequest, TerraformRequest(targetEra), CastSpellRequest(cardId), UseItemRequest(cardId, tileId)
		Server -> Client: StateUpdated(snapshot), ActionResult(message)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CardData = require(ReplicatedStorage.Shared.CardData)
local EraData = require(ReplicatedStorage.Shared.EraData)

local localPlayer = Players.LocalPlayer

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "UIServiceHud"
screenGui.ResetOnSpawn = false
screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

local FONT = Enum.Font.SourceSans
local TEXT_COLOR = Color3.fromRGB(0, 0, 0)
local DIM_TEXT_COLOR = Color3.fromRGB(140, 140, 140)
local PANEL_COLOR = Color3.fromRGB(242, 242, 242)
local INPUT_COLOR = Color3.fromRGB(255, 255, 255)
local BUTTON_COLOR = Color3.fromRGB(225, 225, 225)

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromOffset(400, 510)
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

local function createLabel(name, layoutOrder, height, textSize)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = layoutOrder
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

local turnLabel = createLabel("TurnLabel", 1, 20, 16)
local balanceLabel = createLabel("BalanceLabel", 2, 20, 18)
local tileLabel = createLabel("TileLabel", 3, 60, 14)
local legendLabel = createLabel("LegendLabel", 4, 100, 12)

local cardIdBox = Instance.new("TextBox")
cardIdBox.Name = "CardIdBox"
cardIdBox.LayoutOrder = 5
cardIdBox.Size = UDim2.new(1, 0, 0, 26)
cardIdBox.BackgroundColor3 = INPUT_COLOR
cardIdBox.TextColor3 = TEXT_COLOR
cardIdBox.Font = FONT
cardIdBox.TextSize = 14
cardIdBox.PlaceholderText = "card id"
cardIdBox.Text = ""
cardIdBox.ClearTextOnFocus = false
cardIdBox.Parent = frame

local buttonRow = Instance.new("Frame")
buttonRow.Name = "ButtonRow"
buttonRow.LayoutOrder = 6
buttonRow.Size = UDim2.new(1, 0, 0, 28)
buttonRow.BackgroundTransparency = 1
buttonRow.Parent = frame

local buttonRowLayout = Instance.new("UIListLayout")
buttonRowLayout.FillDirection = Enum.FillDirection.Horizontal
buttonRowLayout.Padding = UDim.new(0, 6)
buttonRowLayout.Parent = buttonRow

local function createButton(name, text, layoutOrder)
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = layoutOrder
	button.Size = UDim2.fromOffset(68, 28)
	button.BackgroundColor3 = BUTTON_COLOR
	button.TextColor3 = TEXT_COLOR
	button.Font = FONT
	button.TextSize = 13
	button.Text = text
	button.Parent = buttonRow
	return button
end

local rollButton = createButton("RollButton", "Roll", 1)
local summonButton = createButton("SummonButton", "Summon", 2)
local challengeButton = createButton("ChallengeButton", "Challenge", 3)
local payTollButton = createButton("PayTollButton", "Pay Toll", 4)
local endTurnButton = createButton("EndTurnButton", "End Turn", 5)

local targetTileBox = Instance.new("TextBox")
targetTileBox.Name = "TargetTileBox"
targetTileBox.LayoutOrder = 7
targetTileBox.Size = UDim2.new(1, 0, 0, 26)
targetTileBox.BackgroundColor3 = INPUT_COLOR
targetTileBox.TextColor3 = TEXT_COLOR
targetTileBox.Font = FONT
targetTileBox.TextSize = 14
targetTileBox.PlaceholderText = "target tile id (Use Item only)"
targetTileBox.Text = ""
targetTileBox.ClearTextOnFocus = false
targetTileBox.Parent = frame

local effectButtonRow = Instance.new("Frame")
effectButtonRow.Name = "EffectButtonRow"
effectButtonRow.LayoutOrder = 8
effectButtonRow.Size = UDim2.new(1, 0, 0, 28)
effectButtonRow.BackgroundTransparency = 1
effectButtonRow.Parent = frame

local effectButtonRowLayout = Instance.new("UIListLayout")
effectButtonRowLayout.FillDirection = Enum.FillDirection.Horizontal
effectButtonRowLayout.Padding = UDim.new(0, 6)
effectButtonRowLayout.Parent = effectButtonRow

local function createEffectButton(name, text, layoutOrder)
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = layoutOrder
	button.Size = UDim2.fromOffset(96, 28)
	button.BackgroundColor3 = BUTTON_COLOR
	button.TextColor3 = TEXT_COLOR
	button.Font = FONT
	button.TextSize = 13
	button.Text = text
	button.Parent = effectButtonRow
	return button
end

local castSpellButton = createEffectButton("CastSpellButton", "Cast Spell", 1)
local useItemButton = createEffectButton("UseItemButton", "Use Item", 2)

local eraBox = Instance.new("TextBox")
eraBox.Name = "EraBox"
eraBox.LayoutOrder = 9
eraBox.Size = UDim2.new(1, 0, 0, 26)
eraBox.BackgroundColor3 = INPUT_COLOR
eraBox.TextColor3 = TEXT_COLOR
eraBox.Font = FONT
eraBox.TextSize = 14
eraBox.PlaceholderText = "terraform era id (blank = neutral)"
eraBox.Text = ""
eraBox.ClearTextOnFocus = false
eraBox.Parent = frame

local terraformButton = Instance.new("TextButton")
terraformButton.Name = "TerraformButton"
terraformButton.LayoutOrder = 10
terraformButton.Size = UDim2.new(1, 0, 0, 28)
terraformButton.BackgroundColor3 = BUTTON_COLOR
terraformButton.TextColor3 = TEXT_COLOR
terraformButton.Font = FONT
terraformButton.TextSize = 13
terraformButton.Text = "Terraform"
terraformButton.Parent = frame

local resultLabel = createLabel("ResultLabel", 11, 60, 14)

local legendLines = {}
for _, card in ipairs(CardData.Cards) do
	local eraText = card.Era and EraData.GetEra(card.Era).DisplayName or "Neutral"
	if card.CardType == "Creature" then
		table.insert(
			legendLines,
			string.format("%d %s [%s] ST%d/HP%d Cost%d", card.Id, card.Name, eraText, card.ST, card.HP, card.Cost)
		)
	else
		table.insert(legendLines, string.format("%d %s [%s] Cost%d - %s", card.Id, card.Name, card.CardType, card.Cost, card.EffectDescription or ""))
	end
end

local eraIdLines = {}
for eraId, era in pairs(EraData.Eras) do
	table.insert(eraIdLines, string.format("%s=%s", eraId, era.DisplayName))
end
table.insert(legendLines, "Era ids: " .. table.concat(eraIdLines, ", "))

legendLabel.Text = table.concat(legendLines, "\n")

local function getCardIdInput()
	local cardId = tonumber(cardIdBox.Text)
	if cardId == nil then
		resultLabel.Text = "Enter a card id first"
	end
	return cardId
end

local function getTargetTileInput()
	local tileId = tonumber(targetTileBox.Text)
	if tileId == nil then
		resultLabel.Text = "Enter a target tile id first"
	end
	return tileId
end

rollButton.Activated:Connect(function()
	Remotes.RollRequest:FireServer()
end)

summonButton.Activated:Connect(function()
	local cardId = getCardIdInput()
	if cardId ~= nil then
		Remotes.SummonRequest:FireServer(cardId)
	end
end)

challengeButton.Activated:Connect(function()
	local cardId = getCardIdInput()
	if cardId ~= nil then
		Remotes.ChallengeRequest:FireServer(cardId)
	end
end)

payTollButton.Activated:Connect(function()
	Remotes.PayTollRequest:FireServer()
end)

endTurnButton.Activated:Connect(function()
	Remotes.EndTurnRequest:FireServer()
end)

castSpellButton.Activated:Connect(function()
	local cardId = getCardIdInput()
	if cardId ~= nil then
		Remotes.CastSpellRequest:FireServer(cardId)
	end
end)

useItemButton.Activated:Connect(function()
	local cardId = getCardIdInput()
	local tileId = getTargetTileInput()
	if cardId ~= nil and tileId ~= nil then
		Remotes.UseItemRequest:FireServer(cardId, tileId)
	end
end)

terraformButton.Activated:Connect(function()
	Remotes.TerraformRequest:FireServer(eraBox.Text)
end)

local function formatTileText(state)
	if state.TileId == nil then
		return "Tile: —"
	end

	local eraText = state.TileEra and EraData.GetEra(state.TileEra).DisplayName or "Start"
	local lines = {
		string.format("Tile #%d — %s — Lv%d", state.TileId, eraText, state.TileLevel or 1),
	}

	if state.TileType == "Property" then
		table.insert(lines, state.TileOwner and ("Owner " .. tostring(state.TileOwner)) or "Unclaimed")
		if state.DefenderName ~= nil then
			table.insert(lines, string.format("Defender: %s (%dHP)", state.DefenderName, state.DefenderHP))
		end
		if state.Toll ~= nil and state.Toll > 0 then
			table.insert(lines, string.format("Toll: %d", state.Toll))
		end
	end

	return table.concat(lines, "\n")
end

local function formatTurnText(state)
	if state.MatchEnded then
		return string.format("Match over — Winner: %s", state.WinnerName or "?")
	end
	if state.IsYourTurn then
		return string.format("Your turn%s", state.HasRolled and " (rolled)" or "")
	end
	return string.format("Turn: %s", state.CurrentTurnName or "?")
end

Remotes.StateUpdated.OnClientEvent:Connect(function(state)
	balanceLabel.Text = string.format("Magic: %d", state.Balance or 0)
	tileLabel.Text = formatTileText(state)
	turnLabel.Text = formatTurnText(state)

	-- Visual cue only — the server is what actually enforces turn order,
	-- these buttons stay clickable and just get rejected via ActionResult.
	local buttonColor = state.IsYourTurn and TEXT_COLOR or DIM_TEXT_COLOR
	rollButton.TextColor3 = buttonColor
	summonButton.TextColor3 = buttonColor
	challengeButton.TextColor3 = buttonColor
	payTollButton.TextColor3 = buttonColor
	endTurnButton.TextColor3 = buttonColor
	terraformButton.TextColor3 = buttonColor
	castSpellButton.TextColor3 = buttonColor
	useItemButton.TextColor3 = buttonColor
end)

Remotes.ActionResult.OnClientEvent:Connect(function(message)
	resultLabel.Text = tostring(message)
end)

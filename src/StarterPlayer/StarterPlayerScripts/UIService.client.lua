--[[
	LocalScript — client, standalone (first slice of a future UIService).

	Studio placement:
		StarterPlayer > StarterPlayerScripts > UIService (LocalScript)

	Purpose:
		Plain monospace "terminal" HUD replacing the temporary /roll
		/summon /challenge /paytoll chat commands with buttons, and
		replacing "check the server output window" with an on-screen
		balance/tile readout and action-result line. Deliberately not
		fancy — no card art, no animations, just readable text and a
		handful of buttons. A real UIService (card hand, deck builder,
		turn indicator) replaces this once more systems (MatchService
		especially) exist to give it more to show.

		Talks to the server only through ReplicatedStorage.Shared.Remotes —
		never requires server ModuleScripts directly (can't; they live in
		ServerScriptService, which the client cannot see). CardData/EraData
		are Shared (ReplicatedStorage), so this reads them directly for the
		card legend — pure static data, no security concern.

		Turn indicator + End Turn button reflect MatchService's turn state
		(pushed via StateUpdated) — action buttons dim when it isn't your
		turn, though they're still clickable; the server is what actually
		enforces turn order, this is just a visual cue.

	Server contract (see ReplicatedStorage > Shared > Remotes):
		Client -> Server: RollRequest, SummonRequest(cardId), ChallengeRequest(cardId), PayTollRequest, EndTurnRequest
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

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromOffset(400, 380)
frame.Position = UDim2.fromOffset(20, 20)
frame.BackgroundColor3 = Color3.new(0, 0, 0)
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0
frame.Parent = screenGui

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(90, 255, 160)
stroke.Thickness = 1
stroke.Parent = frame

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
	label.Font = Enum.Font.Code
	label.TextSize = textSize
	label.TextColor3 = Color3.fromRGB(180, 255, 210)
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
cardIdBox.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
cardIdBox.TextColor3 = Color3.fromRGB(180, 255, 210)
cardIdBox.Font = Enum.Font.Code
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
	button.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	button.TextColor3 = Color3.fromRGB(180, 255, 210)
	button.Font = Enum.Font.Code
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

local resultLabel = createLabel("ResultLabel", 7, 60, 14)

local legendLines = {}
for _, card in ipairs(CardData.Cards) do
	local eraText = card.Era and EraData.GetEra(card.Era).DisplayName or "Neutral"
	if card.CardType == "Creature" then
		table.insert(
			legendLines,
			string.format("%d %s [%s] ST%d/HP%d Cost%d", card.Id, card.Name, eraText, card.ST, card.HP, card.Cost)
		)
	else
		table.insert(legendLines, string.format("%d %s [%s] Cost%d", card.Id, card.Name, card.CardType, card.Cost))
	end
end
legendLabel.Text = table.concat(legendLines, "\n")

local function getCardIdInput()
	local cardId = tonumber(cardIdBox.Text)
	if cardId == nil then
		resultLabel.Text = "> enter a card id first"
	end
	return cardId
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
		return string.format("MATCH OVER — Winner: %s", state.WinnerName or "?")
	end
	if state.IsYourTurn then
		return string.format("YOUR TURN%s", state.HasRolled and " (rolled)" or "")
	end
	return string.format("Turn: %s", state.CurrentTurnName or "?")
end

local ACTIVE_BUTTON_COLOR = Color3.fromRGB(180, 255, 210)
local DIM_BUTTON_COLOR = Color3.fromRGB(90, 100, 95)

Remotes.StateUpdated.OnClientEvent:Connect(function(state)
	balanceLabel.Text = string.format("MAGIC: %d", state.Balance or 0)
	tileLabel.Text = formatTileText(state)
	turnLabel.Text = formatTurnText(state)

	-- Visual cue only — the server is what actually enforces turn order,
	-- these buttons stay clickable and just get rejected via ActionResult.
	local buttonColor = state.IsYourTurn and ACTIVE_BUTTON_COLOR or DIM_BUTTON_COLOR
	rollButton.TextColor3 = buttonColor
	summonButton.TextColor3 = buttonColor
	challengeButton.TextColor3 = buttonColor
	payTollButton.TextColor3 = buttonColor
	endTurnButton.TextColor3 = buttonColor
end)

Remotes.ActionResult.OnClientEvent:Connect(function(message)
	resultLabel.Text = "> " .. tostring(message)
end)

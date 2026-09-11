--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > CardService (ModuleScript)

	Purpose:
		Query API over the static CardData registry. Other systems
		(BattleService for ST/HP comparisons, BoardService for land-bonus
		era matching, future UIService for deck-building screens) go
		through this module rather than requiring CardData directly, so the
		lookup logic has one home and can grow (unlocks, deck/hand state)
		without callers changing.

		Player hand/deck/unlock state is NOT here yet — that needs
		MatchService (match setup) and a persistence layer, neither of
		which exist yet. This module is deliberately just the card
		database lookup for now.

	Public API:
		CardService.GetCard(cardId) -> card or nil
		CardService.GetAllCards() -> array of cards
		CardService.GetCardsByType(cardType) -> array of cards
		CardService.GetCardsByElement(era) -> array of cards
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardData = require(ReplicatedStorage.Shared.CardData)

local CardService = {}

local _cardsById = {}
for _, card in ipairs(CardData.Cards) do
	_cardsById[card.Id] = card
end

function CardService.GetCard(cardId)
	return _cardsById[cardId]
end

function CardService.GetAllCards()
	local cards = {}
	for _, card in ipairs(CardData.Cards) do
		table.insert(cards, card)
	end
	return cards
end

function CardService.GetCardsByType(cardType)
	local cards = {}
	for _, card in ipairs(CardData.Cards) do
		if card.CardType == cardType then
			table.insert(cards, card)
		end
	end
	return cards
end

function CardService.GetCardsByElement(era)
	local cards = {}
	for _, card in ipairs(CardData.Cards) do
		if card.Element == era then
			table.insert(cards, card)
		end
	end
	return cards
end

return CardService

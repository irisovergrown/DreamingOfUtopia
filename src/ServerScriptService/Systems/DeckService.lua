--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > DeckService (ModuleScript)

	Purpose:
		Each player's book, hand and discard pile, and the movement of cards
		between them.

		This is what turns cards from a lookup table into owned objects. Until
		now a player could summon card 3 as many times as they could pay for
		it, because "playing a card" meant naming a row in CardData. A card is
		now an INSTANCE with its own id, held by exactly one player, in
		exactly one zone, and playing it consumes it.

	Instance identity:
		Two copies of Tape Gnome are two instances with different ids. Effects
		that target a specific card need that, but the immediate reason is
		secrecy: the server sends instance ids and definitions to the card's
		owner and only a COUNT to everyone else. Without per-instance identity
		there is nothing to withhold — the hand would just be a list of card
		ids, and any client could ask CardData what they mean.

	Zones are distinct and a card is in exactly one:
		Book       face-down draw pile, order is server-owned
		Hand       playable, capped at RulesConfig.Hand.MaxSize
		Discard    spent, waiting to be recycled
		Removed    out of the match entirely

	Recycling:
		Drawing from an empty book shuffles the discard into a fresh book and
		increments the cycle count. A player with an empty book AND an empty
		discard simply draws nothing — that is a legal state, not an error,
		and returning a short draw is more honest than inventing a card.

	Shuffling:
		Server-side, through the injected RandomService, so a seeded test
		replays the same book every time. Clients never see or influence order.

	Public API:
		DeckService.Init(deps)                    -- deps.Random, deps.Cards
		DeckService.RegisterPlayer(userId, cardIds?)  -- default book if omitted
		DeckService.RemovePlayer(userId)
		DeckService.Draw(userId, count?) -> array of instances actually drawn
		DeckService.GetHand(userId) -> array of { InstanceId, CardId }
		DeckService.GetHandCount(userId) -> number
		DeckService.GetBookCount(userId) -> number
		DeckService.GetDiscardCount(userId) -> number
		DeckService.GetCycleCount(userId) -> number
		DeckService.HasInstance(userId, instanceId) -> boolean
		DeckService.GetInstance(userId, instanceId) -> instance or nil
		DeckService.PlayInstance(userId, instanceId) -> ActionResult  -- hand -> discard
		DeckService.DiscardInstance(userId, instanceId) -> ActionResult
		DeckService.ReturnToHand(userId, cardId) -> ActionResult      -- e.g. a surviving invader
		DeckService.IsHandOverFull(userId) -> boolean
		DeckService.BuildDefaultBook() -> array of cardIds

	Signals:
		DeckService.CardDrawn:Connect(function(userId, instance) end)
		DeckService.CardPlayed:Connect(function(userId, instance) end)
		DeckService.BookRecycled:Connect(function(userId, cycleCount) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local ActionResult = require(ReplicatedStorage.Shared.ActionResult)
local RulesConfig = require(ReplicatedStorage.Shared.RulesConfig)
local Signal = require(ReplicatedStorage.Shared.Signal)
local CardData = require(ReplicatedStorage.Shared.CardData)

local DeckService = {}

DeckService.CardDrawn = Signal.new("Deck.CardDrawn")
DeckService.CardPlayed = Signal.new("Deck.CardPlayed")
DeckService.BookRecycled = Signal.new("Deck.BookRecycled")

local _random = nil
local _cards = CardData

-- userId -> { Book, Hand, Discard, Removed, CycleCount }
local _decks = {}
local _nextInstanceId = 1

local function newInstanceId()
	local id = string.format("c%d", _nextInstanceId)
	_nextInstanceId += 1
	return id
end

local function deckFor(userId)
	return _decks[userId]
end

local function indexOfInstance(zone, instanceId)
	for index, instance in ipairs(zone) do
		if instance.InstanceId == instanceId then
			return index
		end
	end
	return nil
end

function DeckService.Init(deps)
	deps = deps or {}
	_random = deps.Random
	_cards = deps.Cards or CardData
	_decks = {}
	_nextInstanceId = 1
end

-- Fills a legal book from whatever cards exist: every card up to the copy
-- limit, cycling until the book is full. Deliberately not a curated deck —
-- deck BUILDING is a Milestone 8 concern, and this only has to be legal.
function DeckService.BuildDefaultBook()
	local cardIds = {}
	for _, card in ipairs(_cards.Cards) do
		table.insert(cardIds, card.Id)
	end
	table.sort(cardIds)

	local book = {}
	local copies = 0
	while #book < RulesConfig.Book.Size and copies < RulesConfig.Book.MaxCopiesPerCard do
		copies += 1
		for _, cardId in ipairs(cardIds) do
			if #book >= RulesConfig.Book.Size then
				break
			end
			table.insert(book, cardId)
		end
	end
	return book
end

function DeckService.RegisterPlayer(userId, cardIds)
	local book = {}
	for _, cardId in ipairs(cardIds or DeckService.BuildDefaultBook()) do
		table.insert(book, { InstanceId = newInstanceId(), CardId = cardId })
	end

	if _random then
		_random:Shuffle(book)
	end

	_decks[userId] = {
		Book = book,
		Hand = {},
		Discard = {},
		Removed = {},
		CycleCount = 0,
	}
end

function DeckService.RemovePlayer(userId)
	_decks[userId] = nil
end

local function recycle(deck, userId)
	if #deck.Discard == 0 then
		return false
	end

	deck.Book = deck.Discard
	deck.Discard = {}
	deck.CycleCount += 1

	if _random then
		_random:Shuffle(deck.Book)
	end

	DeckService.BookRecycled:Fire(userId, deck.CycleCount)
	return true
end

-- Returns what was ACTUALLY drawn, which may be fewer than asked for: the
-- hand cap and an exhausted book+discard both legitimately shorten a draw,
-- and the caller needs to know rather than assume.
function DeckService.Draw(userId, count)
	count = count or 1
	local deck = deckFor(userId)
	if deck == nil then
		return {}
	end

	local drawn = {}
	for _ = 1, count do
		if #deck.Book == 0 and not recycle(deck, userId) then
			break -- nothing left anywhere; a legal state, not an error
		end

		local instance = table.remove(deck.Book)
		if instance == nil then
			break
		end

		table.insert(deck.Hand, instance)
		table.insert(drawn, instance)
		DeckService.CardDrawn:Fire(userId, instance)
	end

	return drawn
end

-- A copy, and shallow copies of each instance: a caller that mutates what it
-- is handed must not be able to rewrite a player's hand.
function DeckService.GetHand(userId)
	local deck = deckFor(userId)
	if deck == nil then
		return {}
	end

	local hand = {}
	for index, instance in ipairs(deck.Hand) do
		hand[index] = { InstanceId = instance.InstanceId, CardId = instance.CardId }
	end
	return hand
end

function DeckService.GetHandCount(userId)
	local deck = deckFor(userId)
	return deck and #deck.Hand or 0
end

function DeckService.GetBookCount(userId)
	local deck = deckFor(userId)
	return deck and #deck.Book or 0
end

function DeckService.GetDiscardCount(userId)
	local deck = deckFor(userId)
	return deck and #deck.Discard or 0
end

function DeckService.GetCycleCount(userId)
	local deck = deckFor(userId)
	return deck and deck.CycleCount or 0
end

function DeckService.GetInstance(userId, instanceId)
	local deck = deckFor(userId)
	if deck == nil then
		return nil
	end
	local index = indexOfInstance(deck.Hand, instanceId)
	return index and deck.Hand[index] or nil
end

function DeckService.HasInstance(userId, instanceId)
	return DeckService.GetInstance(userId, instanceId) ~= nil
end

function DeckService.IsHandOverFull(userId)
	return DeckService.GetHandCount(userId) > RulesConfig.Hand.MaxSize
end

local function moveFromHandToDiscard(userId, instanceId, signal)
	local deck = deckFor(userId)
	if deck == nil then
		return ActionResult.fail(Enums.RejectReason.NotAParticipant, "no deck for this player")
	end

	local index = indexOfInstance(deck.Hand, instanceId)
	if index == nil then
		-- The check that makes a hand mean something: naming a card you do not
		-- hold is refused, where previously any card id was playable.
		return ActionResult.fail(
			Enums.RejectReason.CardNotInHand,
			string.format("card '%s' is not in your hand", tostring(instanceId))
		)
	end

	local instance = table.remove(deck.Hand, index)
	table.insert(deck.Discard, instance)

	if signal then
		signal:Fire(userId, instance)
	end
	return ActionResult.ok({ InstanceId = instance.InstanceId, CardId = instance.CardId })
end

function DeckService.PlayInstance(userId, instanceId)
	return moveFromHandToDiscard(userId, instanceId, DeckService.CardPlayed)
end

function DeckService.DiscardInstance(userId, instanceId)
	return moveFromHandToDiscard(userId, instanceId, nil)
end

-- An invader that survives without taking the land returns to hand. It comes
-- back as a NEW instance because the old one was consumed on play; what
-- returns is a card of that type, not the same object.
function DeckService.ReturnToHand(userId, cardId)
	local deck = deckFor(userId)
	if deck == nil then
		return ActionResult.fail(Enums.RejectReason.NotAParticipant, "no deck for this player")
	end

	local instance = { InstanceId = newInstanceId(), CardId = cardId }
	table.insert(deck.Hand, instance)
	return ActionResult.ok(instance)
end

return DeckService

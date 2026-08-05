--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > BattleService (ModuleScript)

	Purpose:
		Challenge resolution: claiming unclaimed tiles by summoning a
		Creature card, and challenging enemy-owned tiles (ST vs effective
		HP compare — winner takes the tile), per the gameplay reference.
		Tracks which specific creature currently defends each claimed
		tile — BoardService only tracks Owner/Level and stays creature-
		agnostic; this module layers combat state on top of it and CardService,
		calling their public APIs rather than reaching into their internals.

		Deliberately NOT built here (see CLAUDE.md for the full list of gaps):
		- Paying a toll instead of challenging — no currency/EconomyService yet.
		- Summon or tile-level-up costs — CardData.Cost exists but nothing
		  deducts it yet, same reason.
		- Turn enforcement / team-alliance awareness — needs MatchService,
		  which doesn't exist yet. Any player can call this at any time.
		- Landing-on-your-own-tile actions (e.g. leveling up) — out of scope
		  for this slice.

		Battle resolution is a single binary comparison (attacker ST vs
		defender's effective HP at the moment of the challenge) — no
		partial/persistent damage tracking. CardData only has an HP stat,
		not a separate Defense stat the brief's "HP/defense compare" phrase
		implies Culdcept has; add one to CardData later if needed, this
		module doesn't need to change to support it (just add it into the
		GetEffectiveHP / ChallengeTile comparison).

	Public API:
		BattleService.Init()
		BattleService.GetEffectiveHP(cardId, tileId) -> number
		BattleService.SummonCreature(player, cardId, tileId) -> success, reason
		BattleService.ChallengeTile(player, cardId, tileId) -> attackerWon, reason
		BattleService.GetDefender(tileId) -> { CardId, OwnerUserId, CurrentHP } or nil

	Signals (ReplicatedStorage.Shared.Signal instances):
		BattleService.TileClaimed:Connect(function(tileId, ownerUserId, cardId) end)
		BattleService.ChallengeResolved:Connect(function(tileId, attackerUserId, defenderUserId, attackerWon) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Signal = require(ReplicatedStorage.Shared.Signal)
local BoardService = require(ServerScriptService.Systems.BoardService)
local CardService = require(ServerScriptService.Systems.CardService)

local BattleService = {}

BattleService.TileClaimed = Signal.new()
BattleService.ChallengeResolved = Signal.new()

-- tileId -> { CardId = number, OwnerUserId = number, CurrentHP = number }
local _defenders = {}

local function getUserId(playerOrUserId)
	if playerOrUserId == nil then
		return nil
	end
	if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		return playerOrUserId.UserId
	end
	return playerOrUserId
end

function BattleService.Init()
	_defenders = {}
end

function BattleService.GetEffectiveHP(cardId, tileId)
	local card = CardService.GetCard(cardId)
	local tile = BoardService.GetTile(tileId)
	if card == nil or tile == nil or card.CardType ~= "Creature" then
		return 0
	end

	local hp = card.HP
	if card.Era ~= nil and card.Era == tile.Era then
		hp += BoardService.GetLandBonusHP(tileId)
	end
	return hp
end

function BattleService.GetDefender(tileId)
	return _defenders[tileId]
end

function BattleService.SummonCreature(player, cardId, tileId)
	local card = CardService.GetCard(cardId)
	if card == nil or card.CardType ~= "Creature" then
		return false, "Card is not a summonable creature"
	end

	local tile = BoardService.GetTile(tileId)
	if tile == nil or tile.TileType ~= "Property" then
		return false, "Tile cannot be claimed"
	end

	if tile.Owner ~= nil then
		return false, "Tile is already owned — challenge it instead"
	end

	local userId = getUserId(player)

	-- Set defender state before SetOwner so the BoardService.TileOwnerChanged
	-- listener (which refreshes tile visuals) sees the defender already in
	-- place on its very first refresh, not one refresh later.
	_defenders[tileId] = {
		CardId = cardId,
		OwnerUserId = userId,
		CurrentHP = BattleService.GetEffectiveHP(cardId, tileId),
	}

	BoardService.SetOwner(tileId, userId)
	BattleService.TileClaimed:Fire(tileId, userId, cardId)

	return true, nil
end

function BattleService.ChallengeTile(player, cardId, tileId)
	local card = CardService.GetCard(cardId)
	if card == nil or card.CardType ~= "Creature" then
		return false, "Card is not a battle-capable creature"
	end

	local tile = BoardService.GetTile(tileId)
	if tile == nil or tile.TileType ~= "Property" or tile.Owner == nil then
		return false, "Tile is not owned — nothing to challenge"
	end

	local userId = getUserId(player)
	if tile.Owner == userId then
		return false, "You already own this tile"
	end

	local defender = _defenders[tileId]
	if defender == nil then
		return false, "Tile has no defending creature on record"
	end

	local attackerWon = card.ST >= defender.CurrentHP

	if attackerWon then
		_defenders[tileId] = {
			CardId = cardId,
			OwnerUserId = userId,
			CurrentHP = BattleService.GetEffectiveHP(cardId, tileId),
		}
		BoardService.SetOwner(tileId, userId)
		BattleService.TileClaimed:Fire(tileId, userId, cardId)
	end

	BattleService.ChallengeResolved:Fire(tileId, userId, defender.OwnerUserId, attackerWon)

	return attackerWon, nil
end

return BattleService

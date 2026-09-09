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

		SummonCreature/ChallengeTile spend the card's Magic Cost via
		EconomyService.SpendMagic before resolving — validated last, after
		every other rejection reason, so a failed claim/challenge never
		costs Magic.

		Deliberately NOT built here (see CLAUDE.md for the full list of gaps):
		- Paying a toll instead of challenging lives in EconomyService.PayToll,
		  not here — it's a currency transaction, not a battle outcome.
		- Tile-level-up costs — that's a landing-on-your-own-tile action,
		  out of scope for this slice regardless of currency existing now.
		- Turn enforcement / team-alliance awareness — needs MatchService,
		  which doesn't exist yet. Any player can call this at any time.

		Battle resolution is a single binary comparison (attacker ST vs
		defender's effective HP at the moment of the challenge) — no
		partial/persistent damage tracking. CardData only has an HP stat,
		not a separate Defense stat the brief's "HP/defense compare" phrase
		implies Culdcept has; add one to CardData later if needed, this
		module doesn't need to change to support it (just add it into the
		GetEffectiveHP / ChallengeTile comparison).

		QueueAttackBuff/ApplyDefenderHPBuff exist so CardEffectService (Spell/
		Item resolution) has somewhere to apply its effects without reaching
		into _defenders directly — same reasoning as everything else in this
		module staying the sole owner of that table. A queued attack buff is
		additive and consumed (win or lose) the next time its owner calls
		ChallengeTile; a defender HP buff is permanent until that tile's
		defender record is replaced (recaptured, re-summoned, etc.).

	Public API:
		BattleService.Init()
		BattleService.GetEffectiveHP(cardId, tileId) -> number
		BattleService.SummonCreature(player, cardId, tileId) -> success, reason
		BattleService.ChallengeTile(player, cardId, tileId) -> attackerWon, reason
		BattleService.GetDefender(tileId) -> { CardId, OwnerUserId, CurrentHP } or nil
		BattleService.QueueAttackBuff(player, bonusST) -- consumed on that player's next ChallengeTile
		BattleService.ApplyDefenderHPBuff(player, tileId, bonusHP) -> success, reason

	Signals (ReplicatedStorage.Shared.Signal instances):
		BattleService.TileClaimed:Connect(function(tileId, ownerUserId, cardId) end)
		BattleService.ChallengeResolved:Connect(function(tileId, attackerUserId, defenderUserId, attackerWon) end)
		BattleService.DefenderBuffed:Connect(function(tileId, newHP) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Signal = require(ReplicatedStorage.Shared.Signal)
local BoardService = require(ServerScriptService.Systems.BoardService)
local CardService = require(ServerScriptService.Systems.CardService)
local EconomyService = require(ServerScriptService.Systems.EconomyService)

local BattleService = {}

BattleService.TileClaimed = Signal.new()
BattleService.ChallengeResolved = Signal.new()
BattleService.DefenderBuffed = Signal.new()

-- tileId -> { CardId = number, OwnerUserId = number, CurrentHP = number }
local _defenders = {}

-- userId -> accumulated ST bonus queued by CardEffectService.CastSpell,
-- consumed on that player's next ChallengeTile call.
local _attackBuffs = {}

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
	_attackBuffs = {}
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

	local spendSuccess, spendReason = EconomyService.SpendMagic(player, card.Cost)
	if not spendSuccess then
		return false, spendReason
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

	local spendSuccess, spendReason = EconomyService.SpendMagic(player, card.Cost)
	if not spendSuccess then
		return false, spendReason
	end

	local attackBonus = _attackBuffs[userId] or 0
	_attackBuffs[userId] = nil

	local attackerWon = (card.ST + attackBonus) >= defender.CurrentHP

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

function BattleService.QueueAttackBuff(player, bonusST)
	local userId = getUserId(player)
	_attackBuffs[userId] = (_attackBuffs[userId] or 0) + bonusST
end

function BattleService.ApplyDefenderHPBuff(player, tileId, bonusHP)
	local defender = _defenders[tileId]
	if defender == nil then
		return false, "Tile has no defending creature on record"
	end

	local userId = getUserId(player)
	if defender.OwnerUserId ~= userId then
		return false, "You can only equip your own defending creature"
	end

	defender.CurrentHP += bonusHP
	BattleService.DefenderBuffed:Fire(tileId, defender.CurrentHP)
	return true, nil
end

return BattleService

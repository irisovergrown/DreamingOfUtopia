--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > CardEffectService (ModuleScript)

	Purpose:
		Resolves what a Spell/Item card actually does when played — the
		"Spell/Item effect hooks" CardData's header said would land here
		later. Layers on top of CardService/BattleService/EconomyService
		through their public APIs, same pattern BattleService itself uses
		on top of BoardService/CardService.

		CastSpell (Signal Boost, Id 5): queues an ST bonus via
		BattleService.QueueAttackBuff for whichever creature the caster next
		uses in BattleService.ChallengeTile — no tile target needed, consumed
		on that one challenge (win or lose).

		UseItem (Ninth Signal Charm, Id 6): permanently raises the HP of a
		creature the caster is currently defending a tile with, via
		BattleService.ApplyDefenderHPBuff, for as long as that creature holds
		the tile. Requires an explicit target tile id, unlike every other
		action in the game so far — UIService's TargetTileBox is that first
		real targeting input. If the target turns out invalid (not your
		defender), the Magic already spent is refunded rather than lost.

		EffectValue on the card is the magnitude (ST bonus / HP bonus) —
		this module just decides which BattleService call to make with it,
		it doesn't hardcode per-card numbers itself.

	Public API:
		CardEffectService.CastSpell(player, cardId) -> success, reason
		CardEffectService.UseItem(player, cardId, tileId) -> success, reason
]]

local ServerScriptService = game:GetService("ServerScriptService")

local CardService = require(ServerScriptService.Systems.CardService)
local EconomyService = require(ServerScriptService.Systems.EconomyService)
local BattleService = require(ServerScriptService.Systems.BattleService)

local CardEffectService = {}

function CardEffectService.CastSpell(player, cardId)
	local card = CardService.GetCard(cardId)
	if card == nil or card.CardType ~= "Spell" then
		return false, "Card is not a castable spell"
	end

	local spendSuccess, spendReason = EconomyService.SpendMagic(player, card.Cost)
	if not spendSuccess then
		return false, spendReason
	end

	BattleService.QueueAttackBuff(player, card.EffectValue or 0)
	return true, nil
end

function CardEffectService.UseItem(player, cardId, tileId)
	local card = CardService.GetCard(cardId)
	if card == nil or card.CardType ~= "Item" then
		return false, "Card is not a usable item"
	end

	local spendSuccess, spendReason = EconomyService.SpendMagic(player, card.Cost)
	if not spendSuccess then
		return false, spendReason
	end

	-- ApplyDefenderHPBuff returns an ActionResult since Milestone 4.
	local applied = BattleService.ApplyDefenderHPBuff(player, tileId, card.EffectValue or 0)
	if not applied.Ok then
		-- Refund — the item wasn't actually used if there was nothing valid to equip it to.
		EconomyService.AddMagic(player, card.Cost)
		return false, applied.Message
	end

	return true, nil
end

return CardEffectService

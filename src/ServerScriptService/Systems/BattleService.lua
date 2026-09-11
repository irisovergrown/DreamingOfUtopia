--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > BattleService (ModuleScript)

	Purpose:
		Claiming territories, and resolving invasions as a NESTED STATE
		MACHINE rather than a single comparison.

		The previous version compared attacker ST against a cached defender
		HP and handed the tile to whoever was larger. That has no room for the
		things a Culdcept battle actually is: two sequential item decisions,
		an ordered modifier pipeline, a strike order, a counterattack that may
		not happen, and four distinct outcomes with different toll
		consequences. So a battle is now an object that advances through
		states, the same shape movement took in Milestone 2.

			BeginInvasion       -> AwaitingAttackerItem
			ChooseAttackerItem  -> AwaitingDefenderItem
			ChooseDefenderItem  -> Resolved (one of four outcomes)

		The invader commits first and the defender chooses knowing what was
		committed. That order is Saga's, and it is enforced structurally: the
		defender's choice function refuses to run until the attacker's has.

	The HP model, which is the defect this milestone exists to fix:
		The old code stored `CurrentHP = card.HP + landBonus`, fusing a
		TEMPORARY battle bonus into the creature's persistent health. That is
		why terraforming an owned tile had to be forbidden — changing the
		element afterwards left the cached number wrong with no way to tell.

		Now a defender keeps BaseMHP, BonusMHP (permanent, from items) and
		CurrentHP (persistent damage), and the land bonus is computed fresh at
		every battle from the tile's CURRENT element and level. Nothing about
		the land is ever written into the creature, so the tile can change
		underneath it and the next battle simply computes a different bonus.

		Temporary battle HP absorbs damage BEFORE persistent HP. Total pool is
		unchanged, so survival is identical either way, but it decides how
		much damage carries over — a defender on a level 3 matching tile
		soaks 30 before its own health is touched. UNVERIFIED against the
		source game; isolated here and in RulesConfig rather than guessed at
		three call sites.

	Attack order:
		Speed classes rank First > Normal > Last. The higher class strikes
		first; on equal class the invader does. That single comparison
		reproduces the brief's whole matrix, including the case where the
		DEFENDER is the faster one, so there is no table to keep in sync.

		A lethal first strike ends the battle: the destroyed creature does not
		counterattack.

	Keywords, all read from card data rather than card names:
		First / Last     speed class
		Critical         qualifying damage multiplied by RulesConfig
		Penetration      the defender's land bonus does not apply
		Neutralize       reduces an ordinary incoming strike to zero, once
		Reflect          reduces it to zero and returns the same damage
		Regenerate       a survivor is restored to full at battle end
		Support          may commit a CREATURE card as its battle item

		Scroll items attack in their own right: they bypass the land bonus and
		ordinary Neutralize/Reflect, which is what makes them the answer to a
		defender those keywords would otherwise make unkillable.

	NOT done here (Milestone 6, and honestly so):
		Poison and paralysis. The brief lists them among this milestone's
		tests, but they are STATUSES with durations that outlive a battle, and
		StatusService does not exist. Implementing them as battle-local flags
		would produce something that passes a test and models the wrong thing.

	Public API:
		BattleService.Init(deps)   -- Territory, Card, Economy, Deck
		BattleService.SummonCreature(userId, instanceId, tileId) -> ActionResult
		BattleService.BeginInvasion(userId, instanceId, tileId) -> ActionResult
		BattleService.ChooseAttackerItem(userId, instanceIdOrNil) -> ActionResult
		BattleService.ChooseDefenderItem(userId, instanceIdOrNil) -> ActionResult
		BattleService.GetPendingBattle() -> summary or nil
		BattleService.GetDefenderUserId() -> userId or nil
		BattleService.GetDefender(tileId) -> creature state or nil
		BattleService.QueueAttackBuff(userId, bonusST)
		BattleService.ApplyDefenderHPBuff(userId, tileId, bonusHP) -> ActionResult

	Signals:
		BattleService.TileClaimed:Connect(function(tileId, ownerUserId, cardId) end)
		BattleService.BattleStarted:Connect(function(summary) end)
		BattleService.BattleResolved:Connect(function(result) end)
		BattleService.DefenderBuffed:Connect(function(tileId, newHP) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local ActionResult = require(ReplicatedStorage.Shared.ActionResult)
local RulesConfig = require(ReplicatedStorage.Shared.RulesConfig)
local Signal = require(ReplicatedStorage.Shared.Signal)

local BattleService = {}

BattleService.TileClaimed = Signal.new("Battle.TileClaimed")
BattleService.BattleStarted = Signal.new("Battle.BattleStarted")
BattleService.BattleResolved = Signal.new("Battle.BattleResolved")
BattleService.DefenderBuffed = Signal.new("Battle.DefenderBuffed")

local SPEED_RANK = {
	[Enums.SpeedClass.First] = 3,
	[Enums.SpeedClass.Normal] = 2,
	[Enums.SpeedClass.Last] = 1,
}

local _territory, _card, _economy, _deck, _status

-- tileId -> creature state
local _defenders = {}
-- userId -> queued ST bonus, spent on that player's next invasion
local _attackBuffs = {}
-- The single battle in flight. Turns are sequential, so there is only ever one.
local _battle = nil

function BattleService.Init(deps)
	deps = deps or {}
	_territory = deps.Territory
	_card = deps.Card
	_economy = deps.Economy
	_deck = deps.Deck
	_status = deps.Status

	_defenders = {}
	_attackBuffs = {}
	_battle = nil
end

-- === Creature state =========================================================

local function newCreatureState(cardId, ownerUserId, instanceId)
	local card = _card.GetCard(cardId)
	return {
		InstanceId = instanceId,
		CardId = cardId,
		OwnerUserId = ownerUserId,
		BaseST = card.ST,
		BonusST = 0,
		BaseMHP = card.HP,
		BonusMHP = 0,
		-- Persistent health. The land bonus is deliberately NOT folded in.
		CurrentHP = card.HP,
	}
end

local function maxHP(state)
	return state.BaseMHP + state.BonusMHP
end

function BattleService.GetDefender(tileId)
	return _defenders[tileId]
end

-- The land bonus for whoever is defending this tile RIGHT NOW, computed from
-- the tile's current element and level. Never stored, so a terraform or a
-- level change is picked up automatically by the next battle.
local function landBonusFor(state, tileId)
	if state == nil then
		return 0
	end
	local tile = _territory.GetTerritory(tileId)
	local card = _card.GetCard(state.CardId)
	if tile == nil or card == nil then
		return 0
	end
	-- Neutral creatures never receive it, even standing on elemental land.
	if card.Element == nil or card.Element ~= tile.Element then
		return 0
	end
	return RulesConfig.getLandBonusHP(tile.Level)
end

BattleService.GetLandBonusFor = landBonusFor

-- === Card helpers ===========================================================

local function hasKeyword(card, keyword)
	for _, candidate in ipairs(card and card.Keywords or {}) do
		if candidate == keyword then
			return true
		end
	end
	return false
end

local function speedOf(creatureCard, itemCard)
	-- Checked in order rather than by iterating {itemCard, creatureCard}: with
	-- no item that table is {nil, card}, and ipairs stops dead at the nil, so
	-- every creature silently came out Normal and the entire speed matrix
	-- collapsed to "invader first".
	local function declaredSpeed(card)
		if card == nil then
			return nil
		end
		if hasKeyword(card, Enums.SpeedClass.First) then
			return Enums.SpeedClass.First
		elseif hasKeyword(card, Enums.SpeedClass.Last) then
			return Enums.SpeedClass.Last
		end
		return nil
	end

	-- An item's speed overrides the creature's own when it declares one.
	return declaredSpeed(itemCard) or declaredSpeed(creatureCard) or Enums.SpeedClass.Normal
end

-- === Combatant assembly =====================================================

-- Builds a combatant's battle-time numbers in the brief's stated order: base
-- state, then item modifiers, then the territory's land bonus. Everything that
-- contributes is recorded so the UI and the log can show the breakdown rather
-- than a bare total.
local function buildCombatant(options)
	local card = _card.GetCard(options.CardId)
	local itemCard = options.ItemCardId and _card.GetCard(options.ItemCardId) or nil

	local isScroll = itemCard ~= nil and itemCard.ItemCategory == "Scroll"
	local isWeapon = itemCard ~= nil and itemCard.ItemCategory == "Weapon"
	local isArmor = itemCard ~= nil and itemCard.ItemCategory == "Armor"
	-- A Support creature may commit a creature card; it lends its ST.
	local isSupportCreature = itemCard ~= nil and itemCard.CardType == "Creature"

	local st = (options.BaseST or card.ST) + (options.BonusST or 0)
	if isWeapon then
		st += itemCard.EffectValue or 0
	elseif isSupportCreature then
		st += math.floor((itemCard.ST or 0) / 2)
	end

	local persistentHP = options.CurrentHP or card.HP
	local itemHP = isArmor and (itemCard.EffectValue or 0) or 0

	return {
		UserId = options.UserId,
		CardId = options.CardId,
		Card = card,
		InstanceId = options.InstanceId,
		ItemCardId = options.ItemCardId,
		ItemCard = itemCard,
		IsScrollAttack = isScroll,
		ScrollDamage = isScroll and (itemCard.EffectValue or 0) or 0,

		ST = st,
		PersistentHP = persistentHP,
		ItemHP = itemHP,
		-- Filled by the caller: only the defender receives one.
		TemporaryHP = 0,

		Speed = speedOf(card, itemCard),
		Keywords = {
			Critical = hasKeyword(card, "Critical") or hasKeyword(itemCard, "Critical"),
			Penetration = hasKeyword(card, "Penetration") or hasKeyword(itemCard, "Penetration"),
			Neutralize = hasKeyword(card, "Neutralize"),
			Reflect = hasKeyword(card, "Reflect"),
			Regenerate = hasKeyword(card, "Regenerate"),
			Support = hasKeyword(card, "Support"),
		},

		DamageTaken = 0,
		NeutralizeSpent = false,
		ReflectSpent = false,
	}
end

local function totalPool(combatant)
	return combatant.PersistentHP + combatant.ItemHP + combatant.TemporaryHP
end

local function isDestroyed(combatant)
	return combatant.DamageTaken >= totalPool(combatant)
end

-- === Strike resolution ======================================================

-- Applies one strike and returns a log entry. Returns reflected damage so the
-- caller can apply it to the striker.
local function resolveStrike(striker, target, log)
	local damage = striker.ST
	local isScroll = striker.IsScrollAttack
	if isScroll then
		damage = striker.ScrollDamage
	end

	if striker.Keywords.Critical then
		damage = math.floor(damage * RulesConfig.Battle.CriticalMultiplier)
	end

	local reflected = 0
	local note = nil

	-- Scrolls bypass the defensive keywords, which is the whole reason to
	-- carry one against a Neutralize or Reflect creature.
	if not isScroll and target.Keywords.Neutralize and not target.NeutralizeSpent then
		target.NeutralizeSpent = true
		note = "neutralized"
		damage = 0
	elseif not isScroll and target.Keywords.Reflect and not target.ReflectSpent then
		target.ReflectSpent = true
		note = "reflected"
		reflected = damage
		damage = 0
	end

	target.DamageTaken += damage

	table.insert(log, {
		Striker = striker.CardId,
		Target = target.CardId,
		Damage = damage,
		Reflected = reflected,
		Scroll = isScroll or nil,
		Note = note,
	})

	return reflected
end

-- === Outcome ================================================================

-- Damage lands on temporary battle HP first, then on the creature's own
-- health. The pool is the same either way so survival is unaffected; what this
-- decides is how much damage a survivor CARRIES, which is the number that has
-- to still make sense after the battle ends.
local function persistentHPAfter(combatant)
	local absorbed = math.min(combatant.DamageTaken, combatant.TemporaryHP + combatant.ItemHP)
	local throughToHealth = combatant.DamageTaken - absorbed
	return math.max(combatant.PersistentHP - throughToHealth, 0)
end

local function clearBattle()
	_battle = nil
end

local function finishBattle()
	local battle = _battle
	local attacker, defender = battle.AttackerCombatant, battle.DefenderCombatant
	local tileId = battle.TileId

	local attackerDead = isDestroyed(attacker)
	local defenderDead = isDestroyed(defender)

	local outcome
	local tollOwed = false

	if defenderDead and not attackerDead then
		outcome = Enums.BattleOutcome.AttackerTakesTerritory
	elseif attackerDead and not defenderDead then
		outcome = Enums.BattleOutcome.DefenderHolds
		tollOwed = true
	elseif attackerDead and defenderDead then
		outcome = Enums.BattleOutcome.BothDestroyed
	else
		outcome = Enums.BattleOutcome.BothSurvive
		tollOwed = true
	end

	-- Apply the outcome to persistent state.
	if outcome == Enums.BattleOutcome.AttackerTakesTerritory then
		local state = newCreatureState(attacker.CardId, attacker.UserId, attacker.InstanceId)
		state.CurrentHP = persistentHPAfter(attacker)
		if attacker.Keywords.Regenerate then
			state.CurrentHP = maxHP(state)
		end
		_defenders[tileId] = state
		_territory.SetOwner(tileId, attacker.UserId)
		BattleService.TileClaimed:Fire(tileId, attacker.UserId, attacker.CardId)

	elseif outcome == Enums.BattleOutcome.DefenderHolds then
		defender.State.CurrentHP = persistentHPAfter(defender)
		if defender.Keywords.Regenerate then
			defender.State.CurrentHP = maxHP(defender.State)
		end

	elseif outcome == Enums.BattleOutcome.BothDestroyed then
		_defenders[tileId] = nil
		_territory.SetOwner(tileId, nil)

	else -- BothSurvive
		defender.State.CurrentHP = persistentHPAfter(defender)
		if defender.Keywords.Regenerate then
			defender.State.CurrentHP = maxHP(defender.State)
		end
		-- The invader failed to take the land and returns to hand at full
		-- card health: it is a card again, not a wounded creature.
		if _deck then
			_deck.ReturnToHand(attacker.UserId, attacker.CardId)
		end
	end

	local result = {
		Status = "Resolved",
		Outcome = outcome,
		TileId = tileId,
		TollOwed = tollOwed,
		AttackerUserId = attacker.UserId,
		DefenderUserId = defender.UserId,
		AttackerDestroyed = attackerDead,
		DefenderDestroyed = defenderDead,
		Log = battle.Log,
	}

	clearBattle()
	BattleService.BattleResolved:Fire(result)
	return ActionResult.ok(result)
end

local function runExchange()
	local battle = _battle
	local attacker, defender = battle.AttackerCombatant, battle.DefenderCombatant

	local attackerRank = SPEED_RANK[attacker.Speed]
	local defenderRank = SPEED_RANK[defender.Speed]

	-- One comparison covers the entire First/Normal/Last matrix, including a
	-- faster DEFENDER. On a tie the invader strikes first.
	local attackerStrikesFirst = attackerRank >= defenderRank

	local first = attackerStrikesFirst and attacker or defender
	local second = attackerStrikesFirst and defender or attacker

	local reflected = resolveStrike(first, second, battle.Log)
	if reflected > 0 then
		first.DamageTaken += reflected
	end

	-- A destroyed creature does not counterattack.
	if not isDestroyed(second) and not isDestroyed(first) then
		local back = resolveStrike(second, first, battle.Log)
		if back > 0 then
			second.DamageTaken += back
		end
	end

	return finishBattle()
end

-- === Claiming an empty territory ============================================

function BattleService.SummonCreature(userId, instanceId, tileId)
	local instance = _deck and _deck.GetInstance(userId, instanceId)
	if instance == nil then
		return ActionResult.fail(Enums.RejectReason.CardNotInHand, "that card is not in your hand")
	end

	local card = _card.GetCard(instance.CardId)
	if card == nil or card.CardType ~= "Creature" then
		return ActionResult.fail(Enums.RejectReason.InvalidCard, "only creatures can be summoned")
	end

	local tile = _territory.GetTerritory(tileId)
	if tile == nil then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "this territory cannot be claimed")
	end
	if tile.Owner ~= nil then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "already owned — invade it instead")
	end

	-- Payment last, after every other rejection, so a refused claim is free.
	local paid, reason = _economy.SpendMagic(userId, card.Cost)
	if not paid then
		return ActionResult.fail(Enums.RejectReason.InsufficientMagic, tostring(reason))
	end

	_deck.PlayInstance(userId, instanceId)

	-- Defender state before SetOwner, so a listener repainting the tile sees
	-- the creature on its very first refresh rather than one refresh later.
	_defenders[tileId] = newCreatureState(instance.CardId, userId, instanceId)
	_territory.SetOwner(tileId, userId)
	BattleService.TileClaimed:Fire(tileId, userId, instance.CardId)

	return ActionResult.ok({ TileId = tileId, CardId = instance.CardId })
end

-- === Invasion ===============================================================

function BattleService.GetPendingBattle()
	if _battle == nil then
		return nil
	end
	return {
		Status = _battle.Status,
		TileId = _battle.TileId,
		AttackerUserId = _battle.AttackerUserId,
		DefenderUserId = _battle.DefenderUserId,
		AttackerCardId = _battle.AttackerCardId,
		DefenderCardId = _battle.DefenderState.CardId,
		AttackerItemCardId = _battle.AttackerItemCardId,
	}
end

function BattleService.GetDefenderUserId()
	return _battle and _battle.DefenderUserId or nil
end

function BattleService.BeginInvasion(userId, instanceId, tileId)
	if _battle ~= nil then
		return ActionResult.fail(Enums.RejectReason.IllegalAction, "a battle is already in progress")
	end

	local instance = _deck and _deck.GetInstance(userId, instanceId)
	if instance == nil then
		return ActionResult.fail(Enums.RejectReason.CardNotInHand, "that card is not in your hand")
	end

	local card = _card.GetCard(instance.CardId)
	if card == nil or card.CardType ~= "Creature" then
		return ActionResult.fail(Enums.RejectReason.InvalidCard, "only creatures can invade")
	end

	local tile = _territory.GetTerritory(tileId)
	if tile == nil or tile.Owner == nil then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "nothing to invade here")
	end
	if tile.Owner == userId then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "you already own this territory")
	end

	local defenderState = _defenders[tileId]
	if defenderState == nil then
		return ActionResult.fail(Enums.RejectReason.RuleViolation, "this territory has no defender on record")
	end

	local paid, reason = _economy.SpendMagic(userId, card.Cost)
	if not paid then
		return ActionResult.fail(Enums.RejectReason.InsufficientMagic, tostring(reason))
	end

	-- The card leaves hand into a pending attacker slot. It is committed now:
	-- backing out after seeing the defender's item would be the whole game.
	_deck.PlayInstance(userId, instanceId)

	_battle = {
		Status = "AwaitingAttackerItem",
		TileId = tileId,
		AttackerUserId = userId,
		AttackerCardId = instance.CardId,
		AttackerInstanceId = instanceId,
		AttackerItemCardId = nil,
		DefenderUserId = tile.Owner,
		DefenderState = defenderState,
		Log = {},
	}

	BattleService.BattleStarted:Fire(BattleService.GetPendingBattle())
	return ActionResult.ok(BattleService.GetPendingBattle())
end

-- Shared validation for both item windows. `nil` means "No Item", which is
-- always legal — declining is a choice, not a failure.
local function commitItem(userId, instanceId, expectedStatus, expectedUserId, creatureCardId)
	if _battle == nil then
		return nil, ActionResult.fail(Enums.RejectReason.IllegalAction, "no battle in progress")
	end
	if _battle.Status ~= expectedStatus then
		return nil, ActionResult.fail(
			Enums.RejectReason.WrongPhase,
			string.format("battle is at %s", _battle.Status)
		)
	end
	if userId ~= expectedUserId then
		return nil, ActionResult.fail(Enums.RejectReason.NotAParticipant, "this choice is not yours")
	end

	if instanceId == nil then
		return nil, nil -- declined
	end

	local instance = _deck and _deck.GetInstance(userId, instanceId)
	if instance == nil then
		return nil, ActionResult.fail(Enums.RejectReason.CardNotInHand, "that card is not in your hand")
	end

	local itemCard = _card.GetCard(instance.CardId)
	local creatureCard = _card.GetCard(creatureCardId)

	local isCreatureItem = itemCard.CardType == "Creature"
	if isCreatureItem and not hasKeyword(creatureCard, "Support") then
		-- Only a Support creature may bring a creature to a fight.
		return nil, ActionResult.fail(
			Enums.RejectReason.RuleViolation,
			"only a creature with Support can use a creature as its item"
		)
	end
	if not isCreatureItem and itemCard.CardType ~= "Item" then
		-- Spells are explicitly not selectable in a battle window.
		return nil, ActionResult.fail(
			Enums.RejectReason.RuleViolation,
			itemCard.CardType .. " cards cannot be used as battle items"
		)
	end

	local paid, reason = _economy.SpendMagic(userId, itemCard.Cost)
	if not paid then
		return nil, ActionResult.fail(Enums.RejectReason.InsufficientMagic, tostring(reason))
	end

	_deck.PlayInstance(userId, instanceId)
	return instance.CardId, nil
end

-- Every ST modifier that is not the card or its item, folded in one place.
-- Both combatants run the same hook, which is how a match-wide shift reaches
-- the defender without GlobalAttackShift needing to know a battle has sides.
-- The legacy `_attackBuffs` table seeds the value so a caller that bypassed
-- StatusService still works; nothing in the shipped code does.
local function battleSTBonus(userId, isAttacker, tileId)
	local seed = 0
	if isAttacker then
		seed = _attackBuffs[userId] or 0
		_attackBuffs[userId] = nil
	end
	if _status == nil then
		return seed
	end
	return _status.RunHook(Enums.TimingHook.BeforeBattleStats, {
		UserId = userId,
		IsAttacker = isAttacker,
		NodeId = tileId,
	}, seed) or 0
end

function BattleService.ChooseAttackerItem(userId, instanceId)
	local cardId, failure = commitItem(
		userId, instanceId,
		"AwaitingAttackerItem", _battle and _battle.AttackerUserId,
		_battle and _battle.AttackerCardId
	)
	if failure then
		return failure
	end

	_battle.AttackerItemCardId = cardId
	_battle.Status = "AwaitingDefenderItem"
	return ActionResult.ok(BattleService.GetPendingBattle())
end

function BattleService.ChooseDefenderItem(userId, instanceId)
	local cardId, failure = commitItem(
		userId, instanceId,
		"AwaitingDefenderItem", _battle and _battle.DefenderUserId,
		_battle and _battle.DefenderState.CardId
	)
	if failure then
		return failure
	end

	local battle = _battle
	local tileId = battle.TileId

	local attacker = buildCombatant({
		UserId = battle.AttackerUserId,
		CardId = battle.AttackerCardId,
		InstanceId = battle.AttackerInstanceId,
		ItemCardId = battle.AttackerItemCardId,
		BonusST = battleSTBonus(battle.AttackerUserId, true, tileId),
	})

	local defenderState = battle.DefenderState
	local defender = buildCombatant({
		UserId = battle.DefenderUserId,
		CardId = defenderState.CardId,
		ItemCardId = cardId,
		BaseST = defenderState.BaseST
			+ defenderState.BonusST
			+ battleSTBonus(battle.DefenderUserId, false, tileId),
		CurrentHP = defenderState.CurrentHP,
	})
	defender.State = defenderState

	-- The land bonus belongs to whoever holds the territory, and only if the
	-- attacker cannot ignore it.
	if not attacker.Keywords.Penetration and not attacker.IsScrollAttack then
		defender.TemporaryHP = landBonusFor(defenderState, tileId)
	end

	battle.AttackerCombatant = attacker
	battle.DefenderCombatant = defender
	battle.Status = "Resolving"

	return runExchange()
end

-- === Effects other systems apply ============================================

-- Retained so an older caller does not break, but the ST bonus is a status
-- now: StatusDefinitions.AttackBoost on the caster, resolved through the
-- BeforeBattleStats hook with everything else that modifies a combatant. The
-- private table this used to write into was the exact "unrelated boolean per
-- effect" shape StatusService exists to replace.
function BattleService.QueueAttackBuff(userId, bonusST)
	if _status ~= nil then
		_status.Apply({
			Kind = "AttackBoost",
			TargetId = userId,
			OwnerPlayerId = userId,
			Value = bonusST,
		})
		return
	end
	_attackBuffs[userId] = (_attackBuffs[userId] or 0) + bonusST
end

-- A permanent HP increase on a creature you are defending with. Raises MHP as
-- well as current health, unlike the land bonus, which is why it lives on the
-- creature state and the land bonus does not.
function BattleService.ApplyDefenderHPBuff(userId, tileId, bonusHP)
	local state = _defenders[tileId]
	if state == nil then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "no defending creature here")
	end
	if state.OwnerUserId ~= userId then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "you can only equip your own defender")
	end

	state.BonusMHP += bonusHP
	state.CurrentHP += bonusHP
	BattleService.DefenderBuffed:Fire(tileId, state.CurrentHP)
	return ActionResult.ok({ TileId = tileId, CurrentHP = state.CurrentHP })
end

-- Damage to a defender from OUTSIDE a battle — poison, a hostile territory
-- effect. It goes through this module rather than a status writing to the
-- creature table directly, for the same reason QueueAttackBuff exists: this is
-- the sole owner of defender state, and a caller that mutates it privately
-- also skips the signal the board repaints on.
--
-- Floors at 1 unless the caller explicitly allows a kill. A creature dying
-- outside a battle would leave a territory owned by nobody, and no other code
-- path expects that state.
function BattleService.DamageDefender(tileId, amount, canKill)
	local state = _defenders[tileId]
	if state == nil then
		return nil
	end

	local floor = canKill and 0 or 1
	state.CurrentHP = math.max(state.CurrentHP - (amount or 0), floor)
	BattleService.DefenderBuffed:Fire(tileId, state.CurrentHP)
	return state.CurrentHP
end

return BattleService

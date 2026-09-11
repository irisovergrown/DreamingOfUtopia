--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > EffectPrimitives (ModuleScript)

	Purpose:
		The vocabulary a card's effects are written in.

		The brief is explicit that there must be no module-per-card and no
		`if card.Name == ...` chain. That needs a closed set of reusable verbs,
		so a card says what it does as DATA:

			Effects = {
				{ Primitive = "ForceRoll", Value = 6, Target = "ChosenPlayer" },
				{ Primitive = "Draw", Value = 2, Target = "Caster" },
			}

		and resolving a card is looking each verb up here. Adding a card that
		draws three needs no code at all. Adding a card that does something
		genuinely new adds one primitive, used by every later card that wants
		it.

	Targeting:
		A primitive declares who it can act on, and the resolver turns that
		into a concrete id. Keeping targeting out of the primitives means a
		card can retarget an existing verb without the verb knowing.

			Caster         the player who played the card
			ChosenPlayer   a player named in the request, validated as a
			               participant
			ChosenTerritory a node id named in the request
			CurrentTerritory where the caster is standing
			Global         no target

	Every primitive returns an ActionResult. A primitive that cannot act must
	fail rather than silently doing nothing, because CardEffectService refunds
	the card's cost on failure — a spell that quietly fizzles while taking the
	Magic is worse than one that is refused.

	Public API:
		EffectPrimitives.Init(deps)
		EffectPrimitives.Get(name) -> primitive or nil
		EffectPrimitives.Run(name, effect, context) -> ActionResult
		EffectPrimitives.GetNames() -> sorted array
		EffectPrimitives.RequiredTargetOf(name) -> target kind or nil
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local ActionResult = require(ReplicatedStorage.Shared.ActionResult)

local EffectPrimitives = {}

local _deps = {}

function EffectPrimitives.Init(deps)
	_deps = deps or {}
end

-- Each entry: Target says what the resolver must supply, Run does the work.
local primitives = {}

primitives.GainMagic = {
	Target = "Caster",
	Run = function(effect, context)
		_deps.Economy.AddMagic(context.TargetUserId, effect.Value or 0)
		return ActionResult.ok({ Amount = effect.Value })
	end,
}

primitives.LoseMagic = {
	Target = "ChosenPlayer",
	Run = function(effect, context)
		-- A mandatory loss, so it takes what is there rather than refusing.
		local payment = _deps.Economy.RequirePayment(context.TargetUserId, effect.Value or 0)
		return ActionResult.ok({ Paid = payment.Paid, Shortfall = payment.Shortfall })
	end,
}

primitives.Draw = {
	Target = "Caster",
	Run = function(effect, context)
		local drawn = _deps.Deck.Draw(context.TargetUserId, effect.Value or 1)
		-- A short draw is legal — an exhausted book and discard is a real
		-- state — so this reports the count rather than failing.
		return ActionResult.ok({ Drawn = #drawn })
	end,
}

-- The Holy Word family. Applies a status rather than writing a field, so the
-- forced value goes through the same ModifyRoll pipeline as everything else
-- and can itself be modified by a haste applied afterwards.
primitives.ForceRoll = {
	Target = "ChosenPlayer",
	Run = function(effect, context)
		return _deps.Status.Apply({
			Kind = "ForcedRoll",
			TargetId = context.TargetUserId,
			OwnerPlayerId = context.CasterUserId,
			SourceCardId = context.CardId,
			Value = effect.Value,
		})
	end,
}

primitives.ApplyStatus = {
	Target = "ChosenPlayer",
	Run = function(effect, context)
		return _deps.Status.Apply({
			Kind = effect.Status,
			TargetType = effect.TargetType,
			TargetId = context.TargetUserId,
			OwnerPlayerId = context.CasterUserId,
			SourceCardId = context.CardId,
			Value = effect.Value,
			RemainingDuration = effect.Turns,
		})
	end,
}

primitives.ApplyCreatureStatus = {
	Target = "ChosenTerritory",
	Run = function(effect, context)
		local defender = _deps.Battle.GetDefender(context.TargetNodeId)
		if defender == nil then
			return ActionResult.fail(Enums.RejectReason.InvalidTarget, "no creature is defending there")
		end
		return _deps.Status.Apply({
			Kind = effect.Status,
			TargetType = Enums.StatusTarget.Creature,
			TargetId = context.TargetNodeId,
			OwnerPlayerId = context.CasterUserId,
			-- Counts down on the DEFENDER's turns, not the caster's: the status
			-- lives on their creature even though they did not apply it.
			ScopeUserId = defender.OwnerUserId,
			SourceCardId = context.CardId,
			Value = effect.Value,
			RemainingDuration = effect.Turns,
		})
	end,
}

primitives.ApplyGlobalStatus = {
	Target = "Global",
	Run = function(effect, context)
		return _deps.Status.Apply({
			Kind = effect.Status,
			TargetType = Enums.StatusTarget.Global,
			OwnerPlayerId = context.CasterUserId,
			SourceCardId = context.CardId,
			Value = effect.Value,
			RemainingDuration = effect.Turns,
		})
	end,
}

-- Signal Boost. Now a status on the caster rather than a private table inside
-- BattleService, so it is inspectable, expires on its own terms, and is not a
-- special case the battle engine has to remember.
primitives.BoostNextAttack = {
	Target = "Caster",
	Run = function(effect, context)
		return _deps.Status.Apply({
			Kind = "AttackBoost",
			TargetId = context.TargetUserId,
			OwnerPlayerId = context.CasterUserId,
			SourceCardId = context.CardId,
			Value = effect.Value,
		})
	end,
}

-- Ninth Signal Charm. A permanent HP increase on a creature you are already
-- defending with, which is why it validates ownership rather than just
-- presence.
primitives.BuffDefenderHP = {
	Target = "ChosenTerritory",
	Run = function(effect, context)
		return _deps.Battle.ApplyDefenderHPBuff(
			context.CasterUserId,
			context.TargetNodeId,
			effect.Value or 0
		)
	end,
}

-- Relocation with no walking. The cause travels with it because castle and lap
-- effects are NOT universal across movement kinds: a recall to the castle is
-- not the same as walking across it.
primitives.Teleport = {
	Target = "Caster",
	Run = function(effect, context)
		local destination = effect.NodeId
		if destination == "Castle" then
			destination = _deps.Graph.GetCastleNodeIds()[1]
		end
		if destination == nil then
			return ActionResult.fail(Enums.RejectReason.InvalidTarget, "no destination")
		end
		return _deps.Movement.TeleportTo(
			context.TargetUserId,
			destination,
			Enums.MovementCause.Recall
		)
	end,
}

function EffectPrimitives.Get(name)
	return primitives[name]
end

function EffectPrimitives.RequiredTargetOf(name)
	local primitive = primitives[name]
	return primitive and primitive.Target or nil
end

function EffectPrimitives.GetNames()
	local names = {}
	for name in pairs(primitives) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function EffectPrimitives.Run(name, effect, context)
	local primitive = primitives[name]
	if primitive == nil then
		return ActionResult.fail(
			Enums.RejectReason.IllegalAction,
			string.format("'%s' is not an effect primitive", tostring(name))
		)
	end
	return primitive.Run(effect, context)
end

return EffectPrimitives

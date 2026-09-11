--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > CardEffectService (ModuleScript)

	Purpose:
		Resolving a played card by running its declared effects.

		This used to be two hardcoded behaviours — Signal Boost and Ninth
		Signal Charm, each with its own branch. That is exactly the shape the
		brief forbids, and it does not survive contact with a real card list:
		the third card that boosts an attack would have been a third branch
		doing the same thing.

		Now a card carries an `Effects` list written in EffectPrimitives'
		vocabulary, and resolving it means running each entry. Adding a card
		that draws two and forces a roll needs no code here at all.

	Payment and atomicity:
		Cost is charged first, because a spell that resolves before it is paid
		for can be cast without the Magic. If ANY effect then fails, the cost
		is refunded and the card is not consumed — the brief's "invalid
		targets do not silently eat resources".

		This is a refund rather than a true transaction: effects that already
		succeeded are not rolled back. That is a deliberate limit, and the
		reason primitives validate before they mutate. A card whose second
		effect can fail after its first has changed the board would need real
		rollback, and none of the current cards can.

	Targeting:
		The card declares a target KIND per effect; the request supplies the
		concrete id. Resolution happens here, once, so primitives never parse
		player input and a malformed target is refused before anything runs.

	Public API:
		CardEffectService.Init(deps)
		CardEffectService.CanPlay(userId, cardId) -> ActionResult
		CardEffectService.GetRequiredTargets(cardId) -> array of target kinds
		CardEffectService.Resolve(userId, instanceId, request) -> ActionResult

		`request` supplies targets:
			{ TargetUserId = ..., TargetNodeId = ... }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local ActionResult = require(ReplicatedStorage.Shared.ActionResult)
local EffectPrimitives = require(ServerScriptService.Systems.EffectPrimitives)

local CardEffectService = {}

local _deps = {}

function CardEffectService.Init(deps)
	_deps = deps or {}
end

function CardEffectService.GetRequiredTargets(cardId)
	local card = _deps.Card.GetCard(cardId)
	local kinds = {}
	for _, effect in ipairs(card and card.Effects or {}) do
		local kind = effect.Target or EffectPrimitives.RequiredTargetOf(effect.Primitive)
		if kind ~= nil and kind ~= "Caster" and kind ~= "Global" then
			table.insert(kinds, kind)
		end
	end
	return kinds
end

function CardEffectService.CanPlay(userId, cardId)
	local card = _deps.Card.GetCard(cardId)
	if card == nil then
		return ActionResult.fail(Enums.RejectReason.InvalidCard, "unknown card")
	end
	if card.Effects == nil or #card.Effects == 0 then
		return ActionResult.fail(
			Enums.RejectReason.InvalidCard,
			card.Name .. " has no effects to resolve"
		)
	end
	if (_deps.Economy.GetBalance(userId) or 0) < card.Cost then
		return ActionResult.fail(Enums.RejectReason.InsufficientMagic, "Not enough Magic")
	end
	return ActionResult.ok({ CardId = cardId })
end

-- Turns a declared target kind into a concrete id, validating player input on
-- the way. Returns nil plus a failure when the request cannot satisfy it.
local function resolveTarget(kind, userId, request)
	if kind == "Caster" then
		return { TargetUserId = userId }
	elseif kind == "Global" then
		return {}
	elseif kind == "ChosenPlayer" then
		local targetUserId = request.TargetUserId or userId
		if _deps.IsParticipant and not _deps.IsParticipant(targetUserId) then
			return nil, ActionResult.fail(Enums.RejectReason.InvalidTarget, "not a player in this match")
		end
		return { TargetUserId = targetUserId }
	elseif kind == "CurrentTerritory" then
		return { TargetNodeId = _deps.Movement.GetCurrentNodeId(userId) }
	elseif kind == "ChosenTerritory" then
		local nodeId = request.TargetNodeId
		if typeof(nodeId) ~= "string" or _deps.Territory.GetTerritory(nodeId) == nil then
			return nil, ActionResult.fail(Enums.RejectReason.InvalidTarget, "choose a territory")
		end
		return { TargetNodeId = nodeId }
	end

	return nil, ActionResult.fail(Enums.RejectReason.IllegalAction, "unknown target kind " .. tostring(kind))
end

function CardEffectService.Resolve(userId, instanceId, request)
	request = request or {}

	local instance = _deps.Deck.GetInstance(userId, instanceId)
	if instance == nil then
		return ActionResult.fail(Enums.RejectReason.CardNotInHand, "that card is not in your hand")
	end

	local playable = CardEffectService.CanPlay(userId, instance.CardId)
	if not playable.Ok then
		return playable
	end

	local card = _deps.Card.GetCard(instance.CardId)

	-- Paid first: a spell that resolves before it is paid for can be cast
	-- without the Magic.
	local paid, reason = _deps.Economy.SpendMagic(userId, card.Cost)
	if not paid then
		return ActionResult.fail(Enums.RejectReason.InsufficientMagic, tostring(reason))
	end

	local outcomes = {}
	for index, effect in ipairs(card.Effects) do
		local kind = effect.Target or EffectPrimitives.RequiredTargetOf(effect.Primitive)
		local target, targetFailure = resolveTarget(kind, userId, request)

		if target == nil then
			_deps.Economy.AddMagic(userId, card.Cost)
			return targetFailure
		end

		local context = {
			CasterUserId = userId,
			CardId = instance.CardId,
			TargetUserId = target.TargetUserId,
			TargetNodeId = target.TargetNodeId,
		}

		local result = EffectPrimitives.Run(effect.Primitive, effect, context)
		if not result.Ok then
			-- Refunded and not consumed. Effects already applied are NOT rolled
			-- back; see the header for why that limit is acceptable here.
			_deps.Economy.AddMagic(userId, card.Cost)
			return ActionResult.fail(
				result.Code,
				string.format("%s (effect %d of %s)", result.Message, index, card.Name)
			)
		end

		table.insert(outcomes, { Primitive = effect.Primitive, Payload = result.Payload })
	end

	-- Consumed only once every effect has succeeded.
	_deps.Deck.PlayInstance(userId, instanceId)

	if _deps.Log then
		_deps.Log.Append("CardResolved", {
			UserId = userId,
			CardId = instance.CardId,
			Name = card.Name,
			Effects = #outcomes,
		})
	end

	return ActionResult.ok({
		CardId = instance.CardId,
		Name = card.Name,
		Outcomes = outcomes,
	})
end

return CardEffectService

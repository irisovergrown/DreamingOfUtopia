--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > ActionValidator (ModuleScript)

	Purpose:
		Decides whether a request is admissible in the current phase, and
		answers the inverse question the client needs: what may I do right
		now? One table serves both, so the buttons a player sees and the
		requests the server accepts can never disagree — they are derived
		from the same source.

		This is the "only legal actions are selectable, disabled choices show
		a useful reason" requirement, made structural. A client that offers
		an action the server would refuse is a UI bug today; here it is
		impossible by construction.

		Rejections are typed (Enums.RejectReason), never free strings, so the
		client can render them and tests can assert on them.

	Who acts:
		Each phase names its expected Actor, and it is NOT always the active
		player. DefenderItemChoice belongs to the DEFENDER — Saga's battle
		order has the invader commit an item first, then the defender choose
		knowing what was committed. Modelling the actor per phase rather than
		assuming "active player" is what keeps that from becoming a special
		case buried in battle code.

		Phases with Actor = None are server-driven: they resolve without
		input, and every player request during them is refused. That is most
		of the machine, and saying so explicitly means a stray request during
		resolution cannot slip through on a technicality.

	Scope note (Milestone 1):
		This validates ADMISSIBILITY — right phase, right actor, known
		intent. It does not validate the action's own rules (can you afford
		this card, is that tile yours, is the target adjacent). Those need
		the systems that own that state and are checked at the point of
		execution, where the payment happens.

	Public API:
		ActionValidator.getExpectedActor(phase) -> Enums.Actor
		ActionValidator.getLegalIntents(phase) -> array of Enums.Intent
		ActionValidator.isIntentLegalInPhase(phase, intent) -> boolean
		ActionValidator.validate(context, intent) -> ActionResult
		ActionValidator.getLegalIntentsForPlayer(context, userId) -> array

		context = {
			Phase          = Enums.Phase,
			ActivePlayerId = userId or nil,
			DefenderId     = userId or nil,   -- only during a battle
			Participants   = { [userId] = true, ... } or nil,
		}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local ActionResult = require(ReplicatedStorage.Shared.ActionResult)

local Phase = Enums.Phase
local Intent = Enums.Intent
local Actor = Enums.Actor

local ActionValidator = {}

-- The single source of truth for "who may do what, when". Phases absent from
-- this table are server-driven; see DEFAULT_RULE below.
local PhaseRules = {
	[Phase.HandOverflowDiscard] = {
		Actor = Actor.ActivePlayer,
		Intents = { Intent.DiscardToHandLimit },
	},
	[Phase.SpellChoice] = {
		Actor = Actor.ActivePlayer,
		Intents = { Intent.CastSpell, Intent.SkipSpell },
	},
	[Phase.SpellTargetChoice] = {
		Actor = Actor.ActivePlayer,
		Intents = { Intent.ChooseSpellTarget },
	},
	[Phase.RollReady] = {
		Actor = Actor.ActivePlayer,
		Intents = { Intent.Roll },
	},
	[Phase.JunctionChoice] = {
		Actor = Actor.ActivePlayer,
		Intents = { Intent.ChooseJunction },
	},
	[Phase.PassEffectChoice] = {
		Actor = Actor.ActivePlayer,
		Intents = { Intent.ChoosePassEffect },
	},
	[Phase.LandingActionChoice] = {
		Actor = Actor.ActivePlayer,
		Intents = {
			Intent.ChooseLandingAction,
			Intent.ChooseSummon,
			Intent.ChooseTerritoryCommand,
			Intent.PayToll,
			Intent.EndTurn,
		},
	},
	[Phase.SummonChoice] = {
		Actor = Actor.ActivePlayer,
		Intents = { Intent.ChooseSummon },
	},
	[Phase.AttackerItemChoice] = {
		Actor = Actor.ActivePlayer,
		Intents = { Intent.ChooseBattleItem },
	},
	-- The defender, not the active player. This asymmetry is the whole
	-- reason Actor is modelled per phase.
	[Phase.DefenderItemChoice] = {
		Actor = Actor.Defender,
		Intents = { Intent.ChooseBattleItem },
	},
	[Phase.TollResolution] = {
		Actor = Actor.ActivePlayer,
		Intents = { Intent.PayToll },
	},
	[Phase.Liquidation] = {
		Actor = Actor.ActivePlayer,
		Intents = { Intent.ChooseLiquidation },
	},
	[Phase.TerritoryCommandChoice] = {
		Actor = Actor.ActivePlayer,
		Intents = { Intent.ChooseTerritoryCommand, Intent.EndTurn },
	},
}

-- Everything not listed above resolves without player input.
local DEFAULT_RULE = table.freeze({ Actor = Actor.None, Intents = table.freeze({}) })

for _, rule in pairs(PhaseRules) do
	table.freeze(rule.Intents)
	table.freeze(rule)
end
table.freeze(PhaseRules)

local function ruleFor(phase)
	return PhaseRules[phase] or DEFAULT_RULE
end

function ActionValidator.getExpectedActor(phase)
	return ruleFor(phase).Actor
end

function ActionValidator.getLegalIntents(phase)
	local copy = {}
	for index, intent in ipairs(ruleFor(phase).Intents) do
		copy[index] = intent
	end
	return copy
end

function ActionValidator.isIntentLegalInPhase(phase, intent)
	for _, candidate in ipairs(ruleFor(phase).Intents) do
		if candidate == intent then
			return true
		end
	end
	return false
end

-- Resolves which specific user is entitled to act, given the phase's Actor
-- and the current match context. Returns nil when nobody may act.
local function entitledUserId(context, actor)
	if actor == Actor.ActivePlayer then
		return context.ActivePlayerId
	elseif actor == Actor.Defender then
		return context.DefenderId
	end
	return nil
end

function ActionValidator.validate(context, intent)
	if type(context) ~= "table" then
		return ActionResult.fail(Enums.RejectReason.IllegalAction, "validate needs a context table")
	end

	local phase = context.Phase
	if not Enums.isValid(Phase, phase) then
		return ActionResult.fail(Enums.RejectReason.IllegalAction, string.format("'%s' is not a phase", tostring(phase)))
	end

	if not Enums.isValid(Intent, intent) then
		return ActionResult.fail(Enums.RejectReason.IllegalAction, string.format("'%s' is not an intent", tostring(intent)))
	end

	local rule = ruleFor(phase)

	if rule.Actor == Actor.None then
		return ActionResult.fail(
			Enums.RejectReason.WrongPhase,
			string.format("%s resolves without player input", phase)
		)
	end

	if not ActionValidator.isIntentLegalInPhase(phase, intent) then
		return ActionResult.fail(
			Enums.RejectReason.WrongPhase,
			string.format("%s is not available during %s", intent, phase)
		)
	end

	-- Participation is checked before entitlement so a spectator gets
	-- "you are not in this match" rather than the misleading "not your turn".
	if context.Participants ~= nil and not context.Participants[context.RequesterId] then
		return ActionResult.fail(Enums.RejectReason.NotAParticipant, "not a participant in this match")
	end

	if rule.Actor ~= Actor.AnyParticipant then
		local entitled = entitledUserId(context, rule.Actor)
		if entitled == nil then
			return ActionResult.fail(
				Enums.RejectReason.IllegalAction,
				string.format("%s expects the %s, but there is none", phase, rule.Actor)
			)
		end
		if entitled ~= context.RequesterId then
			local code = rule.Actor == Actor.Defender
					and Enums.RejectReason.NotAParticipant
				or Enums.RejectReason.NotYourTurn
			return ActionResult.fail(
				code,
				string.format("%s is for the %s", phase, rule.Actor)
			)
		end
	end

	return ActionResult.ok({ Phase = phase, Intent = intent, Actor = rule.Actor })
end

-- What this specific player may do right now. The client renders exactly
-- this, so its buttons cannot drift from what the server will accept.
function ActionValidator.getLegalIntentsForPlayer(context, userId)
	if type(context) ~= "table" or not Enums.isValid(Phase, context.Phase) then
		return {}
	end

	local rule = ruleFor(context.Phase)
	if rule.Actor == Actor.None then
		return {}
	end

	if rule.Actor ~= Actor.AnyParticipant and entitledUserId(context, rule.Actor) ~= userId then
		return {}
	end

	if context.Participants ~= nil and not context.Participants[userId] then
		return {}
	end

	return ActionValidator.getLegalIntents(context.Phase)
end

return ActionValidator

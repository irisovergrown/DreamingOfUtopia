--[[
	Script — server, bootstrap / composition root.

	Studio placement:
		ServerScriptService > Main (Script)

	Purpose:
		Starts the match and drives the turn through MatchOrchestrator.

		This was 574 lines doing three unrelated jobs. Presentation moved to
		BoardVisualService, request validation to ActionValidator, and state
		shaping to SnapshotService. What remains is composition and the turn
		driver: the sequence of phases a turn passes through, and what each
		one does.

		Init order is now explicit and asserted rather than implied. The old
		version called four Init functions in an order that silently mattered
		— EconomyService.Init subscribed to MovementService, MatchService.Init
		subscribed to EconomyService — so reordering them would have severed
		the subscriptions with no error anywhere.

	Turn flow (Milestone 1):
		TurnStart -> Draw -> SpellChoice -> RollReady
		  ... player rolls ...
		DiceResolution -> Movement -> LandingResolution -> LandingActionChoice
		  ... player acts or ends turn ...
		TurnEnd -> VictoryCheck -> (RoundEnd) -> TurnStart for the next player

		Draw and SpellChoice pass straight through: there is no book and no
		hand until Milestone 3. They are traversed rather than skipped on
		purpose, so the phases exist, are logged, and are already in the
		right place when the deck arrives.

	Authority:
		Every request enters through one SubmitIntent handler and passes the
		same three checks in order — orchestrator admissibility (right
		player, fresh sequence), expected-phase agreement, then
		ActionValidator (right phase for this intent, right actor). Only then
		does it reach a service. The acting player always comes from
		OnServerEvent's own first argument, never the payload.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RulesConfig = require(ReplicatedStorage.Shared.RulesConfig)

local Systems = ServerScriptService.Systems
local MatchLogService = require(Systems.MatchLogService)
local MatchOrchestrator = require(Systems.MatchOrchestrator)
local ActionValidator = require(Systems.ActionValidator)
local SnapshotService = require(Systems.SnapshotService)
local TerritoryService = require(Systems.TerritoryService)
local BoardGraphService = require(Systems.BoardGraphService)
local BoardVisualService = require(Systems.BoardVisualService)
local LapService = require(Systems.LapService)
local RandomService = require(Systems.RandomService)
local MovementService = require(Systems.MovementService)
local CardService = require(Systems.CardService)
local EconomyService = require(Systems.EconomyService)
local BattleService = require(Systems.BattleService)
local ValuationService = require(Systems.ValuationService)
local VictoryService = require(Systems.VictoryService)
local CardEffectService = require(Systems.CardEffectService)
local EffectPrimitives = require(Systems.EffectPrimitives)
local StatusService = require(Systems.StatusService)
local DeckService = require(Systems.DeckService)

local Phase = Enums.Phase
local Intent = Enums.Intent

-- === Bootstrap ==============================================================
-- Ordered deliberately: state owners first, then things that subscribe to
-- them, then presentation. A comment is not enough on its own, so the
-- dependency is stated next to each call.
MatchLogService.Init()
MatchOrchestrator.Init({ Log = MatchLogService })

-- The board the match is played on. CurrentLoop describes the 16 hand-placed
-- tiles as graph data, so movement runs through the Milestone 2 resolver on
-- the board that already exists. Swapping this line for TestBoard01 loads the
-- proving board with junctions, forts and warps instead.
local ACTIVE_BOARD = require(ReplicatedStorage.Shared.BoardDefinitions.CurrentLoop)
local boardLoaded = BoardGraphService.Load(ACTIVE_BOARD)
if not boardLoaded.Ok then
	-- A malformed board cannot be played, and pretending otherwise strands a
	-- match mid-move. Fail loudly at boot instead.
	error(string.format(
		"[DreamingOfUtopia] board '%s' failed validation: %s",
		tostring(ACTIVE_BOARD.BoardId),
		table.concat(boardLoaded.Details.Errors, "; ")
	))
end

TerritoryService.Init({ Graph = BoardGraphService, Economy = EconomyService })
LapService.Init({ Graph = BoardGraphService })
-- Initialised before the systems that fold through it, so no service is ever
-- handed a nil Status and silently degrades to "no effects exist".
StatusService.Init({ Log = MatchLogService })

MovementService.Init({
	Graph = BoardGraphService,
	Lap = LapService,
	Random = RandomService.default(),
	Status = StatusService,
})
EconomyService.Init({ Territory = TerritoryService, Lap = LapService, Graph = BoardGraphService })
ValuationService.Init({ Territory = TerritoryService, Economy = EconomyService })
VictoryService.Init({ Valuation = ValuationService, Lap = LapService, Graph = BoardGraphService })
VictoryService.SetGoal(ACTIVE_BOARD.TMGoal)
DeckService.Init({ Random = RandomService.default() })
BattleService.Init({
	Territory = TerritoryService,
	Card = CardService,
	Economy = EconomyService,
	Deck = DeckService, -- battles consume and return real cards
	Status = StatusService,
})

-- The card engine: primitives are the verbs, CardEffectService reads a card's
-- Effects list and runs them. Neither knows any card by name.
EffectPrimitives.Init({
	Economy = EconomyService,
	Deck = DeckService,
	Status = StatusService,
	Battle = BattleService,
	Movement = MovementService,
	Graph = BoardGraphService,
})

CardEffectService.Init({
	Card = CardService,
	Economy = EconomyService,
	Deck = DeckService,
	Movement = MovementService,
	Territory = TerritoryService,
	Status = StatusService,
	Log = MatchLogService,
	IsParticipant = function(userId)
		for _, participantId in ipairs(MatchOrchestrator.GetParticipants()) do
			if participantId == userId then
				return true
			end
		end
		return false
	end,
})

BoardVisualService.Init({
	Territory = TerritoryService,
	Battle = BattleService,
	Card = CardService,
	Movement = MovementService,
	Graph = BoardGraphService,
})

SnapshotService.Init({
	Orchestrator = MatchOrchestrator,
	Validator = ActionValidator,
	Territory = TerritoryService,
	Valuation = ValuationService,
	Victory = VictoryService,
	Graph = BoardGraphService,
	Movement = MovementService,
	Economy = EconomyService,
	Battle = BattleService,
	Card = CardService,
	Status = StatusService,
	GetParticipants = MatchOrchestrator.GetParticipants,
	GetParticipantSet = MatchOrchestrator.GetParticipantSet,
	GetHandCount = DeckService.GetHandCount,
	-- Supplied to SnapshotService, which decides who is allowed to see the
	-- contents. It sends identities only to the hand's owner.
	GetHand = DeckService.GetHand,
	GetBookCount = DeckService.GetBookCount,
	GetDiscardCount = DeckService.GetDiscardCount,
	-- Who owes the defender's item choice, so ActionValidator can entitle
	-- them rather than the active player during that one phase.
	GetDefenderId = BattleService.GetDefenderUserId,
})

if #CollectionService:GetTagged("Tile") == 0 then
	warn("[DreamingOfUtopia] No Parts tagged 'Tile' — hand-place and tag a board before playing")
end

-- === State push =============================================================

local function pushStateTo(player)
	Remotes.StateUpdated:FireClient(player, SnapshotService.Build(player.UserId))
end

local function pushStateToAll()
	for _, player in ipairs(Players:GetPlayers()) do
		pushStateTo(player)
	end
end

local function replyTo(player, intent, sequence, result)
	Remotes.ActionResult:FireClient(player, {
		Ok = result.Ok,
		Code = result.Code,
		Message = result.Message,
		Intent = intent,
		Sequence = sequence,
	})
end

-- === Turn driver ============================================================

local function advanceThrough(phases, reason)
	for _, phase in ipairs(phases) do
		local result = MatchOrchestrator.TransitionTo(phase, reason)
		if not result.Ok then
			warn(string.format("[DreamingOfUtopia] turn driver stuck entering %s: %s", phase, result.Message))
			return false
		end
	end
	return true
end

local function beginTurnFor(userId)
	if not advanceThrough({ Phase.TurnStart }, "next turn") then
		return
	end

	local began = MatchOrchestrator.BeginTurn(userId)
	if not began.Ok then
		warn("[DreamingOfUtopia] BeginTurn failed: " .. tostring(began.Message))
		return
	end

	if not advanceThrough({ Phase.Draw }, "start of turn draw") then
		return
	end

	local drawn = DeckService.Draw(userId, 1)
	MatchLogService.Append("Drew", { UserId = userId, Count = #drawn })

	-- Over the cap, the player owes a discard before anything else happens.
	-- The turn genuinely stops here: no roll, no spell, until the hand is legal.
	if DeckService.IsHandOverFull(userId) then
		advanceThrough({ Phase.HandOverflowDiscard }, "hand over the cap")
		pushStateToAll()
		return
	end

	-- SpellChoice now STOPS here. It was traversed through M1-M5 because there
	-- was nothing to cast; there is now, and declining has to be a real choice
	-- the player makes rather than the absence of one — otherwise the server
	-- has already moved to RollReady before the client could offer the button.
	advanceThrough({ Phase.SpellChoice }, "spell phase open")
	pushStateToAll()
end

-- Resumes the turn once an over-full hand has been brought back to the cap.
local function continueAfterDiscard()
	advanceThrough({ Phase.SpellChoice }, "hand is legal again")
	pushStateToAll()
end

local function endTurnAndAdvance()
	if not advanceThrough({ Phase.TurnEnd }, "turn over") then
		return
	end

	-- End-of-turn statuses fire here, inside the phase named for them, before
	-- victory is evaluated: poison that damages a creature has to be counted
	-- in this turn's totals, not next turn's.
	local endingUserId = MatchOrchestrator.GetActivePlayerId()
	StatusService.FireHook(Enums.TimingHook.TurnEnd, {
		UserId = endingUserId,
		GetCreature = BattleService.GetDefender,
		DamageCreature = BattleService.DamageDefender,
	})
	StatusService.TickDurations(Enums.DurationType.Turns, endingUserId)

	if not advanceThrough({ Phase.VictoryCheck }, "turn over") then
		return
	end

	-- Victory is Total Magic, and reaching the goal is NOT winning — it is a
	-- visible state that has to be confirmed at the castle, and can be lost on
	-- the way there. Recomputed for every player because one player's capture
	-- shrinks another player's chain and so moves another player's total.
	VictoryService.RefreshGoalStates(MatchOrchestrator.GetParticipants())

	if VictoryService.IsMatchWon() then
		MatchOrchestrator.TransitionTo(Phase.MatchComplete, "victory confirmed at the castle")
		MatchLogService.Append("MatchWon", { UserId = VictoryService.GetWinner() })
		pushStateToAll()
		return
	end

	local nextUserId, wrapped = MatchOrchestrator.AdvanceToNextPlayer()
	if nextUserId == nil then
		return -- nobody left to play
	end

	if wrapped then
		MatchOrchestrator.TransitionTo(Phase.RoundEnd, "rotation wrapped")
		-- Round-scoped statuses expire here and nowhere else. A match-wide
		-- effect that lasts "a round" has to tick once per rotation, not once
		-- per player, or its stated duration is a lie by the player count.
		StatusService.FireHook(Enums.TimingHook.RoundEnd, {})
		StatusService.TickDurations(Enums.DurationType.Rounds)
	end
	beginTurnFor(nextUserId)
end

-- What the player may actually do where they landed. Returning an empty list
-- means the turn simply ends — landing somewhere with no legal action is a
-- normal outcome, not an error.
-- The brief's landing action matrix. An empty list means the turn simply ends:
-- landing somewhere with nothing to do is a normal outcome, not an error.
local function landingActionsFor(userId, nodeId)
	local territory = TerritoryService.GetTerritory(nodeId)
	if territory == nil then
		return {} -- the castle and special nodes resolve on their own
	end

	if territory.Owner == nil then
		-- Empty: claim it, or walk on.
		return { Intent.ChooseSummon }
	end

	if territory.Owner == userId then
		-- Your own land: level it up or change its element.
		return { Intent.ChooseTerritoryCommand }
	end

	-- Enemy land: invade with a creature, or decline and pay the toll.
	return { Intent.PayToll, Intent.ChooseSummon }
end

-- Movement can stop halfway and ask which way to go, so this handles both
-- outcomes: a finished move falls through to landing, an unfinished one parks
-- the match in JunctionChoice until the player picks a route.
local function settleMovement(player, movementResult)
	if not movementResult.Ok then
		warn("[DreamingOfUtopia] movement failed: " .. tostring(movementResult.Message))
		endTurnAndAdvance()
		return
	end

	if movementResult.Payload.Status == "AwaitingChoice" then
		MatchOrchestrator.TransitionTo(Phase.JunctionChoice, "branch reached")
		MatchLogService.Append("JunctionReached", {
			UserId = player.UserId,
			NodeId = movementResult.Payload.NodeId,
			Options = #movementResult.Payload.Options,
			RemainingSteps = movementResult.Payload.RemainingSteps,
		})
		pushStateToAll()
		return
	end

	-- Movement is finished. Return to Movement first when resuming from a
	-- junction, because LandingResolution is only reachable from there.
	if MatchOrchestrator.GetPhase() == Phase.JunctionChoice then
		MatchOrchestrator.TransitionTo(Phase.Movement, "route chosen")
	end

	if not advanceThrough({ Phase.LandingResolution }, "movement finished") then
		return
	end

	local nodeId = MovementService.GetCurrentNodeId(player)
	if #landingActionsFor(player.UserId, nodeId) == 0 then
		endTurnAndAdvance()
		return
	end

	MatchOrchestrator.TransitionTo(Phase.LandingActionChoice, "awaiting the player's post-move action")
	pushStateToAll()
end

local function resolveMovementAndLanding(player, steps)
	if not advanceThrough({ Phase.DiceResolution, Phase.Movement }, "rolled " .. steps) then
		return
	end
	settleMovement(player, MovementService.BeginMove(player.UserId, steps, Enums.MovementCause.Roll))
end

-- === Intent handling ========================================================

local intentHandlers = {}

-- A spell is cast, its effects resolve, and the phase stays open — Culdcast
-- allows a second spell only through Doublecast, but nothing here forces the
-- player to leave the phase after one either. SkipSpell is what advances.
intentHandlers[Intent.CastSpell] = function(player, payload)
	local instanceId = payload and payload.InstanceId
	if typeof(instanceId) ~= "string" then
		return { Ok = false, Code = Enums.RejectReason.InvalidCard, Message = "no card chosen" }
	end

	local resolved = CardEffectService.Resolve(player.UserId, instanceId, {
		TargetUserId = payload.TargetUserId,
		TargetNodeId = payload.TargetNodeId,
	})
	if not resolved.Ok then
		-- Refused, nothing spent: the player is still in SpellChoice and may
		-- choose again. This is the case the refund path exists for.
		return { Ok = false, Code = resolved.Code, Message = resolved.Message }
	end

	task.spawn(function()
		-- Traversed, not skipped. The effects have already run — this records
		-- WHERE they ran, which is what a later Doublecast needs to return to.
		advanceThrough({ Phase.SpellResolution, Phase.SpellChoice }, "spell resolved")
		pushStateToAll()
	end)
	return { Ok = true, Message = string.format("Cast %s", tostring(resolved.Payload.Name)) }
end

intentHandlers[Intent.SkipSpell] = function()
	task.spawn(function()
		advanceThrough({ Phase.RollReady }, "spell phase declined")
		pushStateToAll()
	end)
	return { Ok = true, Message = "No spell" }
end

intentHandlers[Intent.Roll] = function(player)
	-- Paralysis is a status, not a flag: BeforeRoll decides whether the dice
	-- are thrown at all, and a refused roll still costs the turn.
	if not MovementService.CanRoll(player.UserId) then
		MatchLogService.Append("RollPrevented", { UserId = player.UserId })
		task.spawn(function()
			advanceThrough({ Phase.DiceResolution, Phase.Movement, Phase.LandingResolution }, "roll prevented")
			endTurnAndAdvance()
		end)
		return { Ok = true, Message = "You cannot roll this turn" }
	end

	local total, _rolls, natural = MovementService.RollDice(1, player.UserId)
	MatchLogService.Append("Rolled", {
		UserId = player.UserId,
		Total = total,
		Natural = natural,
	})
	-- Movement resolves in the same call, so the phase never rests in
	-- DiceResolution or Movement waiting on anything.
	task.spawn(resolveMovementAndLanding, player, total)

	if natural ~= nil and natural ~= total then
		-- Reported, not hidden: a player whose roll was changed by a card has
		-- to be able to see that it was.
		return {
			Ok = true,
			Message = string.format("Rolled %d (natural %d)", total, natural),
		}
	end
	return { Ok = true, Message = string.format("Rolled %d", total) }
end

intentHandlers[Intent.ChooseJunction] = function(player, payload)
	local edgeId = payload and payload.EdgeId
	if typeof(edgeId) ~= "string" then
		return { Ok = false, Code = Enums.RejectReason.InvalidTarget, Message = "no route chosen" }
	end

	local result = MovementService.ChooseExit(player.UserId, edgeId)
	if not result.Ok then
		-- The move is still pending, so the player simply chooses again.
		return { Ok = false, Code = result.Code, Message = result.Message }
	end

	task.spawn(settleMovement, player, result)
	return { Ok = true, Message = "Route chosen" }
end

intentHandlers[Intent.DiscardToHandLimit] = function(player, payload)
	local instanceId = payload and payload.InstanceId
	if typeof(instanceId) ~= "string" then
		return { Ok = false, Code = Enums.RejectReason.InvalidCard, Message = "no card chosen" }
	end

	local discarded = DeckService.DiscardInstance(player.UserId, instanceId)
	if not discarded.Ok then
		return { Ok = false, Code = discarded.Code, Message = discarded.Message }
	end

	-- Still over the cap after one discard: stay in this phase and ask again
	-- rather than letting the turn continue with an illegal hand.
	if DeckService.IsHandOverFull(player.UserId) then
		return { Ok = true, Message = "Discarded — still over the limit" }
	end

	task.spawn(continueAfterDiscard)
	return { Ok = true, Message = "Discarded" }
end

intentHandlers[Intent.ChooseSummon] = function(player, payload)
	-- Cards are named by INSTANCE now, not by card id. Naming a type you do
	-- not hold is refused by DeckService, which is what stops the old
	-- behaviour where any card could be played any number of times.
	local instanceId = payload and payload.InstanceId
	if typeof(instanceId) ~= "string" then
		return { Ok = false, Code = Enums.RejectReason.InvalidCard, Message = "no card chosen" }
	end

	local instance = DeckService.GetInstance(player.UserId, instanceId)
	if instance == nil then
		return { Ok = false, Code = Enums.RejectReason.CardNotInHand, Message = "that card is not in your hand" }
	end
	local cardId = instance.CardId

	local nodeId = MovementService.GetCurrentNodeId(player)
	local territory = TerritoryService.GetTerritory(nodeId)
	local isInvasion = territory ~= nil and territory.Owner ~= nil and territory.Owner ~= player.UserId

	if isInvasion then
		-- An invasion is not resolved here. It opens the battle state machine
		-- and the turn parks in the item-choice phases until both sides have
		-- committed. BattleService consumes the card itself.
		local began = BattleService.BeginInvasion(player.UserId, instanceId, nodeId)
		if not began.Ok then
			return { Ok = false, Code = began.Code, Message = began.Message }
		end

		advanceThrough({ Phase.BattleSetup, Phase.AttackerItemChoice }, "invasion declared")
		pushStateToAll()
		return { Ok = true, Message = "Invading " .. nodeId }
	end

	local claimed = BattleService.SummonCreature(player.UserId, instanceId, nodeId)
	if not claimed.Ok then
		return { Ok = false, Code = claimed.Code, Message = claimed.Message }
	end

	task.spawn(endTurnAndAdvance)
	return { Ok = true, Message = "Claimed " .. nodeId }
end

-- Applies a resolved battle: the toll if one is owed, then the turn ends.
-- Ownership and creature state were already settled inside BattleService.
local function settleBattle(result)
	advanceThrough({ Phase.BattleResolution }, "battle resolved")

	MatchLogService.Append("BattleResolved", {
		TileId = result.TileId,
		Outcome = result.Outcome,
		Attacker = result.AttackerUserId,
		Defender = result.DefenderUserId,
	})

	if result.TollOwed then
		advanceThrough({ Phase.TollResolution }, "invader owes the toll")
		EconomyService.PayToll(result.AttackerUserId, result.TileId)
	end

	endTurnAndAdvance()
end

intentHandlers[Intent.ChooseBattleItem] = function(player, payload)
	local pending = BattleService.GetPendingBattle()
	if pending == nil then
		return { Ok = false, Code = Enums.RejectReason.IllegalAction, Message = "no battle in progress" }
	end

	-- An absent InstanceId is "No Item", which is always a legal choice.
	local instanceId = payload and payload.InstanceId
	if instanceId ~= nil and typeof(instanceId) ~= "string" then
		return { Ok = false, Code = Enums.RejectReason.InvalidCard, Message = "bad card reference" }
	end

	if pending.Status == "AwaitingAttackerItem" then
		local chosen = BattleService.ChooseAttackerItem(player.UserId, instanceId)
		if not chosen.Ok then
			return { Ok = false, Code = chosen.Code, Message = chosen.Message }
		end
		-- The defender now chooses, knowing what was committed.
		advanceThrough({ Phase.DefenderItemChoice }, "attacker committed")
		pushStateToAll()
		return { Ok = true, Message = instanceId and "Item committed" or "No item" }
	end

	local resolved = BattleService.ChooseDefenderItem(player.UserId, instanceId)
	if not resolved.Ok then
		return { Ok = false, Code = resolved.Code, Message = resolved.Message }
	end

	task.spawn(settleBattle, resolved.Payload)
	return { Ok = true, Message = "Battle resolved: " .. resolved.Payload.Outcome }
end

intentHandlers[Intent.PayToll] = function(player)
	local nodeId = MovementService.GetCurrentNodeId(player)
	advanceThrough({ Phase.TollResolution }, "toll declined into payment")

	-- A toll is mandatory: RequirePayment takes what is available and records
	-- the rest as a debt rather than refusing, so an unaffordable toll leads to
	-- liquidation instead of leaving the payment simply undone.
	local result = EconomyService.PayToll(player.UserId, nodeId)
	if not result.Ok then
		MatchOrchestrator.TransitionTo(Phase.LandingActionChoice, "no toll owed")
		return { Ok = false, Code = result.Code, Message = result.Message }
	end

	local payload = result.Payload
	if payload.Shortfall > 0 then
		advanceThrough({ Phase.Liquidation }, "cannot cover the toll")
		MatchLogService.Append("PaymentShortfall", { UserId = player.UserId, Shortfall = payload.Shortfall })
		pushStateToAll()
		return {
			Ok = true,
			Message = string.format("Paid %d of %d — %d still owed", payload.Paid, payload.Toll, payload.Shortfall),
		}
	end

	task.spawn(endTurnAndAdvance)
	return { Ok = true, Message = string.format("Toll paid: %d", payload.Toll) }
end

-- One command per turn, on the territory you landed on. The brief allows more
-- targets (anything crossed this move, or anywhere at all from a castle) and
-- more commands (move creature, exchange creature, territory ability); those
-- need the movement path recorded and creature relocation, and land in a later
-- pass. What is here is the two commands that change land itself.
intentHandlers[Intent.ChooseTerritoryCommand] = function(player, payload)
	local nodeId = MovementService.GetCurrentNodeId(player)
	local command = payload and payload.Command

	advanceThrough({ Phase.TerritoryCommandChoice }, "territory command")

	local result
	if command == Enums.TerritoryCommand.LevelLand then
		result = TerritoryService.LevelUp(player.UserId, nodeId, payload.Level)
	elseif command == Enums.TerritoryCommand.ChangeElement then
		-- An empty string means neutral, which is a legal destination.
		local element = payload.Element
		if element == "" then
			element = nil
		end
		result = TerritoryService.ChangeElement(player.UserId, nodeId, element)
	else
		return {
			Ok = false,
			Code = Enums.RejectReason.IllegalAction,
			Message = "unknown territory command " .. tostring(command),
		}
	end

	if not result.Ok then
		-- Refused, so the command was never spent. Return to the action window
		-- rather than burning the player's turn on a rejected request.
		MatchOrchestrator.TransitionTo(Phase.LandingActionChoice, "command refused")
		return { Ok = false, Code = result.Code, Message = result.Message }
	end

	advanceThrough({ Phase.TerritoryCommandResolution }, "command resolved")
	task.spawn(endTurnAndAdvance)

	return {
		Ok = true,
		Message = string.format("%s on %s for %d Magic", command, nodeId, result.Payload.Cost),
	}
end

intentHandlers[Intent.ChooseLiquidation] = function(player, payload)
	local nodeId = payload and payload.NodeId
	if typeof(nodeId) ~= "string" then
		return { Ok = false, Code = Enums.RejectReason.InvalidTarget, Message = "choose a territory to sell" }
	end

	local sale = EconomyService.LiquidateTerritory(player.UserId, nodeId)
	if not sale.Ok then
		return { Ok = false, Code = sale.Code, Message = sale.Message }
	end

	MatchLogService.Append("Liquidated", {
		UserId = player.UserId,
		NodeId = nodeId,
		Proceeds = sale.Payload.Proceeds,
	})

	if sale.Payload.RemainingDebt > 0 then
		-- Still short. Stay in Liquidation and sell something else; the turn
		-- cannot continue while a mandatory payment is outstanding.
		if EconomyService.IsBankrupt(player.UserId) then
			EconomyService.DeclareBankrupt(player.UserId)
			TerritoryService.ReleaseAllOwnedBy(player.UserId)
			MatchLogService.Append("Bankrupted", { UserId = player.UserId })
			task.spawn(endTurnAndAdvance)
			return { Ok = true, Message = "Bankrupt — nothing left to sell" }
		end
		pushStateToAll()
		return {
			Ok = true,
			Message = string.format("Sold %s — %d still owed", nodeId, sale.Payload.RemainingDebt),
		}
	end

	task.spawn(endTurnAndAdvance)
	return { Ok = true, Message = string.format("Sold %s for %d", nodeId, sale.Payload.Proceeds) }
end

intentHandlers[Intent.EndTurn] = function()
	task.spawn(endTurnAndAdvance)
	return { Ok = true, Message = "Turn ended" }
end

-- The single entry point. `player` comes from OnServerEvent itself and cannot
-- be spoofed; nothing in the payload identifies who is asking.
Remotes.SubmitIntent.OnServerEvent:Connect(function(player, intent, sequence, expectedPhase, payload)
	local userId = player.UserId
	local currentPhase = MatchOrchestrator.GetPhase()

	-- Who this phase is waiting on. Usually the active player, but a battle's
	-- defender item window belongs to the DEFENDER, so the entitled user is
	-- resolved from the phase rather than assumed.
	local entitledUserId = MatchOrchestrator.GetActivePlayerId()
	if ActionValidator.getExpectedActor(currentPhase) == Enums.Actor.Defender then
		entitledUserId = BattleService.GetDefenderUserId()
	end

	-- 1. Admissibility: right player for this phase, fresh sequence, match
	-- still running.
	local admitted = MatchOrchestrator.SubmitIntent(userId, tostring(intent), sequence, entitledUserId)
	if not admitted.Ok then
		replyTo(player, intent, sequence, admitted)
		return
	end

	-- 2. The client acted on a screen; if the server has moved on since, the
	-- request is stale by definition rather than merely late.
	if expectedPhase ~= nil and expectedPhase ~= currentPhase then
		replyTo(player, intent, sequence, {
			Ok = false,
			Code = Enums.RejectReason.StaleSequence,
			Message = string.format("you acted during %s, the match is in %s", tostring(expectedPhase), currentPhase),
		})
		pushStateTo(player)
		return
	end

	-- 3. Is this intent legal in this phase, for this actor?
	local allowed = ActionValidator.validate({
		Phase = currentPhase,
		ActivePlayerId = MatchOrchestrator.GetActivePlayerId(),
		DefenderId = BattleService.GetDefenderUserId(),
		RequesterId = userId,
		Participants = MatchOrchestrator.GetParticipantSet(),
	}, intent)
	if not allowed.Ok then
		replyTo(player, intent, sequence, allowed)
		return
	end

	local handler = intentHandlers[intent]
	if handler == nil then
		replyTo(player, intent, sequence, {
			Ok = false,
			Code = Enums.RejectReason.IllegalAction,
			Message = intent .. " is not implemented yet",
		})
		return
	end

	local outcome = handler(player, payload)
	replyTo(player, intent, sequence, outcome)
	pushStateToAll()
end)

-- === Players ================================================================

local function onPlayerAdded(player)
	MovementService.RegisterCepter(player)
	EconomyService.RegisterPlayer(player.UserId, ACTIVE_BOARD.DefaultMagic)
	MatchOrchestrator.AddParticipant(player.UserId)
	BoardVisualService.CreateCepterToken(player)

	-- A shuffled book and an opening hand one below the cap, so the first
	-- start-of-turn draw fills the hand exactly instead of overflowing it.
	DeckService.RegisterPlayer(player.UserId)
	DeckService.Draw(player.UserId, RulesConfig.Hand.OpeningSize)

	-- The first player to arrive starts the match. A real lobby with an
	-- explicit start step is Milestone 8; until then the match begins as
	-- soon as someone is here to play it.
	if MatchOrchestrator.GetPhase() == Phase.WaitingForPlayers then
		MatchOrchestrator.TransitionTo(Phase.MatchSetup, "first player joined")
		beginTurnFor(player.UserId)
	else
		pushStateToAll()
	end
end

local function onPlayerRemoving(player)
	local wasActive = MatchOrchestrator.IsActivePlayer(player.UserId)

	MovementService.RemoveCepter(player)
	DeckService.RemovePlayer(player.UserId)
	EconomyService.RemovePlayer(player.UserId)
	-- Released, not left owned by a ghost: every chain those territories were
	-- part of has to shrink, or the board keeps charging tolls on behalf of
	-- someone who is gone.
	TerritoryService.ReleaseAllOwnedBy(player.UserId)
	BoardVisualService.RemoveCepterToken(player)
	MatchOrchestrator.RemoveParticipant(player.UserId)

	-- Leaving mid-turn must not strand the match on a player who is gone.
	if wasActive and MatchOrchestrator.GetParticipantCount() > 0 then
		task.spawn(endTurnAndAdvance)
	else
		pushStateToAll()
	end
end

-- Both signals report userIds and node ids since Milestone 2: movement speaks
-- in graph nodes, and lap completion belongs to LapService rather than to
-- movement, because a lap is "every required fort, then the castle".
MovementService.CepterLanded:Connect(function(userId, nodeId)
	MatchLogService.Append("CepterLanded", { UserId = userId, NodeId = nodeId })
end, 0, "Main.CepterLanded")

-- Victory is confirmed by ARRIVING, so this listens to node entry rather than
-- to the end of a turn. It fires on a crossing as well as a landing, which is
-- the brief's rule: reaching or crossing the castle confirms it. TM is
-- re-checked inside TryConfirmAtCastle, so a player who slipped under the goal
-- on the way home arrives to nothing.
MovementService.NodeEntered:Connect(function(userId, nodeId)
	if VictoryService.TryConfirmAtCastle(userId, nodeId) then
		MatchLogService.Append("VictoryConfirmed", {
			UserId = userId,
			NodeId = nodeId,
			TotalMagic = ValuationService.GetTotalMagic(userId),
		})
	end
end, 10, "Main.CastleVictoryCheck")

VictoryService.GoalReached:Connect(function(userId, totalMagic)
	MatchLogService.Append("GoalReached", { UserId = userId, TotalMagic = totalMagic })
end, 0, "Main.GoalReached")

VictoryService.GoalLost:Connect(function(userId, totalMagic)
	MatchLogService.Append("GoalLost", { UserId = userId, TotalMagic = totalMagic })
end, 0, "Main.GoalLost")

LapService.LapCompleted:Connect(function(userId, lapNumber)
	MatchLogService.Append("LapCompleted", { UserId = userId, Lap = lapNumber })
end, 0, "Main.LapCompleted")

LapService.FortVisited:Connect(function(userId, fortType)
	MatchLogService.Append("FortVisited", { UserId = userId, FortType = fortType })
end, 0, "Main.FortVisited")

EconomyService.BalanceChanged:Connect(function(userId)
	local player = Players:GetPlayerByUserId(userId)
	if player ~= nil then
		pushStateTo(player)
	end
end, 0, "Main.BalanceChanged")

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

print(string.format(
	"[DreamingOfUtopia] Ready — %d territories, %d cards, phase %s",
	#TerritoryService.GetAllTerritories(),
	#CardService.GetAllCards(),
	MatchOrchestrator.GetPhase()
))

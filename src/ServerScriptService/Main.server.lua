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
local BoardService = require(Systems.BoardService)
local BoardGraphService = require(Systems.BoardGraphService)
local BoardVisualService = require(Systems.BoardVisualService)
local LapService = require(Systems.LapService)
local RandomService = require(Systems.RandomService)
local MovementService = require(Systems.MovementService)
local CardService = require(Systems.CardService)
local EconomyService = require(Systems.EconomyService)
local BattleService = require(Systems.BattleService)
local TerraformService = require(Systems.TerraformService)
local CardEffectService = require(Systems.CardEffectService)
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

BoardService.Init() -- tile ownership/level state, keyed by the tagged Parts
LapService.Init({ Graph = BoardGraphService })
MovementService.Init({
	Graph = BoardGraphService,
	Lap = LapService,
	Random = RandomService.default(),
})
EconomyService.Init() -- subscribes to LapService.LapCompleted
BattleService.Init()
DeckService.Init({ Random = RandomService.default() })

BoardVisualService.Init({
	Board = BoardService,
	Battle = BattleService,
	Card = CardService,
	Movement = MovementService,
	Graph = BoardGraphService,
})

SnapshotService.Init({
	Orchestrator = MatchOrchestrator,
	Validator = ActionValidator,
	Board = BoardService,
	Movement = MovementService,
	Economy = EconomyService,
	Battle = BattleService,
	Card = CardService,
	GetParticipants = MatchOrchestrator.GetParticipants,
	GetParticipantSet = MatchOrchestrator.GetParticipantSet,
	GetHandCount = DeckService.GetHandCount,
	-- Supplied to SnapshotService, which decides who is allowed to see the
	-- contents. It sends identities only to the hand's owner.
	GetHand = DeckService.GetHand,
	GetBookCount = DeckService.GetBookCount,
	GetDiscardCount = DeckService.GetDiscardCount,
	GetDefenderId = function()
		return nil -- no battle phases entered until Milestone 4
	end,
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

	-- SpellChoice is traversed rather than skipped: casting arrives in
	-- Milestone 6, but the phase is real, logged, and already in place.
	advanceThrough({ Phase.SpellChoice, Phase.RollReady }, "no spell casting yet")
	pushStateToAll()
end

-- Resumes the turn once an over-full hand has been brought back to the cap.
local function continueAfterDiscard()
	advanceThrough({ Phase.SpellChoice, Phase.RollReady }, "hand is legal again")
	pushStateToAll()
end

local function endTurnAndAdvance()
	if not advanceThrough({ Phase.TurnEnd, Phase.VictoryCheck }, "turn over") then
		return
	end

	-- Victory is still Current Magic against a target; Total Magic and the
	-- return-to-castle confirmation arrive in Milestone 5.
	local winnerId = nil
	for _, userId in ipairs(MatchOrchestrator.GetParticipants()) do
		local balance = EconomyService.GetBalance(userId)
		if balance ~= nil and balance >= 3000 then
			winnerId = userId
			break
		end
	end

	if winnerId ~= nil then
		MatchOrchestrator.TransitionTo(Phase.MatchComplete, "win target reached")
		MatchLogService.Append("MatchWon", { UserId = winnerId })
		pushStateToAll()
		return
	end

	local nextUserId, wrapped = MatchOrchestrator.AdvanceToNextPlayer()
	if nextUserId == nil then
		return -- nobody left to play
	end

	if wrapped then
		MatchOrchestrator.TransitionTo(Phase.RoundEnd, "rotation wrapped")
	end
	beginTurnFor(nextUserId)
end

-- What the player may actually do where they landed. Returning an empty list
-- means the turn simply ends — landing somewhere with no legal action is a
-- normal outcome, not an error.
local function landingActionsFor(userId, tileId)
	local tile = BoardService.GetTile(tileId)
	if tile == nil or tile.TileType ~= "Property" then
		return {}
	end
	if tile.Owner == nil then
		return { Intent.ChooseSummon }
	end
	if tile.Owner == userId then
		return {} -- own territory; level-up lands in Milestone 5
	end
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

	local tileId = MovementService.GetCurrentTile(player)
	if #landingActionsFor(player.UserId, tileId) == 0 then
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

intentHandlers[Intent.Roll] = function(player)
	local total = MovementService.RollDice(1)
	MatchLogService.Append("Rolled", { UserId = player.UserId, Total = total })
	-- Movement resolves in the same call, so the phase never rests in
	-- DiceResolution or Movement waiting on anything.
	task.spawn(resolveMovementAndLanding, player, total)
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

	local tileId = MovementService.GetCurrentTile(player)
	local tile = BoardService.GetTile(tileId)
	local isInvasion = tile ~= nil and tile.Owner ~= nil and tile.Owner ~= player.UserId

	local ok, reason
	if isInvasion then
		ok, reason = BattleService.ChallengeTile(player, cardId, tileId)
		if reason ~= nil then
			-- Rejected outright, so the card was never played and stays in hand.
			return { Ok = false, Code = Enums.RejectReason.RuleViolation, Message = reason }
		end

		-- The challenge resolved, so the card is spent either way.
		DeckService.PlayInstance(player.UserId, instanceId)

		-- A lost challenge is a successful action with an unfavourable
		-- outcome; the visitor then owes the toll.
		if not ok then
			EconomyService.PayToll(player, tileId)
		end
		task.spawn(endTurnAndAdvance)
		return { Ok = true, Message = ok and ("Won tile #" .. tileId) or "Lost the challenge; toll paid" }
	end

	ok, reason = BattleService.SummonCreature(player, cardId, tileId)
	if not ok then
		return { Ok = false, Code = Enums.RejectReason.RuleViolation, Message = tostring(reason) }
	end

	-- Consumed only after the summon succeeded, so a refused summon never
	-- costs the card.
	DeckService.PlayInstance(player.UserId, instanceId)

	task.spawn(endTurnAndAdvance)
	return { Ok = true, Message = "Claimed tile #" .. tileId }
end

intentHandlers[Intent.PayToll] = function(player)
	local tileId = MovementService.GetCurrentTile(player)
	local ok, reason = EconomyService.PayToll(player, tileId)
	if not ok then
		return { Ok = false, Code = Enums.RejectReason.InsufficientMagic, Message = tostring(reason) }
	end
	task.spawn(endTurnAndAdvance)
	return { Ok = true, Message = "Toll paid" }
end

intentHandlers[Intent.ChooseTerritoryCommand] = function(player, payload)
	local targetElement = payload and payload.Element
	if targetElement ~= nil and typeof(targetElement) ~= "string" then
		return { Ok = false, Code = Enums.RejectReason.InvalidTarget, Message = "bad element" }
	end

	local normalized = (targetElement ~= "" and targetElement) or nil
	local tileId = MovementService.GetCurrentTile(player)
	local ok, reason = TerraformService.TerraformTile(player, tileId, normalized)
	if not ok then
		return { Ok = false, Code = Enums.RejectReason.RuleViolation, Message = tostring(reason) }
	end
	task.spawn(endTurnAndAdvance)
	return { Ok = true, Message = "Terraformed tile #" .. tileId }
end

intentHandlers[Intent.EndTurn] = function()
	task.spawn(endTurnAndAdvance)
	return { Ok = true, Message = "Turn ended" }
end

-- The single entry point. `player` comes from OnServerEvent itself and cannot
-- be spoofed; nothing in the payload identifies who is asking.
Remotes.SubmitIntent.OnServerEvent:Connect(function(player, intent, sequence, expectedPhase, payload)
	local userId = player.UserId

	-- 1. Admissibility: active player, fresh sequence, match still running.
	local admitted = MatchOrchestrator.SubmitIntent(userId, tostring(intent), sequence)
	if not admitted.Ok then
		replyTo(player, intent, sequence, admitted)
		return
	end

	-- 2. The client acted on a screen; if the server has moved on since, the
	-- request is stale by definition rather than merely late.
	local currentPhase = MatchOrchestrator.GetPhase()
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
		DefenderId = nil,
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
	EconomyService.RegisterPlayer(player)
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
	EconomyService.RemovePlayer(player)
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
	"[DreamingOfUtopia] Ready — %d tiles, %d cards, phase %s",
	#BoardService.GetAllTiles(),
	#CardService.GetAllCards(),
	MatchOrchestrator.GetPhase()
))

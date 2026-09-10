--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > MovementService (ModuleScript)

	Purpose:
		Moves a Cepter across the board graph, one edge at a time, as a
		RESUMABLE TRANSACTION.

		The previous version walked a sorted ring in a `for` loop with a
		task.wait between steps. That shape cannot express the thing Culdcept
		movement actually does: stop halfway, ask the player which way to go,
		and carry on with the steps that are left. A loop cannot pause and
		return; a transaction can.

		So a move is an object. BeginMove starts it and returns either
		Completed or AwaitingChoice. If it is awaiting, the remaining steps sit
		in the transaction until ChooseExit resumes it. Nothing about the move
		lives on the call stack, which is what makes junctions, transports and
		forced movement one mechanism rather than three.

		The wait is gone too. Movement resolves instantly and publishes an
		ordered path; the client animates from that. The brief requires a
		server result to stay valid even if every animation is skipped, and
		a rules loop that sleeps 0.25s per step cannot honour that.

	Ordering within a step:
		NodeExited -> EdgeTraversed -> NodeEntered, then that node's own
		effects: fort credit, castle lap check, then transport. Deterministic
		and logged, because a status or card that intervenes on any of these
		has to know exactly when it runs.

	Transports:
		Entering a node with a transport relocates the token. A MandatoryWarp
		fires even when merely crossed; a LandingWarp fires only when the move
		ends on it. After a relocation the token has no "came from" node, so
		every exit at the destination is legal — you did not walk in, so there
		is nothing to reverse into.

		Transport chains are capped. A pair of warps pointing at each other is
		an authoring mistake the validator cannot catch (each is individually
		valid), and without a cap it would hang the server rather than warn.

	Compatibility:
		GetCurrentTile returns the node's StudioNodeId, so callers still
		holding numeric tile ids (BoardService's ownership state, the visual
		layer) keep working while territory state migrates in Milestone 5.

	Public API:
		MovementService.Init(deps)              -- deps.Graph, deps.Lap, deps.Random
		MovementService.RegisterCepter(playerOrUserId)
		MovementService.RemoveCepter(playerOrUserId)
		MovementService.GetCurrentNodeId(userId) -> nodeId or nil
		MovementService.GetCurrentTile(playerOrUserId) -> StudioNodeId or nil
		MovementService.RollDice(diceCount?) -> total, rolls
		MovementService.BeginMove(userId, steps, cause) -> ActionResult
		MovementService.ChooseExit(userId, edgeId) -> ActionResult
		MovementService.GetPendingChoice(userId) -> { NodeId, Options } or nil
		MovementService.IsAwaitingChoice(userId) -> boolean
		MovementService.TeleportTo(userId, nodeId, cause) -> ActionResult

		Payload on a movement result:
			Status          "Completed" | "AwaitingChoice"
			NodeId          where the token is now
			RemainingSteps  0 when completed
			Path            node ids entered during this move, in order
			Options         when awaiting: { { EdgeId, To }, ... }

	Signals:
		MovementService.NodeExited:Connect(function(userId, nodeId) end)
		MovementService.EdgeTraversed:Connect(function(userId, edgeId) end)
		MovementService.NodeEntered:Connect(function(userId, nodeId, isFinalStep) end)
		MovementService.JunctionReached:Connect(function(userId, nodeId, options) end)
		MovementService.CepterLanded:Connect(function(userId, nodeId) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local ActionResult = require(ReplicatedStorage.Shared.ActionResult)
local Signal = require(ReplicatedStorage.Shared.Signal)

local MovementService = {}

MovementService.NodeExited = Signal.new("Movement.NodeExited")
MovementService.EdgeTraversed = Signal.new("Movement.EdgeTraversed")
MovementService.NodeEntered = Signal.new("Movement.NodeEntered")
MovementService.JunctionReached = Signal.new("Movement.JunctionReached")
MovementService.CepterLanded = Signal.new("Movement.CepterLanded")

-- A warp pair pointing at each other is individually valid to the validator
-- but would loop forever here. Cap and warn rather than hang.
local MAX_TRANSPORT_HOPS = 16

local _graph, _lap, _random

-- userId -> { NodeId }
local _positions = {}
-- userId -> movement transaction, present only while a move is in flight
local _transactions = {}

local function getUserId(playerOrUserId)
	if playerOrUserId == nil then
		return nil
	end
	if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		return playerOrUserId.UserId
	end
	return playerOrUserId
end

function MovementService.Init(deps)
	deps = deps or {}
	_graph = deps.Graph
	_lap = deps.Lap
	_random = deps.Random

	_positions = {}
	_transactions = {}
end

function MovementService.RegisterCepter(playerOrUserId)
	local userId = getUserId(playerOrUserId)
	_positions[userId] = { NodeId = _graph and _graph.GetStartNodeId() or nil }
	if _lap then
		_lap.RegisterPlayer(userId)
	end
end

function MovementService.RemoveCepter(playerOrUserId)
	local userId = getUserId(playerOrUserId)
	_positions[userId] = nil
	_transactions[userId] = nil
	if _lap then
		_lap.RemovePlayer(userId)
	end
end

function MovementService.GetCurrentNodeId(playerOrUserId)
	local position = _positions[getUserId(playerOrUserId)]
	return position and position.NodeId
end

-- Compatibility shim for callers that still speak in numeric tile ids.
function MovementService.GetCurrentTile(playerOrUserId)
	local nodeId = MovementService.GetCurrentNodeId(playerOrUserId)
	if nodeId == nil or _graph == nil then
		return nil
	end
	local node = _graph.GetNode(nodeId)
	return node and (node.StudioNodeId or node.StudioTileId)
end

function MovementService.GetLapCount(playerOrUserId)
	return _lap and _lap.GetLapCount(getUserId(playerOrUserId)) or 0
end

-- The range comes from the board, never a hardcoded d6: some maps present a
-- range up to ten, and a global six-sided assumption would silently cap them.
function MovementService.RollDice(diceCount)
	diceCount = diceCount or 1
	local min, max = 1, 6
	if _graph and _graph.IsLoaded() then
		min, max = _graph.GetRollRange()
	end

	local rolls, total = {}, 0
	for index = 1, diceCount do
		local roll = _random and _random:NextInteger(min, max) or min
		rolls[index] = roll
		total += roll
	end
	return total, rolls
end

-- === The movement transaction ==============================================

local enterNode

local function relocate(transaction, toNodeId)
	transaction.TransportHops += 1
	if transaction.TransportHops > MAX_TRANSPORT_HOPS then
		warn(string.format(
			"[DreamingOfUtopia] MovementService: transport chain exceeded %d hops at '%s' — check the board for warps pointing at each other",
			MAX_TRANSPORT_HOPS, tostring(toNodeId)
		))
		return
	end

	MovementService.NodeExited:Fire(transaction.UserId, transaction.CurrentNodeId)

	-- Arriving by warp leaves no edge behind you, so nothing is "the way you
	-- came" and every exit at the destination is legal.
	transaction.PreviousNodeId = nil
	transaction.CurrentNodeId = toNodeId

	enterNode(transaction, toNodeId)
end

function enterNode(transaction, nodeId)
	table.insert(transaction.Path, nodeId)

	local isFinalStep = transaction.RemainingSteps == 0
	MovementService.NodeEntered:Fire(transaction.UserId, nodeId, isFinalStep)

	-- Forts and castles credit on pass as well as on landing: crossing a fort
	-- counts, and crossing the castle can complete a lap mid-move.
	if _lap then
		local fortType = _graph.GetFortType(nodeId)
		if fortType ~= nil then
			_lap.CreditFort(transaction.UserId, fortType)
		end

		if _graph.IsCastle(nodeId) then
			_lap.TryCompleteLap(transaction.UserId)
		end
	end

	local transport = _graph.GetTransport(nodeId)
	if transport ~= nil and (transport.TriggersOnPass or isFinalStep) then
		relocate(transaction, transport.To)
	end
end

local function traverse(transaction, exit)
	MovementService.NodeExited:Fire(transaction.UserId, transaction.CurrentNodeId)

	transaction.PreviousNodeId = transaction.CurrentNodeId
	transaction.CurrentNodeId = exit.To
	transaction.RemainingSteps -= 1

	MovementService.EdgeTraversed:Fire(transaction.UserId, exit.EdgeId)
	enterNode(transaction, exit.To)
end

local function finish(transaction)
	_transactions[transaction.UserId] = nil
	_positions[transaction.UserId] = { NodeId = transaction.CurrentNodeId }

	MovementService.CepterLanded:Fire(transaction.UserId, transaction.CurrentNodeId)

	return ActionResult.ok({
		Status = "Completed",
		NodeId = transaction.CurrentNodeId,
		RemainingSteps = 0,
		Path = transaction.Path,
	})
end

-- Walks until the steps run out or a branch needs a decision. Returning
-- AwaitingChoice leaves the transaction intact with its remaining steps.
local function advance(transaction)
	while transaction.RemainingSteps > 0 do
		local exits = _graph.GetLegalExits(transaction.CurrentNodeId, transaction.PreviousNodeId)

		if #exits == 0 then
			-- The validator rejects boards where this is possible, so reaching
			-- it means the graph was mutated after loading.
			_transactions[transaction.UserId] = nil
			_positions[transaction.UserId] = { NodeId = transaction.CurrentNodeId }
			return ActionResult.fail(
				Enums.RejectReason.RuleViolation,
				string.format("no legal exit from '%s'", transaction.CurrentNodeId)
			)
		end

		if #exits > 1 then
			transaction.PendingChoice = exits
			MovementService.JunctionReached:Fire(transaction.UserId, transaction.CurrentNodeId, exits)
			return ActionResult.ok({
				Status = "AwaitingChoice",
				NodeId = transaction.CurrentNodeId,
				RemainingSteps = transaction.RemainingSteps,
				Path = transaction.Path,
				Options = exits,
			})
		end

		traverse(transaction, exits[1])
	end

	return finish(transaction)
end

function MovementService.BeginMove(userId, steps, cause)
	local position = _positions[userId]
	if position == nil or position.NodeId == nil then
		return ActionResult.fail(Enums.RejectReason.NotAParticipant, "no Cepter registered")
	end
	if _transactions[userId] ~= nil then
		return ActionResult.fail(Enums.RejectReason.IllegalAction, "a move is already in progress")
	end
	if type(steps) ~= "number" or steps < 1 or steps % 1 ~= 0 then
		return ActionResult.fail(Enums.RejectReason.IllegalAction, "steps must be a positive integer")
	end

	local transaction = {
		UserId = userId,
		OriginNodeId = position.NodeId,
		CurrentNodeId = position.NodeId,
		-- A fresh move has no incoming edge, so the first node offers every
		-- exit. Reversal only becomes meaningful once you have travelled one.
		PreviousNodeId = nil,
		RemainingSteps = steps,
		Path = {},
		TransportHops = 0,
		Cause = cause or Enums.MovementCause.Roll,
		PendingChoice = nil,
	}
	_transactions[userId] = transaction

	return advance(transaction)
end

function MovementService.ChooseExit(userId, edgeId)
	local transaction = _transactions[userId]
	if transaction == nil then
		return ActionResult.fail(Enums.RejectReason.IllegalAction, "no move in progress")
	end
	if transaction.PendingChoice == nil then
		return ActionResult.fail(Enums.RejectReason.WrongPhase, "this move is not waiting on a choice")
	end

	local chosen = nil
	for _, exit in ipairs(transaction.PendingChoice) do
		if exit.EdgeId == edgeId then
			chosen = exit
			break
		end
	end
	if chosen == nil then
		-- Refusing without clearing PendingChoice matters: the player still
		-- owes a decision, and dropping it would strand the move.
		return ActionResult.fail(
			Enums.RejectReason.InvalidTarget,
			string.format("'%s' is not one of the routes offered here", tostring(edgeId))
		)
	end

	transaction.PendingChoice = nil
	traverse(transaction, chosen)
	return advance(transaction)
end

function MovementService.GetPendingChoice(userId)
	local transaction = _transactions[userId]
	if transaction == nil or transaction.PendingChoice == nil then
		return nil
	end
	return {
		NodeId = transaction.CurrentNodeId,
		RemainingSteps = transaction.RemainingSteps,
		Options = transaction.PendingChoice,
	}
end

function MovementService.IsAwaitingChoice(userId)
	return MovementService.GetPendingChoice(userId) ~= nil
end

-- Relocation with no walking: recalls, board effects, setup placement. The
-- cause travels with it because castle and lap effects are NOT universal
-- across movement kinds — a recall to the castle is not the same as walking
-- across it, and the caller states which it is.
function MovementService.TeleportTo(userId, nodeId, cause)
	if _graph.GetNode(nodeId) == nil then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "unknown node " .. tostring(nodeId))
	end
	if _transactions[userId] ~= nil then
		return ActionResult.fail(Enums.RejectReason.IllegalAction, "a move is already in progress")
	end

	MovementService.NodeExited:Fire(userId, MovementService.GetCurrentNodeId(userId))
	_positions[userId] = { NodeId = nodeId }
	MovementService.NodeEntered:Fire(userId, nodeId, true)
	MovementService.CepterLanded:Fire(userId, nodeId)

	return ActionResult.ok({
		Status = "Completed",
		NodeId = nodeId,
		RemainingSteps = 0,
		Path = { nodeId },
		Cause = cause or Enums.MovementCause.ForcedMove,
	})
end

return MovementService

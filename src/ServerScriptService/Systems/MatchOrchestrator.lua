--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > MatchOrchestrator (ModuleScript)

	Purpose:
		The sole phase-transition authority. Nothing else in the project may
		change the match phase; every other service reacts to PhaseChanged or
		is called by the code driving a transition.

		This replaces the pattern where turn state was implicit ("rolled /
		not rolled" on MatchService) and services subscribed to each other's
		signals in an order that silently mattered. Here the sequence of a
		turn is explicit, every move is checked against PhaseGraph, and every
		accepted or rejected move is logged.

		Scope note (Milestone 1): this owns phase, active player, turn/round
		counters, and intent sequencing. It does NOT yet decide which player
		actions are legal within a phase — that is ActionValidator's job, and
		it does not exist yet. Until it does, the orchestrator answers
		"is this request even admissible?" (right phase, right player, fresh
		sequence) and nothing about the action's own rules.

	Why intents carry a sequence number:
		Two identical requests can arrive from one client through a double
		click, a laggy retry, or a replayed packet. Without an ordinal the
		server cannot tell a retry from a genuine second action, and the
		brief requires that duplicates and stale requests change nothing. So
		each player has a monotonically increasing counter: a sequence at or
		below the last accepted one is refused as duplicate or stale, and
		refusal is free — nothing is spent, nothing moves.

	Rejection is never a state change:
		Every path that returns a failing ActionResult does so before
		touching phase, counters or sequence state. That is the property the
		tests actually assert, because it is the one that matters: a client
		spamming illegal requests must not be able to advance anything.

	Public API:
		MatchOrchestrator.Init(options?)          -- options.Log
		MatchOrchestrator.GetPhase() -> phase
		MatchOrchestrator.GetActivePlayerId() -> userId or nil
		MatchOrchestrator.GetTurnNumber() -> number
		MatchOrchestrator.GetRoundNumber() -> number
		MatchOrchestrator.CanTransitionTo(phase) -> boolean
		MatchOrchestrator.TransitionTo(phase, reason) -> ActionResult
		MatchOrchestrator.BeginTurn(userId) -> ActionResult
		MatchOrchestrator.SubmitIntent(userId, intentName, sequence) -> ActionResult
		MatchOrchestrator.PeekSequence(userId) -> number
		MatchOrchestrator.IsActivePlayer(userId) -> boolean
		MatchOrchestrator.IsMatchComplete() -> boolean

	Signals:
		MatchOrchestrator.PhaseChanged:Connect(function(from, to, reason) end)
		MatchOrchestrator.TurnBegan:Connect(function(userId, turnNumber) end)
		MatchOrchestrator.RoundBegan:Connect(function(roundNumber) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local ActionResult = require(ReplicatedStorage.Shared.ActionResult)
local PhaseGraph = require(ReplicatedStorage.Shared.PhaseGraph)
local Signal = require(ReplicatedStorage.Shared.Signal)
local MatchLogService = require(ServerScriptService.Systems.MatchLogService)

local MatchOrchestrator = {}

MatchOrchestrator.PhaseChanged = Signal.new("Orchestrator.PhaseChanged")
MatchOrchestrator.TurnBegan = Signal.new("Orchestrator.TurnBegan")
MatchOrchestrator.RoundBegan = Signal.new("Orchestrator.RoundBegan")

local _phase = PhaseGraph.InitialPhase
local _activePlayerId = nil
local _turnNumber = 0
local _roundNumber = 0
-- userId -> highest sequence number accepted from that player.
local _lastSequence = {}
local _log = MatchLogService

local function context()
	return { Phase = _phase, Turn = _turnNumber }
end

-- Injectable so tests can supply a spy without reaching into the real log,
-- and so a future replay harness can record elsewhere.
function MatchOrchestrator.Init(options)
	options = options or {}
	_log = options.Log or MatchLogService

	_phase = PhaseGraph.InitialPhase
	_activePlayerId = nil
	_turnNumber = 0
	_roundNumber = 0
	_lastSequence = {}

	_log.Append("MatchInitialised", { Phase = _phase }, context())
end

function MatchOrchestrator.GetPhase()
	return _phase
end

function MatchOrchestrator.GetActivePlayerId()
	return _activePlayerId
end

function MatchOrchestrator.GetTurnNumber()
	return _turnNumber
end

function MatchOrchestrator.GetRoundNumber()
	return _roundNumber
end

function MatchOrchestrator.IsMatchComplete()
	return _phase == Enums.Phase.MatchComplete
end

function MatchOrchestrator.IsActivePlayer(userId)
	return _activePlayerId ~= nil and _activePlayerId == userId
end

function MatchOrchestrator.CanTransitionTo(phase)
	return PhaseGraph.canTransition(_phase, phase)
end

-- The only way the phase ever changes. `reason` is free text for the log;
-- it is what makes a transition trail readable months later.
function MatchOrchestrator.TransitionTo(phase, reason)
	if not Enums.isValid(Enums.Phase, phase) then
		local failure = ActionResult.fail(
			Enums.RejectReason.IllegalAction,
			string.format("'%s' is not a phase", tostring(phase))
		)
		_log.Append("PhaseTransitionRejected", {
			From = _phase,
			To = tostring(phase),
			Code = failure.Code,
		}, context())
		return failure
	end

	if not PhaseGraph.canTransition(_phase, phase) then
		local failure = ActionResult.fail(
			Enums.RejectReason.WrongPhase,
			string.format("cannot go from %s to %s", _phase, phase)
		)
		_log.Append("PhaseTransitionRejected", {
			From = _phase,
			To = phase,
			Code = failure.Code,
		}, context())
		return failure
	end

	local from = _phase
	_phase = phase

	-- Counters advance as a consequence of entering their phase, so nothing
	-- else has to remember to bump them. RoundEnd increments the round; the
	-- turn number is owned by BeginTurn, which needs the player anyway.
	if phase == Enums.Phase.RoundEnd then
		_roundNumber += 1
		_log.Append("RoundBegan", { Round = _roundNumber }, context())
		MatchOrchestrator.RoundBegan:Fire(_roundNumber)
	end

	_log.Append("PhaseChanged", { From = from, To = phase, Reason = reason }, context())
	MatchOrchestrator.PhaseChanged:Fire(from, phase, reason)

	return ActionResult.ok({ From = from, To = phase })
end

-- Records whose turn it is. Must be called in TurnStart: the active player is
-- what every subsequent intent is checked against, and leaving it stale across
-- a turn boundary would let the previous player keep acting.
function MatchOrchestrator.BeginTurn(userId)
	if _phase ~= Enums.Phase.TurnStart then
		return ActionResult.fail(
			Enums.RejectReason.WrongPhase,
			string.format("BeginTurn requires TurnStart, phase is %s", _phase)
		)
	end
	if userId == nil then
		return ActionResult.fail(Enums.RejectReason.NotAParticipant, "BeginTurn needs a userId")
	end

	_activePlayerId = userId
	_turnNumber += 1

	_log.Append("TurnBegan", { UserId = userId, Turn = _turnNumber }, context())
	MatchOrchestrator.TurnBegan:Fire(userId, _turnNumber)

	return ActionResult.ok({ UserId = userId, Turn = _turnNumber })
end

function MatchOrchestrator.PeekSequence(userId)
	return _lastSequence[userId] or 0
end

-- Admissibility only: right match state, right player, fresh sequence. What
-- the intent is allowed to DO belongs to ActionValidator.
--
-- The sequence counter is advanced only on acceptance, so a rejected request
-- does not consume an ordinal and the client's next genuine request is not
-- knocked out of step by having been refused once.
function MatchOrchestrator.SubmitIntent(userId, intentName, sequence)
	local function reject(code, message)
		_log.Append("IntentRejected", {
			UserId = userId,
			Intent = intentName,
			Sequence = sequence,
			Code = code,
		}, context())
		return ActionResult.fail(code, message)
	end

	if MatchOrchestrator.IsMatchComplete() then
		return reject(Enums.RejectReason.MatchEnded, "the match is over")
	end

	if type(intentName) ~= "string" or intentName == "" then
		return reject(Enums.RejectReason.IllegalAction, "intent name missing")
	end

	if not MatchOrchestrator.IsActivePlayer(userId) then
		return reject(Enums.RejectReason.NotYourTurn, "not the active player")
	end

	if type(sequence) ~= "number" or sequence % 1 ~= 0 then
		return reject(Enums.RejectReason.IllegalAction, "sequence must be an integer")
	end

	local last = _lastSequence[userId] or 0
	if sequence == last then
		return reject(Enums.RejectReason.DuplicateSequence, string.format("sequence %d already accepted", sequence))
	end
	if sequence < last then
		return reject(Enums.RejectReason.StaleSequence, string.format("sequence %d is behind %d", sequence, last))
	end

	_lastSequence[userId] = sequence
	_log.Append("IntentAccepted", {
		UserId = userId,
		Intent = intentName,
		Sequence = sequence,
	}, context())

	return ActionResult.ok({ UserId = userId, Intent = intentName, Sequence = sequence })
end

-- === Turn rotation ==========================================================
--
-- The rotation lives here rather than in MatchService because "whose turn is
-- it" and "what phase are we in" have to agree, and two modules each holding
-- half of that is how they silently diverge. MatchService's turn-gating
-- functions are superseded by these; see its header.

local _participants = {}
local _rotationIndex = 1

local function indexOfParticipant(userId)
	for index, id in ipairs(_participants) do
		if id == userId then
			return index
		end
	end
	return nil
end

function MatchOrchestrator.AddParticipant(userId)
	if userId == nil or indexOfParticipant(userId) then
		return false
	end
	table.insert(_participants, userId)
	_log.Append("ParticipantAdded", { UserId = userId, Count = #_participants }, context())
	return true
end

-- Keeps the rotation pointing at the same player it was on. Removing someone
-- earlier in the order would otherwise shift the index and silently skip or
-- repeat a turn.
function MatchOrchestrator.RemoveParticipant(userId)
	local index = indexOfParticipant(userId)
	if index == nil then
		return false
	end

	table.remove(_participants, index)

	if index < _rotationIndex then
		_rotationIndex -= 1
	end
	if _rotationIndex > #_participants then
		_rotationIndex = 1
	end

	if _activePlayerId == userId then
		_activePlayerId = nil
	end
	_lastSequence[userId] = nil

	_log.Append("ParticipantRemoved", { UserId = userId, Count = #_participants }, context())
	return true
end

function MatchOrchestrator.GetParticipants()
	local copy = {}
	for index, id in ipairs(_participants) do
		copy[index] = id
	end
	return copy
end

function MatchOrchestrator.GetParticipantSet()
	local set = {}
	for _, id in ipairs(_participants) do
		set[id] = true
	end
	return set
end

function MatchOrchestrator.GetParticipantCount()
	return #_participants
end

-- Returns the next player and whether the rotation wrapped. Wrapping is what
-- completes a round, and the caller uses it to decide whether to pass through
-- RoundEnd — the orchestrator does not transition on its own here, because
-- the phase move belongs to whoever is driving the turn.
function MatchOrchestrator.AdvanceToNextPlayer()
	if #_participants == 0 then
		return nil, false
	end

	local nextIndex = (_rotationIndex % #_participants) + 1
	local wrapped = nextIndex <= _rotationIndex
	_rotationIndex = nextIndex

	return _participants[_rotationIndex], wrapped
end

function MatchOrchestrator.PeekCurrentRotationPlayer()
	return _participants[_rotationIndex]
end

-- Wrap Init so rotation state resets with everything else. Done by
-- composition rather than by editing Init above, so the reset list cannot
-- drift out of sync with the state this section owns.
local baseInit = MatchOrchestrator.Init
function MatchOrchestrator.Init(options)
	_participants = {}
	_rotationIndex = 1
	return baseInit(options)
end

return MatchOrchestrator

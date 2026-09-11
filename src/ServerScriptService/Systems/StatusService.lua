--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > StatusService (ModuleScript)

	Purpose:
		Timed and persistent modifiers on players, creatures, territories,
		areas and the match itself — and the ordered hook dispatch that lets
		them intervene in the rules.

		This is the module that decides whether adding a card means editing a
		service or adding data. Without it, every effect that outlives its own
		resolution has to be a bespoke flag somewhere: BattleService already
		grew an `_attackBuffs` table for exactly one spell, and a forced roll,
		a poison, a silence and a global boost would each have grown another.
		Four unrelated booleans modelling the same idea is how a rules engine
		stops being editable.

	Hooks are a fold, not an announcement:
		A status attaches to named points (Enums.TimingHook) and TRANSFORMS the
		value passing through — RunHook threads a value through every attached
		status in order and returns the result. "ModifyRoll" is the clearest
		case: a forced roll replaces the value, a haste adds to it, a clamp
		bounds it, and the answer depends on the order they run in.

		Order is explicit priority first, then application order as a stable
		tiebreak, and the resolved order is logged. The brief requires that;
		it is also the only way a player can be told why their 3 became a 6.

	Definitions are code, instances are data:
		A status INSTANCE is a plain record — kind, target, duration, values —
		so cards can create them declaratively. The behaviour lives once in
		StatusDefinitions, keyed by kind. Cards therefore never carry
		functions, and a new card that poisons reuses the poison definition
		rather than describing poisoning again.

	Replacement groups:
		Two statuses in the same ReplacementGroup cannot coexist on one
		target: applying one removes the other. That is what makes "one
		movement effect at a time" expressible without every movement card
		knowing about every other movement card.

	Public API:
		StatusService.Init(deps)                 -- deps.Log
		StatusService.Apply(spec) -> ActionResult
		StatusService.Remove(statusId) -> boolean
		StatusService.RemoveKindFrom(kind, targetType, targetId) -> number
		StatusService.Get(statusId) -> status or nil
		StatusService.GetStatuses(targetType, targetId) -> array
		StatusService.HasKind(kind, targetType, targetId) -> boolean
		StatusService.RunHook(hook, context, value) -> value
		StatusService.FireHook(hook, context)          -- no value to thread
		StatusService.TickDurations(durationType, scopeUserId) -> expired count
		StatusService.GetDispatchOrder(hook) -> array of labels
		StatusService.ClearAll()

	Signals:
		StatusService.StatusApplied:Connect(function(status) end)
		StatusService.StatusExpired:Connect(function(status) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local ActionResult = require(ReplicatedStorage.Shared.ActionResult)
local Signal = require(ReplicatedStorage.Shared.Signal)
local StatusDefinitions = require(ServerScriptService.Systems.StatusDefinitions)

local StatusService = {}

StatusService.StatusApplied = Signal.new("Status.Applied")
StatusService.StatusExpired = Signal.new("Status.Expired")

local _log = nil
local _statuses = {}
local _order = {}
local _nextId = 1
local _nextOrder = 1

function StatusService.Init(deps)
	_log = (deps or {}).Log
	StatusService.ClearAll()
end

function StatusService.ClearAll()
	_statuses = {}
	_order = {}
	_nextId = 1
	_nextOrder = 1
end

local function targetKey(targetType, targetId)
	return string.format("%s:%s", tostring(targetType), tostring(targetId))
end

function StatusService.Get(statusId)
	return _statuses[statusId]
end

function StatusService.GetStatuses(targetType, targetId)
	local key = targetKey(targetType, targetId)
	local result = {}
	for _, statusId in ipairs(_order) do
		local status = _statuses[statusId]
		if status ~= nil and targetKey(status.TargetType, status.TargetId) == key then
			table.insert(result, status)
		end
	end
	return result
end

function StatusService.HasKind(kind, targetType, targetId)
	for _, status in ipairs(StatusService.GetStatuses(targetType, targetId)) do
		if status.Kind == kind then
			return true
		end
	end
	return false
end

local function removeFromOrder(statusId)
	for index, candidate in ipairs(_order) do
		if candidate == statusId then
			table.remove(_order, index)
			return
		end
	end
end

function StatusService.Remove(statusId)
	local status = _statuses[statusId]
	if status == nil then
		return false
	end
	_statuses[statusId] = nil
	removeFromOrder(statusId)

	if _log then
		_log.Append("StatusRemoved", { StatusId = statusId, Kind = status.Kind })
	end
	StatusService.StatusExpired:Fire(status)
	return true
end

function StatusService.RemoveKindFrom(kind, targetType, targetId)
	local removed = 0
	for _, status in ipairs(StatusService.GetStatuses(targetType, targetId)) do
		if status.Kind == kind then
			StatusService.Remove(status.StatusId)
			removed += 1
		end
	end
	return removed
end

-- Applies a status. `spec` names the kind, the target, and any per-instance
-- values; everything behavioural comes from the definition.
function StatusService.Apply(spec)
	if type(spec) ~= "table" then
		return ActionResult.fail(Enums.RejectReason.IllegalAction, "status spec must be a table")
	end

	local definition = StatusDefinitions.Get(spec.Kind)
	if definition == nil then
		return ActionResult.fail(
			Enums.RejectReason.IllegalAction,
			string.format("'%s' is not a known status", tostring(spec.Kind))
		)
	end

	local targetType = spec.TargetType or definition.TargetType
	if not Enums.isValid(Enums.StatusTarget, targetType) then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "unknown status target type")
	end

	local existing = StatusService.GetStatuses(targetType, spec.TargetId)
	local stacking = spec.StackingPolicy or definition.StackingPolicy or Enums.StackingPolicy.Replace

	for _, other in ipairs(existing) do
		local sameKind = other.Kind == spec.Kind
		-- Two statuses in one replacement group cannot coexist even when they
		-- are different kinds: that is the point of the group.
		local sameGroup = definition.ReplacementGroup ~= nil
			and other.ReplacementGroup == definition.ReplacementGroup

		if sameKind or sameGroup then
			if sameKind and stacking == Enums.StackingPolicy.Ignore then
				return ActionResult.ok({ StatusId = other.StatusId, Ignored = true })
			elseif sameKind and stacking == Enums.StackingPolicy.RefreshDuration then
				other.RemainingDuration = spec.RemainingDuration or definition.RemainingDuration or other.RemainingDuration
				return ActionResult.ok({ StatusId = other.StatusId, Refreshed = true })
			elseif stacking ~= Enums.StackingPolicy.Stack or sameGroup then
				StatusService.Remove(other.StatusId)
			end
		end
	end

	local statusId = string.format("s%d", _nextId)
	_nextId += 1

	local status = {
		StatusId = statusId,
		Kind = spec.Kind,
		TargetType = targetType,
		TargetId = spec.TargetId,
		OwnerPlayerId = spec.OwnerPlayerId,
		-- Whose turns this counts down on, when that is neither the caster nor
		-- the target. A poison on a creature is owned by the player who cast
		-- it and targets a NODE, so without this it would belong to nobody's
		-- turn and never expire. Whoever applies it knows; this module cannot.
		ScopeUserId = spec.ScopeUserId,
		SourceCardId = spec.SourceCardId,
		DurationType = spec.DurationType or definition.DurationType or Enums.DurationType.Permanent,
		RemainingDuration = spec.RemainingDuration or definition.RemainingDuration,
		ReplacementGroup = definition.ReplacementGroup,
		-- Lower runs first. Definitions set a sensible default so a card only
		-- states a priority when it genuinely needs to cut in front.
		Priority = spec.Priority or definition.Priority or 0,
		Order = _nextOrder,
		Value = spec.Value,
		Visibility = spec.Visibility or definition.Visibility or Enums.Visibility.Public,
		Definition = definition,
	}
	_nextOrder += 1

	_statuses[statusId] = status
	table.insert(_order, statusId)

	if _log then
		_log.Append("StatusApplied", {
			StatusId = statusId,
			Kind = status.Kind,
			Target = tostring(status.TargetId),
			Value = status.Value,
		})
	end
	StatusService.StatusApplied:Fire(status)

	return ActionResult.ok({ StatusId = statusId })
end

-- Every status attached to a hook, in resolved order: priority ascending,
-- then application order. Built fresh per dispatch because statuses come and
-- go constantly and a cached list would be wrong within one turn.
local function statusesForHook(hook, context)
	local matching = {}
	for _, statusId in ipairs(_order) do
		local status = _statuses[statusId]
		if status ~= nil and status.Definition.Hooks[hook] ~= nil then
			-- A status only fires for the thing it is attached to. A poison on
			-- one player must not tick on another player's turn end.
			if StatusDefinitions.AppliesTo(status, context) then
				table.insert(matching, status)
			end
		end
	end

	table.sort(matching, function(a, b)
		if a.Priority ~= b.Priority then
			return a.Priority < b.Priority
		end
		return a.Order < b.Order
	end)
	return matching
end

-- Threads `value` through every status attached to `hook`. A handler returns
-- the new value; returning nil leaves it unchanged, so a status that only
-- observes cannot erase what it was given.
function StatusService.RunHook(hook, context, value)
	if not Enums.isValid(Enums.TimingHook, hook) then
		error(string.format("'%s' is not a timing hook", tostring(hook)), 2)
	end

	local matching = statusesForHook(hook, context)
	if #matching == 0 then
		return value
	end

	local applied = {}
	for _, status in ipairs(matching) do
		local handler = status.Definition.Hooks[hook]
		local ok, result = pcall(handler, value, context or {}, status)

		if not ok then
			warn(string.format("[StatusService] %s handler for %s errored: %s", status.Kind, hook, tostring(result)))
		elseif result ~= nil then
			value = result
			table.insert(applied, string.format("%s=%s", status.Kind, tostring(result)))
		end

		-- A status may consume itself in its own handler (a forced roll is
		-- spent by the roll it forces), so re-check before continuing.
		if status.Consumed then
			StatusService.Remove(status.StatusId)
		end
	end

	-- The brief requires the resolved order to be logged: this is what makes
	-- "why was my roll a 6" answerable after the fact.
	if _log and #applied > 0 then
		_log.Append("HookResolved", { Hook = hook, Applied = table.concat(applied, ", ") })
	end

	return value
end

-- For hooks with nothing to thread (OnLap, TurnEnd) where statuses act by
-- side effect rather than by transforming a value.
function StatusService.FireHook(hook, context)
	StatusService.RunHook(hook, context, nil)
end

function StatusService.GetDispatchOrder(hook)
	local labels = {}
	for _, status in ipairs(statusesForHook(hook, nil)) do
		table.insert(labels, status.Kind)
	end
	return labels
end

-- Decrements every status of the given duration type and expires the ones
-- that run out. `scopeUserId` limits it to one player's statuses, because a
-- "lasts 3 turns" status should tick on ITS owner's turns, not on everyone's.
function StatusService.TickDurations(durationType, scopeUserId)
	local expired = 0

	for _, statusId in ipairs(table.clone(_order)) do
		local status = _statuses[statusId]
		if status ~= nil and status.DurationType == durationType then
			-- An explicit scope wins outright. Falling through to it would let
			-- a creature poison ALSO tick on its caster's turn, which is twice
			-- per round rather than once.
			local inScope
			if scopeUserId == nil then
				inScope = true
			elseif status.ScopeUserId ~= nil then
				inScope = status.ScopeUserId == scopeUserId
			else
				inScope = status.OwnerPlayerId == scopeUserId
					or status.TargetId == scopeUserId
			end

			if inScope and status.RemainingDuration ~= nil then
				status.RemainingDuration -= 1
				if status.RemainingDuration <= 0 then
					StatusService.Remove(statusId)
					expired += 1
				end
			end
		end
	end

	return expired
end

return StatusService

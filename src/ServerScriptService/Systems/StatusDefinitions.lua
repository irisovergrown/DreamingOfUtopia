--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > StatusDefinitions (ModuleScript)

	Purpose:
		What each kind of status actually DOES, keyed by kind.

		Behaviour has to be code — a hook is a function — but it lives here,
		once, rather than on cards. A card that poisons says
		`{ Kind = "Poison", Turns = 3 }` and reuses this definition; it does
		not describe poisoning. That split is what keeps CardData declarative
		while still allowing effects that are genuinely programmatic.

		Adding a status is adding an entry here plus the cards that apply it.
		No service changes, because StatusService dispatches whatever it finds.

	A definition may declare:
		TargetType        default attachment (Player, Creature, Territory, ...)
		DurationType      how it expires
		RemainingDuration default duration, overridable per instance
		StackingPolicy    what a second application does
		ReplacementGroup  statuses that cannot coexist on one target
		Priority          lower runs first within a hook
		Hooks             { [TimingHook] = function(value, context, status) }
		AppliesTo         optional extra filter beyond target matching

	Hook contract:
		A handler receives the running value, a context table, and its own
		status record. It returns the new value, or nil to leave it unchanged.
		Setting `status.Consumed = true` makes StatusService remove it after
		the handler returns — which is how a one-shot effect spends itself at
		the exact moment it applies rather than on a later tick.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local RulesConfig = require(ReplicatedStorage.Shared.RulesConfig)

local TimingHook = Enums.TimingHook
local StatusDefinitions = {}

local definitions = {}

-- === Movement ===============================================================

-- The Holy Word family: the next roll becomes exactly this number. Consumed by
-- the roll it forces, so it cannot leak into a later turn.
--
-- Priority is deliberately LOW (runs early) so that additive effects like a
-- haste apply on top of the forced value rather than being overwritten by it.
-- A forced roll that ran last would silently cancel everything else.
definitions.ForcedRoll = {
	TargetType = Enums.StatusTarget.Player,
	DurationType = Enums.DurationType.UntilNextRoll,
	StackingPolicy = Enums.StackingPolicy.Replace,
	ReplacementGroup = "RollOverride",
	Priority = -100,
	Hooks = {
		[TimingHook.ModifyRoll] = function(_value, _context, status)
			status.Consumed = true
			return status.Value
		end,
	},
}

-- Adds to the roll rather than replacing it, so it stacks on top of a forced
-- value. Priority 0 puts it after ForcedRoll by construction.
definitions.Haste = {
	TargetType = Enums.StatusTarget.Player,
	DurationType = Enums.DurationType.Turns,
	RemainingDuration = 2,
	StackingPolicy = Enums.StackingPolicy.RefreshDuration,
	Priority = 0,
	Hooks = {
		[TimingHook.ModifyRoll] = function(value, _context, status)
			return (value or 0) + (status.Value or 1)
		end,
	},
}

definitions.Slow = {
	TargetType = Enums.StatusTarget.Player,
	DurationType = Enums.DurationType.Turns,
	RemainingDuration = 2,
	StackingPolicy = Enums.StackingPolicy.RefreshDuration,
	Priority = 0,
	Hooks = {
		[TimingHook.ModifyRoll] = function(value, _context, status)
			return (value or 0) - (status.Value or 1)
		end,
	},
}

-- Runs last and bounds whatever the others produced. A roll of zero or a
-- negative roll is not a legal move, and clamping inside each individual
-- effect would mean every effect had to know the board's range.
definitions.RollClamp = {
	TargetType = Enums.StatusTarget.Global,
	DurationType = Enums.DurationType.Permanent,
	Priority = 1000,
	Hooks = {
		[TimingHook.ModifyRoll] = function(value, context, _status)
			local min = (context and context.Min) or RulesConfig.Roll.DefaultMin
			local max = (context and context.Max) or RulesConfig.Roll.DefaultMax
			return math.clamp(value or min, min, max)
		end,
	},
}

-- === Conditions =============================================================

-- Deferred out of Milestone 4 on purpose: poison is a DURATION, and modelling
-- it as a battle-local flag would have passed a test while modelling the wrong
-- thing. It needs exactly this framework to exist.
definitions.Poison = {
	TargetType = Enums.StatusTarget.Creature,
	DurationType = Enums.DurationType.Turns,
	RemainingDuration = 3,
	StackingPolicy = Enums.StackingPolicy.RefreshDuration,
	Priority = 0,
	Hooks = {
		[TimingHook.TurnEnd] = function(_value, context, status)
			context = context or {}

			-- The dispatch context is shared by every status in the fold, so it
			-- cannot carry "the" creature — each poison is on a different node.
			-- It carries a LOOKUP instead, and the status resolves its own
			-- target. A spec may pass Creature directly.
			local creature = context.Creature
			if creature == nil and context.GetCreature ~= nil then
				creature = context.GetCreature(status.TargetId)
			end

			-- Ticks on the turn of the player whose creature it is, once per
			-- round, not once per opponent. UNVERIFIED against the source game:
			-- Saga may tick at the start of the afflicted player's turn instead,
			-- which differs by one tick when the poison is applied mid-round.
			if creature ~= nil
				and context.UserId ~= nil
				and creature.OwnerUserId ~= nil
				and creature.OwnerUserId ~= context.UserId
			then
				return nil
			end

			if creature == nil then
				return nil
			end

			-- Applied through the owner of defender state when one is reachable,
			-- so the board repaints. Writing to the table directly works and is
			-- invisible — the creature quietly loses HP and every display keeps
			-- showing the old number. A spec passing a bare Creature falls back
			-- to the direct write, which is the only case with no board to tell.
			if context.DamageCreature ~= nil then
				context.DamageCreature(status.TargetId, status.Value or 10)
			else
				-- Floors at 1: poison cannot kill on its own.
				creature.CurrentHP = math.max(creature.CurrentHP - (status.Value or 10), 1)
			end
			return nil
		end,
	},
}

-- Skips the affected player's roll entirely. Expressed as a movement
-- override rather than a flag MovementService checks, so anything that grants
-- or removes it goes through the same path as every other status.
definitions.Paralysis = {
	TargetType = Enums.StatusTarget.Player,
	DurationType = Enums.DurationType.Turns,
	RemainingDuration = 1,
	StackingPolicy = Enums.StackingPolicy.Replace,
	ReplacementGroup = "RollOverride",
	Priority = -200,
	Hooks = {
		[TimingHook.BeforeRoll] = function(_value, _context, _status)
			-- Returning false tells the caller the roll does not happen.
			return false
		end,
	},
}

-- === Battle =================================================================

-- The ST bonus Signal Boost used to implement with a bespoke table inside
-- BattleService. Same behaviour, now one of many rather than a special case.
definitions.AttackBoost = {
	TargetType = Enums.StatusTarget.Player,
	DurationType = Enums.DurationType.UntilBattleEnd,
	StackingPolicy = Enums.StackingPolicy.Stack,
	Priority = 0,
	Hooks = {
		[TimingHook.BeforeBattleStats] = function(value, context, status)
			if context and context.IsAttacker then
				status.Consumed = true
				return (value or 0) + (status.Value or 0)
			end
			return nil
		end,
	},
}

-- A match-wide modifier with no target: every creature's ST shifts. Proves
-- the Global target type carries its weight rather than being an unused enum
-- entry.
definitions.GlobalAttackShift = {
	TargetType = Enums.StatusTarget.Global,
	DurationType = Enums.DurationType.Rounds,
	RemainingDuration = 1,
	StackingPolicy = Enums.StackingPolicy.Stack,
	Priority = 10,
	Hooks = {
		[TimingHook.BeforeBattleStats] = function(value, _context, status)
			return (value or 0) + (status.Value or 0)
		end,
	},
}

-- === Dispatch filtering =====================================================

-- Whether a status should fire for this particular dispatch. Target matching
-- is the common case; a Global status always fires. Without this, one
-- player's poison would tick on every player's turn end.
function StatusDefinitions.AppliesTo(status, context)
	if status.TargetType == Enums.StatusTarget.Global then
		return true
	end
	if context == nil then
		return true
	end

	if status.TargetType == Enums.StatusTarget.Player then
		return context.UserId == nil or context.UserId == status.TargetId
	end
	if status.TargetType == Enums.StatusTarget.Creature then
		return context.NodeId == nil or context.NodeId == status.TargetId
	end
	if status.TargetType == Enums.StatusTarget.Territory then
		return context.NodeId == nil or context.NodeId == status.TargetId
	end
	if status.TargetType == Enums.StatusTarget.Area then
		return context.AreaId == nil or context.AreaId == status.TargetId
	end

	return true
end

function StatusDefinitions.Get(kind)
	return definitions[kind]
end

function StatusDefinitions.GetAllKinds()
	local kinds = {}
	for kind in pairs(definitions) do
		table.insert(kinds, kind)
	end
	table.sort(kinds)
	return kinds
end

return StatusDefinitions

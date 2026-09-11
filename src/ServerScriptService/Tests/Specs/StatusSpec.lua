--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > StatusSpec (ModuleScript)

	The Milestone 6 status engine. These are mostly ORDERING tests, because
	ordering is the whole reason this module exists: "a forced roll, a haste
	and a clamp all apply" is trivially satisfiable by any of six different
	answers, and only one of them is right.

	Poison and paralysis appear here rather than in BattleSpec on purpose —
	they were deferred out of Milestone 4 precisely because they are durations
	that outlive a battle, and this is the framework that gives them somewhere
	to live.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local StatusService = require(ServerScriptService.Systems.StatusService)
local MovementService = require(ServerScriptService.Systems.MovementService)
local BoardGraphService = require(ServerScriptService.Systems.BoardGraphService)
local LapService = require(ServerScriptService.Systems.LapService)
local RandomService = require(ServerScriptService.Systems.RandomService)
local CurrentLoop = require(ReplicatedStorage.Shared.BoardDefinitions.CurrentLoop)

local Hook = Enums.TimingHook
local Target = Enums.StatusTarget

local ALICE, BOB = 501, 502
local NODE = "T5"

local function fresh()
	StatusService.Init({})
	StatusService.ClearAll()
end

-- Applies a status and returns its id, asserting the application succeeded so
-- a later assertion cannot pass for the wrong reason.
local function apply(spec)
	local result = StatusService.Apply(spec)
	assert(result.Ok, "status refused: " .. tostring(result.Message))
	return result.Payload.StatusId
end

local function rollFor(userId, natural)
	return StatusService.RunHook(Hook.ModifyRoll, {
		UserId = userId,
		Min = 1,
		Max = 6,
		Natural = natural,
	}, natural)
end

return {
	Name = "Status",
	Tests = {
		-- === Ordering ===============================================

		{ "hooks resolve in priority order, not application order", function(t)
			fresh()
			-- Applied haste FIRST and forced roll SECOND. If dispatch used
			-- application order, the forced 6 would overwrite the haste and
			-- the answer would be 6.
			apply({ Kind = "Haste", TargetId = ALICE, Value = 2 })
			apply({ Kind = "ForcedRoll", TargetId = ALICE, Value = 6 })

			t:Equal(rollFor(ALICE, 3), 8, "forced value first, then added to")
		end },

		{ "the clamp runs last and bounds whatever the others produced", function(t)
			fresh()
			apply({ Kind = "RollClamp" })
			apply({ Kind = "ForcedRoll", TargetId = ALICE, Value = 6 })
			apply({ Kind = "Haste", TargetId = ALICE, Value = 2 })

			t:Equal(rollFor(ALICE, 3), 6, "8 clamped back to the legal maximum")
		end },

		{ "the resolved order is reportable", function(t)
			fresh()
			apply({ Kind = "RollClamp" })
			apply({ Kind = "Haste", TargetId = ALICE, Value = 2 })
			apply({ Kind = "ForcedRoll", TargetId = ALICE, Value = 6 })

			t:DeepEqual(
				StatusService.GetDispatchOrder(Hook.ModifyRoll),
				{ "ForcedRoll", "Haste", "RollClamp" },
				"-100, then 0, then 1000"
			)
		end },

		{ "a status that only observes cannot erase the running value", function(t)
			fresh()
			-- Poison's TurnEnd handler returns nil. A fold that treated nil as
			-- "the new value" would wipe everything computed before it.
			apply({ Kind = "Poison", TargetType = Target.Creature, TargetId = NODE, Value = 10 })
			t:Equal(StatusService.RunHook(Hook.TurnEnd, { NodeId = NODE }, 7), 7)
		end },

		-- === Consumption and duration ================================

		{ "a forced roll is spent by the roll it forces", function(t)
			fresh()
			apply({ Kind = "ForcedRoll", TargetId = ALICE, Value = 6 })

			t:Equal(rollFor(ALICE, 2), 6, "first roll is forced")
			t:False(
				StatusService.HasKind("ForcedRoll", Target.Player, ALICE),
				"and removed itself in the same dispatch"
			)
			t:Equal(rollFor(ALICE, 2), 2, "the next roll is the natural one")
		end },

		{ "a turn-scoped status ticks down on its own player's turns only", function(t)
			fresh()
			apply({ Kind = "Haste", TargetId = ALICE, Value = 2, RemainingDuration = 2 })

			StatusService.TickDurations(Enums.DurationType.Turns, BOB)
			t:True(StatusService.HasKind("Haste", Target.Player, ALICE), "Bob's turn is not Alice's")

			StatusService.TickDurations(Enums.DurationType.Turns, ALICE)
			t:True(StatusService.HasKind("Haste", Target.Player, ALICE), "one of two turns used")

			StatusService.TickDurations(Enums.DurationType.Turns, ALICE)
			t:False(StatusService.HasKind("Haste", Target.Player, ALICE), "expired on the second")
		end },

		{ "a creature status ticks on the creature owner's turns, not the caster's", function(t)
			fresh()
			-- Cast by Alice onto Bob's creature. Without an explicit scope this
			-- status belongs to Alice (the caster) and a node id (the target),
			-- so it would tick on the wrong turns — or on both.
			apply({
				Kind = "Poison",
				TargetType = Target.Creature,
				TargetId = NODE,
				OwnerPlayerId = ALICE,
				ScopeUserId = BOB,
				Value = 10,
				RemainingDuration = 1,
			})

			StatusService.TickDurations(Enums.DurationType.Turns, ALICE)
			t:True(
				StatusService.HasKind("Poison", Target.Creature, NODE),
				"the caster's turn does not spend the defender's poison"
			)

			StatusService.TickDurations(Enums.DurationType.Turns, BOB)
			t:False(StatusService.HasKind("Poison", Target.Creature, NODE))
		end },

		{ "a round-scoped status survives individual turns", function(t)
			fresh()
			apply({ Kind = "GlobalAttackShift", Value = 10, RemainingDuration = 1 })

			StatusService.TickDurations(Enums.DurationType.Turns, ALICE)
			StatusService.TickDurations(Enums.DurationType.Turns, BOB)
			t:True(StatusService.HasKind("GlobalAttackShift", Target.Global, nil))

			StatusService.TickDurations(Enums.DurationType.Rounds)
			t:False(StatusService.HasKind("GlobalAttackShift", Target.Global, nil))
		end },

		-- === Stacking ================================================

		{ "a replacement group evicts a different kind on the same target", function(t)
			fresh()
			apply({ Kind = "ForcedRoll", TargetId = ALICE, Value = 6 })
			apply({ Kind = "Paralysis", TargetId = ALICE })

			t:False(
				StatusService.HasKind("ForcedRoll", Target.Player, ALICE),
				"you cannot be both forced to roll a 6 and unable to roll"
			)
			t:Equal(#StatusService.GetStatuses(Target.Player, ALICE), 1)
		end },

		{ "RefreshDuration extends the existing status rather than adding one", function(t)
			fresh()
			apply({ Kind = "Haste", TargetId = ALICE, Value = 2, RemainingDuration = 1 })
			apply({ Kind = "Haste", TargetId = ALICE, Value = 2, RemainingDuration = 5 })

			local held = StatusService.GetStatuses(Target.Player, ALICE)
			t:Equal(#held, 1, "one haste, not two")
			t:Equal(held[1].RemainingDuration, 5, "refreshed to the longer duration")
			t:Equal(rollFor(ALICE, 3), 5, "and adds 2 once, not 4")
		end },

		{ "Stack keeps both copies and both apply", function(t)
			fresh()
			apply({ Kind = "AttackBoost", TargetId = ALICE, Value = 20 })
			apply({ Kind = "AttackBoost", TargetId = ALICE, Value = 30 })

			t:Equal(#StatusService.GetStatuses(Target.Player, ALICE), 2)
			t:Equal(
				StatusService.RunHook(Hook.BeforeBattleStats, { UserId = ALICE, IsAttacker = true }, 0),
				50,
				"both boosts land"
			)
		end },

		-- === Targeting ===============================================

		{ "a player status does not fire for a different player", function(t)
			fresh()
			apply({ Kind = "Haste", TargetId = ALICE, Value = 2 })
			t:Equal(rollFor(BOB, 3), 3, "Bob rolls what the dice said")
			t:Equal(rollFor(ALICE, 3), 5)
		end },

		{ "a global status fires for everyone", function(t)
			fresh()
			apply({ Kind = "GlobalAttackShift", Value = 10 })

			t:Equal(StatusService.RunHook(Hook.BeforeBattleStats, { UserId = ALICE }, 0), 10)
			t:Equal(StatusService.RunHook(Hook.BeforeBattleStats, { UserId = BOB }, 0), 10)
		end },

		{ "an attack boost applies to the attacker only, and is then spent", function(t)
			fresh()
			apply({ Kind = "AttackBoost", TargetId = ALICE, Value = 20 })

			t:Equal(
				StatusService.RunHook(Hook.BeforeBattleStats, { UserId = ALICE, IsAttacker = false }, 0),
				0,
				"defending with it does not consume or apply it"
			)
			t:True(StatusService.HasKind("AttackBoost", Target.Player, ALICE))

			t:Equal(
				StatusService.RunHook(Hook.BeforeBattleStats, { UserId = ALICE, IsAttacker = true }, 0),
				20
			)
			t:False(StatusService.HasKind("AttackBoost", Target.Player, ALICE), "spent by the battle")
		end },

		-- === Poison ==================================================

		{ "poison damages the creature on its owner's turn end", function(t)
			fresh()
			local creature = { OwnerUserId = BOB, CurrentHP = 25 }
			local context = {
				GetCreature = function(nodeId)
					return nodeId == NODE and creature or nil
				end,
			}

			apply({
				Kind = "Poison",
				TargetType = Target.Creature,
				TargetId = NODE,
				ScopeUserId = BOB,
				Value = 10,
			})

			context.UserId = ALICE
			StatusService.FireHook(Hook.TurnEnd, context)
			t:Equal(creature.CurrentHP, 25, "not on an opponent's turn")

			context.UserId = BOB
			StatusService.FireHook(Hook.TurnEnd, context)
			t:Equal(creature.CurrentHP, 15)
		end },

		{ "poison floors at 1 and cannot kill on its own", function(t)
			fresh()
			local creature = { OwnerUserId = BOB, CurrentHP = 8 }
			apply({
				Kind = "Poison",
				TargetType = Target.Creature,
				TargetId = NODE,
				ScopeUserId = BOB,
				Value = 10,
			})

			StatusService.FireHook(Hook.TurnEnd, { UserId = BOB, Creature = creature })
			t:Equal(
				creature.CurrentHP,
				1,
				"a creature dying outside a battle would leave a territory owned by nothing"
			)
		end },

		{ "poison damages through the owner of defender state, not the table", function(t)
			fresh()
			local damaged = {}
			apply({
				Kind = "Poison",
				TargetType = Target.Creature,
				TargetId = NODE,
				ScopeUserId = BOB,
				Value = 10,
			})

			StatusService.FireHook(Hook.TurnEnd, {
				UserId = BOB,
				GetCreature = function() return { OwnerUserId = BOB, CurrentHP = 40 } end,
				-- Standing in for BattleService.DamageDefender. A status that
				-- writes CurrentHP directly works and is invisible: the board
				-- repaints on that service's signal, not on the write.
				DamageCreature = function(nodeId, amount)
					table.insert(damaged, { NodeId = nodeId, Amount = amount })
				end,
			})

			t:DeepEqual(damaged, { { NodeId = NODE, Amount = 10 } })
		end },

		{ "poison on one node does not tick a creature on another", function(t)
			fresh()
			local creature = { OwnerUserId = BOB, CurrentHP = 40 }
			apply({
				Kind = "Poison",
				TargetType = Target.Creature,
				TargetId = "T9",
				ScopeUserId = BOB,
				Value = 10,
			})

			StatusService.FireHook(Hook.TurnEnd, {
				UserId = BOB,
				NodeId = NODE,
				GetCreature = function() return creature end,
			})
			t:Equal(creature.CurrentHP, 40)
		end },

		-- === Movement integration ====================================

		{ "paralysis refuses the roll rather than modifying it", function(t)
			fresh()
			BoardGraphService.Load(CurrentLoop)
			LapService.Init({ Graph = BoardGraphService })
			MovementService.Init({
				Graph = BoardGraphService,
				Lap = LapService,
				Random = RandomService.new(7),
				Status = StatusService,
			})

			t:True(MovementService.CanRoll(ALICE), "nothing stops an ordinary roll")

			apply({ Kind = "Paralysis", TargetId = ALICE })
			t:False(MovementService.CanRoll(ALICE))
			t:True(MovementService.CanRoll(BOB), "and only for the afflicted player")
		end },

		{ "a modified roll reports the natural roll alongside the total", function(t)
			fresh()
			BoardGraphService.Load(CurrentLoop)
			LapService.Init({ Graph = BoardGraphService })
			MovementService.Init({
				Graph = BoardGraphService,
				Lap = LapService,
				Random = RandomService.new(7),
				Status = StatusService,
			})

			apply({ Kind = "ForcedRoll", TargetId = ALICE, Value = 4 })
			local total, rolls, natural = MovementService.RollDice(1, ALICE)

			t:Equal(total, 4, "the forced value")
			t:Equal(natural, rolls[1], "the dice still rolled something")
			t:NotEqual(
				natural,
				nil,
				"a player whose roll was changed has to be able to see that it was"
			)
		end },

		{ "a roll with no statuses is the natural roll untouched", function(t)
			fresh()
			BoardGraphService.Load(CurrentLoop)
			LapService.Init({ Graph = BoardGraphService })
			MovementService.Init({
				Graph = BoardGraphService,
				Lap = LapService,
				Random = RandomService.new(7),
				Status = StatusService,
			})

			local total, _rolls, natural = MovementService.RollDice(1, ALICE)
			t:Equal(total, natural)
		end },

		-- === Robustness ==============================================

		{ "an unknown status kind is refused, not silently created", function(t)
			fresh()
			local result = StatusService.Apply({ Kind = "Nonsense", TargetId = ALICE })
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.IllegalAction)
			t:Equal(#StatusService.GetStatuses(Target.Player, ALICE), 0)
		end },

		{ "a handler that errors does not stop the ones after it", function(t)
			fresh()
			local statusId = apply({ Kind = "Haste", TargetId = ALICE, Value = 2 })
			apply({ Kind = "Haste", TargetId = BOB, Value = 3 })

			-- Swapped in deliberately: no shipped definition throws, and the
			-- isolation guarantee is worth asserting anyway, because the whole
			-- point of a fold is that one bad card cannot strand a turn.
			local broken = StatusService.Get(statusId)
			broken.Definition = {
				Hooks = {
					[Hook.ModifyRoll] = function()
						error("deliberate")
					end,
				},
			}

			t:DoesNotThrow(function()
				rollFor(ALICE, 3)
			end)
			t:Equal(rollFor(BOB, 3), 6, "an unrelated player's statuses are unaffected")
		end },

		{ "removing a status stops it applying", function(t)
			fresh()
			local statusId = apply({ Kind = "Haste", TargetId = ALICE, Value = 2 })
			t:Equal(rollFor(ALICE, 3), 5)

			t:True(StatusService.Remove(statusId))
			t:Equal(rollFor(ALICE, 3), 3)
			t:False(StatusService.Remove(statusId), "removing it twice is not a second removal")
		end },
	},
}

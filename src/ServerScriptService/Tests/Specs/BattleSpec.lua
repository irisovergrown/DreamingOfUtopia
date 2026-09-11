--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > BattleSpec (ModuleScript)

	The brief's "Battle" acceptance criteria. Built on stubbed board, economy
	and deck services so a battle can be set up in three lines with exactly the
	cards, element and level a case needs — a live match cannot be steered
	precisely enough to test a strike order.

	Poison and paralysis are absent on purpose. They are statuses with
	durations that outlive a battle, StatusService arrives in Milestone 6, and
	faking them as battle-local flags would pass a test while modelling the
	wrong thing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local CardData = require(ReplicatedStorage.Shared.CardData)
local BattleService = require(ServerScriptService.Systems.BattleService)

local ATTACKER, DEFENDER = 111, 222
local TILE = 5

-- Card ids used often enough to name.
local TAPE_GNOME = 1 -- Earth, ST 40, HP 60
local LASER_SALAMANDER = 2 -- Fire, ST 60, HP 50
local CHROME_VULCAN = 7 -- Fire, ST 50, HP 40, First
local FERRITE_GOLEM = 11 -- Earth, ST 30, HP 80, Last
local SPOOL_WARDEN = 12 -- Earth, ST 35, HP 55, Neutralize
local AERO_NEREID = 13 -- Water, ST 45, HP 45, Reflect
local SIGNAL_DRONE = 15 -- Neutral, ST 25, HP 25
local GRID_PHOENIX = 8 -- Fire, ST 40, HP 60, Regenerate
local PACKET_WRAITH = 9 -- Air, ST 45, HP 30, Penetration
local DAEMON_COURIER = 10 -- Air, ST 30, HP 50, Support
local CATHODE_LANCE = 17 -- Weapon, +30 ST
local MYLAR_PLATING = 18 -- Armor, +30 HP
local STATIC_SCROLL = 19 -- Scroll, 40 damage
local RIBBON_CUTTER = 20 -- Weapon, +20 ST, Critical
local SIGNAL_BOOST = 5 -- Spell

local cardsById = {}
for _, card in ipairs(CardData.Cards) do
	cardsById[card.Id] = card
end

-- Stub world. `tile` is mutated per test to set element and level.
local tile
local balances
local hands
local nextInstance

local function stubs()
	tile = { Id = TILE, TileType = "Property", Element = nil, Level = 1, Owner = DEFENDER }
	balances = { [ATTACKER] = 9999, [DEFENDER] = 9999 }
	hands = { [ATTACKER] = {}, [DEFENDER] = {} }
	nextInstance = 1

	-- Stands in for TerritoryService. `tile` is a territory snapshot: the
	-- shape BattleService reads is Element, Level and Owner.
	local territory = {
		GetTerritory = function(nodeId)
			return nodeId == TILE and tile or nil
		end,
		SetOwner = function(_, ownerUserId)
			tile.Owner = ownerUserId
		end,
	}

	local economy = {
		SpendMagic = function(userId, amount)
			if balances[userId] < amount then
				return false, "Not enough Magic"
			end
			balances[userId] -= amount
			return true, balances[userId]
		end,
	}

	-- Declared before it is populated: inside a `local deck = { ... }`
	-- constructor the name is not yet in scope, so a closure written there
	-- would capture the global `deck` (nil) rather than this table.
	local deck = {}
	deck.Returned = {}
	deck.GetInstance = function(userId, instanceId)
		return hands[userId][instanceId]
	end
	deck.PlayInstance = function(userId, instanceId)
		hands[userId][instanceId] = nil
	end
	deck.ReturnToHand = function(userId, cardId)
		table.insert(deck.Returned, { UserId = userId, CardId = cardId })
	end

	BattleService.Init({
		Territory = territory,
		Card = { GetCard = function(cardId) return cardsById[cardId] end },
		Economy = economy,
		Deck = deck,
	})

	return deck
end

-- Puts a card in a hand and returns its instance id.
local function give(userId, cardId)
	local instanceId = "i" .. nextInstance
	nextInstance += 1
	hands[userId][instanceId] = { InstanceId = instanceId, CardId = cardId }
	return instanceId
end

-- Installs a defender directly, bypassing the summon path.
local function placeDefender(cardId)
	local instanceId = give(DEFENDER, cardId)
	tile.Owner = nil
	local result = BattleService.SummonCreature(DEFENDER, instanceId, TILE)
	assert(result.Ok, "could not place defender")
	return BattleService.GetDefender(TILE)
end

-- Runs a whole invasion with the given item choices and returns the result.
local function invade(attackerCardId, attackerItemCardId, defenderItemCardId)
	local attackerInstance = give(ATTACKER, attackerCardId)
	local began = BattleService.BeginInvasion(ATTACKER, attackerInstance, TILE)
	assert(began.Ok, "invasion refused: " .. tostring(began.Message))

	local attackerItem = attackerItemCardId and give(ATTACKER, attackerItemCardId) or nil
	BattleService.ChooseAttackerItem(ATTACKER, attackerItem)

	local defenderItem = defenderItemCardId and give(DEFENDER, defenderItemCardId) or nil
	return BattleService.ChooseDefenderItem(DEFENDER, defenderItem)
end

return {
	Name = "Battle",
	Tests = {
		{ "summoning claims an empty territory and records the defender", function(t)
			stubs()
			local state = placeDefender(TAPE_GNOME)

			t:Equal(tile.Owner, DEFENDER)
			t:Equal(state.CardId, TAPE_GNOME)
			t:Equal(state.CurrentHP, 60, "full health, with no land bonus folded in")
			t:Equal(state.BaseMHP, 60)
		end },

		{ "the land bonus is never written into the creature", function(t)
			-- The defect this milestone exists to fix. A matching element must
			-- not inflate the stored health, or a later terraform leaves it
			-- stale with no way to tell.
			stubs()
			tile.Element = "Earth"
			tile.Level = 3
			local state = placeDefender(TAPE_GNOME)

			t:Equal(state.CurrentHP, 60, "stored health is the card's own")
			t:Equal(BattleService.GetLandBonusFor(state, TILE), 30, "the bonus is computed, not stored")

			-- Change the land underneath it; the bonus follows immediately.
			tile.Element = "Fire"
			t:Equal(BattleService.GetLandBonusFor(state, TILE), 0, "mismatched element, no bonus")
		end },

		{ "a neutral creature never receives a land bonus", function(t)
			stubs()
			tile.Element = "Earth"
			tile.Level = 5
			local state = placeDefender(SIGNAL_DRONE)
			t:Equal(BattleService.GetLandBonusFor(state, TILE), 0)
		end },

		{ "the invader chooses an item before the defender", function(t)
			stubs()
			placeDefender(TAPE_GNOME)
			local attackerInstance = give(ATTACKER, LASER_SALAMANDER)
			BattleService.BeginInvasion(ATTACKER, attackerInstance, TILE)

			t:Equal(BattleService.GetPendingBattle().Status, "AwaitingAttackerItem")

			-- The defender cannot pre-empt the window.
			local early = BattleService.ChooseDefenderItem(DEFENDER, nil)
			t:False(early.Ok, "defender cannot choose first")
			t:Equal(early.Code, Enums.RejectReason.WrongPhase)

			BattleService.ChooseAttackerItem(ATTACKER, nil)
			t:Equal(BattleService.GetPendingBattle().Status, "AwaitingDefenderItem")
		end },

		{ "a player cannot make the other side's item choice", function(t)
			stubs()
			placeDefender(TAPE_GNOME)
			BattleService.BeginInvasion(ATTACKER, give(ATTACKER, LASER_SALAMANDER), TILE)

			local wrong = BattleService.ChooseAttackerItem(DEFENDER, nil)
			t:False(wrong.Ok)
			t:Equal(wrong.Code, Enums.RejectReason.NotAParticipant)
		end },

		{ "the defender sees the invader's committed item", function(t)
			stubs()
			placeDefender(TAPE_GNOME)
			BattleService.BeginInvasion(ATTACKER, give(ATTACKER, LASER_SALAMANDER), TILE)
			BattleService.ChooseAttackerItem(ATTACKER, give(ATTACKER, CATHODE_LANCE))

			t:Equal(BattleService.GetPendingBattle().AttackerItemCardId, CATHODE_LANCE,
				"the commitment is visible before the defender decides")
		end },

		{ "a spell cannot be used as a battle item", function(t)
			stubs()
			placeDefender(TAPE_GNOME)
			BattleService.BeginInvasion(ATTACKER, give(ATTACKER, LASER_SALAMANDER), TILE)

			local result = BattleService.ChooseAttackerItem(ATTACKER, give(ATTACKER, SIGNAL_BOOST))
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.RuleViolation)
		end },

		{ "only a Support creature may use a creature as its item", function(t)
			stubs()
			placeDefender(TAPE_GNOME)

			-- Laser Salamander has no Support keyword.
			BattleService.BeginInvasion(ATTACKER, give(ATTACKER, LASER_SALAMANDER), TILE)
			local refused = BattleService.ChooseAttackerItem(ATTACKER, give(ATTACKER, SIGNAL_DRONE))
			t:False(refused.Ok, "a creature item needs Support")
			BattleService.ChooseAttackerItem(ATTACKER, nil)
			BattleService.ChooseDefenderItem(DEFENDER, nil)

			-- Daemon Courier has it.
			stubs()
			placeDefender(TAPE_GNOME)
			BattleService.BeginInvasion(ATTACKER, give(ATTACKER, DAEMON_COURIER), TILE)
			local allowed = BattleService.ChooseAttackerItem(ATTACKER, give(ATTACKER, SIGNAL_DRONE))
			t:True(allowed.Ok, "Support permits it")
		end },

		{ "declining an item is always legal", function(t)
			stubs()
			placeDefender(TAPE_GNOME)
			BattleService.BeginInvasion(ATTACKER, give(ATTACKER, LASER_SALAMANDER), TILE)

			t:True(BattleService.ChooseAttackerItem(ATTACKER, nil).Ok)
			t:True(BattleService.ChooseDefenderItem(DEFENDER, nil).Ok)
		end },

		{ "invader wins: territory transfers and no toll is owed", function(t)
			stubs()
			placeDefender(SIGNAL_DRONE) -- 25 HP
			local result = invade(LASER_SALAMANDER, nil, nil) -- ST 60

			t:Equal(result.Payload.Outcome, Enums.BattleOutcome.AttackerTakesTerritory)
			t:False(result.Payload.TollOwed, "a winner pays nothing")
			t:Equal(tile.Owner, ATTACKER, "ownership transferred")
			t:Equal(BattleService.GetDefender(TILE).CardId, LASER_SALAMANDER, "and it now defends")
		end },

		{ "invader dies: defender holds and the visitor owes the toll", function(t)
			stubs()
			placeDefender(FERRITE_GOLEM) -- HP 80, ST 30, Last
			local result = invade(SIGNAL_DRONE, nil, nil) -- ST 25, HP 25

			t:Equal(result.Payload.Outcome, Enums.BattleOutcome.DefenderHolds)
			t:True(result.Payload.TollOwed)
			t:Equal(tile.Owner, DEFENDER, "territory retained")
		end },

		{ "both survive: the invader returns to hand and the toll is owed", function(t)
			local deck = stubs()
			placeDefender(FERRITE_GOLEM) -- ST 30, HP 80
			local result = invade(TAPE_GNOME, nil, nil) -- ST 40, HP 60

			t:Equal(result.Payload.Outcome, Enums.BattleOutcome.BothSurvive)
			t:True(result.Payload.TollOwed)
			t:Equal(tile.Owner, DEFENDER)
			t:Equal(#deck.Returned, 1, "the invader went back to hand")
			t:Equal(deck.Returned[1].CardId, TAPE_GNOME)
		end },

		{ "an attacker can be killed by its own reflected strike", function(t)
			stubs()
			placeDefender(AERO_NEREID) -- ST 45, HP 45, Reflect
			local result = invade(CHROME_VULCAN, nil, nil) -- First, ST 50, HP 40

			-- Vulcan strikes first for 50; Reflect zeroes it and returns all 50
			-- onto Vulcan's own 40 HP. The reflector is untouched.
			t:Equal(result.Payload.Outcome, Enums.BattleOutcome.DefenderHolds)
			t:True(result.Payload.AttackerDestroyed, "killed by its own reflected strike")
			t:True(result.Payload.TollOwed)
		end },

		{ "the both-destroyed outcome is handled but not yet reachable", function(t)
			-- Worth stating rather than quietly omitting. Strikes resolve
			-- sequentially and a destroyed creature does not counterattack, so
			-- no combination of the current keywords kills both sides: the
			-- only way to die while killing is Reflect, which zeroes the
			-- incoming damage and so spares the reflector.
			--
			-- It becomes reachable with simultaneous-damage effects in
			-- Milestone 6. The branch exists and vacates the territory; this
			-- records that it is deliberately untested by live play rather
			-- than forgotten.
			t:NotNil(Enums.BattleOutcome.BothDestroyed, "the outcome is defined")

			stubs()
			placeDefender(SIGNAL_DRONE)
			local result = invade(LASER_SALAMANDER, nil, nil)
			t:NotEqual(result.Payload.Outcome, Enums.BattleOutcome.BothDestroyed,
				"and an ordinary exchange never produces it")
		end },

		{ "a lethal first strike prevents the counterattack", function(t)
			stubs()
			placeDefender(SIGNAL_DRONE) -- ST 25, HP 25
			local result = invade(CHROME_VULCAN, nil, nil) -- First, ST 50

			t:Equal(#result.Payload.Log, 1, "exactly one strike was thrown")
			t:Equal(result.Payload.Outcome, Enums.BattleOutcome.AttackerTakesTerritory)
			t:False(result.Payload.AttackerDestroyed, "the dead defender did not hit back")
		end },

		{ "First strikes before Normal, whichever side holds it", function(t)
			-- Attacker is First.
			stubs()
			placeDefender(SIGNAL_DRONE)
			local a = invade(CHROME_VULCAN, nil, nil)
			t:Equal(a.Payload.Log[1].Striker, CHROME_VULCAN, "attacking First goes first")

			-- Defender is First. Same rule, other side.
			stubs()
			placeDefender(CHROME_VULCAN)
			local b = invade(SIGNAL_DRONE, nil, nil)
			t:Equal(b.Payload.Log[1].Striker, CHROME_VULCAN, "defending First still goes first")
		end },

		{ "Normal strikes before Last", function(t)
			stubs()
			placeDefender(FERRITE_GOLEM) -- Last
			local result = invade(TAPE_GNOME, nil, nil) -- Normal
			t:Equal(result.Payload.Log[1].Striker, TAPE_GNOME)

			stubs()
			placeDefender(TAPE_GNOME) -- Normal
			local other = invade(FERRITE_GOLEM, nil, nil) -- Last attacking
			t:Equal(other.Payload.Log[1].Striker, TAPE_GNOME, "the Normal defender goes first")
		end },

		{ "on equal speed the invader strikes first", function(t)
			stubs()
			placeDefender(TAPE_GNOME) -- Normal
			local result = invade(LASER_SALAMANDER, nil, nil) -- Normal
			t:Equal(result.Payload.Log[1].Striker, LASER_SALAMANDER, "the invader")

			-- And with both Last.
			stubs()
			placeDefender(FERRITE_GOLEM)
			local both = invade(FERRITE_GOLEM, nil, nil)
			t:Equal(both.Payload.Log[1].Striker, FERRITE_GOLEM)
		end },

		{ "the land bonus decides a battle it would otherwise lose", function(t)
			-- Tape Gnome on matching Earth at level 3 gets +30, so 60 becomes
			-- an effective 90 and survives a 60-power strike it would not
			-- otherwise.
			stubs()
			tile.Element = "Earth"
			tile.Level = 3
			placeDefender(TAPE_GNOME)

			local result = invade(LASER_SALAMANDER, nil, nil) -- ST 60
			t:Equal(result.Payload.Outcome, Enums.BattleOutcome.BothSurvive, "the bonus held the line")

			-- Without it, the same attack kills.
			stubs()
			tile.Element = "Fire"
			tile.Level = 3
			placeDefender(TAPE_GNOME)
			local unprotected = invade(LASER_SALAMANDER, nil, nil)
			t:Equal(unprotected.Payload.Outcome, Enums.BattleOutcome.AttackerTakesTerritory)
		end },

		{ "temporary land HP absorbs damage before the creature's own", function(t)
			-- And so the survivor's carried damage still makes sense after the
			-- battle: the bonus is gone, the health it protected is not.
			stubs()
			tile.Element = "Earth"
			tile.Level = 3 -- +30
			local state = placeDefender(TAPE_GNOME) -- 60 HP

			invade(SIGNAL_DRONE, nil, nil) -- ST 25, fully absorbed by the bonus
			t:Equal(state.CurrentHP, 60, "the bonus took all of it")
			t:Equal(state.BaseMHP, 60, "and MHP was never inflated")
		end },

		{ "damage past the bonus carries into persistent health", function(t)
			stubs()
			tile.Element = "Earth"
			tile.Level = 1 -- +10
			local state = placeDefender(FERRITE_GOLEM) -- 80 HP, Last

			invade(LASER_SALAMANDER, nil, nil) -- ST 60: 10 absorbed, 50 through
			t:Equal(state.CurrentHP, 30, "80 - (60 - 10)")
		end },

		{ "persistent damage survives between battles", function(t)
			stubs()
			local state = placeDefender(FERRITE_GOLEM) -- 80 HP
			invade(TAPE_GNOME, nil, nil) -- ST 40
			t:Equal(state.CurrentHP, 40, "wounded")

			-- A second, weaker invader now finds a weakened defender.
			local result = invade(LASER_SALAMANDER, nil, nil) -- ST 60 > 40 left
			t:Equal(result.Payload.Outcome, Enums.BattleOutcome.AttackerTakesTerritory,
				"the accumulated damage is what killed it")
		end },

		{ "Penetration ignores the land bonus", function(t)
			stubs()
			tile.Element = "Earth"
			tile.Level = 5 -- +50, a huge shield
			placeDefender(TAPE_GNOME) -- 60 HP, so effectively 110

			-- Packet Wraith has ST 45 and Penetration; without it 45 could
			-- never break 110, and with it the comparison is against 60.
			local result = invade(PACKET_WRAITH, nil, nil)
			t:Equal(result.Payload.Log[1].Damage, 45, "full damage landed")

			-- Confirm the bonus really would have applied to another attacker.
			stubs()
			tile.Element = "Earth"
			tile.Level = 5
			local state = placeDefender(TAPE_GNOME)
			invade(SIGNAL_DRONE, nil, nil)
			t:Equal(state.CurrentHP, 60, "a non-penetrating hit was soaked by the bonus")
		end },

		{ "Neutralize reduces one ordinary strike to zero", function(t)
			stubs()
			local state = placeDefender(SPOOL_WARDEN) -- HP 55, Neutralize
			invade(LASER_SALAMANDER, nil, nil) -- ST 60 would otherwise kill

			t:Equal(state.CurrentHP, 55, "took nothing")
			t:Equal(tile.Owner, DEFENDER, "and held the territory")
		end },

		{ "Reflect returns the damage to its sender", function(t)
			stubs()
			placeDefender(AERO_NEREID) -- HP 45, Reflect
			local result = invade(SIGNAL_DRONE, nil, nil) -- ST 25, HP 25

			t:Equal(result.Payload.Log[1].Reflected, 25, "returned in full")
			t:True(result.Payload.AttackerDestroyed, "and it killed the sender")
			t:Equal(tile.Owner, DEFENDER)
		end },

		{ "a Scroll bypasses Neutralize and the land bonus", function(t)
			-- The answer to a defender those keywords would make unkillable.
			stubs()
			tile.Element = "Earth"
			tile.Level = 5
			placeDefender(SPOOL_WARDEN) -- 55 HP, Neutralize, +50 land bonus

			local result = invade(SIGNAL_DRONE, STATIC_SCROLL, nil) -- 40 scroll damage
			t:Equal(result.Payload.Log[1].Damage, 40, "not neutralized")
			t:True(result.Payload.Log[1].Scroll)
		end },

		{ "a Weapon raises ST and an Armor raises HP", function(t)
			stubs()
			placeDefender(TAPE_GNOME) -- 60 HP
			-- Signal Drone at ST 25 cannot dent 60; with +30 it reaches 55,
			-- still short, so check the log rather than the outcome.
			local armed = invade(SIGNAL_DRONE, CATHODE_LANCE, nil)
			t:Equal(armed.Payload.Log[1].Damage, 55, "25 + 30")

			stubs()
			local state = placeDefender(SIGNAL_DRONE) -- 25 HP, would die to 40
			invade(TAPE_GNOME, nil, MYLAR_PLATING) -- +30 armour, so a pool of 55
			t:Equal(tile.Owner, DEFENDER, "the armour saved it")
			-- The armour soaks its 30 first, so only the remaining 10 reaches
			-- the creature: 25 - 10 = 15 carried forward.
			t:Equal(state.CurrentHP, 15, "armour absorbed 30 of the 40")
		end },

		{ "Critical multiplies the damage", function(t)
			stubs()
			placeDefender(FERRITE_GOLEM) -- 80 HP
			local result = invade(SIGNAL_DRONE, RIBBON_CUTTER, nil) -- 25 + 20 = 45, x1.5

			t:Equal(result.Payload.Log[1].Damage, 67, "floor(45 * 1.5)")
		end },

		{ "Regenerate restores a survivor to full", function(t)
			stubs()
			local state = placeDefender(GRID_PHOENIX) -- 60 HP, Regenerate
			invade(TAPE_GNOME, nil, nil) -- ST 40

			t:Equal(state.CurrentHP, 60, "back to full at battle end")
		end },

		{ "an invasion cannot start while one is running", function(t)
			stubs()
			placeDefender(TAPE_GNOME)
			BattleService.BeginInvasion(ATTACKER, give(ATTACKER, LASER_SALAMANDER), TILE)

			local second = BattleService.BeginInvasion(ATTACKER, give(ATTACKER, SIGNAL_DRONE), TILE)
			t:False(second.Ok)
			t:Equal(second.Code, Enums.RejectReason.IllegalAction)
		end },

		{ "invading your own territory is refused", function(t)
			stubs()
			placeDefender(TAPE_GNOME)
			local result = BattleService.BeginInvasion(DEFENDER, give(DEFENDER, LASER_SALAMANDER), TILE)
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.InvalidTarget)
		end },

		{ "an unaffordable invasion costs nothing and starts nothing", function(t)
			stubs()
			placeDefender(TAPE_GNOME)
			balances[ATTACKER] = 5 -- Laser Salamander costs 40

			local result = BattleService.BeginInvasion(ATTACKER, give(ATTACKER, LASER_SALAMANDER), TILE)
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.InsufficientMagic)
			t:Equal(balances[ATTACKER], 5, "nothing was spent")
			t:Nil(BattleService.GetPendingBattle(), "and no battle is pending")
		end },

		{ "a queued attack buff applies once and is consumed", function(t)
			stubs()
			placeDefender(FERRITE_GOLEM) -- 80 HP
			BattleService.QueueAttackBuff(ATTACKER, 20)

			local first = invade(TAPE_GNOME, nil, nil) -- ST 40 + 20
			t:Equal(first.Payload.Log[1].Damage, 60, "the buff applied")

			local second = invade(TAPE_GNOME, nil, nil)
			t:Equal(second.Payload.Log[1].Damage, 40, "and was spent")
		end },

		{ "a defender HP buff raises MHP as well as current health", function(t)
			-- Unlike the land bonus, which is why one lives on the creature
			-- and the other never does.
			stubs()
			local state = placeDefender(TAPE_GNOME)
			BattleService.ApplyDefenderHPBuff(DEFENDER, TILE, 25)

			t:Equal(state.CurrentHP, 85)
			t:Equal(state.BaseMHP + state.BonusMHP, 85, "MHP moved too")
		end },

		{ "only the owner may equip a defender", function(t)
			stubs()
			placeDefender(TAPE_GNOME)
			local result = BattleService.ApplyDefenderHPBuff(ATTACKER, TILE, 25)
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.InvalidTarget)
		end },
	},
}

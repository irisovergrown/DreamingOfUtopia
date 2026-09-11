--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > EffectSpec (ModuleScript)

	The Milestone 6 card effect resolver: a card is a LIST OF VERBS, and
	playing it means running them.

	The tests that matter most here are the negative ones. A resolver that
	charges for a spell and then fizzles on a bad target is worse than one that
	refuses outright, and the only way to know which we built is to aim a card
	at nothing and count the Magic afterwards.

	The last test is a data check rather than a behaviour check: it walks the
	whole card library and asserts every declared primitive exists. A typo in
	CardData would otherwise surface as a refused spell in a live match, which
	is exactly the "buried guess" the brief forbids.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local CardData = require(ReplicatedStorage.Shared.CardData)
local StatusService = require(ServerScriptService.Systems.StatusService)
local EffectPrimitives = require(ServerScriptService.Systems.EffectPrimitives)
local CardEffectService = require(ServerScriptService.Systems.CardEffectService)

local ALICE, BOB = 601, 602
local NODE = "T5"

-- Cards named where a test depends on what they do.
local SIGNAL_BOOST = 5 -- BoostNextAttack 20
local CALL_SIGN_SIX = 22 -- ForceRoll 6, ChosenPlayer
local REWIND_TAPE = 23 -- Draw 2
local CORRODED_TAPE = 24 -- Poison a defending creature
local OVERCLOCK = 26 -- Haste on the caster
local TAPE_GNOME = 1 -- a creature: no Effects at all

local cardsById = {}
for _, card in ipairs(CardData.Cards) do
	cardsById[card.Id] = card
end

local balances, hands, drawn, defender, nextInstance

local function fresh()
	balances = { [ALICE] = 500, [BOB] = 500 }
	hands = { [ALICE] = {}, [BOB] = {} }
	drawn = {}
	defender = { OwnerUserId = BOB, CardId = TAPE_GNOME, CurrentHP = 60 }
	nextInstance = 1

	StatusService.Init({})
	StatusService.ClearAll()

	local economy = {
		GetBalance = function(userId)
			return balances[userId]
		end,
		SpendMagic = function(userId, amount)
			if balances[userId] < amount then
				return false, "Not enough Magic"
			end
			balances[userId] -= amount
			return true, balances[userId]
		end,
		AddMagic = function(userId, amount)
			balances[userId] += amount
			return balances[userId]
		end,
		RequirePayment = function(userId, amount)
			local paid = math.min(balances[userId], amount)
			balances[userId] -= paid
			return { Paid = paid, Shortfall = amount - paid }
		end,
	}

	-- Declared empty first: a closure inside the constructor would capture the
	-- global `deck`, not this table.
	local deck = {}
	deck.Played = {}
	deck.GetInstance = function(userId, instanceId)
		return hands[userId][instanceId]
	end
	deck.PlayInstance = function(userId, instanceId)
		hands[userId][instanceId] = nil
		table.insert(deck.Played, instanceId)
	end
	deck.Draw = function(userId, count)
		local cards = {}
		for index = 1, count do
			cards[index] = { InstanceId = "d" .. index, CardId = REWIND_TAPE }
		end
		drawn[userId] = (drawn[userId] or 0) + count
		return cards
	end

	local battle = {
		GetDefender = function(nodeId)
			return nodeId == NODE and defender or nil
		end,
		ApplyDefenderHPBuff = function()
			return { Ok = true, Payload = {} }
		end,
	}

	local territory = {
		GetTerritory = function(nodeId)
			return (nodeId == NODE or nodeId == "T1") and { Id = nodeId } or nil
		end,
	}

	EffectPrimitives.Init({
		Economy = economy,
		Deck = deck,
		Status = StatusService,
		Battle = battle,
		Movement = { GetCurrentNodeId = function() return NODE end },
		Graph = { GetCastleNodeIds = function() return { "T1" } end },
	})

	CardEffectService.Init({
		Card = { GetCard = function(cardId) return cardsById[cardId] end },
		Economy = economy,
		Deck = deck,
		Movement = { GetCurrentNodeId = function() return NODE end },
		Territory = territory,
		Status = StatusService,
		IsParticipant = function(userId)
			return userId == ALICE or userId == BOB
		end,
	})

	return deck
end

local function give(userId, cardId)
	local instanceId = "i" .. nextInstance
	nextInstance += 1
	hands[userId][instanceId] = { InstanceId = instanceId, CardId = cardId }
	return instanceId
end

return {
	Name = "CardEffects",
	Tests = {
		-- === Resolution ==============================================

		{ "a card's declared effects run without any code knowing its name", function(t)
			fresh()
			local instanceId = give(ALICE, REWIND_TAPE)
			local result = CardEffectService.Resolve(ALICE, instanceId)

			t:True(result.Ok, tostring(result.Message))
			t:Equal(drawn[ALICE], 2, "Draw 2 is data, not a branch")
			t:Equal(balances[ALICE], 485, "and the cost was charged")
		end },

		{ "a resolved card is consumed", function(t)
			local deck = fresh()
			local instanceId = give(ALICE, REWIND_TAPE)
			CardEffectService.Resolve(ALICE, instanceId)

			t:DeepEqual(deck.Played, { instanceId })
			t:Nil(hands[ALICE][instanceId])
		end },

		{ "a spell that applies a status leaves one behind", function(t)
			fresh()
			CardEffectService.Resolve(ALICE, give(ALICE, OVERCLOCK))

			t:True(StatusService.HasKind("Haste", Enums.StatusTarget.Player, ALICE))
			t:Equal(
				StatusService.RunHook(Enums.TimingHook.ModifyRoll, { UserId = ALICE, Min = 1, Max = 6 }, 3),
				5,
				"and it reaches the roll pipeline"
			)
		end },

		{ "a targeted spell hits the player the request names", function(t)
			fresh()
			local result = CardEffectService.Resolve(ALICE, give(ALICE, CALL_SIGN_SIX), {
				TargetUserId = BOB,
			})

			t:True(result.Ok, tostring(result.Message))
			t:True(StatusService.HasKind("ForcedRoll", Enums.StatusTarget.Player, BOB))
			t:False(
				StatusService.HasKind("ForcedRoll", Enums.StatusTarget.Player, ALICE),
				"the caster is not the target just because they cast it"
			)
		end },

		{ "a creature status needs a creature to land on", function(t)
			fresh()
			local result = CardEffectService.Resolve(ALICE, give(ALICE, CORRODED_TAPE), {
				TargetNodeId = NODE,
			})

			t:True(result.Ok, tostring(result.Message))
			t:True(StatusService.HasKind("Poison", Enums.StatusTarget.Creature, NODE))
		end },

		-- === Refusal and refund ======================================

		{ "an unknown territory refunds the cost and does not consume the card", function(t)
			local deck = fresh()
			local instanceId = give(ALICE, CORRODED_TAPE)
			local result = CardEffectService.Resolve(ALICE, instanceId, { TargetNodeId = "NOPE" })

			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.InvalidTarget)
			t:Equal(balances[ALICE], 500, "nothing spent")
			t:DeepEqual(deck.Played, {}, "and nothing consumed")
			t:NotNil(hands[ALICE][instanceId], "the card is still in hand")
		end },

		{ "a territory with no defender refunds rather than fizzling", function(t)
			fresh()
			defender = nil
			local instanceId = give(ALICE, CORRODED_TAPE)
			local result = CardEffectService.Resolve(ALICE, instanceId, { TargetNodeId = NODE })

			t:False(result.Ok, "a spell that quietly does nothing while taking the Magic is worse")
			t:Equal(balances[ALICE], 500)
			t:NotNil(hands[ALICE][instanceId])
		end },

		{ "a non-participant cannot be targeted", function(t)
			fresh()
			local result = CardEffectService.Resolve(ALICE, give(ALICE, CALL_SIGN_SIX), {
				TargetUserId = 999999,
			})

			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.InvalidTarget)
			t:Equal(balances[ALICE], 500)
		end },

		{ "a card not in hand cannot be played", function(t)
			fresh()
			local result = CardEffectService.Resolve(ALICE, "not-an-instance")
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.CardNotInHand)
		end },

		{ "an unaffordable card is refused before anything runs", function(t)
			fresh()
			balances[ALICE] = 5
			local instanceId = give(ALICE, REWIND_TAPE)
			local result = CardEffectService.Resolve(ALICE, instanceId)

			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.InsufficientMagic)
			t:Equal(balances[ALICE], 5)
			t:Nil(drawn[ALICE], "no cards drawn on a refused spell")
		end },

		{ "a card with no effects is refused rather than silently doing nothing", function(t)
			fresh()
			local result = CardEffectService.Resolve(ALICE, give(ALICE, TAPE_GNOME))
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.InvalidCard)
		end },

		-- === Targeting contract ======================================

		{ "required targets exclude the ones the server supplies itself", function(t)
			fresh()
			t:DeepEqual(
				CardEffectService.GetRequiredTargets(SIGNAL_BOOST),
				{},
				"Caster needs nothing from the player"
			)
			t:DeepEqual(CardEffectService.GetRequiredTargets(CALL_SIGN_SIX), { "ChosenPlayer" })
			t:DeepEqual(CardEffectService.GetRequiredTargets(CORRODED_TAPE), { "ChosenTerritory" })
		end },

		{ "an unknown primitive is refused, not skipped", function(t)
			fresh()
			local result = EffectPrimitives.Run("NoSuchVerb", {}, {})
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.IllegalAction)
		end },

		-- === Data integrity ==========================================

		{ "every effect in the card library names a real primitive", function(t)
			fresh()
			for _, card in ipairs(CardData.Cards) do
				for index, effect in ipairs(card.Effects or {}) do
					t:NotNil(
						EffectPrimitives.Get(effect.Primitive),
						string.format(
							"card %d (%s) effect %d: '%s'",
							card.Id, card.Name, index, tostring(effect.Primitive)
						)
					)
				end
			end
		end },

		{ "every card id in the library is unique", function(t)
			fresh()
			local seen = {}
			for _, card in ipairs(CardData.Cards) do
				t:Nil(seen[card.Id], string.format("card id %d is declared twice", card.Id))
				seen[card.Id] = card.Name
			end
		end },
	},
}

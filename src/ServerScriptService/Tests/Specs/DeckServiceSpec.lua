--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > DeckServiceSpec (ModuleScript)

	The brief's "Cards and secrecy" criteria: the hand cap holds, the book
	recycles deterministically under a seed, and a card you do not hold cannot
	be played.

	Every test uses an explicit seed so the shuffled book is reproducible;
	without that, "the same book was dealt twice" is untestable.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local RulesConfig = require(ReplicatedStorage.Shared.RulesConfig)
local CardData = require(ReplicatedStorage.Shared.CardData)
local DeckService = require(ServerScriptService.Systems.DeckService)
local RandomService = require(ServerScriptService.Systems.RandomService)

local ALICE, BOB = 101, 202

local function fresh(seed)
	DeckService.Init({ Random = RandomService.new(seed or 7) })
	DeckService.RegisterPlayer(ALICE)
	DeckService.RegisterPlayer(BOB)
end

local function handCardIds(userId)
	local ids = {}
	for _, instance in ipairs(DeckService.GetHand(userId)) do
		table.insert(ids, instance.CardId)
	end
	return ids
end

return {
	Name = "DeckService",
	Tests = {
		{ "a registered player gets a full, legal book", function(t)
			fresh()
			t:Equal(DeckService.GetBookCount(ALICE), RulesConfig.Book.Size, "book size")
			t:Equal(DeckService.GetHandCount(ALICE), 0, "hand starts empty")
			t:Equal(DeckService.GetDiscardCount(ALICE), 0)
		end },

		{ "the default book respects the copy limit", function(t)
			-- Four copies of one card is legal; five is not, and a book built
			-- past that limit would be illegal the moment deck building exists.
			local book = DeckService.BuildDefaultBook()
			local counts = {}
			for _, cardId in ipairs(book) do
				counts[cardId] = (counts[cardId] or 0) + 1
			end
			for cardId, count in pairs(counts) do
				t:True(
					count <= RulesConfig.Book.MaxCopiesPerCard,
					string.format("card %d appears %d times", cardId, count)
				)
			end
			t:Equal(#book, RulesConfig.Book.Size)
		end },

		{ "there are enough distinct cards to fill a legal book", function(t)
			-- 50 cards at 4 copies each needs at least 13 distinct definitions.
			-- Falling below that would make a legal book impossible to build.
			local needed = math.ceil(RulesConfig.Book.Size / RulesConfig.Book.MaxCopiesPerCard)
			t:True(
				#CardData.Cards >= needed,
				string.format("%d cards defined, %d needed", #CardData.Cards, needed)
			)
		end },

		{ "drawing moves cards from book to hand", function(t)
			fresh()
			local drawn = DeckService.Draw(ALICE, 5)

			t:Equal(#drawn, 5, "drew five")
			t:Equal(DeckService.GetHandCount(ALICE), 5)
			t:Equal(DeckService.GetBookCount(ALICE), RulesConfig.Book.Size - 5, "book shrank by the same five")
		end },

		{ "every card instance is unique", function(t)
			-- Two copies of one card are two objects. Without that there is
			-- nothing to withhold from an opponent and nothing for an effect
			-- to target.
			fresh()
			DeckService.Draw(ALICE, 10)

			local seen = {}
			for _, instance in ipairs(DeckService.GetHand(ALICE)) do
				t:Nil(seen[instance.InstanceId], "instance id " .. instance.InstanceId .. " was reused")
				seen[instance.InstanceId] = true
			end
		end },

		{ "two players never share an instance id", function(t)
			fresh()
			DeckService.Draw(ALICE, 6)
			DeckService.Draw(BOB, 6)

			local alices = {}
			for _, instance in ipairs(DeckService.GetHand(ALICE)) do
				alices[instance.InstanceId] = true
			end
			for _, instance in ipairs(DeckService.GetHand(BOB)) do
				t:Nil(alices[instance.InstanceId], "Bob holds one of Alice's instances")
			end
		end },

		{ "the same seed deals the same book", function(t)
			DeckService.Init({ Random = RandomService.new(9090) })
			DeckService.RegisterPlayer(ALICE)
			DeckService.Draw(ALICE, 8)
			local first = handCardIds(ALICE)

			DeckService.Init({ Random = RandomService.new(9090) })
			DeckService.RegisterPlayer(ALICE)
			DeckService.Draw(ALICE, 8)

			t:DeepEqual(handCardIds(ALICE), first, "identical seeds, identical deal")
		end },

		{ "different seeds deal differently", function(t)
			DeckService.Init({ Random = RandomService.new(1) })
			DeckService.RegisterPlayer(ALICE)
			DeckService.Draw(ALICE, 12)
			local first = table.concat(handCardIds(ALICE), ",")

			DeckService.Init({ Random = RandomService.new(2) })
			DeckService.RegisterPlayer(ALICE)
			DeckService.Draw(ALICE, 12)

			t:NotEqual(table.concat(handCardIds(ALICE), ","), first)
		end },

		{ "playing a card moves it to the discard", function(t)
			fresh()
			DeckService.Draw(ALICE, 3)
			local instance = DeckService.GetHand(ALICE)[1]

			local result = DeckService.PlayInstance(ALICE, instance.InstanceId)
			t:True(result.Ok)
			t:Equal(DeckService.GetHandCount(ALICE), 2, "hand shrank")
			t:Equal(DeckService.GetDiscardCount(ALICE), 1, "discard grew")
			t:False(DeckService.HasInstance(ALICE, instance.InstanceId), "no longer in hand")
		end },

		{ "a card cannot be played twice", function(t)
			-- The exact hole this closes: previously a card id could be
			-- summoned as many times as a player could pay for it.
			fresh()
			DeckService.Draw(ALICE, 3)
			local instance = DeckService.GetHand(ALICE)[1]

			t:True(DeckService.PlayInstance(ALICE, instance.InstanceId).Ok, "first play")

			local second = DeckService.PlayInstance(ALICE, instance.InstanceId)
			t:False(second.Ok, "second play is refused")
			t:Equal(second.Code, Enums.RejectReason.CardNotInHand)
		end },

		{ "a player cannot play a card from someone else's hand", function(t)
			fresh()
			DeckService.Draw(ALICE, 3)
			DeckService.Draw(BOB, 3)
			local alices = DeckService.GetHand(ALICE)[1]

			local result = DeckService.PlayInstance(BOB, alices.InstanceId)
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.CardNotInHand)
			t:True(DeckService.HasInstance(ALICE, alices.InstanceId), "and Alice still holds it")
		end },

		{ "an unknown instance id is refused", function(t)
			fresh()
			DeckService.Draw(ALICE, 2)
			t:Equal(DeckService.PlayInstance(ALICE, "c99999").Code, Enums.RejectReason.CardNotInHand)
			t:Equal(DeckService.PlayInstance(ALICE, "").Code, Enums.RejectReason.CardNotInHand)
		end },

		{ "the hand cap is observable but not silently enforced on draw", function(t)
			-- Drawing over the cap is legal; what is not legal is CONTINUING
			-- the turn while over it. The overflow decision belongs to the
			-- turn driver, so the deck reports the condition rather than
			-- quietly discarding for the player.
			fresh()
			DeckService.Draw(ALICE, RulesConfig.Hand.MaxSize)
			t:False(DeckService.IsHandOverFull(ALICE), "exactly at the cap is fine")

			DeckService.Draw(ALICE, 1)
			t:True(DeckService.IsHandOverFull(ALICE), "one over is reported")
			t:Equal(DeckService.GetHandCount(ALICE), RulesConfig.Hand.MaxSize + 1)
		end },

		{ "discarding brings an over-full hand back to legal", function(t)
			fresh()
			DeckService.Draw(ALICE, RulesConfig.Hand.MaxSize + 1)
			local instance = DeckService.GetHand(ALICE)[1]

			t:True(DeckService.DiscardInstance(ALICE, instance.InstanceId).Ok)
			t:False(DeckService.IsHandOverFull(ALICE))
		end },

		{ "an exhausted book recycles the discard", function(t)
			fresh()
			-- Draw the whole book out, play it all away, then keep drawing.
			DeckService.Draw(ALICE, RulesConfig.Book.Size)
			t:Equal(DeckService.GetBookCount(ALICE), 0, "book emptied")

			for _, instance in ipairs(DeckService.GetHand(ALICE)) do
				DeckService.PlayInstance(ALICE, instance.InstanceId)
			end
			t:Equal(DeckService.GetDiscardCount(ALICE), RulesConfig.Book.Size)
			t:Equal(DeckService.GetCycleCount(ALICE), 0, "not recycled yet")

			local drawn = DeckService.Draw(ALICE, 1)
			t:Equal(#drawn, 1, "drew from the recycled book")
			t:Equal(DeckService.GetCycleCount(ALICE), 1, "cycle counted")
			t:Equal(DeckService.GetDiscardCount(ALICE), 0, "discard was consumed")
		end },

		{ "recycling preserves every card", function(t)
			fresh()
			DeckService.Draw(ALICE, RulesConfig.Book.Size)
			for _, instance in ipairs(DeckService.GetHand(ALICE)) do
				DeckService.PlayInstance(ALICE, instance.InstanceId)
			end
			DeckService.Draw(ALICE, 1)

			local total = DeckService.GetBookCount(ALICE)
				+ DeckService.GetHandCount(ALICE)
				+ DeckService.GetDiscardCount(ALICE)
			t:Equal(total, RulesConfig.Book.Size, "no card was lost or duplicated by the recycle")
		end },

		{ "an empty book and empty discard draws nothing rather than erroring", function(t)
			-- A legal state, not a failure: returning a short draw is more
			-- honest than inventing a card.
			fresh()
			DeckService.Draw(ALICE, RulesConfig.Book.Size)
			-- Cards are all in hand, so nothing is in the book or discard.
			local drawn = DeckService.Draw(ALICE, 3)
			t:Equal(#drawn, 0, "drew nothing")
			t:Equal(DeckService.GetHandCount(ALICE), RulesConfig.Book.Size, "hand unchanged")
		end },

		{ "GetHand hands back a copy", function(t)
			fresh()
			DeckService.Draw(ALICE, 3)

			local hand = DeckService.GetHand(ALICE)
			table.remove(hand, 1)
			hand[1].CardId = 999

			t:Equal(DeckService.GetHandCount(ALICE), 3, "the real hand is unchanged")
			t:NotEqual(DeckService.GetHand(ALICE)[1].CardId, 999, "and its cards were not rewritten")
		end },

		{ "a returned creature comes back as a new instance", function(t)
			-- An invader that survives without taking the land returns to hand.
			-- The original instance was consumed on play, so what comes back is
			-- a card of that type rather than the same object.
			fresh()
			DeckService.Draw(ALICE, 1)
			local original = DeckService.GetHand(ALICE)[1]
			DeckService.PlayInstance(ALICE, original.InstanceId)

			local returned = DeckService.ReturnToHand(ALICE, original.CardId)
			t:True(returned.Ok)
			t:Equal(returned.Payload.CardId, original.CardId, "same card type")
			t:NotEqual(returned.Payload.InstanceId, original.InstanceId, "different instance")
			t:Equal(DeckService.GetHandCount(ALICE), 1)
		end },

		{ "removing a player clears their deck", function(t)
			fresh()
			DeckService.Draw(ALICE, 4)
			DeckService.RemovePlayer(ALICE)

			t:Equal(DeckService.GetHandCount(ALICE), 0)
			t:Equal(DeckService.GetBookCount(ALICE), 0)
			t:Equal(DeckService.GetHandCount(BOB), 0, "Bob is untouched but undealt")
			t:Equal(DeckService.GetBookCount(BOB), RulesConfig.Book.Size, "and still has his book")
		end },
	},
}

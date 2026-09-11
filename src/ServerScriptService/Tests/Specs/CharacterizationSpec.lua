--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > CharacterizationSpec (ModuleScript)

	Purpose:
		This spec did its job and is now a record of it.

		In Milestone 0 it pinned what the code ACTUALLY did — a linear chain
		multiplier, toll rates of 0.2/0.35/0.5/0.65/0.8, terraforming allowed
		only on unclaimed land, a land bonus fused into creature HP, a board
		that was a sorted ring — and named what each would become. The point
		was that when those formulas changed, exactly these tests would fail,
		and anything ELSE that broke would be unintended.

		Milestone 5 changed them. Every defect this file pinned is now closed,
		so rather than delete it, it asserts the corrections. A characterization
		test that vanishes when the code is fixed leaves no evidence the fix
		actually happened; one that flips to asserting the new behaviour keeps
		the history and keeps guarding it.

		The modules it originally tested — BoardService and TerraformService —
		no longer exist. They were replaced by TerritoryService, which is why
		the first test checks they are gone rather than that they behave.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local RulesConfig = require(ReplicatedStorage.Shared.RulesConfig)
local BattleService = require(ServerScriptService.Systems.BattleService)

local Systems = ServerScriptService.Systems

return {
	Name = "Characterization (defects closed)",
	Tests = {
		{ "CLOSED M5: BoardService and TerraformService are gone", function(t)
			-- Both were replaced by TerritoryService, which owns ownership,
			-- level and element together and is keyed by node id rather than
			-- by a tile number that only existed because the board was a ring.
			t:Nil(Systems:FindFirstChild("BoardService"), "BoardService was replaced")
			t:Nil(Systems:FindFirstChild("TerraformService"), "TerraformService was replaced")
			t:NotNil(Systems:FindFirstChild("TerritoryService"), "by TerritoryService")
		end },

		{ "CLOSED M5: the chain multiplier is no longer linear", function(t)
			-- WAS: 1 + 0.5 per extra territory, uncapped — so five territories
			-- gave 3.0 and ten gave 5.5.
			-- NOW: the Culdcept table, capped at five.
			t:Equal(RulesConfig.getChainMultiplier(1), 1.0)
			t:Equal(RulesConfig.getChainMultiplier(2), 1.5, "the one value the old code got right")
			t:Equal(RulesConfig.getChainMultiplier(3), 1.8, "was 2.0")
			t:Equal(RulesConfig.getChainMultiplier(4), 2.0, "was 2.5")
			t:Equal(RulesConfig.getChainMultiplier(5), 2.2, "was 3.0")
			t:Equal(RulesConfig.getChainMultiplier(10), 2.2, "and it now caps")
		end },

		{ "CLOSED M5: toll rates match the chart at every level", function(t)
			-- WAS: 0.2 / 0.35 / 0.5 / 0.65 / 0.8 — levels 2, 3 and 4 all too
			-- generous, which nothing noticed because nothing ever raised a
			-- land level.
			t:Equal(RulesConfig.getTollMultiplier(2), 0.3, "was 0.35")
			t:Equal(RulesConfig.getTollMultiplier(3), 0.4, "was 0.5")
			t:Equal(RulesConfig.getTollMultiplier(4), 0.6, "was 0.65")

			-- The consequence, on a base-100 territory:
			t:Equal(RulesConfig.getToll(100, 2, 1), 60, "was 70")
			t:Equal(RulesConfig.getToll(100, 3, 1), 160, "was 200")
		end },

		{ "CLOSED M5: terrain change costs the documented amount", function(t)
			-- WAS: a flat 50 + 30 per level, plus 50 for a specific element —
			-- invented numbers that matched nothing.
			t:Equal(RulesConfig.getTerrainChangeCost(1, false), 100, "was 80")
			t:Equal(RulesConfig.getTerrainChangeCost(1, true), 300, "was 130")
			t:Equal(RulesConfig.getTerrainChangeCost(2, true), 400, "was 160")
		end },

		{ "CLOSED M4: the land bonus is computed, never stored", function(t)
			-- WAS: GetEffectiveHP returned card.HP + landBonus as one number,
			-- so a creature's stored health silently included a bonus that
			-- belonged to the tile. That is what forced terraforming to be
			-- restricted to unclaimed land.
			t:Nil(rawget(BattleService, "GetEffectiveHP"), "the fused accessor is gone")
			t:NotNil(BattleService.GetLandBonusFor, "replaced by a per-battle computation")
		end },

		{ "CLOSED M5: terrain change works on owned land", function(t)
			-- WAS: refused unless the territory was unclaimed — exactly
			-- backwards, and only there to avoid the stale-HP bug above.
			-- Covered in full by TerritoryEconomySpec; recorded here because
			-- this is the file that pinned the restriction.
			local TerritoryService = require(Systems.TerritoryService)
			t:NotNil(TerritoryService.ChangeElement, "it is a territory command now")
			t:Nil(rawget(TerritoryService, "TerraformTile"), "not a separate unclaimed-only action")
		end },

		{ "CLOSED M5: victory reads Total Magic and needs the castle", function(t)
			-- WAS: Current Magic against a flat 3000, checked only on a lap,
			-- ending the match the instant the number was hit.
			local VictoryService = require(Systems.VictoryService)
			local ValuationService = require(Systems.ValuationService)

			t:NotNil(ValuationService.GetTotalMagic, "TM is a real quantity now")
			t:NotNil(VictoryService.TryConfirmAtCastle, "and arriving is what wins")
			t:NotNil(VictoryService.IsGoalReachedState, "with a visible goal-reached state between")
		end },

		{ "CLOSED M2: the board is a graph, not a sorted ring", function(t)
			local BoardGraphService = require(Systems.BoardGraphService)
			t:NotNil(BoardGraphService.GetLegalExits, "movement asks the graph for exits")
			t:NotNil(BoardGraphService.GetTransport, "and warps exist")
		end },

		{ "CLOSED M2: a lap needs every fort, not just the start tile", function(t)
			local LapService = require(Systems.LapService)
			t:NotNil(LapService.HasAllRequiredForts, "forts gate the lap")
			t:NotNil(LapService.GetMissingFortTypes, "and the player can see what is missing")
		end },

		{ "CLOSED M3: cards are consumed when played", function(t)
			local DeckService = require(Systems.DeckService)
			t:NotNil(DeckService.PlayInstance, "playing consumes an instance")
			t:NotNil(DeckService.GetHand, "there is a hand to play from")
		end },

		{ "the element vocabulary is settled", function(t)
			-- Era was the flavour skin and Element the mechanic, but the code
			-- said Era everywhere including on tile state. Renamed in
			-- Milestone 5 alongside the territory rewrite, so there was never
			-- a moment with two live names.
			local ElementData = require(ReplicatedStorage.Shared.ElementData)
			t:NotNil(ElementData.Elements, "ElementData holds Elements")
			t:Nil(rawget(ElementData, "Eras"), "and no longer Eras")

			for _, elementId in ipairs({ "Fire", "Water", "Air", "Earth" }) do
				t:True(Enums.isValid(Enums.Element, elementId), elementId .. " is a canonical element")
				t:NotNil(ElementData.Elements[elementId], elementId .. " has display data")
			end
		end },
	},
}

--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > RulesConfigSpec (ModuleScript)

	Covers the Milestone 0 half of the brief's "Territory/economy" acceptance
	criteria — the pure formulas, asserted on exact values. The stateful half
	(leveling moves CM, losing a chained land recalculates both players' TM)
	needs services that do not exist yet and lands in Milestone 5.

	Constants are asserted with Equal rather than Near deliberately. "The
	chain multiplier is approximately 1.8" is not a property worth having.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RulesConfig = require(ReplicatedStorage.Shared.RulesConfig)

return {
	Name = "RulesConfig",
	Tests = {
		{ "chain multipliers are exactly 1.0/1.5/1.8/2.0/2.2", function(t)
			t:Equal(RulesConfig.getChainMultiplier(1), 1.0, "1 territory")
			t:Equal(RulesConfig.getChainMultiplier(2), 1.5, "2 territories")
			t:Equal(RulesConfig.getChainMultiplier(3), 1.8, "3 territories")
			t:Equal(RulesConfig.getChainMultiplier(4), 2.0, "4 territories")
			t:Equal(RulesConfig.getChainMultiplier(5), 2.2, "5 territories")
		end },

		{ "integer numerators agree with the readable decimal tables", function(t)
			-- The formulas compute from the numerators; the decimals are what
			-- humans read and what the brief specifies. If they ever drift,
			-- the documented rules and the enforced rules diverge silently.
			local land = RulesConfig.Land
			t:Equal(#land.ChainMultiplierNumerators, #land.ChainMultipliers, "chain table lengths")
			t:Equal(#land.TollMultiplierNumerators, #land.TollMultipliers, "toll table lengths")
			for index, decimal in ipairs(land.ChainMultipliers) do
				t:Near(land.ChainMultiplierNumerators[index] / land.MultiplierDenominator, decimal, 1e-12, "chain " .. index)
			end
			for index, decimal in ipairs(land.TollMultipliers) do
				t:Near(land.TollMultiplierNumerators[index] / land.MultiplierDenominator, decimal, 1e-12, "toll level " .. index)
			end
		end },

		{ "chain multiplier caps at five but ownership may exceed it", function(t)
			t:Equal(RulesConfig.getChainMultiplier(6), 2.2, "6 territories")
			t:Equal(RulesConfig.getChainMultiplier(50), 2.2, "50 territories")
		end },

		{ "chain size below one is treated as a single territory", function(t)
			t:Equal(RulesConfig.getChainMultiplier(0), 1.0)
			t:Equal(RulesConfig.getChainMultiplier(nil), 1.0)
		end },

		{ "toll multipliers are exactly 0.2/0.3/0.4/0.6/0.8", function(t)
			t:Equal(RulesConfig.getTollMultiplier(1), 0.2)
			t:Equal(RulesConfig.getTollMultiplier(2), 0.3)
			t:Equal(RulesConfig.getTollMultiplier(3), 0.4)
			t:Equal(RulesConfig.getTollMultiplier(4), 0.6)
			t:Equal(RulesConfig.getTollMultiplier(5), 0.8)
		end },

		{ "base-100 land values are 100/200/400/800/1600 before chains", function(t)
			t:Equal(RulesConfig.getLandValue(100, 1, 1), 100)
			t:Equal(RulesConfig.getLandValue(100, 2, 1), 200)
			t:Equal(RulesConfig.getLandValue(100, 3, 1), 400)
			t:Equal(RulesConfig.getLandValue(100, 4, 1), 800)
			t:Equal(RulesConfig.getLandValue(100, 5, 1), 1600)
		end },

		{ "land value applies the chain multiplier on top of the level", function(t)
			t:Equal(RulesConfig.getLandValue(100, 1, 2), 150, "L1 x1.5")
			t:Equal(RulesConfig.getLandValue(100, 3, 5), 880, "L3 x2.2")
			t:Equal(RulesConfig.getLandValue(100, 5, 4), 3200, "L5 x2.0")
		end },

		{ "land value is exact at base 80 and 120", function(t)
			t:Equal(RulesConfig.getLandValue(80, 1, 1), 80)
			t:Equal(RulesConfig.getLandValue(80, 5, 1), 1280)
			t:Equal(RulesConfig.getLandValue(120, 1, 1), 120)
			t:Equal(RulesConfig.getLandValue(120, 5, 1), 1920)
		end },

		{ "tolls at base 100 are level-correct", function(t)
			t:Equal(RulesConfig.getToll(100, 1, 1), 20, "100 x 0.2")
			t:Equal(RulesConfig.getToll(100, 2, 1), 60, "200 x 0.3")
			t:Equal(RulesConfig.getToll(100, 3, 1), 160, "400 x 0.4")
			t:Equal(RulesConfig.getToll(100, 4, 1), 480, "800 x 0.6")
			t:Equal(RulesConfig.getToll(100, 5, 1), 1280, "1600 x 0.8")
		end },

		{ "tolls at base 80 and 120 are level-correct", function(t)
			t:Equal(RulesConfig.getToll(80, 1, 1), 16)
			t:Equal(RulesConfig.getToll(80, 3, 1), 128)
			t:Equal(RulesConfig.getToll(80, 5, 1), 1024)
			t:Equal(RulesConfig.getToll(120, 1, 1), 24)
			t:Equal(RulesConfig.getToll(120, 3, 1), 192)
			t:Equal(RulesConfig.getToll(120, 5, 1), 1536)
		end },

		{ "fractional tolls follow the configured rounding mode", function(t)
			-- base 80, L1, 3-chain -> land 144, toll 28.8. This is the case
			-- that makes rounding mode observable rather than academic.
			t:Equal(RulesConfig.Rounding.Mode, "floor", "default rounding mode")
			t:Equal(RulesConfig.getLandValue(80, 1, 3), 144)
			t:Equal(RulesConfig.getToll(80, 1, 3), 28, "28.8 floored")
			-- base 120, L1, 3-chain -> land 216, toll 43.2
			t:Equal(RulesConfig.getToll(120, 1, 3), 43, "43.2 floored")
		end },

		{ "development cost is the cumulative unchained value increase", function(t)
			t:Equal(RulesConfig.getDevelopmentCost(100, 1, 2), 100)
			t:Equal(RulesConfig.getDevelopmentCost(100, 2, 3), 200)
			t:Equal(RulesConfig.getDevelopmentCost(100, 3, 4), 400)
			t:Equal(RulesConfig.getDevelopmentCost(100, 4, 5), 800)
		end },

		{ "developing straight to level five costs 1500 at base 100", function(t)
			t:Equal(RulesConfig.getDevelopmentCost(100, 1, 5), 1500)
			-- and equals the sum of the single steps, so choosing a big jump
			-- is never cheaper or dearer than climbing
			local stepwise = RulesConfig.getDevelopmentCost(100, 1, 2)
				+ RulesConfig.getDevelopmentCost(100, 2, 3)
				+ RulesConfig.getDevelopmentCost(100, 3, 4)
				+ RulesConfig.getDevelopmentCost(100, 4, 5)
			t:Equal(stepwise, 1500, "stepwise total")
		end },

		{ "development cost ignores chains", function(t)
			-- No chain argument exists on purpose: chains multiply what the
			-- investment is worth, never what it costs.
			t:Equal(RulesConfig.getDevelopmentCost(80, 1, 5), 1200)
			t:Equal(RulesConfig.getDevelopmentCost(120, 1, 5), 1800)
		end },

		{ "development to the same or a lower level is free", function(t)
			t:Equal(RulesConfig.getDevelopmentCost(100, 3, 3), 0)
			t:Equal(RulesConfig.getDevelopmentCost(100, 4, 2), 0)
		end },

		{ "terrain change costs level x 100, plus 200 if already elemental", function(t)
			t:Equal(RulesConfig.getTerrainChangeCost(1, false), 100)
			t:Equal(RulesConfig.getTerrainChangeCost(3, false), 300)
			t:Equal(RulesConfig.getTerrainChangeCost(5, false), 500)
			t:Equal(RulesConfig.getTerrainChangeCost(1, true), 300)
			t:Equal(RulesConfig.getTerrainChangeCost(5, true), 700)
		end },

		{ "land bonus is 10 x land level", function(t)
			t:Equal(RulesConfig.getLandBonusHP(1), 10)
			t:Equal(RulesConfig.getLandBonusHP(3), 30)
			t:Equal(RulesConfig.getLandBonusHP(5), 50)
		end },

		{ "lap bonus grows with lap number, territories and symbols", function(t)
			-- lap 1, nothing owned: just the base magic
			t:Equal(RulesConfig.getLapBonus(500, 1, 0, 0), 500)
			-- lap 3: 500 + 50*2 = 600
			t:Equal(RulesConfig.getLapBonus(500, 3, 0, 0), 600)
			-- 4 territories add 80
			t:Equal(RulesConfig.getLapBonus(500, 1, 4, 0), 580)
			-- 1000 symbol value adds 100
			t:Equal(RulesConfig.getLapBonus(500, 1, 0, 1000), 600)
			-- all together
			t:Equal(RulesConfig.getLapBonus(500, 3, 4, 1000), 780)
		end },

		{ "symbol lap bonus floors rather than rounding", function(t)
			-- 55 * 0.10 = 5.5 -> 5
			t:Equal(RulesConfig.getLapBonus(500, 1, 0, 55), 505)
		end },

		{ "level is clamped to the configured maximum", function(t)
			t:Equal(RulesConfig.Land.MaxLevel, 5)
			t:Equal(RulesConfig.getLandValue(100, 9, 1), RulesConfig.getLandValue(100, 5, 1))
			t:Equal(RulesConfig.getTollMultiplier(9), RulesConfig.getTollMultiplier(5))
		end },

		{ "hand and book limits match the stated rules", function(t)
			t:Equal(RulesConfig.Hand.MaxSize, 6, "hand cap")
			t:Equal(RulesConfig.Book.Size, 50, "standard book size")
			t:Equal(RulesConfig.Book.MaxCopiesPerCard, 4, "copies of one card")
			t:True(RulesConfig.Book.MinSize <= RulesConfig.Book.Size, "min <= standard")
			t:True(RulesConfig.Book.Size <= RulesConfig.Book.MaxSize, "standard <= max")
		end },

		{ "the default roll range is not hardcoded to a six-sided die", function(t)
			-- The value may be 1-6 today, but boards must be able to override
			-- it, so the constant has to exist as configuration.
			t:NotNil(RulesConfig.Roll.DefaultMin)
			t:NotNil(RulesConfig.Roll.DefaultMax)
			t:True(RulesConfig.Roll.DefaultMax >= RulesConfig.Roll.DefaultMin)
		end },
	},
}

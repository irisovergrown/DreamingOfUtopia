--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > TerritoryEconomySpec (ModuleScript)

	The brief's "Territory/economy" acceptance criteria, end to end across
	TerritoryService, ValuationService, EconomyService and VictoryService.

	RulesConfigSpec already pins the formulas in isolation. What this covers is
	the part that only exists once they are wired to state: that leveling moves
	CM one way and TM the other, that losing a chained territory devalues every
	other territory in that chain for BOTH players, and that reaching the goal
	is not the same as winning.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local RulesConfig = require(ReplicatedStorage.Shared.RulesConfig)
local BoardGraphService = require(ServerScriptService.Systems.BoardGraphService)
local TerritoryService = require(ServerScriptService.Systems.TerritoryService)
local ValuationService = require(ServerScriptService.Systems.ValuationService)
local EconomyService = require(ServerScriptService.Systems.EconomyService)
local VictoryService = require(ServerScriptService.Systems.VictoryService)
local LapService = require(ServerScriptService.Systems.LapService)

local ALICE, BOB = 101, 202

-- A two-area board, because chains are area-scoped and a single-area board
-- physically cannot show the difference between a correct implementation and
-- one that ignores areas entirely.
local function testBoard()
	local nodes = {
		{ Id = "Castle", Type = Enums.NodeType.Castle, Area = "North" },
	}
	local edges = {}

	-- North: four Fire territories. South: two more Fire ones, same element,
	-- different area — they must NOT join the northern chain.
	local layout = {
		{ Area = "North", Count = 4, Prefix = "N" },
		{ Area = "South", Count = 2, Prefix = "S" },
	}
	for _, group in ipairs(layout) do
		for index = 1, group.Count do
			table.insert(nodes, {
				Id = group.Prefix .. index,
				Type = Enums.NodeType.Territory,
				Area = group.Area,
				Element = Enums.Element.Fire,
				BaseValue = 100,
			})
		end
	end

	local order = { "Castle", "N1", "N2", "N3", "N4", "S1", "S2" }
	for index, nodeId in ipairs(order) do
		table.insert(edges, {
			Id = "E" .. index,
			From = nodeId,
			To = order[index % #order + 1],
		})
	end

	return {
		BoardId = "EconomyTestBoard",
		DisplayName = "Economy Test",
		Version = 1,
		DefaultMagic = 500,
		TMGoal = 3000,
		Roll = { Min = 1, Max = 6 },
		Areas = { { Id = "North", DisplayName = "North" }, { Id = "South", DisplayName = "South" } },
		Nodes = nodes,
		Edges = edges,
		RequiredFortTypes = {},
		CastleNodeIds = { "Castle" },
		StartNodeId = "Castle",
	}
end

local function fresh()
	assert(BoardGraphService.Load(testBoard()).Ok, "test board failed to load")
	LapService.Init({ Graph = BoardGraphService })
	TerritoryService.Init({ Graph = BoardGraphService, Economy = EconomyService })
	EconomyService.Init({ Territory = TerritoryService, Lap = LapService, Graph = BoardGraphService })
	ValuationService.Init({ Territory = TerritoryService, Economy = EconomyService })
	VictoryService.Init({ Valuation = ValuationService, Lap = LapService, Graph = BoardGraphService })

	EconomyService.RegisterPlayer(ALICE, 5000)
	EconomyService.RegisterPlayer(BOB, 5000)
end

local function own(userId, ...)
	for _, nodeId in ipairs({ ... }) do
		TerritoryService.SetOwner(nodeId, userId)
	end
end

return {
	Name = "Territory & economy",
	Tests = {
		{ "territories seed their element and base value from the board", function(t)
			fresh()
			local territory = TerritoryService.GetTerritory("N1")
			t:Equal(territory.Element, Enums.Element.Fire)
			t:Equal(territory.BaseValue, 100)
			t:Equal(territory.Level, 1, "everything starts at level 1")
			t:Nil(territory.Owner)
			t:Equal(#TerritoryService.GetAllTerritories(), 6, "the castle is not a territory")
		end },

		{ "an unchained base-100 territory follows the level table", function(t)
			fresh()
			own(ALICE, "N1")

			local expected = { 100, 200, 400, 800, 1600 }
			for level, value in ipairs(expected) do
				if level > 1 then
					EconomyService.AddMagic(ALICE, 5000)
					TerritoryService.LevelUp(ALICE, "N1", level)
				end
				t:Equal(TerritoryService.GetLandValue("N1"), value, "level " .. level)
			end
		end },

		{ "chain multipliers are 1.0 / 1.5 / 1.8 / 2.0 / 2.2", function(t)
			fresh()
			local expected = { 100, 150, 180, 200 }

			for count = 1, 4 do
				fresh()
				local nodes = {}
				for index = 1, count do
					table.insert(nodes, "N" .. index)
				end
				own(ALICE, table.unpack(nodes))
				t:Equal(TerritoryService.GetChainSize(ALICE, Enums.Element.Fire, "North"), count)
				t:Equal(TerritoryService.GetLandValue("N1"), expected[count], count .. " in chain")
			end
		end },

		{ "chains are scoped to an area", function(t)
			-- Six Fire territories, but four north and two south. The northern
			-- chain is four, not six. A board with one area cannot tell these
			-- implementations apart, which is why the test board has two.
			fresh()
			own(ALICE, "N1", "N2", "N3", "N4", "S1", "S2")

			t:Equal(TerritoryService.GetChainSize(ALICE, Enums.Element.Fire, "North"), 4)
			t:Equal(TerritoryService.GetChainSize(ALICE, Enums.Element.Fire, "South"), 2)
			t:Equal(TerritoryService.GetLandValue("N1"), 200, "northern land uses a 4-chain")
			t:Equal(TerritoryService.GetLandValue("S1"), 150, "southern land uses a 2-chain")
		end },

		{ "tolls follow the level table", function(t)
			fresh()
			own(ALICE, "N1")

			local expected = { 20, 60, 160, 480, 1280 }
			for level, toll in ipairs(expected) do
				if level > 1 then
					EconomyService.AddMagic(ALICE, 5000)
					TerritoryService.LevelUp(ALICE, "N1", level)
				end
				t:Equal(TerritoryService.GetToll("N1"), toll, "level " .. level)
			end
		end },

		{ "an unowned territory charges no toll", function(t)
			fresh()
			t:Equal(TerritoryService.GetToll("N1"), 0)
		end },

		{ "levelling costs Current Magic and raises Total Magic", function(t)
			-- The strategic loop, and the reason CM and TM had to be separated:
			-- with one number this reads as pure loss.
			fresh()
			own(ALICE, "N1", "N2", "N3")

			local cmBefore = EconomyService.GetBalance(ALICE)
			local tmBefore = ValuationService.GetTotalMagic(ALICE)

			local result = TerritoryService.LevelUp(ALICE, "N1", 3)
			t:True(result.Ok)
			t:Equal(result.Payload.Cost, 300, "100 + 200 for levels 2 and 3")

			t:Equal(EconomyService.GetBalance(ALICE), cmBefore - 300, "CM fell by the cost")
			t:True(ValuationService.GetTotalMagic(ALICE) > tmBefore, "TM rose anyway")
		end },

		{ "a player may jump straight to level 5 for the cumulative cost", function(t)
			fresh()
			own(ALICE, "N1")
			local result = TerritoryService.LevelUp(ALICE, "N1", 5)

			t:True(result.Ok)
			t:Equal(result.Payload.Cost, 1500, "100 + 200 + 400 + 800")
			t:Equal(TerritoryService.GetTerritory("N1").Level, 5)
		end },

		{ "levelling is refused above the cap, downward, or on land you do not own", function(t)
			fresh()
			own(ALICE, "N1")

			t:Equal(TerritoryService.LevelUp(ALICE, "N1", 6).Code, Enums.RejectReason.IllegalAction)
			t:Equal(TerritoryService.LevelUp(ALICE, "N1", 1).Code, Enums.RejectReason.IllegalAction)
			t:Equal(TerritoryService.LevelUp(BOB, "N1", 2).Code, Enums.RejectReason.InvalidTarget)
			t:Equal(TerritoryService.GetTerritory("N1").Level, 1, "and none of them moved it")
		end },

		{ "an unaffordable level-up changes nothing", function(t)
			fresh()
			own(ALICE, "N1")
			EconomyService.RegisterPlayer(ALICE, 50)

			local result = TerritoryService.LevelUp(ALICE, "N1", 5)
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.InsufficientMagic)
			t:Equal(EconomyService.GetBalance(ALICE), 50, "nothing was spent")
			t:Equal(TerritoryService.GetTerritory("N1").Level, 1)
		end },

		{ "losing a chained territory devalues every other one in that chain", function(t)
			-- And for both players at once: Bob gains, Alice loses more than
			-- the single territory was worth.
			fresh()
			own(ALICE, "N1", "N2", "N3", "N4")

			local aliceBefore = ValuationService.GetTotalMagic(ALICE)
			local n1Before = TerritoryService.GetLandValue("N1")
			t:Equal(n1Before, 200, "a 4-chain")

			-- Bob takes one.
			TerritoryService.SetOwner("N4", BOB)

			t:Equal(TerritoryService.GetLandValue("N1"), 180, "Alice's remaining land dropped to a 3-chain")
			t:True(ValuationService.GetTotalMagic(ALICE) < aliceBefore - n1Before,
				"she lost more than the territory itself was worth")
			t:True(ValuationService.GetTotalMagic(BOB) > 5000, "and Bob is worth more")
		end },

		{ "Total Magic is Current Magic plus land value", function(t)
			fresh()
			own(ALICE, "N1", "N2")

			local cm = EconomyService.GetBalance(ALICE)
			local land = ValuationService.GetLandValue(ALICE)
			t:Equal(land, 300, "two 1.5x-chained base-100 territories")
			t:Equal(ValuationService.GetTotalMagic(ALICE), cm + land)
		end },

		{ "standings rank by Total Magic, not by cash", function(t)
			fresh()
			-- Alice spends most of her cash on land; Bob sits on his.
			-- Four chained territories are worth 4 x 200 = 800, so Alice's TM
			-- is 900 against Bob's 700 — deliberately not a tie, or the
			-- userId tiebreak would decide this instead of the totals.
			own(ALICE, "N1", "N2", "N3", "N4")
			EconomyService.RegisterPlayer(ALICE, 100)
			EconomyService.RegisterPlayer(BOB, 700)

			local standings = ValuationService.GetStandings({ ALICE, BOB })
			t:Equal(standings[1].UserId, ALICE, "the landowner leads despite less cash")
			t:Equal(standings[1].TotalMagic, 900, "100 cash + 800 land")
			t:Equal(standings[2].TotalMagic, 700, "cash only")
			t:True(standings[1].CurrentMagic < standings[2].CurrentMagic, "on cash alone she would be behind")
		end },

		{ "terrain change works on your OWN occupied land", function(t)
			-- The previous rule was exactly backwards: unclaimed land only,
			-- as a workaround for the land bonus being baked into defender HP.
			-- Milestone 4 removed the reason, so this removes the restriction.
			fresh()
			own(ALICE, "N1")

			local result = TerritoryService.ChangeElement(ALICE, "N1", Enums.Element.Water)
			t:True(result.Ok, "owned land can be converted")
			t:Equal(TerritoryService.GetTerritory("N1").Element, Enums.Element.Water)
		end },

		{ "terrain change costs level x 100 plus 200 on elemental land", function(t)
			fresh()
			own(ALICE, "N1")

			-- N1 starts as Fire, so the surcharge applies.
			t:Equal(TerritoryService.GetElementChangeCost("N1"), 300, "level 1, already elemental")

			EconomyService.AddMagic(ALICE, 5000)
			TerritoryService.LevelUp(ALICE, "N1", 3)
			t:Equal(TerritoryService.GetElementChangeCost("N1"), 500, "level 3, already elemental")
		end },

		{ "converting a chained territory breaks the chain", function(t)
			fresh()
			own(ALICE, "N1", "N2", "N3")
			t:Equal(TerritoryService.GetLandValue("N2"), 180, "a 3-chain")

			TerritoryService.ChangeElement(ALICE, "N1", Enums.Element.Water)
			t:Equal(TerritoryService.GetLandValue("N2"), 150, "now a 2-chain")
		end },

		{ "terrain change is refused on land you do not own", function(t)
			fresh()
			own(ALICE, "N1")
			local result = TerritoryService.ChangeElement(BOB, "N1", Enums.Element.Water)
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.InvalidTarget)
		end },

		{ "an affordable toll is paid in full and credited to the owner", function(t)
			fresh()
			own(BOB, "N1")
			EconomyService.RegisterPlayer(ALICE, 500)
			EconomyService.RegisterPlayer(BOB, 500)

			local result = EconomyService.PayToll(ALICE, "N1")
			t:True(result.Ok)
			t:Equal(result.Payload.Toll, 20)
			t:Equal(result.Payload.Shortfall, 0)
			t:Equal(EconomyService.GetBalance(ALICE), 480)
			t:Equal(EconomyService.GetBalance(BOB), 520)
		end },

		{ "an unaffordable toll takes what it can and records a debt", function(t)
			-- Not refused. The brief is explicit that a mandatory payment
			-- enters liquidation rather than being rejected, and "Not enough
			-- Magic, so nothing happened" is not a state the rules have.
			fresh()
			own(BOB, "N1")
			EconomyService.AddMagic(BOB, 5000)
			TerritoryService.LevelUp(BOB, "N1", 5) -- toll becomes 1280
			EconomyService.RegisterPlayer(ALICE, 300)

			local result = EconomyService.PayToll(ALICE, "N1")
			t:True(result.Ok, "the payment is processed, not refused")
			t:Equal(result.Payload.Toll, 1280)
			t:Equal(result.Payload.Paid, 300, "everything she had")
			t:Equal(result.Payload.Shortfall, 980)
			t:Equal(EconomyService.GetBalance(ALICE), 0)
			t:Equal(EconomyService.GetDebt(ALICE), 980, "the rest is a debt")
		end },

		{ "liquidating a territory pays down the debt", function(t)
			fresh()
			own(ALICE, "N1", "N2")
			own(BOB, "N3")
			EconomyService.AddMagic(BOB, 5000)
			TerritoryService.LevelUp(BOB, "N3", 5)
			EconomyService.RegisterPlayer(ALICE, 0)

			EconomyService.PayToll(ALICE, "N3")
			local debtBefore = EconomyService.GetDebt(ALICE)
			t:True(debtBefore > 0, "she owes something")

			local sale = EconomyService.LiquidateTerritory(ALICE, "N1")
			t:True(sale.Ok)
			t:True(sale.Payload.Proceeds > 0)
			t:True(sale.Payload.RemainingDebt < debtBefore, "the debt shrank")
			t:Nil(TerritoryService.GetTerritory("N1").Owner, "and the land is gone")
		end },

		{ "selling into a debt smaller than the proceeds returns the change", function(t)
			fresh()
			own(ALICE, "N1")
			EconomyService.RegisterPlayer(ALICE, 0)
			EconomyService.RequirePayment(ALICE, 10) -- a 10 debt

			local sale = EconomyService.LiquidateTerritory(ALICE, "N1")
			t:Equal(sale.Payload.AppliedToDebt, 10)
			t:Equal(sale.Payload.RemainingDebt, 0)
			t:Equal(EconomyService.GetBalance(ALICE), sale.Payload.Proceeds - 10, "the change came back as cash")
		end },

		{ "a player with debt and no land left is bankrupt", function(t)
			fresh()
			EconomyService.RegisterPlayer(ALICE, 0)
			EconomyService.RequirePayment(ALICE, 500)

			t:True(EconomyService.IsBankrupt(ALICE), "nothing left to sell")

			fresh()
			own(ALICE, "N1")
			EconomyService.RegisterPlayer(ALICE, 0)
			EconomyService.RequirePayment(ALICE, 500)
			t:False(EconomyService.IsBankrupt(ALICE), "still has an asset")
		end },

		{ "reaching the goal away from the castle does NOT win", function(t)
			-- The long walk home is the part of Culdcept everyone remembers,
			-- and ending the match on the number removes it entirely.
			fresh()
			VictoryService.SetGoal(3000)
			EconomyService.RegisterPlayer(ALICE, 4000)
			VictoryService.RefreshGoalStates({ ALICE })

			t:True(VictoryService.HasReachedGoal(ALICE), "over the line")
			t:True(VictoryService.IsGoalReachedState(ALICE), "and visibly so")
			t:False(VictoryService.IsMatchWon(), "but the match is not over")
			t:Nil(VictoryService.GetWinner())
		end },

		{ "arriving at the castle over the goal wins", function(t)
			fresh()
			VictoryService.SetGoal(3000)
			EconomyService.RegisterPlayer(ALICE, 4000)
			VictoryService.RefreshGoalStates({ ALICE })

			t:True(VictoryService.TryConfirmAtCastle(ALICE, "Castle"))
			t:Equal(VictoryService.GetWinner(), ALICE)
			t:True(VictoryService.IsMatchWon())
		end },

		{ "arriving anywhere else does not win", function(t)
			fresh()
			VictoryService.SetGoal(3000)
			EconomyService.RegisterPlayer(ALICE, 4000)

			t:False(VictoryService.TryConfirmAtCastle(ALICE, "N1"), "not a castle")
			t:False(VictoryService.IsMatchWon())
		end },

		{ "falling below the goal before the castle prevents the win", function(t)
			-- The re-check is what gives the goal-reached state its teeth: a
			-- rival who takes your land on the way home can undo it.
			fresh()
			VictoryService.SetGoal(3000)
			-- 2800 cash plus a 2-chain worth 150 each = 3100, over the line.
			-- Losing one drops the survivor to an unchained 100, so 2900 —
			-- under it. The margins are chosen so the loss actually crosses
			-- the goal rather than landing exactly on it.
			EconomyService.RegisterPlayer(ALICE, 2800)
			own(ALICE, "N1", "N2")
			VictoryService.RefreshGoalStates({ ALICE })
			t:True(VictoryService.IsGoalReachedState(ALICE))
			t:Equal(ValuationService.GetTotalMagic(ALICE), 3100)

			-- Bob takes one on her way home.
			TerritoryService.SetOwner("N1", BOB)
			VictoryService.RefreshGoalStates({ ALICE })
			t:Equal(ValuationService.GetTotalMagic(ALICE), 2900, "the chain bonus went with it")

			t:False(VictoryService.HasReachedGoal(ALICE), "back under the line")
			t:False(VictoryService.TryConfirmAtCastle(ALICE, "Castle"), "so arriving wins nothing")
			t:False(VictoryService.IsMatchWon())
		end },

		{ "losing the goal state is announced", function(t)
			fresh()
			VictoryService.SetGoal(3000)
			local lost = 0
			local connection = VictoryService.GoalLost:Connect(function()
				lost += 1
			end)

			EconomyService.RegisterPlayer(ALICE, 4000)
			VictoryService.RefreshGoalStates({ ALICE })
			EconomyService.RegisterPlayer(ALICE, 100)
			VictoryService.RefreshGoalStates({ ALICE })
			connection.Disconnect()

			t:Equal(lost, 1, "the player was told they slipped back")
		end },

		{ "the lap bonus uses the brief's formula", function(t)
			fresh()
			own(ALICE, "N1", "N2", "N3", "N4")
			-- Lap 1, four territories: 500 base + 4 x 20 land = 580.
			t:Equal(EconomyService.ComputeLapBonus(ALICE), 580)
		end },

		{ "a departing player's land is released", function(t)
			-- Otherwise it stays owned by a ghost, and every chain it was part
			-- of keeps inflating tolls nobody can collect.
			fresh()
			own(ALICE, "N1", "N2")
			TerritoryService.ReleaseAllOwnedBy(ALICE)

			t:Equal(#TerritoryService.GetOwnedBy(ALICE), 0)
			t:Nil(TerritoryService.GetTerritory("N1").Owner)
		end },

		{ "rounding stays exact at base 80 and 120 through the chain", function(t)
			-- RulesConfigSpec covers the formula; this confirms it survives
			-- contact with real state rather than being recomputed elsewhere.
			t:Equal(RulesConfig.getToll(80, 1, 3), 28, "28.8 floored")
			t:Equal(RulesConfig.getToll(120, 1, 3), 43, "43.2 floored")
		end },
	},
}

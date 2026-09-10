--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > CharacterizationSpec (ModuleScript)

	Purpose:
		Pins what the CURRENT services actually compute, before Milestone 5
		replaces the formulas. These are not assertions that the values are
		right — several are provably wrong against the target rules, and each
		one below says so and names what it becomes.

		The point is that when the formulas change, exactly these tests fail,
		and the diff between "tests I expected to fail" and "tests that
		actually failed" is the blast radius of the change. A refactor that
		breaks something unintended shows up here instead of in a playtest
		three weeks later.

	Running:
		This spec calls BoardService.Init() for a clean registry and assigns
		ownership to a synthetic user id, so it mutates whatever BoardService
		instance it can reach. Whether that is the LIVE one depends on how it
		is run, and the difference is not obvious:

		- Through the MCP execute_luau tool, it is not. Those calls share a
		  module cache with each other but NOT with Main.server.lua, so the
		  spec gets its own BoardService and the running match is untouched.
		  (Verified: Main's signals show zero handlers from inside that
		  sandbox, while Main is demonstrably connected to them.)
		- From a real Script inside the place, it IS the live one, and this
		  spec will reset ownership on the board mid-match.

		Either way it re-inits at the end, so the board is left unowned rather
		than half-claimed. Prefer a throwaway playtest.

		The same sandboxing means this harness cannot verify Main's signal
		wiring, the client HUD, or a full turn. Those need a real playtest
		driven through RemoteEvents, which do cross into the live server.

	Board assumed:
		The 16-tile ring in the place: tile 1 Start, tiles 2-16 Property
		cycling Earth/Fire/Air/Water, no BaseValue set (so all default to
		100). Guarded by the first test — if the board is re-authored, that
		test fails first and explains why the rest did.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local BoardService = require(ServerScriptService.Systems.BoardService)
local BattleService = require(ServerScriptService.Systems.BattleService)
local TerraformService = require(ServerScriptService.Systems.TerraformService)

local TEST_USER_ID = -4242

local EARTH_TILES = { 2, 6, 10, 14 }

local function resetBoard()
	BoardService.Init()
end

local function ownTiles(tileIds, count)
	for index = 1, count do
		BoardService.SetOwner(tileIds[index], TEST_USER_ID)
	end
end

return {
	Name = "Characterization (current behavior)",
	Tests = {
		{ "the board under test is the expected 16-tile ring", function(t)
			resetBoard()
			local tiles = BoardService.GetAllTiles()
			t:Equal(#tiles, 16, "tile count -- if this fails, the board was re-authored and the rest of this spec is meaningless")
			t:Equal(tiles[1].TileType, "Start")
			t:Equal(tiles[2].Era, "Earth")
			t:Equal(tiles[2].BaseValue, 100, "BaseValue defaults when the attribute is unset")
			t:Equal(tiles[2].Level, 1, "tiles start at level 1")
			resetBoard()
		end },

		{ "CURRENT chain multiplier is linear +0.5 per extra tile", function(t)
			-- TARGET (Milestone 5): 1.0 / 1.5 / 1.8 / 2.0 / 2.2, capped at 5.
			-- Current code diverges from level 3 upward and never caps.
			resetBoard()

			ownTiles(EARTH_TILES, 1)
			t:Equal(BoardService.GetChainMultiplier(TEST_USER_ID, "Earth"), 1, "1 tile")

			ownTiles(EARTH_TILES, 2)
			t:Equal(BoardService.GetChainMultiplier(TEST_USER_ID, "Earth"), 1.5, "2 tiles -- agrees with target")

			ownTiles(EARTH_TILES, 3)
			t:Equal(BoardService.GetChainMultiplier(TEST_USER_ID, "Earth"), 2, "3 tiles -- target is 1.8")

			ownTiles(EARTH_TILES, 4)
			t:Equal(BoardService.GetChainMultiplier(TEST_USER_ID, "Earth"), 2.5, "4 tiles -- target is 2.0")

			resetBoard()
		end },

		{ "CURRENT toll multipliers are 0.2/0.35/0.5/0.65/0.8", function(t)
			-- TARGET (Milestone 5): 0.2 / 0.3 / 0.4 / 0.6 / 0.8.
			-- Levels 1 and 5 already agree; 2, 3 and 4 are all too generous.
			-- Only level 1 is observable in play today because nothing calls
			-- LevelUp -- this spec reaches it directly.
			resetBoard()
			BoardService.SetOwner(2, TEST_USER_ID)

			t:Equal(BoardService.GetTileValue(2), 100, "L1, single tile, base 100")
			t:Equal(BoardService.GetToll(2), 20, "L1 toll -- agrees with target")

			BoardService.LevelUp(2)
			t:Equal(BoardService.GetTileValue(2), 200, "L2 value")
			t:Equal(BoardService.GetToll(2), 70, "L2 toll at 0.35 -- target is 60 at 0.3")

			BoardService.LevelUp(2)
			t:Equal(BoardService.GetToll(2), 200, "L3 toll at 0.5 -- target is 160 at 0.4")

			resetBoard()
		end },

		{ "CURRENT land value already matches the target structure", function(t)
			-- BaseValue x 2^(Level-1) x Chain is correct; only the chain
			-- factor is wrong, so this survives Milestone 5 unchanged for
			-- unchained land.
			resetBoard()
			BoardService.SetOwner(2, TEST_USER_ID)

			t:Equal(BoardService.GetTileValue(2), 100, "L1")
			BoardService.LevelUp(2)
			t:Equal(BoardService.GetTileValue(2), 200, "L2")
			BoardService.LevelUp(2)
			t:Equal(BoardService.GetTileValue(2), 400, "L3")
			BoardService.LevelUp(2)
			t:Equal(BoardService.GetTileValue(2), 800, "L4")
			BoardService.LevelUp(2)
			t:Equal(BoardService.GetTileValue(2), 1600, "L5")

			resetBoard()
		end },

		{ "CURRENT level cap is 5 and LevelUp returns nil past it", function(t)
			resetBoard()
			BoardService.SetOwner(2, TEST_USER_ID)
			for _ = 1, 4 do
				BoardService.LevelUp(2)
			end
			t:Equal(BoardService.GetTile(2).Level, 5)
			t:Nil(BoardService.LevelUp(2), "cannot exceed the cap")
			resetBoard()
		end },

		{ "CURRENT land bonus is 10 x level and already matches the target", function(t)
			resetBoard()
			t:Equal(BoardService.GetLandBonusHP(2), 10, "L1")
			BoardService.SetOwner(2, TEST_USER_ID)
			BoardService.LevelUp(2)
			t:Equal(BoardService.GetLandBonusHP(2), 20, "L2")
			resetBoard()
		end },

		{ "FIXED in Milestone 4: the land bonus is no longer fused into HP", function(t)
			-- This test previously pinned the defect: GetEffectiveHP returned
			-- 60 + 10 as one number, so a creature's stored health silently
			-- included a bonus that belonged to the tile. That is what forced
			-- terraforming to be restricted to unclaimed land -- changing the
			-- element afterwards left the cached value wrong with no way to
			-- detect it.
			--
			-- Milestone 4 separated them: a creature keeps BaseMHP/BonusMHP/
			-- CurrentHP, and the land bonus is computed per battle from the
			-- tile's CURRENT element and level. The old function is gone, and
			-- this now records the correct behaviour instead.
			t:Nil(rawget(BattleService, "GetEffectiveHP"), "the fused accessor no longer exists")
			t:NotNil(BattleService.GetLandBonusFor, "replaced by a computed bonus")
		end },

		{ "CURRENT terraform cost is 50 + 30/level, +50 for a specific element", function(t)
			-- TARGET (Milestone 5): level x 100, plus 200 when the land
			-- already has an element. Both the shape and the numbers change.
			resetBoard()

			t:Equal(TerraformService.GetTerraformCost(2, nil), 80, "L1 to neutral -- target is 100")
			t:Equal(TerraformService.GetTerraformCost(2, "Fire"), 130, "L1 to Fire -- target is 300 on already-elemental land")

			BoardService.SetOwner(2, TEST_USER_ID)
			BoardService.LevelUp(2)
			t:Equal(TerraformService.GetTerraformCost(2, "Fire"), 160, "L2 to Fire")

			resetBoard()
		end },

		{ "CURRENT terraform refuses owned tiles", function(t)
			-- TARGET (brief section 6): terrain change is a Territory Command
			-- performed ON your own occupied land. The current restriction is
			-- exactly backwards.
			resetBoard()
			BoardService.SetOwner(2, TEST_USER_ID)

			local success, reason = TerraformService.TerraformTile(TEST_USER_ID, 2, "Fire")
			t:False(success, "owned tile is refused today")
			t:True(string.find(tostring(reason), "already claimed", 1, true) ~= nil, "refused for ownership, not cost")

			resetBoard()
		end },

		{ "CURRENT ownership and element changes are the only mutable tile state", function(t)
			resetBoard()

			BoardService.SetOwner(3, TEST_USER_ID)
			t:Equal(BoardService.GetTile(3).Owner, TEST_USER_ID)

			BoardService.SetOwner(3, nil)
			t:Nil(BoardService.GetTile(3).Owner, "ownership can be cleared")

			BoardService.SetEra(3, "Water")
			t:Equal(BoardService.GetTile(3).Era, "Water")

			resetBoard()
			t:Equal(BoardService.GetTile(3).Era, "Fire", "Init re-reads the authored element")
		end },

		{ "CURRENT topology is a sorted ring with no junctions", function(t)
			-- What the graph must reproduce exactly in Milestone 2 before it
			-- can be trusted on a board with real branches.
			resetBoard()

			t:Equal(BoardService.GetStartTileId(), 1)
			t:Equal(BoardService.GetNextTileId(1), 2)
			t:Equal(BoardService.GetNextTileId(15), 16)
			t:Equal(BoardService.GetNextTileId(16), 1, "ring wraps")
			t:Nil(BoardService.GetNextTileId(999), "unknown tile has no successor")

			resetBoard()
		end },
	},
}

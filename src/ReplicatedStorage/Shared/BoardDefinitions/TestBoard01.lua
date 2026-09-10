--[[
	ModuleScript — shared, data asset.

	Studio placement:
		ReplicatedStorage > Shared > BoardDefinitions > TestBoard01 (ModuleScript)

	Purpose:
		A deliberately small board that contains one of every movement feature
		Milestone 2 has to prove, so each acceptance test has something real to
		run against rather than a fixture invented for it.

		Disposable greybox. It exists to exercise the movement resolver, not
		to be played, and it does not touch the hand-authored 16-tile board in
		Workspace. tools/generate-test-board.lua spawns matching Parts when a
		visual is wanted.

	The main loop, nine steps from the castle back to it:

		Castle -> P1 -> FortSun -> JT -> P2 -> Bridge ==> P4 -> FortMoon -> Pool -> Castle
		                            |                (warp)
		                            +-> S1 <-> DeadEnd

	What each feature is here to test:

		JT          A real T-junction. Arriving from FortSun, both P2 and S1
		            are legal, so movement must pause and ask. Arriving back
		            from S1, only P2 is legal — you may not immediately
		            reverse down the spur you just came up.

		DeadEnd     Its only edge leads back to S1. Reversal is normally
		            forbidden, so this proves the dead-end exception: there,
		            the way back is the only continuation.

		Bridge      A MandatoryWarp. Triggers even when merely crossed, and
		            movement continues from P4 with the steps that were left.

		Pool        A LandingWarp. Must NOT fire when crossed — only when
		            movement ends exactly on it.

		FortSun     Two fort types, both required for a lap. Visiting one
		FortMoon    twice must not substitute for the other, and crossing the
		            castle without both must not complete a lap.

	Deliberately NOT here: symbols, shrines, fountains and multi-area chains.
	Those belong to Milestone 6 and would add surface with nothing yet to
	check it against.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local RulesConfig = require(ReplicatedStorage.Shared.RulesConfig)

local AREA = "Proving"
local BASE = RulesConfig.Land.DefaultBaseValue

local function territory(id, element, studioNodeId, extra)
	local node = {
		Id = id,
		Type = Enums.NodeType.Territory,
		Area = AREA,
		Element = element,
		BaseValue = BASE,
		StudioNodeId = studioNodeId,
	}
	for key, value in pairs(extra or {}) do
		node[key] = value
	end
	return node
end

return {
	BoardId = "TestBoard01",
	DisplayName = "Proving Ground",
	Version = 1,

	RecommendedPlayers = { Min = 2, Max = 4 },

	DefaultMagic = RulesConfig.Match.DefaultStartingMagic,
	TMGoal = RulesConfig.Match.DefaultTMGoal,

	Roll = { Min = 1, Max = 6 },

	Areas = {
		{ Id = AREA, DisplayName = "Proving Ground" },
	},

	Nodes = {
		{ Id = "Castle", Type = Enums.NodeType.Castle, Area = AREA, StudioNodeId = 1 },

		territory("P1", Enums.Element.Fire, 2),

		{ Id = "FortSun", Type = Enums.NodeType.Fort, Area = AREA, FortType = "Sun", StudioNodeId = 3 },

		-- The junction. Three edges touch it: in from FortSun, out to P2, and
		-- a two-way spur to S1.
		territory("JT", Enums.Element.Air, 4),

		territory("P2", Enums.Element.Water, 5),

		-- Pass-through transport. Entering relocates to P4 whether this was
		-- the final step or a step along the way.
		{
			Id = "Bridge",
			Type = Enums.NodeType.MandatoryWarp,
			Area = AREA,
			TransportTo = "P4",
			StudioNodeId = 6,
		},

		territory("S1", Enums.Element.Earth, 7),
		territory("DeadEnd", Enums.Element.Fire, 8),

		territory("P4", Enums.Element.Earth, 9),

		{ Id = "FortMoon", Type = Enums.NodeType.Fort, Area = AREA, FortType = "Moon", StudioNodeId = 10 },

		-- Landing-only transport. Crossing it must do nothing at all.
		{
			Id = "Pool",
			Type = Enums.NodeType.LandingWarp,
			Area = AREA,
			TransportTo = "P1",
			StudioNodeId = 11,
		},
	},

	Edges = {
		{ Id = "E01", From = "Castle", To = "P1" },
		{ Id = "E02", From = "P1", To = "FortSun" },
		{ Id = "E03", From = "FortSun", To = "JT" },

		-- The branch: main route and spur, both legal from JT.
		{ Id = "E04", From = "JT", To = "P2" },
		{ Id = "E05", From = "JT", To = "S1" },

		{ Id = "E06", From = "P2", To = "Bridge" },
		{ Id = "E07", From = "Bridge", To = "P4" },

		-- Spur, two-way. S1 -> JT is what makes the "no immediate reversal"
		-- rule observable at the junction.
		{ Id = "E08", From = "S1", To = "DeadEnd" },
		{ Id = "E09", From = "S1", To = "JT" },
		{ Id = "E10", From = "DeadEnd", To = "S1" },

		{ Id = "E11", From = "P4", To = "FortMoon" },
		{ Id = "E12", From = "FortMoon", To = "Pool" },
		{ Id = "E13", From = "Pool", To = "Castle" },
	},

	-- Both are required, so one fort alone can never complete a lap.
	RequiredFortTypes = { "Sun", "Moon" },

	CastleNodeIds = { "Castle" },
	StartNodeId = "Castle",
}

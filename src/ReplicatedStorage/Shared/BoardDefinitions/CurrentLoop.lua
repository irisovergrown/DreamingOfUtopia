--[[
	ModuleScript — shared, data asset.

	Studio placement:
		ReplicatedStorage > Shared > BoardDefinitions > CurrentLoop (ModuleScript)

	Purpose:
		The board that is actually in the place today, expressed as graph
		data: sixteen nodes in a one-way ring, one castle, no forts, no
		junctions, no warps, one area.

		This is the migration bridge. It is a faithful description of current
		behavior, not a target board — a degenerate graph with exactly one
		exit per node walks identically to the sorted-ID loop BoardService
		uses now. That makes it the honest baseline: the graph movement
		system can be built and proved against a board whose correct output
		is already known, before any board with real junctions exists.

		It also gives the validator something real to run on, so the schema
		is tested against authored data rather than only against fixtures.

		Node ids are strings ("T1") while StudioTileId is the number in each
		Part's `Id` attribute. Keeping them distinct means renaming or
		re-authoring the geometry never renames a graph node, and a node can
		exist before anyone has modelled it.

		Element assignment mirrors what is set on the Parts right now:
		tile 1 is the castle, tiles 2-16 cycle Earth, Fire, Air, Water.
		BaseValue is unset on every Part, so all territories take the
		RulesConfig default.

	Known gaps versus a target board (deliberate — this describes today):
		- No forts, so RequiredFortTypes is empty and a lap completes on
		  reaching the castle alone. That is exactly what happens now.
		- One-way edges only; there is nothing to turn around at.
		- A single area, so every same-element territory chains with every
		  other regardless of distance.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local RulesConfig = require(ReplicatedStorage.Shared.RulesConfig)

local MAIN_AREA = "Main"

-- Elements on tiles 2..16, in tile order, as authored in the place.
local TERRITORY_ELEMENTS = {
	Enums.Element.Earth,
	Enums.Element.Fire,
	Enums.Element.Air,
	Enums.Element.Water,
	Enums.Element.Earth,
	Enums.Element.Fire,
	Enums.Element.Air,
	Enums.Element.Water,
	Enums.Element.Earth,
	Enums.Element.Fire,
	Enums.Element.Air,
	Enums.Element.Water,
	Enums.Element.Earth,
	Enums.Element.Fire,
	Enums.Element.Air,
}

local nodes = {
	{
		Id = "T1",
		Type = Enums.NodeType.Castle,
		Area = MAIN_AREA,
		StudioTileId = 1,
	},
}

for offset, element in ipairs(TERRITORY_ELEMENTS) do
	local tileId = offset + 1
	table.insert(nodes, {
		Id = "T" .. tileId,
		Type = Enums.NodeType.Territory,
		Area = MAIN_AREA,
		Element = element,
		BaseValue = RulesConfig.Land.DefaultBaseValue,
		StudioTileId = tileId,
	})
end

-- One-way ring: T1 -> T2 -> ... -> T16 -> T1.
local edges = {}
for index = 1, #nodes do
	local fromId = "T" .. index
	local toId = "T" .. (index % #nodes + 1)
	table.insert(edges, {
		Id = string.format("E%d", index),
		From = fromId,
		To = toId,
	})
end

return {
	BoardId = "CurrentLoop",
	DisplayName = "Placeholder Ring",
	Version = 1,

	RecommendedPlayers = { Min = 2, Max = 4 },

	DefaultMagic = RulesConfig.Match.DefaultStartingMagic,
	TMGoal = RulesConfig.Match.DefaultTMGoal,

	Roll = { Min = RulesConfig.Roll.DefaultMin, Max = RulesConfig.Roll.DefaultMax },

	Areas = {
		{ Id = MAIN_AREA, DisplayName = "Main" },
	},

	Nodes = nodes,
	Edges = edges,

	-- Empty on purpose: this board has no forts, so a lap needs only the
	-- castle. Matches current lap behavior exactly.
	RequiredFortTypes = {},

	CastleNodeIds = { "T1" },
	StartNodeId = "T1",
}

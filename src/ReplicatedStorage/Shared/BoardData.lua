--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > BoardData (ModuleScript)

	Purpose:
		Static layout for the FIRST greybox board only — a plain 16-tile
		perimeter loop used to stand up BoardService and prove the render
		pipeline. This is not final board content (brief calls for a fixed
		official board SET later, multiple boards). Board rendering and
		movement code should key off Tiles by Id / NextTileId, never assume
		this exact geometry.

		GridPosition is in tile units, not studs — multiply by
		BoardData.TileSpacing to get world offsets (see bootstrap script).

	Usage:
		local BoardData = require(game:GetService("ReplicatedStorage").Shared.BoardData)
		for _, tile in ipairs(BoardData.Tiles) do
			print(tile.Id, tile.Era, tile.BaseValue)
		end
]]

local BoardData = {}

BoardData.TileSpacing = 10 -- studs between tile centers
BoardData.TileSize = 8 -- stud footprint of one tile part

-- Placeholder 16-tile perimeter loop (5x5 grid border). Tile 1 is Start.
-- Era assignment below just cycles through the 4 confirmed eras in order —
-- not a real board design, purely to exercise the system end to end.
BoardData.Tiles = {
	{ Id = 1, GridPosition = { X = 0, Z = 0 }, Era = nil, BaseValue = 0, TileType = "Start" },
	{ Id = 2, GridPosition = { X = 1, Z = 0 }, Era = "CassetteFuturism", BaseValue = 100, TileType = "Property" },
	{ Id = 3, GridPosition = { X = 2, Z = 0 }, Era = "LaserGrid", BaseValue = 100, TileType = "Property" },
	{ Id = 4, GridPosition = { X = 3, Z = 0 }, Era = "EarlyCyber", BaseValue = 100, TileType = "Property" },
	{ Id = 5, GridPosition = { X = 4, Z = 0 }, Era = "FrutigerAero", BaseValue = 100, TileType = "Property" },
	{ Id = 6, GridPosition = { X = 4, Z = 1 }, Era = "CassetteFuturism", BaseValue = 100, TileType = "Property" },
	{ Id = 7, GridPosition = { X = 4, Z = 2 }, Era = "LaserGrid", BaseValue = 100, TileType = "Property" },
	{ Id = 8, GridPosition = { X = 4, Z = 3 }, Era = "EarlyCyber", BaseValue = 100, TileType = "Property" },
	{ Id = 9, GridPosition = { X = 4, Z = 4 }, Era = "FrutigerAero", BaseValue = 100, TileType = "Property" },
	{ Id = 10, GridPosition = { X = 3, Z = 4 }, Era = "CassetteFuturism", BaseValue = 100, TileType = "Property" },
	{ Id = 11, GridPosition = { X = 2, Z = 4 }, Era = "LaserGrid", BaseValue = 100, TileType = "Property" },
	{ Id = 12, GridPosition = { X = 1, Z = 4 }, Era = "EarlyCyber", BaseValue = 100, TileType = "Property" },
	{ Id = 13, GridPosition = { X = 0, Z = 4 }, Era = "FrutigerAero", BaseValue = 100, TileType = "Property" },
	{ Id = 14, GridPosition = { X = 0, Z = 3 }, Era = "CassetteFuturism", BaseValue = 100, TileType = "Property" },
	{ Id = 15, GridPosition = { X = 0, Z = 2 }, Era = "LaserGrid", BaseValue = 100, TileType = "Property" },
	{ Id = 16, GridPosition = { X = 0, Z = 1 }, Era = "EarlyCyber", BaseValue = 100, TileType = "Property" },
}

-- Convenience: tile id a Cepter moves to after landing on `tileId`, wrapping
-- around the loop back to Start. Movement/lap-bonus logic will use this.
function BoardData.GetNextTileId(tileId)
	local nextId = tileId + 1
	if nextId > #BoardData.Tiles then
		nextId = 1
	end
	return nextId
end

return BoardData

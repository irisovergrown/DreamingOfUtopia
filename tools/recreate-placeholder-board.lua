--[[
	Studio Command Bar script — ONE-TIME utility, not a runtime system.
	Not required by any ModuleScript/Script in src/, nothing references it.

	How to run:
		Studio > View tab > Command Bar (must be in EDIT mode, not Play —
		Command Bar edits made in Play mode don't save). Paste this whole
		file in and press Enter once.

	What it does:
		Recreates the old 16-tile procedural greybox loop as real, saved
		Parts under Workspace.Board, each tagged "Tile" and carrying the
		Id/TileType/Era/BaseValue attributes BoardService now reads (see
		its header). Gives you a working starting board matching what
		you've already tested, which you can then freely move, resize,
		retexture, or replace with real models — just keep the tag and
		attributes intact on whatever Parts end up representing tiles.
		Delete this script/folder from the repo once you've built your own
		board design and no longer need the starting point.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local ERA_COLORS = {
	Earth = Color3.fromRGB(196, 172, 130),
	Fire = Color3.fromRGB(255, 45, 185),
	Air = Color3.fromRGB(60, 255, 130),
	Water = Color3.fromRGB(110, 210, 255),
}
local NEUTRAL_COLOR = Color3.fromRGB(230, 225, 210)

local TILES = {
	{ Id = 1, X = -20, Z = -20, Era = nil, TileType = "Start", BaseValue = 0 },
	{ Id = 2, X = -10, Z = -20, Era = "Earth", TileType = "Property" },
	{ Id = 3, X = 0, Z = -20, Era = "Fire", TileType = "Property" },
	{ Id = 4, X = 10, Z = -20, Era = "Air", TileType = "Property" },
	{ Id = 5, X = 20, Z = -20, Era = "Water", TileType = "Property" },
	{ Id = 6, X = 20, Z = -10, Era = "Earth", TileType = "Property" },
	{ Id = 7, X = 20, Z = 0, Era = "Fire", TileType = "Property" },
	{ Id = 8, X = 20, Z = 10, Era = "Air", TileType = "Property" },
	{ Id = 9, X = 20, Z = 20, Era = "Water", TileType = "Property" },
	{ Id = 10, X = 10, Z = 20, Era = "Earth", TileType = "Property" },
	{ Id = 11, X = 0, Z = 20, Era = "Fire", TileType = "Property" },
	{ Id = 12, X = -10, Z = 20, Era = "Air", TileType = "Property" },
	{ Id = 13, X = -20, Z = 20, Era = "Water", TileType = "Property" },
	{ Id = 14, X = -20, Z = 10, Era = "Earth", TileType = "Property" },
	{ Id = 15, X = -20, Z = 0, Era = "Fire", TileType = "Property" },
	{ Id = 16, X = -20, Z = -10, Era = "Air", TileType = "Property" },
}

local folder = Workspace:FindFirstChild("Board") or Instance.new("Folder")
folder.Name = "Board"
folder.Parent = Workspace

for _, tile in ipairs(TILES) do
	local part = Instance.new("Part")
	part.Name = "Tile_" .. tile.Id
	part.Anchored = true
	part.Size = Vector3.new(8, 2, 8)
	part.Position = Vector3.new(tile.X, 1, tile.Z)
	part.Color = tile.Era and ERA_COLORS[tile.Era] or NEUTRAL_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part:SetAttribute("Id", tile.Id)
	part:SetAttribute("TileType", tile.TileType)
	if tile.Era ~= nil then
		part:SetAttribute("Era", tile.Era)
	end
	if tile.BaseValue ~= nil then
		part:SetAttribute("BaseValue", tile.BaseValue)
	end
	CollectionService:AddTag(part, "Tile")
	part.Parent = folder
end

print("Placed " .. #TILES .. " tagged Tile parts under Workspace.Board.")

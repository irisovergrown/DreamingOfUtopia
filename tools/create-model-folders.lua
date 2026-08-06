--[[
	Studio Command Bar script — ONE-TIME utility, not a runtime system.
	Not required by any ModuleScript/Script in src/, nothing references it.

	How to run:
		Studio > View tab > Command Bar (must be in EDIT mode, not Play —
		Command Bar edits made in Play mode don't save). Paste this whole
		file in and press Enter once.

	What it does:
		Creates the empty ReplicatedStorage > Models > Player and
		ReplicatedStorage > Models > Summons folders Main.server.lua expects
		(see its header, "Model authoring"). Just the container structure —
		it does NOT create any actual character/creature models. Place your
		own PlayerTemplate model (R6 Character + Humanoid, with a part
		named "HumanoidRootPart") under Models.Player, and one Model per
		creature under Models.Summons with a number Attribute named
		"CardId" matching its CardData entry.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modelsFolder = ReplicatedStorage:FindFirstChild("Models") or Instance.new("Folder")
modelsFolder.Name = "Models"
modelsFolder.Parent = ReplicatedStorage

local playerFolder = modelsFolder:FindFirstChild("Player") or Instance.new("Folder")
playerFolder.Name = "Player"
playerFolder.Parent = modelsFolder

local summonsFolder = modelsFolder:FindFirstChild("Summons") or Instance.new("Folder")
summonsFolder.Name = "Summons"
summonsFolder.Parent = modelsFolder

print("Created ReplicatedStorage.Models.Player and ReplicatedStorage.Models.Summons.")

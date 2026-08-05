--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > EraData (ModuleScript)

	Purpose:
		Single source of truth for the "element/color" system — retrofuturism
		eras standing in for Culdcept's classical elements. Board tiles,
		creature cards, and chain bonuses all key off the era ids defined
		here. The era roster is deliberately NOT hardcoded to 4 — add a new
		entry to Eras below and every system that reads this table (board
		rendering, chain calculation, deck filters, etc.) picks it up
		without other code changes.

	Usage:
		local EraData = require(game:GetService("ReplicatedStorage").Shared.EraData)
		local era = EraData.Eras["CassetteFuturism"]
		print(era.DisplayName, era.Color)
]]

local EraData = {}

-- Placeholder colors for greybox/visualization purposes only — not final art direction.
EraData.Eras = {
	CassetteFuturism = {
		DisplayName = "Cassette Futurism",
		Color = Color3.fromRGB(196, 172, 130), -- beige plastic / analog tape
	},
	LaserGrid = {
		DisplayName = "Laser Grid",
		Color = Color3.fromRGB(255, 45, 185), -- neon grid / chrome airbrush
	},
	EarlyCyber = {
		DisplayName = "Early Cyber",
		Color = Color3.fromRGB(60, 255, 130), -- phosphor-green terminal
	},
	FrutigerAero = {
		DisplayName = "Frutiger Aero",
		Color = Color3.fromRGB(110, 210, 255), -- glossy blue/green aqua
	},
}

-- Neutral is not an era players can build chains in — it's the Start tile /
-- unclaimed default, kept separate from Eras so era-only iteration works.
EraData.Neutral = {
	DisplayName = "Neutral",
	Color = Color3.fromRGB(230, 225, 210),
}

function EraData.GetEra(eraId)
	if eraId == nil then
		return EraData.Neutral
	end
	return EraData.Eras[eraId]
end

return EraData

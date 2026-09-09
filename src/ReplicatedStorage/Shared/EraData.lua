--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > EraData (ModuleScript)

	Purpose:
		Single source of truth for the classic four-element system — Fire,
		Air, Earth, and Water. This is the mechanical unit: board tiles,
		creature cards, and chain bonuses all key off these four element
		ids. Each element is skinned in one retrofuturism era for visual/
		creature flavor only (EraName/EraFlavor below) — the era is
		cosmetic, the element is the mechanic. Fixed at these 4 by design
		decision, not open-ended.

	Usage:
		local EraData = require(game:GetService("ReplicatedStorage").Shared.EraData)
		local element = EraData.Eras["Fire"]
		print(element.DisplayName, element.EraName, element.Color)
]]

local EraData = {}

-- Placeholder colors for greybox/visualization purposes only — not final art direction.
EraData.Eras = {
	Fire = {
		DisplayName = "Fire",
		EraName = "Laser Grid",
		EraFlavor = "1980s corporate future: neon grids, reflective glass, chrome airbrushing",
		Color = Color3.fromRGB(255, 45, 185), -- neon grid / chrome airbrush
	},
	Air = {
		DisplayName = "Air",
		EraName = "Early Cyber",
		EraFlavor = "Tron-grid, phosphor-green terminal, digital-frontier utopianism",
		Color = Color3.fromRGB(60, 255, 130), -- phosphor-green terminal
	},
	Earth = {
		DisplayName = "Earth",
		EraName = "Cassette Futurism",
		EraFlavor = "beige plastic, tape reels, analog-optimism (Nostromo-computer energy)",
		Color = Color3.fromRGB(196, 172, 130), -- beige plastic / analog tape
	},
	Water = {
		DisplayName = "Water",
		EraName = "Frutiger Aero",
		EraFlavor = "glossy blue/green, translucent plastic, dew-drop/nature-tech optimism",
		Color = Color3.fromRGB(110, 210, 255), -- glossy blue/green aqua
	},
}

-- Neutral is not an element players can build chains in — it's the Start tile /
-- unclaimed default, kept separate from Eras so element-only iteration works.
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

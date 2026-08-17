--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > EraData (ModuleScript)

	Purpose:
		Single source of truth for the "element/color" system — the classic
		four elements (Fire, Air, Earth, Water), which is what board tiles,
		creature cards, and chain bonuses actually key off. Each element is
		additionally skinned in one distinct retrofuturism "era" for visual/
		creature flavor only (DisplayName/Color below carry that flavor) —
		the era is a skin, the element key is the mechanic. Fixed at these 4
		by design decision; the roster used to be open-ended back when eras
		themselves were the element system (see CLAUDE.md), that's no longer
		the case now that eras are a flavor layer instead.

	Usage:
		local EraData = require(game:GetService("ReplicatedStorage").Shared.EraData)
		local era = EraData.Eras["Fire"]
		print(era.DisplayName, era.Color)
]]

local EraData = {}

-- Placeholder colors for greybox/visualization purposes only — not final art
-- direction. Each element keeps its retrofuturism-era skin's color identity:
-- Fire = Laser Grid, Air = Early Cyber, Earth = Cassette Futurism, Water = Frutiger Aero.
EraData.Eras = {
	Fire = {
		DisplayName = "Fire",
		Color = Color3.fromRGB(255, 45, 185), -- Laser Grid: neon grid / chrome airbrush
	},
	Air = {
		DisplayName = "Air",
		Color = Color3.fromRGB(60, 255, 130), -- Early Cyber: phosphor-green terminal
	},
	Earth = {
		DisplayName = "Earth",
		Color = Color3.fromRGB(196, 172, 130), -- Cassette Futurism: beige plastic / analog tape
	},
	Water = {
		DisplayName = "Water",
		Color = Color3.fromRGB(110, 210, 255), -- Frutiger Aero: glossy blue/green aqua
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

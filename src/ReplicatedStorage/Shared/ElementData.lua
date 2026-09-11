--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > ElementData (ModuleScript)

	Purpose:
		Single source of truth for the classic four-element system (renamed from
		EraData in Milestone 5 — an era is the flavour skin, the element is the
		mechanic, and the module holds elements) — Fire,
		Air, Earth, and Water. This is the mechanical unit: board tiles,
		creature cards, and chain bonuses all key off these four element
		ids. Each element is skinned in one retrofuturism era for visual/
		creature flavor only (EraName/EraFlavor below) — the era is
		cosmetic, the element is the mechanic. Fixed at these 4 by design
		decision, not open-ended.

	Usage:
		local ElementData = require(game:GetService("ReplicatedStorage").Shared.ElementData)
		local element = ElementData.Elements["Fire"]
		print(element.DisplayName, element.EraName, element.Color)
]]

local ElementData = {}

-- Placeholder colors for greybox/visualization purposes only — not final art direction.
ElementData.Elements = {
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
-- unclaimed default, kept separate from Elements so element-only iteration works.
ElementData.Neutral = {
	DisplayName = "Neutral",
	Color = Color3.fromRGB(230, 225, 210),
}

function ElementData.GetElement(elementId)
	if elementId == nil then
		return ElementData.Neutral
	end
	return ElementData.Elements[elementId]
end

return ElementData

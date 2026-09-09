--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > CardData (ModuleScript)

	Purpose:
		Static registry of Creature / Spell / Item cards. This is a small
		placeholder set (one creature per element, one generic spell, one
		generic item) to exercise CardService/BattleService end to end —
		NOT the real 60-80 card launch library, which is still open per
		the project brief. Card stats are a tunable starting point.
		Creature names pair the classic element with a nod to its
		traditional Paracelsian elemental archetype (gnome/salamander/
		sylph/undine) — flavor only, no mechanical effect.

		Spell/Item EffectValue magnitudes are consumed by CardEffectService
		(ServerScriptService.Systems), which resolves what casting/using each
		one actually does — see its header for Signal Boost/Ninth Signal
		Charm specifically.

	Card fields:
		Id                 number, unique
		Name               string
		CardType           "Creature" | "Spell" | "Item"
		Era                element id from EraData.Eras, or nil for colorless cards
		Cost               number, Magic cost to play (placeholder economy)
		ST                 number, attack power (Creature only)
		HP                 number, hit points (Creature only)
		EffectDescription  string, player-facing text describing the effect
		EffectValue        number, magnitude for Spell/Item effects (nil for Creature) — read by CardEffectService

	Usage:
		local CardData = require(game:GetService("ReplicatedStorage").Shared.CardData)
		for _, card in ipairs(CardData.Cards) do
			print(card.Id, card.Name, card.CardType)
		end
]]

local CardData = {}

-- Placeholder cards only — real card list/content is still undecided per brief.
CardData.Cards = {
	{
		Id = 1,
		Name = "Tape Gnome",
		CardType = "Creature",
		Era = "Earth",
		Cost = 30,
		ST = 40,
		HP = 60,
	},
	{
		Id = 2,
		Name = "Laser Salamander",
		CardType = "Creature",
		Era = "Fire",
		Cost = 40,
		ST = 60,
		HP = 50,
	},
	{
		Id = 3,
		Name = "Phosphor Sylph",
		CardType = "Creature",
		Era = "Air",
		Cost = 25,
		ST = 35,
		HP = 45,
	},
	{
		Id = 4,
		Name = "Dewdrop Undine",
		CardType = "Creature",
		Era = "Water",
		Cost = 20,
		ST = 30,
		HP = 55,
	},
	{
		Id = 5,
		Name = "Signal Boost",
		CardType = "Spell",
		Era = nil,
		Cost = 15,
		EffectValue = 20,
		EffectDescription = "Raises your ST by 20 for your next Challenge this match (one use).",
	},
	{
		Id = 6,
		Name = "Ninth Signal Charm",
		CardType = "Item",
		Era = nil,
		Cost = 10,
		EffectValue = 25,
		EffectDescription = "Permanently raises a defending creature's HP by 25 while it holds that tile.",
	},
}

return CardData

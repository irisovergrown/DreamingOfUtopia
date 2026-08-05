--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > CardData (ModuleScript)

	Purpose:
		Static registry of Creature / Spell / Item cards. This is a small
		placeholder set (one creature per confirmed era, one generic spell,
		one generic item) to exercise CardService/BattleService end to end
		— NOT the real 60-80 card launch library, which is still open per
		the project brief. Card stats are a tunable starting point.

	Card fields:
		Id                 number, unique
		Name               string
		CardType           "Creature" | "Spell" | "Item"
		Era                era id from EraData.Eras, or nil for colorless cards
		Cost               number, Magic cost to play (placeholder economy)
		ST                 number, attack power (Creature only)
		HP                 number, hit points (Creature only)
		EffectDescription  string, placeholder text — real Spell/Item effect
		                   hooks land with BattleService/EconomyService later

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
		Name = "Tape Drone",
		CardType = "Creature",
		Era = "CassetteFuturism",
		Cost = 30,
		ST = 40,
		HP = 60,
	},
	{
		Id = 2,
		Name = "Chrome Enforcer",
		CardType = "Creature",
		Era = "LaserGrid",
		Cost = 40,
		ST = 60,
		HP = 50,
	},
	{
		Id = 3,
		Name = "Grid Runner",
		CardType = "Creature",
		Era = "EarlyCyber",
		Cost = 25,
		ST = 35,
		HP = 45,
	},
	{
		Id = 4,
		Name = "Dewdrop Sprite",
		CardType = "Creature",
		Era = "FrutigerAero",
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
		EffectDescription = "Placeholder: raises target creature's ST for one battle.",
	},
	{
		Id = 6,
		Name = "Ninth Signal Charm",
		CardType = "Item",
		Era = nil,
		Cost = 10,
		EffectDescription = "Placeholder: equips a creature, raises HP while held.",
	},
}

return CardData

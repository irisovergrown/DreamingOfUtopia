--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > CardData (ModuleScript)

	Purpose:
		Static registry of Creature / Spell / Item cards.

		DISPOSABLE TEST CONTENT. This is not the 60-80 card launch library,
		and the numbers are not a balance proposal. It exists so the deck,
		hand and battle systems have enough distinct cards to be exercised
		honestly: a 50-card book at four copies each needs at least thirteen
		distinct cards, and the Milestone 4 battle tests need one card for
		each keyword they check. Names and flavour are original.

		Ids 1-6 are the original placeholder set and are deliberately
		unchanged — tests reference card 1 by its exact stats, and renumbering
		would silently rewrite what those tests assert.

	Keywords:
		Declared here now, consumed in Milestone 4. Writing them as data means
		the battle engine reads a list rather than growing a branch per card
		name, which is the difference between adding a card and editing a
		service. Until then they are inert and no code reads them.

			First / Last     attack-order class; absent means Normal
			Critical         qualifying damage multiplied (RulesConfig)
			Penetration      ignores the defender's land bonus
			Neutralize       reduces qualifying damage to zero
			Reflect          returns defined damage instead of taking it
			Regenerate       restores HP at battle end
			Support          may use a creature card as its battle item

	Card fields:
		Id                 number, unique and stable
		Name               string
		CardType           "Creature" | "Spell" | "Item"
		Element            element id from Enums.Element, or nil for neutral
		Cost               number, Magic cost to play
		ST, HP             Creature only
		ItemCategory       Item only: Weapon | Armor | Tool | Scroll
		Keywords           array of the strings above, or nil
		EffectValue        magnitude for Spell/Item effects, read by CardEffectService
		EffectDescription  player-facing text
		RulesText          short line shown on the card face

	Note on `Era`:
		Still named Era rather than Element while BoardService's tile state
		uses that key. Both are renamed together when territory state moves in
		Milestone 5; splitting the rename would leave two names live at once,
		which is worse than one wrong one.
]]

local CardData = {}

CardData.Cards = {
	-- === The original six. Ids and stats are load-bearing for tests. =====

	{
		Id = 1,
		Name = "Tape Gnome",
		CardType = "Creature",
		Element = "Earth",
		Cost = 30,
		ST = 40,
		HP = 60,
		RulesText = "Patient. Reels on.",
	},
	{
		Id = 2,
		Name = "Laser Salamander",
		CardType = "Creature",
		Element = "Fire",
		Cost = 40,
		ST = 60,
		HP = 50,
		RulesText = "Burns bright on the grid.",
	},
	{
		Id = 3,
		Name = "Phosphor Sylph",
		CardType = "Creature",
		Element = "Air",
		Cost = 25,
		ST = 35,
		HP = 45,
		RulesText = "Flickers between frames.",
	},
	{
		Id = 4,
		Name = "Dewdrop Undine",
		CardType = "Creature",
		Element = "Water",
		Cost = 20,
		ST = 30,
		HP = 55,
		RulesText = "Condenses where it is needed.",
	},
	{
		Id = 5,
		Name = "Signal Boost",
		CardType = "Spell",
		Element = nil,
		Cost = 15,
		EffectValue = 20,
		EffectDescription = "Raises your ST by 20 for your next Challenge this match (one use).",
		RulesText = "+20 ST, next challenge.",
	},
	{
		Id = 6,
		Name = "Ninth Signal Charm",
		CardType = "Item",
		ItemCategory = "Tool",
		Element = nil,
		Cost = 10,
		EffectValue = 25,
		EffectDescription = "Permanently raises a defending creature's HP by 25 while it holds that tile.",
		RulesText = "+25 HP while it holds.",
	},

	-- === Fire — Laser Grid ===============================================

	{
		Id = 7,
		Name = "Chrome Vulcan",
		CardType = "Creature",
		Element = "Fire",
		Cost = 30,
		ST = 50,
		HP = 40,
		Keywords = { "First" },
		RulesText = "First. Strikes before the glare fades.",
	},
	{
		Id = 8,
		Name = "Grid Phoenix",
		CardType = "Creature",
		Element = "Fire",
		Cost = 45,
		ST = 40,
		HP = 60,
		Keywords = { "Regenerate" },
		RulesText = "Regenerate. Redraws itself each cycle.",
	},

	-- === Air — Early Cyber ===============================================

	{
		Id = 9,
		Name = "Packet Wraith",
		CardType = "Creature",
		Element = "Air",
		Cost = 25,
		ST = 45,
		HP = 30,
		Keywords = { "Penetration" },
		RulesText = "Penetration. Routes around the ground.",
	},
	{
		Id = 10,
		Name = "Daemon Courier",
		CardType = "Creature",
		Element = "Air",
		Cost = 30,
		ST = 30,
		HP = 50,
		Keywords = { "Support" },
		RulesText = "Support. Carries what it is given.",
	},

	-- === Earth — Cassette Futurism =======================================

	{
		Id = 11,
		Name = "Ferrite Golem",
		CardType = "Creature",
		Element = "Earth",
		Cost = 45,
		ST = 30,
		HP = 80,
		Keywords = { "Last" },
		RulesText = "Last. Slow, and still standing.",
	},
	{
		Id = 12,
		Name = "Spool Warden",
		CardType = "Creature",
		Element = "Earth",
		Cost = 35,
		ST = 35,
		HP = 55,
		Keywords = { "Neutralize" },
		RulesText = "Neutralize. Absorbs the first blow.",
	},

	-- === Water — Frutiger Aero ===========================================

	{
		Id = 13,
		Name = "Aero Nereid",
		CardType = "Creature",
		Element = "Water",
		Cost = 35,
		ST = 45,
		HP = 45,
		Keywords = { "Reflect" },
		RulesText = "Reflect. Returns what it receives.",
	},
	{
		Id = 14,
		Name = "Bloom Leviathan",
		CardType = "Creature",
		Element = "Water",
		Cost = 60,
		ST = 70,
		HP = 70,
		RulesText = "Expensive, and worth it.",
	},

	-- === Neutral creatures ===============================================
	-- No element, so they never receive a land bonus. Cheap and flexible.

	{
		Id = 15,
		Name = "Signal Drone",
		CardType = "Creature",
		Element = nil,
		Cost = 10,
		ST = 25,
		HP = 25,
		RulesText = "Cheap. Expendable. Everywhere.",
	},
	{
		Id = 16,
		Name = "Null Sentinel",
		CardType = "Creature",
		Element = nil,
		Cost = 40,
		ST = 20,
		HP = 70,
		Keywords = { "Neutralize" },
		RulesText = "Neutralize. Holds ground it does not own.",
	},

	-- === Items ===========================================================

	{
		Id = 17,
		Name = "Cathode Lance",
		CardType = "Item",
		ItemCategory = "Weapon",
		Element = nil,
		Cost = 20,
		EffectValue = 30,
		EffectDescription = "+30 ST to the creature using it in this battle.",
		RulesText = "Weapon. +30 ST.",
	},
	{
		Id = 18,
		Name = "Mylar Plating",
		CardType = "Item",
		ItemCategory = "Armor",
		Element = nil,
		Cost = 20,
		EffectValue = 30,
		EffectDescription = "+30 HP to the creature using it in this battle.",
		RulesText = "Armor. +30 HP.",
	},
	{
		Id = 19,
		Name = "Static Scroll",
		CardType = "Item",
		ItemCategory = "Scroll",
		Element = nil,
		Cost = 25,
		EffectValue = 40,
		EffectDescription = "Deals 40 scroll damage, bypassing the land bonus.",
		RulesText = "Scroll. 40 damage, ignores land.",
	},
	{
		Id = 20,
		Name = "Ribbon Cutter",
		CardType = "Item",
		ItemCategory = "Weapon",
		Element = nil,
		Cost = 25,
		EffectValue = 20,
		Keywords = { "Critical" },
		EffectDescription = "+20 ST, and its damage counts as critical.",
		RulesText = "Weapon. +20 ST, Critical.",
	},

	-- === Spells ==========================================================

	{
		Id = 21,
		Name = "Call Sign One",
		CardType = "Spell",
		Element = nil,
		Cost = 20,
		EffectValue = 1,
		EffectDescription = "Sets the target player's next roll to exactly 1.",
		RulesText = "Next roll becomes 1.",
	},
	{
		Id = 22,
		Name = "Call Sign Six",
		CardType = "Spell",
		Element = nil,
		Cost = 20,
		EffectValue = 6,
		EffectDescription = "Sets the target player's next roll to exactly 6.",
		RulesText = "Next roll becomes 6.",
	},
	{
		Id = 23,
		Name = "Rewind Tape",
		CardType = "Spell",
		Element = nil,
		Cost = 15,
		EffectValue = 2,
		EffectDescription = "Draw two cards.",
		RulesText = "Draw 2.",
	},
}

return CardData

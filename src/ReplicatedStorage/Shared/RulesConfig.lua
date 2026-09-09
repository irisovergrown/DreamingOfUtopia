--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > RulesConfig (ModuleScript)

	Purpose:
		Every tunable rule constant and every rule formula, in one file.
		Nothing anywhere else in the project may inline a chain multiplier,
		a toll rate, a hand size or a development cost — if a number governs
		play, it lives here and is reachable by tests.

		This exists because rule values are the part of the project most
		likely to be wrong. Some are reconstructed from community formula
		sheets for a console game rather than measured from it, so the ones
		that are genuinely unverified are marked UNVERIFIED below with what
		would settle them. An unverified value isolated here is a question
		we can answer later; the same value inlined across six services is a
		bug we will never find.

		Pure Lua on purpose — no Roblox API is touched at any point in this
		module, so the whole rule core stays runnable outside Studio if a CI
		harness is added later.

	Rounding:
		Land value and toll are rounded on output (default: floor). Most
		base/level/chain combinations land on integers anyway, but a 1.8x
		chain on a base-80 or base-120 territory does not, so the mode has
		to be explicit rather than incidental. Development and terrain-change
		costs are exact integers by construction and are never rounded.

	Public API:
		RulesConfig.Land / Book / Hand / Battle / Lap / LapBonus / Roll /
			TerrainChange / Match / Rounding   -- constant tables
		RulesConfig.round(n) -> integer
		RulesConfig.getChainMultiplier(chainSize) -> number
		RulesConfig.getTollMultiplier(level) -> number
		RulesConfig.getLandValue(baseValue, level, chainSize) -> integer
		RulesConfig.getToll(baseValue, level, chainSize) -> integer
		RulesConfig.getDevelopmentCost(baseValue, fromLevel, toLevel) -> integer
		RulesConfig.getTerrainChangeCost(level, isCurrentlyElemental) -> integer
		RulesConfig.getLandBonusHP(level) -> integer
		RulesConfig.getLapBonus(defaultMagic, lapNumber, ownedCount, symbolValue) -> integer
]]

local RulesConfig = {}

RulesConfig.Rounding = {
	-- "floor" | "round" | "none". UNVERIFIED: which way the source game
	-- breaks a fractional toll. Only affects 1.8x chains on base-80/120
	-- territories and similar; settle with an in-game toll reading before
	-- content lock.
	Mode = "floor",
}

RulesConfig.Land = {
	MaxLevel = 5,

	-- Indexed by chain size. Ownership may exceed five territories, but the
	-- multiplier stops climbing at five.
	ChainMultipliers = { 1.0, 1.5, 1.8, 2.0, 2.2 },
	MaxChainSize = 5,

	-- Indexed by land level.
	TollMultipliers = { 0.2, 0.3, 0.4, 0.6, 0.8 },

	-- The same two tables as exact integer rationals over MultiplierDenominator.
	-- Land value and toll are computed from THESE, never from the decimals
	-- above, because 0.2/0.3/1.8/2.2 are not representable in binary floating
	-- point. Multiplying by them lands on the right integer only by rounding
	-- luck: 200 * 0.3 happens to round to exactly 60.0, but the exact product
	-- is 59.99999999999999778, and a floor() over that arithmetic is one
	-- unlucky constant away from charging a player 59 instead of 60. Integer
	-- numerators make every value in the toll chart exact by construction.
	ChainMultiplierNumerators = { 10, 15, 18, 20, 22 },
	TollMultiplierNumerators = { 2, 3, 4, 6, 8 },
	MultiplierDenominator = 10,

	-- Temporary battle HP for a defender whose element matches its
	-- territory: 10 x land level. Neutral creatures never receive it, and it
	-- must never raise permanent MHP.
	LandBonusHPPerLevel = 10,

	-- +10 ST per board-graph-adjacent territory owned by the creature's
	-- owner, where the board enables classic adjacent-land support.
	SupportSTPerAdjacent = 10,

	DefaultBaseValue = 100,
}

RulesConfig.TerrainChange = {
	CostPerLevel = 100,
	-- Surcharge for converting land that already has an element, as opposed
	-- to neutral or multi-element land.
	ElementalSurcharge = 200,
}

RulesConfig.Book = {
	Size = 50,
	MinSize = 30,
	MaxSize = 60,
	MaxCopiesPerCard = 4,
}

RulesConfig.Hand = {
	MaxSize = 6,
}

RulesConfig.Battle = {
	CriticalMultiplier = 1.5,
}

RulesConfig.Lap = {
	-- UNVERIFIED: fraction of MHP restored to a player's creatures on lap
	-- completion. Flagged in the source research as version-sensitive.
	-- Confirm against a real lap before content lock.
	HealPercentOfMHP = 0.5,
}

RulesConfig.LapBonus = {
	-- BaseLapBonus = DefaultMagic + (DefaultMagic / BaseGrowthDivisor * (lap - 1))
	BaseGrowthDivisor = 10,
	LandBonusPerTerritory = 20,
	-- Awarded per element/area only to a strict symbol-count leader; ties
	-- award nothing for that symbol class. Expressed as an integer percent
	-- so the bonus is computed exactly (see getLapBonus).
	SymbolBonusPercent = 10,
}

RulesConfig.Roll = {
	-- Board definitions override these. Deliberately not a d6 constant: some
	-- maps present a range up to ten.
	DefaultMin = 1,
	DefaultMax = 6,
}

RulesConfig.Match = {
	DefaultStartingMagic = 500,
	DefaultTMGoal = 3000,
	MinPlayers = 2,
	MaxPlayers = 4,
}

function RulesConfig.round(n)
	local mode = RulesConfig.Rounding.Mode
	if mode == "none" then
		return n
	elseif mode == "round" then
		return math.floor(n + 0.5)
	end
	return math.floor(n)
end

-- Chain sizes below 1 are treated as 1 (an unowned or single territory has
-- no chain bonus); sizes above the cap clamp to the cap.
function RulesConfig.getChainMultiplier(chainSize)
	local size = math.clamp(math.floor(chainSize or 1), 1, RulesConfig.Land.MaxChainSize)
	return RulesConfig.Land.ChainMultipliers[size]
end

function RulesConfig.getTollMultiplier(level)
	local clamped = math.clamp(math.floor(level or 1), 1, RulesConfig.Land.MaxLevel)
	return RulesConfig.Land.TollMultipliers[clamped]
end

local function chainNumerator(chainSize)
	local size = math.clamp(math.floor(chainSize or 1), 1, RulesConfig.Land.MaxChainSize)
	return RulesConfig.Land.ChainMultiplierNumerators[size]
end

local function tollNumerator(level)
	local clamped = math.clamp(math.floor(level or 1), 1, RulesConfig.Land.MaxLevel)
	return RulesConfig.Land.TollMultiplierNumerators[clamped]
end

-- LandValue = BaseValue x 2^(Level-1) x ChainMultiplier
--
-- Every factor in the numerator is an integer, so the product is exact; only
-- the single division by 10 can be fractional, and rounding it once is the
-- only place precision is decided.
function RulesConfig.getLandValue(baseValue, level, chainSize)
	local clampedLevel = math.clamp(math.floor(level or 1), 1, RulesConfig.Land.MaxLevel)
	local numerator = (baseValue or 0) * (2 ^ (clampedLevel - 1)) * chainNumerator(chainSize)
	return RulesConfig.round(numerator / RulesConfig.Land.MultiplierDenominator)
end

-- Toll = LandValue x TollMultiplier, computed from the ROUNDED land value so
-- the toll always agrees with the land value shown to players rather than
-- with an invisible higher-precision one.
function RulesConfig.getToll(baseValue, level, chainSize)
	local landValue = RulesConfig.getLandValue(baseValue, level, chainSize)
	local numerator = landValue * tollNumerator(level)
	return RulesConfig.round(numerator / RulesConfig.Land.MultiplierDenominator)
end

-- Cost to develop from one level to a higher one, as the cumulative
-- UNCHAINED land-value increase. Chains multiply what the investment is
-- worth, but never what it costs. Base 100: 1->2 = 100, 2->3 = 200,
-- 3->4 = 400, 4->5 = 800, and 1->5 in a single command = 1500.
function RulesConfig.getDevelopmentCost(baseValue, fromLevel, toLevel)
	local from = math.clamp(math.floor(fromLevel or 1), 1, RulesConfig.Land.MaxLevel)
	local to = math.clamp(math.floor(toLevel or 1), 1, RulesConfig.Land.MaxLevel)
	if to <= from then
		return 0
	end
	return (baseValue or 0) * (2 ^ (to - 1) - 2 ^ (from - 1))
end

-- level x 100, plus a surcharge when the land already has an element.
function RulesConfig.getTerrainChangeCost(level, isCurrentlyElemental)
	local clamped = math.clamp(math.floor(level or 1), 1, RulesConfig.Land.MaxLevel)
	local cost = clamped * RulesConfig.TerrainChange.CostPerLevel
	if isCurrentlyElemental then
		cost += RulesConfig.TerrainChange.ElementalSurcharge
	end
	return cost
end

-- Temporary battle HP only. Callers must not fold this into MHP.
function RulesConfig.getLandBonusHP(level)
	local clamped = math.clamp(math.floor(level or 1), 1, RulesConfig.Land.MaxLevel)
	return RulesConfig.Land.LandBonusHPPerLevel * clamped
end

-- symbolValue is the player's eligible owned symbol value for classes they
-- strictly lead; the caller decides eligibility, this only prices it.
--
-- Both fractional terms are floored through integer division for the same
-- reason as the toll formula: SymbolBonusRate as 0.10 is not exact, and
-- floor(x * 0.10) can disagree with floor(x / 10) on values that matter.
function RulesConfig.getLapBonus(defaultMagic, lapNumber, ownedCount, symbolValue)
	local magic = defaultMagic or RulesConfig.Match.DefaultStartingMagic
	local lap = math.max(math.floor(lapNumber or 1), 1)

	local growth = math.floor(magic * (lap - 1) / RulesConfig.LapBonus.BaseGrowthDivisor)
	local land = (ownedCount or 0) * RulesConfig.LapBonus.LandBonusPerTerritory
	local symbol = math.floor((symbolValue or 0) * RulesConfig.LapBonus.SymbolBonusPercent / 100)

	return magic + growth + land + symbol
end

return RulesConfig

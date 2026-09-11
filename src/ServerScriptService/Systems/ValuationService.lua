--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > ValuationService (ModuleScript)

	Purpose:
		Total Magic, and the standings derived from it.

		The project has had one number called "Magic" and used it for both
		spending and winning. Those are different quantities and conflating
		them makes the game's central decision meaningless: developing land
		SHOULD lower what you can spend while raising what you are worth, and
		with a single balance it just looks like losing.

			Current Magic (CM)   spendable cash. EconomyService owns it.
			Total Magic (TM)     CM + owned land value + owned symbol value.
			                     What standings and victory read.

		So spending 400 to raise a territory two levels drops CM by 400 and
		raises that land's value by more than 400 once a chain multiplies it.
		TM goes UP. That is the whole strategic loop, and it cannot exist
		until the two numbers are separate.

	Recomputed, never cached:
		TM changes without anyone spending anything — a rival capturing one of
		your territories shrinks a chain and devalues every other territory in
		it. A cached total would be wrong from the moment someone else moved,
		and the invalidation rules would have to know about ownership, levels,
		elements, chains and areas. Summing on read is cheap at board scale and
		cannot go stale.

	Symbols:
		Board-optional and unimplemented (Milestone 6). GetSymbolValue returns
		zero and is summed anyway, so the formula is already complete and the
		milestone adds a source rather than a term.

	Public API:
		ValuationService.Init(deps)              -- deps.Territory, deps.Economy
		ValuationService.GetLandValue(userId) -> integer
		ValuationService.GetSymbolValue(userId) -> integer
		ValuationService.GetTotalMagic(userId) -> integer
		ValuationService.GetStandings(userIds) -> array, richest first
		ValuationService.GetRank(userIds, userId) -> 1-based position
]]

local ValuationService = {}

local _territory, _economy

function ValuationService.Init(deps)
	deps = deps or {}
	_territory = deps.Territory
	_economy = deps.Economy
end

-- Chain multipliers are already inside each territory's value, so a player
-- holding four Fire territories in one area is worth more than four times a
-- single one. That compounding is the point.
function ValuationService.GetLandValue(userId)
	if _territory == nil then
		return 0
	end

	local total = 0
	for _, nodeId in ipairs(_territory.GetOwnedBy(userId)) do
		total += _territory.GetLandValue(nodeId)
	end
	return total
end

function ValuationService.GetSymbolValue(_userId)
	return 0 -- Milestone 6
end

function ValuationService.GetTotalMagic(userId)
	local currentMagic = _economy and _economy.GetBalance(userId) or 0
	return currentMagic
		+ ValuationService.GetLandValue(userId)
		+ ValuationService.GetSymbolValue(userId)
end

-- Sorted by TM descending, with userId as a tiebreak so the order is stable
-- between calls — standings that reshuffle on every push are unreadable.
function ValuationService.GetStandings(userIds)
	local standings = {}
	for _, userId in ipairs(userIds or {}) do
		table.insert(standings, {
			UserId = userId,
			CurrentMagic = _economy and _economy.GetBalance(userId) or 0,
			LandValue = ValuationService.GetLandValue(userId),
			SymbolValue = ValuationService.GetSymbolValue(userId),
			TotalMagic = ValuationService.GetTotalMagic(userId),
			TerritoriesOwned = _territory and #_territory.GetOwnedBy(userId) or 0,
		})
	end

	table.sort(standings, function(a, b)
		if a.TotalMagic ~= b.TotalMagic then
			return a.TotalMagic > b.TotalMagic
		end
		return a.UserId < b.UserId
	end)
	return standings
end

function ValuationService.GetRank(userIds, userId)
	for position, standing in ipairs(ValuationService.GetStandings(userIds)) do
		if standing.UserId == userId then
			return position
		end
	end
	return nil
end

return ValuationService

--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > MatchLogService (ModuleScript)

	Purpose:
		The ordered event record for a match. Every phase transition, every
		rejected intent, and every resolution worth reconstructing goes here
		with a monotonic index.

		This exists because the brief requires transitions to be "legal,
		deterministic, and logged", and because effect ordering has to be
		auditable: when four modifiers touch one roll, the answer to "why was
		it 7" must be readable after the fact rather than reproduced by
		guesswork. It is also the seam a replay viewer and an AI action
		provider will both read from later.

		Entries are append-only and frozen. A log a service can retroactively
		edit is not evidence of anything.

		The log is capped (see MaxEntries) and drops oldest-first, because a
		long match must not grow memory without bound. Dropping is counted
		and reported by GetStats, so a caller can tell "nothing happened
		before index 400" apart from "the first 400 entries were discarded" —
		silently losing history would make the log actively misleading.

	Entry shape:
		Index       monotonic, starts at 1, never reused
		Type        a short machine-readable string (e.g. "PhaseChanged")
		Phase       the phase current when the entry was appended, if any
		Turn        the turn number current when appended, if any
		Payload     arbitrary table of detail, frozen shallowly
		Clock       os.clock() at append, for relative timing only

	Public API:
		MatchLogService.Init()
		MatchLogService.Append(entryType, payload, context) -> entry
		MatchLogService.GetEntries(fromIndex?) -> array of entries
		MatchLogService.GetLast(count?) -> array of entries
		MatchLogService.GetStats() -> { Count, NextIndex, Dropped }
		MatchLogService.Format(count?) -> string, for console inspection
		MatchLogService.MaxEntries -> number (tunable)

	Signals:
		MatchLogService.EntryAppended:Connect(function(entry) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

local MatchLogService = {}

MatchLogService.EntryAppended = Signal.new("MatchLog.EntryAppended")

-- Generous enough that a full match is retained, bounded enough that a
-- pathological loop cannot exhaust memory.
MatchLogService.MaxEntries = 2000

local _entries = {}
local _nextIndex = 1
local _dropped = 0

function MatchLogService.Init()
	_entries = {}
	_nextIndex = 1
	_dropped = 0
end

-- `context` carries the ambient facts worth stamping on the entry (current
-- phase, turn number). The orchestrator supplies it; callers that have no
-- such context may omit it.
function MatchLogService.Append(entryType, payload, context)
	if type(entryType) ~= "string" or entryType == "" then
		error("MatchLogService.Append needs a non-empty entry type", 2)
	end

	context = context or {}

	local entry = table.freeze({
		Index = _nextIndex,
		Type = entryType,
		Phase = context.Phase,
		Turn = context.Turn,
		Payload = payload,
		Clock = os.clock(),
	})

	_entries[#_entries + 1] = entry
	_nextIndex += 1

	-- Oldest-first drop. table.remove on index 1 is O(n), but n is bounded by
	-- MaxEntries and this only runs once the cap is reached, so the cost is
	-- flat rather than growing.
	while #_entries > MatchLogService.MaxEntries do
		table.remove(_entries, 1)
		_dropped += 1
	end

	MatchLogService.EntryAppended:Fire(entry)
	return entry
end

-- fromIndex is an absolute entry index, not an array position, so a caller
-- polling for "everything since I last looked" stays correct across drops.
function MatchLogService.GetEntries(fromIndex)
	local result = {}
	for _, entry in ipairs(_entries) do
		if fromIndex == nil or entry.Index >= fromIndex then
			table.insert(result, entry)
		end
	end
	return result
end

function MatchLogService.GetLast(count)
	count = count or 20
	local result = {}
	local startAt = math.max(#_entries - count + 1, 1)
	for position = startAt, #_entries do
		table.insert(result, _entries[position])
	end
	return result
end

function MatchLogService.GetStats()
	return {
		Count = #_entries,
		NextIndex = _nextIndex,
		Dropped = _dropped,
	}
end

local function describePayload(payload)
	if type(payload) ~= "table" then
		return payload ~= nil and tostring(payload) or ""
	end
	local parts = {}
	for key, value in pairs(payload) do
		table.insert(parts, string.format("%s=%s", tostring(key), tostring(value)))
	end
	table.sort(parts)
	return table.concat(parts, " ")
end

function MatchLogService.Format(count)
	local lines = {}
	for _, entry in ipairs(MatchLogService.GetLast(count)) do
		table.insert(lines, string.format(
			"%4d [%s%s] %-22s %s",
			entry.Index,
			entry.Phase and tostring(entry.Phase) or "-",
			entry.Turn and (" t" .. tostring(entry.Turn)) or "",
			entry.Type,
			describePayload(entry.Payload)
		))
	end
	if _dropped > 0 then
		table.insert(lines, 1, string.format("(%d earlier entries dropped)", _dropped))
	end
	return table.concat(lines, "\n")
end

return MatchLogService

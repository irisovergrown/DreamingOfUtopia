--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > Signal (ModuleScript)

	Purpose:
		Ordered, deterministic pub/sub. Still the cross-system communication
		layer — systems fire and listen here instead of calling into each
		other — but with the two properties the rules engine actually needs.

		1. ORDER. Handlers run in explicit priority order (lower first), ties
		   broken by connection order. The previous implementation dispatched
		   with task.spawn over a pairs() loop, so handlers ran on separate
		   threads in hash order. That is fine for "repaint a label" and
		   unusable for "these four effects modify a roll, in this sequence."
		   Fire is now synchronous: when it returns, every handler has run.

		2. TRANSFORMATION. Fold threads a value through the handlers, each
		   receiving the running value and returning the next one. This is
		   the primitive behind every ordered modifier pipeline — ModifyRoll,
		   BeforeBattleStats, toll modifiers. A signal that can only announce
		   cannot express "then halve it."

		Handler errors are isolated: a throwing handler is caught, reported,
		and the remaining handlers still run. One broken listener must not
		strand a turn mid-phase.

		FireAsync keeps the old fire-and-forget behavior for presentation
		work that may yield. Rules code should never use it — if ordering
		does not matter, that is worth being explicit about.

	Determinism note:
		Because Fire is synchronous, a handler that yields (task.wait, a
		remote round-trip) now blocks the firing thread and delays later
		handlers. That is intentional — it makes accidental ordering
		dependencies visible instead of silently racing. Yield in FireAsync
		or spawn your own thread.

	Usage:
		local moved = Signal.new("CepterMoved")
		moved:Connect(function(player, from, to) end)                 -- priority 0
		moved:Connect(logIt, -100, "MatchLog")                        -- runs first
		moved:Fire(player, 3, 4)

		local modifyRoll = Signal.new("ModifyRoll")
		modifyRoll:Connect(function(value) return value + 1 end, 10, "Haste")
		local finalRoll = modifyRoll:Fold(3)                          -- 4

	Public API:
		Signal.new(name?) -> signal
		signal:Connect(fn, priority?, label?) -> connection
		signal:Once(fn, priority?, label?) -> connection
		signal:Fire(...)                  -- ordered, synchronous
		signal:Fold(value, ...) -> value  -- ordered transformation pipeline
		signal:FireAsync(...)             -- unordered, non-blocking
		signal:DisconnectAll()
		signal:GetHandlerCount() -> number
		signal:GetDispatchOrder() -> array of labels, in run order
		connection:Disconnect()
		connection.Connected -> boolean
]]

local Signal = {}
Signal.__index = Signal

-- Roblox provides these globally; the fallbacks keep this module runnable
-- under a plain Lua interpreter so the rule core stays CI-testable.
local reportError = warn or print
local spawnThread = task and task.spawn or function(fn, ...)
	coroutine.wrap(fn)(...)
end

function Signal.new(name)
	return setmetatable({
		_name = name or "Signal",
		_handlers = {},
		_nextId = 1,
		_nextOrder = 1,
	}, Signal)
end

-- Sorted on insert rather than on dispatch: connections are rare, fires are
-- hot, and a stable sorted array makes dispatch order inspectable at any time
-- (see GetDispatchOrder) rather than only observable by firing.
local function sortHandlers(self)
	table.sort(self._handlers, function(a, b)
		if a.Priority ~= b.Priority then
			return a.Priority < b.Priority
		end
		return a.Order < b.Order
	end)
end

local function connect(self, fn, priority, label, once)
	if type(fn) ~= "function" then
		error(string.format("%s:Connect expects a function, got %s", self._name, typeof and typeof(fn) or type(fn)), 3)
	end

	local record = {
		Id = self._nextId,
		Fn = fn,
		Priority = priority or 0,
		Order = self._nextOrder,
		Label = label or string.format("handler#%d", self._nextId),
		Once = once or false,
		Connected = true,
	}

	self._nextId += 1
	self._nextOrder += 1
	table.insert(self._handlers, record)
	sortHandlers(self)

	local connection = {
		Connected = true,
	}

	function connection.Disconnect()
		if not record.Connected then
			return
		end
		record.Connected = false
		connection.Connected = false
		for i, candidate in ipairs(self._handlers) do
			if candidate == record then
				table.remove(self._handlers, i)
				break
			end
		end
	end

	return connection
end

function Signal:Connect(fn, priority, label)
	return connect(self, fn, priority, label, false)
end

function Signal:Once(fn, priority, label)
	return connect(self, fn, priority, label, true)
end

-- Dispatch iterates a snapshot so a handler may safely connect or disconnect
-- anything (including itself) mid-fire without skipping or repeating others.
-- Records disconnected during this same dispatch are still skipped.
local function snapshot(self)
	local copy = table.create and table.create(#self._handlers) or {}
	for i, record in ipairs(self._handlers) do
		copy[i] = record
	end
	return copy
end

local function consumeOnce(self, record)
	record.Connected = false
	for i, candidate in ipairs(self._handlers) do
		if candidate == record then
			table.remove(self._handlers, i)
			break
		end
	end
end

function Signal:Fire(...)
	for _, record in ipairs(snapshot(self)) do
		if record.Connected then
			if record.Once then
				consumeOnce(self, record)
			end

			local ok, err = pcall(record.Fn, ...)
			if not ok then
				reportError(string.format("[Signal:%s] handler '%s' errored: %s", self._name, record.Label, tostring(err)))
			end
		end
	end
end

-- Threads `value` through every handler in dispatch order. A handler returns
-- the new value; returning nil leaves the value unchanged, so a handler that
-- only wants to observe the pipeline cannot accidentally erase it. A handler
-- that throws is skipped and the running value survives intact.
function Signal:Fold(value, ...)
	for _, record in ipairs(snapshot(self)) do
		if record.Connected then
			if record.Once then
				consumeOnce(self, record)
			end

			local ok, result = pcall(record.Fn, value, ...)
			if not ok then
				reportError(string.format("[Signal:%s] fold handler '%s' errored: %s", self._name, record.Label, tostring(result)))
			elseif result ~= nil then
				value = result
			end
		end
	end
	return value
end

-- Fire-and-forget, for presentation handlers that may yield. Ordering is not
-- guaranteed; do not use for rules.
function Signal:FireAsync(...)
	for _, record in ipairs(snapshot(self)) do
		if record.Connected then
			spawnThread(record.Fn, ...)
		end
	end
end

function Signal:DisconnectAll()
	for _, record in ipairs(self._handlers) do
		record.Connected = false
	end
	self._handlers = {}
end

function Signal:GetHandlerCount()
	return #self._handlers
end

-- The resolved order, for the match log and for asserting on ordering in
-- tests without having to fire and observe side effects.
function Signal:GetDispatchOrder()
	local labels = {}
	for _, record in ipairs(self._handlers) do
		table.insert(labels, record.Label)
	end
	return labels
end

function Signal:GetName()
	return self._name
end

return Signal

--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > SignalSpec (ModuleScript)

	Signal is the foundation the whole effect/timing framework sits on, so
	these tests pin the three properties the rules engine depends on and that
	the previous task.spawn implementation could not provide: strict ordering,
	synchronous completion, and value transformation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

return {
	Name = "Signal",
	Tests = {
		{ "fires handlers in ascending priority order", function(t)
			local signal = Signal.new("test")
			local order = {}

			signal:Connect(function() table.insert(order, "third") end, 10)
			signal:Connect(function() table.insert(order, "first") end, -10)
			signal:Connect(function() table.insert(order, "second") end, 0)

			signal:Fire()
			t:DeepEqual(order, { "first", "second", "third" })
		end },

		{ "breaks priority ties by connection order", function(t)
			local signal = Signal.new("test")
			local order = {}

			for index = 1, 5 do
				signal:Connect(function() table.insert(order, index) end, 0)
			end

			signal:Fire()
			t:DeepEqual(order, { 1, 2, 3, 4, 5 })
		end },

		{ "is synchronous: every handler has run when Fire returns", function(t)
			-- The property the old task.spawn implementation lacked. Without
			-- it, a service cannot rely on a signal's effects having landed.
			local signal = Signal.new("test")
			local ran = false

			signal:Connect(function() ran = true end)
			signal:Fire()

			t:True(ran, "handler ran before Fire returned")
		end },

		{ "passes all arguments through to handlers", function(t)
			local signal = Signal.new("test")
			local received

			signal:Connect(function(...) received = { ... } end)
			signal:Fire("a", 2, true)

			t:DeepEqual(received, { "a", 2, true })
		end },

		{ "a throwing handler does not prevent later handlers", function(t)
			-- A broken listener must never strand a turn mid-phase.
			local signal = Signal.new("test")
			local reached = false

			signal:Connect(function() error("deliberate failure") end, 0)
			signal:Connect(function() reached = true end, 1)

			signal:Fire()
			t:True(reached, "handler after the throwing one still ran")
		end },

		{ "Fold threads a value through handlers in order", function(t)
			local signal = Signal.new("ModifyRoll")

			signal:Connect(function(value) return value + 1 end, 0, "add")
			signal:Connect(function(value) return value * 2 end, 1, "double")

			-- (3 + 1) * 2, not 3 + (1 * 2): order is the whole point
			t:Equal(signal:Fold(3), 8)
		end },

		{ "Fold order follows priority, not connection order", function(t)
			local signal = Signal.new("ModifyRoll")

			signal:Connect(function(value) return value * 2 end, 20, "double")
			signal:Connect(function(value) return value + 1 end, 10, "add")

			t:Equal(signal:Fold(3), 8, "add runs first despite connecting second")
		end },

		{ "a Fold handler returning nil leaves the value untouched", function(t)
			-- So a handler that only observes the pipeline cannot erase it.
			local signal = Signal.new("ModifyRoll")
			local observed

			signal:Connect(function(value) observed = value end, 0, "observer")
			signal:Connect(function(value) return value + 5 end, 1, "modifier")

			t:Equal(signal:Fold(10), 15)
			t:Equal(observed, 10, "observer saw the value")
		end },

		{ "a throwing Fold handler leaves the running value intact", function(t)
			local signal = Signal.new("ModifyRoll")

			signal:Connect(function(value) return value + 1 end, 0)
			signal:Connect(function() error("deliberate failure") end, 1)
			signal:Connect(function(value) return value + 1 end, 2)

			t:Equal(signal:Fold(0), 2, "both working handlers applied")
		end },

		{ "Fold passes extra arguments alongside the folded value", function(t)
			local signal = Signal.new("ModifyRoll")
			signal:Connect(function(value, bonus) return value + bonus end)
			t:Equal(signal:Fold(1, 4), 5)
		end },

		{ "disconnect stops a handler firing", function(t)
			local signal = Signal.new("test")
			local calls = 0

			local connection = signal:Connect(function() calls += 1 end)
			signal:Fire()
			connection.Disconnect()
			signal:Fire()

			t:Equal(calls, 1)
		end },

		{ "disconnecting during dispatch skips that handler in the same fire", function(t)
			local signal = Signal.new("test")
			local laterRan = false
			local connection

			signal:Connect(function() connection.Disconnect() end, 0)
			connection = signal:Connect(function() laterRan = true end, 1)

			signal:Fire()
			t:False(laterRan, "handler disconnected mid-dispatch did not run")
		end },

		{ "connecting during dispatch does not affect the in-flight fire", function(t)
			local signal = Signal.new("test")
			local newHandlerCalls = 0

			signal:Connect(function()
				signal:Connect(function() newHandlerCalls += 1 end, 99)
			end, 0)

			signal:Fire()
			t:Equal(newHandlerCalls, 0, "handler added mid-fire waits for the next one")

			signal:Fire()
			t:Equal(newHandlerCalls, 1)
		end },

		{ "Once fires exactly one time", function(t)
			local signal = Signal.new("test")
			local calls = 0

			signal:Once(function() calls += 1 end)
			signal:Fire()
			signal:Fire()
			signal:Fire()

			t:Equal(calls, 1)
			t:Equal(signal:GetHandlerCount(), 0, "removed itself after firing")
		end },

		{ "DisconnectAll clears every handler", function(t)
			local signal = Signal.new("test")
			local calls = 0

			signal:Connect(function() calls += 1 end)
			signal:Connect(function() calls += 1 end)
			signal:DisconnectAll()
			signal:Fire()

			t:Equal(calls, 0)
			t:Equal(signal:GetHandlerCount(), 0)
		end },

		{ "GetDispatchOrder reports the resolved order without firing", function(t)
			-- Serves the brief's requirement to log hook order: the order is
			-- inspectable rather than only observable through side effects.
			local signal = Signal.new("test")
			signal:Connect(function() end, 10, "Late")
			signal:Connect(function() end, -5, "Early")
			signal:Connect(function() end, 0, "Middle")

			t:DeepEqual(signal:GetDispatchOrder(), { "Early", "Middle", "Late" })
		end },

		{ "Connect rejects a non-function", function(t)
			local signal = Signal.new("test")
			t:Throws(function() signal:Connect("not a function") end)
		end },

		{ "handler count tracks connections", function(t)
			local signal = Signal.new("test")
			t:Equal(signal:GetHandlerCount(), 0)

			local first = signal:Connect(function() end)
			signal:Connect(function() end)
			t:Equal(signal:GetHandlerCount(), 2)

			first.Disconnect()
			t:Equal(signal:GetHandlerCount(), 1)
		end },

		{ "double disconnect is harmless", function(t)
			local signal = Signal.new("test")
			local connection = signal:Connect(function() end)

			connection.Disconnect()
			t:DoesNotThrow(function() connection.Disconnect() end)
			t:Equal(signal:GetHandlerCount(), 0)
		end },
	},
}

--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > RandomServiceSpec (ModuleScript)

	Determinism is the whole reason this module exists: without a reproducible
	generator, "book recycle uses a deterministic shuffle under a test seed"
	and "forced roll values produce exact steps" are untestable claims.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local RandomService = require(ServerScriptService.Systems.RandomService)

local function take(generator, count, min, max)
	local values = {}
	for _ = 1, count do
		table.insert(values, generator:NextInteger(min, max))
	end
	return values
end

return {
	Name = "RandomService",
	Tests = {
		{ "the same seed produces the same sequence", function(t)
			local a = RandomService.new(12345)
			local b = RandomService.new(12345)
			t:DeepEqual(take(a, 20, 1, 6), take(b, 20, 1, 6))
		end },

		{ "different seeds diverge", function(t)
			local a = take(RandomService.new(1), 20, 1, 1000)
			local b = take(RandomService.new(2), 20, 1, 1000)
			t:NotEqual(table.concat(a, ","), table.concat(b, ","))
		end },

		{ "NextInteger stays within bounds", function(t)
			local generator = RandomService.new(99)
			for _ = 1, 500 do
				local value = generator:NextInteger(1, 6)
				t:True(value >= 1 and value <= 6, "roll " .. tostring(value) .. " out of range")
			end
		end },

		{ "NextInteger covers its whole range", function(t)
			-- Guards against an off-by-one that silently makes a die never
			-- roll its maximum.
			local generator = RandomService.new(7)
			local seen = {}
			for _ = 1, 2000 do
				seen[generator:NextInteger(1, 6)] = true
			end
			for face = 1, 6 do
				t:True(seen[face] == true, "never rolled a " .. face)
			end
		end },

		{ "NextInteger handles a single-value range", function(t)
			local generator = RandomService.new(3)
			for _ = 1, 10 do
				t:Equal(generator:NextInteger(4, 4), 4)
			end
		end },

		{ "NextInteger supports a range beyond a six-sided die", function(t)
			-- Boards may present a range up to ten; nothing here assumes d6.
			local generator = RandomService.new(11)
			local seen = {}
			for _ = 1, 3000 do
				local value = generator:NextInteger(1, 10)
				t:True(value >= 1 and value <= 10, "out of range")
				seen[value] = true
			end
			t:True(seen[10] == true, "never rolled a 10")
		end },

		{ "NextInteger rejects an inverted range", function(t)
			local generator = RandomService.new(1)
			t:Throws(function() generator:NextInteger(6, 1) end)
		end },

		{ "NextNumber stays in [0, 1)", function(t)
			local generator = RandomService.new(42)
			for _ = 1, 500 do
				local value = generator:NextNumber()
				t:True(value >= 0 and value < 1, "value " .. tostring(value) .. " outside [0,1)")
			end
		end },

		{ "shuffle is deterministic for a given seed", function(t)
			local function shuffled(seed)
				local array = {}
				for index = 1, 50 do
					array[index] = index
				end
				return RandomService.new(seed):Shuffle(array)
			end
			t:DeepEqual(shuffled(2024), shuffled(2024))
		end },

		{ "shuffle permutes rather than losing or duplicating cards", function(t)
			local array = {}
			for index = 1, 50 do
				array[index] = index
			end

			RandomService.new(5):Shuffle(array)

			t:Equal(#array, 50, "length preserved")
			local seen = {}
			for _, value in ipairs(array) do
				t:Nil(seen[value], "value " .. tostring(value) .. " appeared twice")
				seen[value] = true
			end
			for index = 1, 50 do
				t:True(seen[index] == true, "value " .. index .. " was lost")
			end
		end },

		{ "shuffle actually reorders a book-sized array", function(t)
			local array, original = {}, {}
			for index = 1, 50 do
				array[index] = index
				original[index] = index
			end
			RandomService.new(777):Shuffle(array)
			t:NotEqual(table.concat(array, ","), table.concat(original, ","))
		end },

		{ "a zero seed does not freeze the generator", function(t)
			-- Zero is a fixed point for a Lehmer generator; the constructor
			-- has to normalise it or every roll would be identical forever.
			local generator = RandomService.new(0)
			local values = take(generator, 10, 1, 1000)
			local allSame = true
			for _, value in ipairs(values) do
				if value ~= values[1] then
					allSame = false
					break
				end
			end
			t:False(allSame, "generator produced a constant sequence")
		end },

		{ "clone continues the parent's sequence independently", function(t)
			local generator = RandomService.new(31337)
			take(generator, 5, 1, 100)

			local clone = generator:Clone()
			local fromParent = take(generator, 10, 1, 100)
			local fromClone = take(clone, 10, 1, 100)

			t:DeepEqual(fromClone, fromParent, "clone replays from the same state")
		end },

		{ "state can be captured and restored", function(t)
			local generator = RandomService.new(8)
			take(generator, 3, 1, 100)

			local saved = generator:GetState()
			local before = take(generator, 5, 1, 100)

			generator:SetState(saved)
			t:DeepEqual(take(generator, 5, 1, 100), before)
		end },

		{ "the seed is recoverable for replay", function(t)
			t:Equal(RandomService.new(4242):GetSeed(), 4242)
		end },
	},
}

--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > RandomService (ModuleScript)

	Purpose:
		The only source of randomness in the match. Every dice roll, shuffle
		and random selection draws from an injected generator so that a test
		can pin a seed and replay an entire match deterministically.

		Deliberately NOT Roblox's Random. Roblox's generator is deterministic
		for a given seed but its algorithm is not specified, so a recorded
		seed is not guaranteed to reproduce the same match on a different
		engine version, and it cannot run outside Studio at all. This is a
		Lehmer generator (MINSTD) written out in full: same seed, same
		sequence, forever, in Studio or under a plain Lua interpreter.

		MINSTD is not cryptographic and its low bits are weak. That is fine
		here — nothing in this game needs unpredictability against an
		adversary who already has to get past a server-authoritative match —
		but NextInteger derives from the high-order float rather than the low
		bits so the dice stay evenly distributed. If a stronger generator is
		ever needed, replace the three lines in `step` and nothing else.

		The generator lives on the server. Clients receive rolls as results,
		never as a seed they could run forward.

	Usage:
		local rng = RandomService.new(12345)
		rng:NextInteger(1, 6)
		rng:Shuffle(book)

		-- production
		RandomService.default():NextInteger(1, 6)

	Public API:
		RandomService.new(seed?) -> generator
		RandomService.default() -> generator      -- lazily created, time-seeded
		generator:NextInteger(min, max) -> integer
		generator:NextNumber() -> number in [0, 1)
		generator:Shuffle(array) -> array         -- in place, Fisher-Yates
		generator:GetSeed() -> number             -- the seed it started from
		generator:GetState() / :SetState(state)
		generator:Clone() -> generator            -- same state, independent
]]

local RandomService = {}
RandomService.__index = RandomService

-- Lehmer / MINSTD constants. MODULUS is the Mersenne prime 2^31 - 1, and
-- MULTIPLIER * (MODULUS - 1) stays under 2^53, so every step is exact in a
-- double and the sequence is identical on any conforming Lua.
local MULTIPLIER = 16807
local MODULUS = 2147483647
local MAX_STATE = MODULUS - 1

local _default = nil

-- State must land in [1, MODULUS-1]; zero is a fixed point that would make
-- the generator emit the same value forever.
local function normalizeSeed(seed)
	local n = math.floor(math.abs(tonumber(seed) or 0)) % MODULUS
	if n == 0 then
		n = 1
	end
	return n
end

function RandomService.new(seed)
	local resolvedSeed = normalizeSeed(seed ~= nil and seed or os.time())
	return setmetatable({
		_seed = resolvedSeed,
		_state = resolvedSeed,
	}, RandomService)
end

-- Production generator. Time-seeded, created on first use. Tests must never
-- use this — construct an explicit seed instead.
function RandomService.default()
	if _default == nil then
		_default = RandomService.new(os.time())
	end
	return _default
end

local function step(self)
	self._state = (self._state * MULTIPLIER) % MODULUS
	return self._state
end

-- [0, 1). Uses the whole state as a fraction rather than masking low bits,
-- which is where MINSTD is weakest.
function RandomService:NextNumber()
	return (step(self) - 1) / MAX_STATE
end

function RandomService:NextInteger(min, max)
	if min > max then
		error(string.format("NextInteger: min (%s) is greater than max (%s)", tostring(min), tostring(max)), 2)
	end

	local span = max - min + 1
	-- clamp guards the vanishing case where NextNumber returns exactly 1 - eps
	-- and floating point rounds the product up to span.
	return math.clamp(min + math.floor(self:NextNumber() * span), min, max)
end

-- Fisher-Yates, in place. Deterministic for a given seed and starting order,
-- which is what makes "book recycle uses a deterministic shuffle under a test
-- seed" an assertable property rather than a hope.
function RandomService:Shuffle(array)
	for i = #array, 2, -1 do
		local j = self:NextInteger(1, i)
		array[i], array[j] = array[j], array[i]
	end
	return array
end

function RandomService:GetSeed()
	return self._seed
end

function RandomService:GetState()
	return self._state
end

function RandomService:SetState(state)
	self._state = normalizeSeed(state)
end

-- An independent generator positioned at this one's current state — for
-- forking a deterministic sub-sequence without disturbing the parent.
function RandomService:Clone()
	local clone = RandomService.new(self._seed)
	clone._state = self._state
	return clone
end

return RandomService

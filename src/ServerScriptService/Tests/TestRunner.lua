--[[
	ModuleScript — server, development tooling (not part of the runtime game).

	Studio placement:
		ServerScriptService > Tests > TestRunner (ModuleScript)

	Purpose:
		A minimal test runner. Deliberately tiny and dependency-free rather
		than a port of a full framework — the value here is that the
		acceptance criteria in the project brief become executable, not that
		the harness is sophisticated.

		Specs are plain data: a name and an ORDERED array of {description,
		function} pairs. Ordered, not a keyed table, because pairs() order is
		not stable and a test report whose lines shuffle between runs is
		much harder to diff.

		Each test gets an assertion object and runs under pcall, so one
		failure reports and the suite continues. Assertions throw with the
		actual and expected values already formatted; a failure you have to
		re-run with prints added is a failure that wasted your time.

	Running:
		Tests must run in a PLAYTEST (Server datamodel), not in Edit. Roblox
		caches `require` per Edit session, so a module edited after being
		required once returns the stale table for the rest of that session
		and the suite silently tests old code. Starting a playtest builds a
		fresh datamodel with a fresh cache.

		From the command bar or an MCP execute_luau call against the Server
		datamodel:

			local Tests = game.ServerScriptService.Tests
			print(require(Tests.TestRunner).runAll(Tests.Specs))

	Spec shape:
		return {
			Name = "RulesConfig",
			Tests = {
				{ "chain multiplier for 3 territories is 1.8", function(t)
					t:Equal(RulesConfig.getChainMultiplier(3), 1.8)
				end },
			},
		}

	Public API:
		TestRunner.run(specs) -> summary, report
		TestRunner.runAll(specsFolder) -> report string
		TestRunner.newAsserter() -> t   -- exposed for testing the runner
]]

local TestRunner = {}

local function formatValue(value)
	local valueType = type(value)
	if valueType == "string" then
		return string.format("%q", value)
	elseif valueType == "number" then
		-- %.14g so 1.8 prints as 1.8 rather than 1.8000000000000000444,
		-- while still exposing a genuine floating-point discrepancy.
		return string.format("%.14g", value)
	elseif valueType == "table" then
		local parts = {}
		for k, v in pairs(value) do
			table.insert(parts, string.format("%s=%s", tostring(k), tostring(v)))
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end

	for key, valueA in pairs(a) do
		if not deepEqual(valueA, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local Asserter = {}
Asserter.__index = Asserter

function TestRunner.newAsserter()
	return setmetatable({ Count = 0 }, Asserter)
end

function Asserter:_fail(message)
	error(message, 3)
end

function Asserter:_pass()
	self.Count += 1
end

function Asserter:Equal(actual, expected, message)
	self:_pass()
	if actual ~= expected then
		self:_fail(string.format("%sexpected %s, got %s", message and (message .. ": ") or "", formatValue(expected), formatValue(actual)))
	end
end

function Asserter:NotEqual(actual, unexpected, message)
	self:_pass()
	if actual == unexpected then
		self:_fail(string.format("%sexpected anything but %s", message and (message .. ": ") or "", formatValue(unexpected)))
	end
end

function Asserter:True(value, message)
	self:_pass()
	if value ~= true then
		self:_fail(string.format("%sexpected true, got %s", message and (message .. ": ") or "", formatValue(value)))
	end
end

function Asserter:False(value, message)
	self:_pass()
	if value ~= false then
		self:_fail(string.format("%sexpected false, got %s", message and (message .. ": ") or "", formatValue(value)))
	end
end

function Asserter:Nil(value, message)
	self:_pass()
	if value ~= nil then
		self:_fail(string.format("%sexpected nil, got %s", message and (message .. ": ") or "", formatValue(value)))
	end
end

function Asserter:NotNil(value, message)
	self:_pass()
	if value == nil then
		self:_fail(string.format("%sexpected a value, got nil", message and (message .. ": ") or ""))
	end
end

-- For genuine floating-point comparisons only. Rule constants are asserted
-- with Equal on purpose: "the chain multiplier is approximately 1.8" is not
-- the property we want to guarantee.
function Asserter:Near(actual, expected, epsilon, message)
	self:_pass()
	epsilon = epsilon or 1e-9
	if type(actual) ~= "number" or math.abs(actual - expected) > epsilon then
		self:_fail(string.format("%sexpected %s within %s, got %s", message and (message .. ": ") or "", formatValue(expected), formatValue(epsilon), formatValue(actual)))
	end
end

function Asserter:DeepEqual(actual, expected, message)
	self:_pass()
	if not deepEqual(actual, expected) then
		self:_fail(string.format("%sexpected %s, got %s", message and (message .. ": ") or "", formatValue(expected), formatValue(actual)))
	end
end

function Asserter:Throws(fn, message)
	self:_pass()
	local ok, err = pcall(fn)
	if ok then
		self:_fail(string.format("%sexpected an error, none was thrown", message and (message .. ": ") or ""))
	end
	return tostring(err)
end

function Asserter:DoesNotThrow(fn, message)
	self:_pass()
	local ok, err = pcall(fn)
	if not ok then
		self:_fail(string.format("%sexpected no error, got: %s", message and (message .. ": ") or "", tostring(err)))
	end
end

function Asserter:Contains(array, value, message)
	self:_pass()
	for _, candidate in ipairs(array) do
		if candidate == value then
			return
		end
	end
	self:_fail(string.format("%sexpected array to contain %s", message and (message .. ": ") or "", formatValue(value)))
end

-- `loadFailures` are specs that could not even be required. They count as
-- failures: a suite that silently skips a spec it could not load and then
-- reports ALL PASS is worse than no suite at all.
function TestRunner.run(specs, loadFailures)
	local summary = {
		Passed = 0,
		Failed = 0,
		Assertions = 0,
		Failures = {},
	}
	local lines = {}

	for _, failure in ipairs(loadFailures or {}) do
		summary.Failed += 1
		table.insert(summary.Failures, failure)
		table.insert(lines, string.format("  XX  %-34s failed to load: %s", failure.Name, failure.Error))
	end

	for _, spec in ipairs(specs) do
		local specPassed, specFailed = 0, 0
		local specFailureLines = {}

		for _, entry in ipairs(spec.Tests) do
			local description, fn = entry[1], entry[2]
			local asserter = TestRunner.newAsserter()

			local ok, err = pcall(fn, asserter)
			summary.Assertions += asserter.Count

			if ok then
				specPassed += 1
				summary.Passed += 1
			else
				specFailed += 1
				summary.Failed += 1
				local label = string.format("%s > %s", spec.Name, description)
				table.insert(summary.Failures, { Name = label, Error = tostring(err) })
				table.insert(specFailureLines, string.format("          %s\n            %s", description, tostring(err)))
			end
		end

		-- Spec header first, then that spec's own failures indented beneath
		-- it. Spec order comes from runAll and is already stable; sorting
		-- here would tear failures away from the spec they belong to.
		table.insert(lines, string.format("%s  %-34s %d passed, %d failed", specFailed == 0 and "  ok  " or "  XX  ", spec.Name, specPassed, specFailed))
		for _, failureLine in ipairs(specFailureLines) do
			table.insert(lines, failureLine)
		end
	end

	local report = table.concat(lines, "\n")
	report = report
		.. string.format(
			"\n\n%s  %d passed, %d failed, %d assertions",
			summary.Failed == 0 and "ALL PASS" or "FAILURES",
			summary.Passed,
			summary.Failed,
			summary.Assertions
		)

	return summary, report
end

-- Loads every ModuleScript directly under `specsFolder`. Sorted by name so
-- the report is stable across runs.
function TestRunner.runAll(specsFolder)
	local moduleScripts = {}
	for _, child in ipairs(specsFolder:GetChildren()) do
		if child:IsA("ModuleScript") then
			table.insert(moduleScripts, child)
		end
	end
	table.sort(moduleScripts, function(a, b)
		return a.Name < b.Name
	end)

	local specs = {}
	local loadFailures = {}
	for _, moduleScript in ipairs(moduleScripts) do
		local ok, specOrError = pcall(require, moduleScript)
		if ok then
			table.insert(specs, specOrError)
		else
			table.insert(loadFailures, { Name = moduleScript.Name, Error = tostring(specOrError) })
		end
	end

	local _, report = TestRunner.run(specs, loadFailures)
	return report
end

return TestRunner

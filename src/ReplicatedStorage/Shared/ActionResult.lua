--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > ActionResult (ModuleScript)

	Purpose:
		One structured return shape for every action a player can attempt.

		This replaces the project's `success, reason` convention, which
		cannot express a legal action with a negative outcome. BattleService
		hit that wall first: `ChallengeTile` returns `false, nil` for "the
		challenge happened and you lost" and `false, "reason"` for "the
		challenge was rejected", forcing its caller to disambiguate on
		whether the second return was nil. Those are opposite events — one
		spent Magic and resolved a battle, the other changed nothing — and
		they must not share a representation.

		So: `Ok` means the request was accepted and processed. What actually
		happened goes in `Payload` (including losing a battle, which is a
		successful action with an unfavourable result). `Ok = false` means
		the request was refused, nothing was spent, and nothing moved.

		Results are frozen. A rejection that a caller can quietly edit into
		an acceptance is not a safety net.

	Usage:
		local ok = ActionResult.ok({ Outcome = Enums.BattleOutcome.DefenderHolds })
		local no = ActionResult.fail(Enums.RejectReason.WrongPhase, "Cannot roll during SpellChoice")

		if result.Ok then ... else warn(result.Code, result.Message) end

	Public API:
		ActionResult.ok(payload) -> result
		ActionResult.fail(code, message, details) -> result
		ActionResult.isOk(value) -> boolean
		ActionResult.isResult(value) -> boolean
		ActionResult.assertOk(result, context) -> payload   -- throws on failure
		ActionResult.describe(result) -> string
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)

local ActionResult = {}

-- Marker so isResult can tell a real result from any table with an Ok field.
local RESULT_MARKER = newproxy(false)

function ActionResult.ok(payload)
	return table.freeze({
		Ok = true,
		Payload = payload,
		_marker = RESULT_MARKER,
	})
end

-- `code` must be an Enums.RejectReason. Passing anything else is a
-- programming error and throws here rather than producing a rejection
-- nothing can match on.
function ActionResult.fail(code, message, details)
	if not Enums.isValid(Enums.RejectReason, code) then
		error(string.format("ActionResult.fail needs an Enums.RejectReason, got %s", tostring(code)), 2)
	end

	return table.freeze({
		Ok = false,
		Code = code,
		Message = message or code,
		Details = details,
		_marker = RESULT_MARKER,
	})
end

function ActionResult.isResult(value)
	return type(value) == "table" and rawget(value, "_marker") == RESULT_MARKER
end

function ActionResult.isOk(value)
	return ActionResult.isResult(value) and value.Ok == true
end

-- For tests and for internal call sites where a failure means the caller
-- built something impossible, rather than a player asking for something
-- illegal. Never use this on a path that handles player input.
function ActionResult.assertOk(result, context)
	if not ActionResult.isResult(result) then
		error(string.format("%s: expected an ActionResult, got %s", context or "assertOk", tostring(result)), 2)
	end
	if not result.Ok then
		error(string.format("%s: %s (%s)", context or "assertOk", tostring(result.Message), tostring(result.Code)), 2)
	end
	return result.Payload
end

function ActionResult.describe(result)
	if not ActionResult.isResult(result) then
		return "<not an ActionResult>"
	end
	if result.Ok then
		return "Ok"
	end
	return string.format("%s: %s", tostring(result.Code), tostring(result.Message))
end

return ActionResult

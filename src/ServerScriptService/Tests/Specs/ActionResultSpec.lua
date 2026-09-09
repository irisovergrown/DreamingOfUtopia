--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > ActionResultSpec (ModuleScript)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local ActionResult = require(ReplicatedStorage.Shared.ActionResult)

return {
	Name = "ActionResult",
	Tests = {
		{ "ok carries its payload", function(t)
			local result = ActionResult.ok({ TileId = 4 })
			t:True(result.Ok)
			t:Equal(result.Payload.TileId, 4)
		end },

		{ "ok with no payload is still a success", function(t)
			local result = ActionResult.ok()
			t:True(result.Ok)
			t:True(ActionResult.isOk(result))
		end },

		{ "fail carries a typed code and a message", function(t)
			local result = ActionResult.fail(Enums.RejectReason.WrongPhase, "cannot roll yet")
			t:False(result.Ok)
			t:Equal(result.Code, Enums.RejectReason.WrongPhase)
			t:Equal(result.Message, "cannot roll yet")
		end },

		{ "fail defaults its message to the code", function(t)
			local result = ActionResult.fail(Enums.RejectReason.NotYourTurn)
			t:Equal(result.Message, Enums.RejectReason.NotYourTurn)
		end },

		{ "fail rejects a code that is not a RejectReason", function(t)
			-- Otherwise a typo produces a rejection nothing can match on.
			t:Throws(function() ActionResult.fail("NotARealReason", "x") end)
			t:Throws(function() ActionResult.fail(nil, "x") end)
		end },

		{ "a losing battle is a successful action, not a failure", function(t)
			-- The distinction the old `success, reason` convention could not
			-- express: the challenge resolved and cost Magic, the attacker
			-- simply lost. That is not a rejected request.
			local lost = ActionResult.ok({ Outcome = Enums.BattleOutcome.DefenderHolds })
			local rejected = ActionResult.fail(Enums.RejectReason.InsufficientMagic, "not enough Magic")

			t:True(lost.Ok, "losing a battle is Ok")
			t:False(rejected.Ok, "an unaffordable challenge is not")
			t:NotEqual(lost.Ok, rejected.Ok, "the two are distinguishable without inspecting a reason string")
		end },

		{ "results are frozen", function(t)
			-- A rejection a caller can quietly edit into an acceptance is not
			-- a safety net.
			local result = ActionResult.fail(Enums.RejectReason.WrongPhase, "no")
			t:Throws(function() result.Ok = true end)
		end },

		{ "isOk and isResult reject look-alike tables", function(t)
			t:False(ActionResult.isOk({ Ok = true }), "a bare table is not a result")
			t:False(ActionResult.isResult({ Ok = true }))
			t:False(ActionResult.isOk(nil))
			t:False(ActionResult.isOk(true))
			t:True(ActionResult.isResult(ActionResult.ok()))
			t:True(ActionResult.isResult(ActionResult.fail(Enums.RejectReason.Timeout)))
		end },

		{ "assertOk returns the payload and throws on failure", function(t)
			t:Equal(ActionResult.assertOk(ActionResult.ok(7)), 7)
			t:Throws(function()
				ActionResult.assertOk(ActionResult.fail(Enums.RejectReason.InvalidTarget, "bad target"))
			end)
		end },

		{ "describe summarises both outcomes", function(t)
			t:Equal(ActionResult.describe(ActionResult.ok()), "Ok")
			local text = ActionResult.describe(ActionResult.fail(Enums.RejectReason.WrongPhase, "nope"))
			t:True(string.find(text, "WrongPhase", 1, true) ~= nil, "includes the code")
			t:True(string.find(text, "nope", 1, true) ~= nil, "includes the message")
		end },
	},
}

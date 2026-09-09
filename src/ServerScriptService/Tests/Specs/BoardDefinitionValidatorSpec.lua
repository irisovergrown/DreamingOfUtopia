--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > BoardDefinitionValidatorSpec (ModuleScript)

	Each malformation test deep-copies the real CurrentLoop board and breaks
	exactly one thing, so a test that passes proves the validator catches that
	specific fault rather than tripping over unrelated damage in a fixture.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local CurrentLoop = require(ReplicatedStorage.Shared.BoardDefinitions.CurrentLoop)
local BoardDefinitionValidator = require(ServerScriptService.Systems.BoardDefinitionValidator)

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, entry in pairs(value) do
		copy[key] = deepCopy(entry)
	end
	return copy
end

-- Copies the real board, applies one deliberate break, and validates it.
local function broken(mutate)
	local definition = deepCopy(CurrentLoop)
	mutate(definition)
	return BoardDefinitionValidator.validate(definition)
end

local function errorsContain(result, fragment)
	for _, message in ipairs(result.Details and result.Details.Errors or {}) do
		if string.find(message, fragment, 1, true) then
			return true
		end
	end
	return false
end

local function findNode(definition, nodeId)
	for _, node in ipairs(definition.Nodes) do
		if node.Id == nodeId then
			return node
		end
	end
	return nil
end

return {
	Name = "BoardDefinitionValidator",
	Tests = {
		{ "accepts the board that is actually in the place", function(t)
			local result = BoardDefinitionValidator.validate(CurrentLoop)
			if not result.Ok then
				t:True(false, "CurrentLoop failed validation: " .. table.concat(result.Details.Errors, "; "))
			end
			t:Equal(result.Payload.NodeCount, 16, "sixteen nodes")
			t:Equal(result.Payload.EdgeCount, 16, "sixteen edges, ring closed")
			t:Equal(result.Payload.AreaCount, 1)
		end },

		{ "rejects a non-table definition", function(t)
			t:False(BoardDefinitionValidator.validate(nil).Ok)
			t:False(BoardDefinitionValidator.validate("board").Ok)
		end },

		{ "rejects duplicate node ids", function(t)
			local result = broken(function(definition)
				definition.Nodes[3].Id = definition.Nodes[2].Id
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "duplicate node id"), "reported the duplicate")
		end },

		{ "rejects an edge pointing at a node that does not exist", function(t)
			local result = broken(function(definition)
				definition.Edges[1].To = "TypoNode"
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "unknown node 'TypoNode'"), "named the missing node")
		end },

		{ "rejects a node with no way out", function(t)
			-- The unrecoverable case: a token that lands here can never leave.
			local result = broken(function(definition)
				for index, edge in ipairs(definition.Edges) do
					if edge.From == "T5" then
						table.remove(definition.Edges, index)
						break
					end
				end
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "no outgoing edge"), "reported the softlock")
		end },

		{ "rejects an unreachable node", function(t)
			local result = broken(function(definition)
				table.insert(definition.Nodes, {
					Id = "Orphan",
					Type = Enums.NodeType.Territory,
					Area = "Main",
					Element = Enums.Element.Fire,
					BaseValue = 100,
				})
				-- Give it an exit so it fails on reachability, not softlock.
				table.insert(definition.Edges, { Id = "EOrphan", From = "Orphan", To = "T1" })
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "'Orphan' is unreachable"), "reported unreachability")
		end },

		{ "rejects a required fort type that no node provides", function(t)
			-- Silent lap-completion failure: players would circle forever.
			local result = broken(function(definition)
				definition.RequiredFortTypes = { "Water" }
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "lap could never complete"), "explained the consequence")
		end },

		{ "accepts a required fort type that a Fort node provides", function(t)
			local definition = deepCopy(CurrentLoop)
			local node = findNode(definition, "T9")
			node.Type = Enums.NodeType.Fort
			node.FortType = "Water"
			node.Element = nil
			node.BaseValue = nil
			definition.RequiredFortTypes = { "Water" }

			local result = BoardDefinitionValidator.validate(definition)
			if not result.Ok then
				t:True(false, "unexpected errors: " .. table.concat(result.Details.Errors, "; "))
			end
		end },

		{ "rejects a Fort node with no FortType", function(t)
			local result = broken(function(definition)
				local node = findNode(definition, "T9")
				node.Type = Enums.NodeType.Fort
				node.BaseValue = nil
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "needs a FortType"))
		end },

		{ "rejects a warp with no destination", function(t)
			local result = broken(function(definition)
				local node = findNode(definition, "T4")
				node.Type = Enums.NodeType.MandatoryWarp
				node.BaseValue = nil
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "needs a TransportTo node id"))
		end },

		{ "rejects a warp pointing at a node that does not exist", function(t)
			local result = broken(function(definition)
				local node = findNode(definition, "T4")
				node.Type = Enums.NodeType.LandingWarp
				node.BaseValue = nil
				node.TransportTo = "Nowhere"
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "transports to unknown node 'Nowhere'"))
		end },

		{ "rejects a Castle node missing from CastleNodeIds", function(t)
			-- Would look like a castle and never complete a lap.
			local result = broken(function(definition)
				findNode(definition, "T8").Type = Enums.NodeType.Castle
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "missing from CastleNodeIds"))
		end },

		{ "rejects CastleNodeIds naming a node that is not a Castle", function(t)
			local result = broken(function(definition)
				definition.CastleNodeIds = { "T5" }
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "not a Castle"))
		end },

		{ "rejects an unknown StartNodeId", function(t)
			local result = broken(function(definition)
				definition.StartNodeId = "T99"
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "StartNodeId 'T99' is not a known node"))
		end },

		{ "rejects a node in an area that does not exist", function(t)
			local result = broken(function(definition)
				findNode(definition, "T7").Area = "Nonexistent"
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "unknown Area 'Nonexistent'"))
		end },

		{ "rejects an invalid element", function(t)
			local result = broken(function(definition)
				findNode(definition, "T2").Element = "Lightning"
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "invalid Element 'Lightning'"))
		end },

		{ "rejects a territory with no base value", function(t)
			local result = broken(function(definition)
				findNode(definition, "T2").BaseValue = nil
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "needs a non-negative BaseValue"))
		end },

		{ "rejects a self-loop edge", function(t)
			local result = broken(function(definition)
				definition.Edges[1].To = definition.Edges[1].From
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "self-loop"))
		end },

		{ "rejects a duplicated edge", function(t)
			local result = broken(function(definition)
				table.insert(definition.Edges, { Id = "EDupe", From = "T1", To = "T2" })
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "duplicate edge T1->T2"))
		end },

		{ "rejects a roll range whose max is below its min", function(t)
			local result = broken(function(definition)
				definition.Roll = { Min = 5, Max = 2 }
			end)
			t:False(result.Ok)
			t:True(errorsContain(result, "less than Roll.Min"))
		end },

		{ "reports every problem at once rather than only the first", function(t)
			local result = broken(function(definition)
				definition.BoardId = ""
				definition.StartNodeId = "T99"
				findNode(definition, "T2").Element = "Lightning"
			end)
			t:False(result.Ok)
			t:True(#result.Details.Errors >= 3, "expected at least three errors, got " .. #result.Details.Errors)
		end },
	},
}

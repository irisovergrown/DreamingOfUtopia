--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > BoardDefinitionValidator (ModuleScript)

	Purpose:
		Rejects malformed boards at load time instead of at 2am mid-match.

		A board is a graph, and the ways a hand-authored graph goes wrong are
		specific and repeatable: an edge pointing at a node that was renamed,
		a fort type required for lap completion that no node actually
		provides, a warp with no landing site, a node with no way out. Every
		one of those is silent until a player walks into it, at which point
		the match is unrecoverable. All of them are cheap to detect here.

		Reports EVERY problem it finds rather than stopping at the first, so
		authoring a board is one fix-and-revalidate cycle instead of a dozen.

		Pure logic — no Roblox instances, no CollectionService, no Workspace.
		A board definition is data; whether Parts exist to render it is a
		separate question that belongs to the rendering layer.

	Board definition shape:
		BoardId, DisplayName, Version    identity
		RecommendedPlayers {Min, Max}
		DefaultMagic, TMGoal             match economy
		Roll {Min, Max}                  per-board roll range, never a global d6
		Areas[]  {Id, DisplayName}       chains and symbols are area-scoped
		Nodes[]  {Id, Type, Area, Element?, BaseValue?, FortType?,
		          TransportTo?, StudioTileId?}
		Edges[]  {Id, From, To}          directed; author both ways for a
		                                 two-way path
		RequiredFortTypes[]              all must be visited to complete a lap
		CastleNodeIds[]
		StartNodeId

	Public API:
		BoardDefinitionValidator.validate(definition) -> ActionResult
			ok payload:  { NodeCount, EdgeCount, AreaCount, Warnings }
			fail details: { Errors = { "...", ... } }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local ActionResult = require(ReplicatedStorage.Shared.ActionResult)

local BoardDefinitionValidator = {}

local function isNonEmptyArray(value)
	return type(value) == "table" and #value > 0
end

-- Node types whose whole purpose is relocating a token, so a missing or
-- dangling TransportTo is a hard error rather than an omission.
local TRANSPORT_NODE_TYPES = {
	[Enums.NodeType.LandingWarp] = true,
	[Enums.NodeType.MandatoryWarp] = true,
}

local function validateTopLevel(definition, errors)
	if type(definition.BoardId) ~= "string" or definition.BoardId == "" then
		table.insert(errors, "BoardId must be a non-empty string")
	end
	if type(definition.DisplayName) ~= "string" or definition.DisplayName == "" then
		table.insert(errors, "DisplayName must be a non-empty string")
	end
	if type(definition.Version) ~= "number" then
		table.insert(errors, "Version must be a number")
	end
	if type(definition.DefaultMagic) ~= "number" or definition.DefaultMagic < 0 then
		table.insert(errors, "DefaultMagic must be a non-negative number")
	end
	if type(definition.TMGoal) ~= "number" or definition.TMGoal <= 0 then
		table.insert(errors, "TMGoal must be a positive number")
	end

	local roll = definition.Roll
	if type(roll) ~= "table" then
		table.insert(errors, "Roll must be a table with Min and Max")
	else
		if type(roll.Min) ~= "number" or roll.Min < 1 then
			table.insert(errors, "Roll.Min must be a number >= 1")
		end
		if type(roll.Max) ~= "number" then
			table.insert(errors, "Roll.Max must be a number")
		elseif type(roll.Min) == "number" and roll.Max < roll.Min then
			table.insert(errors, string.format("Roll.Max (%d) is less than Roll.Min (%d)", roll.Max, roll.Min))
		end
	end
end

local function validateAreas(definition, errors)
	local areaIds = {}
	if not isNonEmptyArray(definition.Areas) then
		table.insert(errors, "Areas must be a non-empty array")
		return areaIds
	end

	for index, area in ipairs(definition.Areas) do
		if type(area.Id) ~= "string" or area.Id == "" then
			table.insert(errors, string.format("Areas[%d].Id must be a non-empty string", index))
		elseif areaIds[area.Id] then
			table.insert(errors, string.format("duplicate Area id '%s'", area.Id))
		else
			areaIds[area.Id] = true
		end
	end

	return areaIds
end

local function validateNodes(definition, areaIds, errors)
	local nodesById = {}
	if not isNonEmptyArray(definition.Nodes) then
		table.insert(errors, "Nodes must be a non-empty array")
		return nodesById
	end

	for index, node in ipairs(definition.Nodes) do
		local label = string.format("Nodes[%d]", index)

		if type(node.Id) ~= "string" or node.Id == "" then
			table.insert(errors, label .. ".Id must be a non-empty string")
			continue
		end

		label = string.format("node '%s'", node.Id)

		if nodesById[node.Id] then
			table.insert(errors, string.format("duplicate node id '%s'", node.Id))
			continue
		end
		nodesById[node.Id] = node

		if not Enums.isValid(Enums.NodeType, node.Type) then
			table.insert(errors, string.format("%s has invalid Type '%s'", label, tostring(node.Type)))
		end

		if not areaIds[node.Area] then
			table.insert(errors, string.format("%s references unknown Area '%s'", label, tostring(node.Area)))
		end

		if node.Element ~= nil and not Enums.isValid(Enums.Element, node.Element) then
			table.insert(errors, string.format("%s has invalid Element '%s'", label, tostring(node.Element)))
		end

		if node.Type == Enums.NodeType.Territory then
			if type(node.BaseValue) ~= "number" or node.BaseValue < 0 then
				table.insert(errors, string.format("%s is a Territory and needs a non-negative BaseValue", label))
			end
		end

		if node.Type == Enums.NodeType.Fort and (type(node.FortType) ~= "string" or node.FortType == "") then
			table.insert(errors, string.format("%s is a Fort and needs a FortType", label))
		end

		if TRANSPORT_NODE_TYPES[node.Type] and (type(node.TransportTo) ~= "string" or node.TransportTo == "") then
			table.insert(errors, string.format("%s is a %s and needs a TransportTo node id", label, node.Type))
		end
	end

	-- Deferred until every node id is known, so forward references are legal.
	for _, node in pairs(nodesById) do
		if node.TransportTo ~= nil and nodesById[node.TransportTo] == nil then
			table.insert(errors, string.format("node '%s' transports to unknown node '%s'", node.Id, tostring(node.TransportTo)))
		end
	end

	return nodesById
end

local function validateEdges(definition, nodesById, errors)
	local outgoing = {}
	for nodeId in pairs(nodesById) do
		outgoing[nodeId] = {}
	end

	if not isNonEmptyArray(definition.Edges) then
		table.insert(errors, "Edges must be a non-empty array")
		return outgoing
	end

	local edgeIds, seenPairs = {}, {}
	for index, edge in ipairs(definition.Edges) do
		local label = string.format("Edges[%d]", index)

		if type(edge.Id) ~= "string" or edge.Id == "" then
			table.insert(errors, label .. ".Id must be a non-empty string")
		elseif edgeIds[edge.Id] then
			table.insert(errors, string.format("duplicate edge id '%s'", edge.Id))
		else
			edgeIds[edge.Id] = true
		end

		local fromExists = nodesById[edge.From] ~= nil
		local toExists = nodesById[edge.To] ~= nil

		if not fromExists then
			table.insert(errors, string.format("%s.From references unknown node '%s'", label, tostring(edge.From)))
		end
		if not toExists then
			table.insert(errors, string.format("%s.To references unknown node '%s'", label, tostring(edge.To)))
		end

		if fromExists and toExists then
			if edge.From == edge.To then
				table.insert(errors, string.format("%s is a self-loop on '%s'", label, edge.From))
			else
				local key = edge.From .. "->" .. edge.To
				if seenPairs[key] then
					table.insert(errors, string.format("duplicate edge %s", key))
				else
					seenPairs[key] = true
					table.insert(outgoing[edge.From], edge.To)
				end
			end
		end
	end

	-- A node with no exit is an unrecoverable softlock: a token that lands
	-- there can never leave and the match cannot continue.
	for nodeId, destinations in pairs(outgoing) do
		if #destinations == 0 then
			table.insert(errors, string.format("node '%s' has no outgoing edge (movement would softlock)", nodeId))
		end
	end

	return outgoing
end

local function validateStartCastleAndForts(definition, nodesById, errors)
	if type(definition.StartNodeId) ~= "string" or nodesById[definition.StartNodeId] == nil then
		table.insert(errors, string.format("StartNodeId '%s' is not a known node", tostring(definition.StartNodeId)))
	end

	local declaredCastles = {}
	if not isNonEmptyArray(definition.CastleNodeIds) then
		table.insert(errors, "CastleNodeIds must list at least one castle")
	else
		for _, castleId in ipairs(definition.CastleNodeIds) do
			local node = nodesById[castleId]
			if node == nil then
				table.insert(errors, string.format("CastleNodeIds references unknown node '%s'", tostring(castleId)))
			elseif node.Type ~= Enums.NodeType.Castle then
				table.insert(errors, string.format("CastleNodeIds lists '%s', which is a %s, not a Castle", castleId, tostring(node.Type)))
			else
				declaredCastles[castleId] = true
			end
		end
	end

	-- Both directions: a Castle node absent from CastleNodeIds would never
	-- complete a lap despite looking like it should.
	for nodeId, node in pairs(nodesById) do
		if node.Type == Enums.NodeType.Castle and not declaredCastles[nodeId] then
			table.insert(errors, string.format("node '%s' is a Castle but is missing from CastleNodeIds", nodeId))
		end
	end

	if definition.RequiredFortTypes ~= nil then
		if type(definition.RequiredFortTypes) ~= "table" then
			table.insert(errors, "RequiredFortTypes must be an array")
		else
			local availableFortTypes = {}
			for _, node in pairs(nodesById) do
				if node.Type == Enums.NodeType.Fort and node.FortType then
					availableFortTypes[node.FortType] = true
				end
			end
			for _, fortType in ipairs(definition.RequiredFortTypes) do
				if not availableFortTypes[fortType] then
					table.insert(errors, string.format("RequiredFortTypes needs '%s' but no Fort node provides it (lap could never complete)", tostring(fortType)))
				end
			end
		end
	end
end

local function validateReachability(definition, nodesById, outgoing, errors)
	local startId = definition.StartNodeId
	if nodesById[startId] == nil then
		return -- already reported; nothing to walk from
	end

	local seen, queue = { [startId] = true }, { startId }
	while #queue > 0 do
		local nodeId = table.remove(queue)
		local node = nodesById[nodeId]
		-- A dangling TransportTo names a node that does not exist. That is
		-- already reported by validateNodes, but the destination still has to
		-- be skipped here or the walk indexes a nil node and the whole
		-- validation crashes instead of returning the error it just found.
		if node ~= nil then
			for _, destination in ipairs(outgoing[nodeId] or {}) do
				if not seen[destination] then
					seen[destination] = true
					table.insert(queue, destination)
				end
			end
			-- Transports are movement too: a node only reachable through a
			-- warp is legitimately reachable.
			local transportTo = node.TransportTo
			if transportTo and nodesById[transportTo] and not seen[transportTo] then
				seen[transportTo] = true
				table.insert(queue, transportTo)
			end
		end
	end

	local unreachable = {}
	for nodeId in pairs(nodesById) do
		if not seen[nodeId] then
			table.insert(unreachable, nodeId)
		end
	end
	table.sort(unreachable)

	for _, nodeId in ipairs(unreachable) do
		table.insert(errors, string.format("node '%s' is unreachable from StartNodeId '%s'", nodeId, startId))
	end
end

function BoardDefinitionValidator.validate(definition)
	if type(definition) ~= "table" then
		return ActionResult.fail(Enums.RejectReason.RuleViolation, "board definition must be a table", {
			Errors = { "board definition must be a table" },
		})
	end

	local errors = {}

	validateTopLevel(definition, errors)
	local areaIds = validateAreas(definition, errors)
	local nodesById = validateNodes(definition, areaIds, errors)
	local outgoing = validateEdges(definition, nodesById, errors)
	validateStartCastleAndForts(definition, nodesById, errors)
	validateReachability(definition, nodesById, outgoing, errors)

	if #errors > 0 then
		return ActionResult.fail(
			Enums.RejectReason.RuleViolation,
			string.format("board '%s' failed validation with %d error(s)", tostring(definition.BoardId), #errors),
			{ Errors = errors }
		)
	end

	local nodeCount = 0
	for _ in pairs(nodesById) do
		nodeCount += 1
	end

	return ActionResult.ok({
		NodeCount = nodeCount,
		EdgeCount = #definition.Edges,
		AreaCount = #definition.Areas,
		Warnings = {},
	})
end

return BoardDefinitionValidator

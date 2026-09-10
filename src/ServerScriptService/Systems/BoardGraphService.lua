--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > BoardGraphService (ModuleScript)

	Purpose:
		The board's topology: which nodes exist, what connects to what, which
		are forts or castles, and where transports lead.

		This replaces BoardService's sorted-ID loop as the authoritative
		answer to "where can I go from here". A Culdcept board is a graph —
		branches, spurs, dead ends, one-way segments — and none of that can be
		expressed by incrementing an index. Node order is not derivable from
		numbering or from world position, so it is authored as edges.

		Pure topology, deliberately. This module knows a node is a Territory
		with a base value and an element; it does NOT know who owns it, what
		level it is, or what defends it. That mutable state stays in
		BoardService (and becomes TerritoryService in Milestone 5), so the
		graph can be reasoned about and tested without a match running.

		Rendering reads this. It never defines it: a node's `StudioNodeId`
		points at the Part that draws it, and a board with no Parts at all is
		still a completely valid board as far as this module is concerned.

	The reversal rule:
		GetLegalExits takes the node you came FROM, not the edge you arrived
		on. In a directed graph a two-way path is two separate edges, so the
		return route has a different edge id and comparing ids would never
		detect a reversal. Comparing destinations does.

		Normal movement may not immediately double back. The exception is a
		dead end, where the way you came is the only way out — there,
		reversing is not a choice, it is the only legal continuation. A node
		may also set AllowReversal to permit it explicitly.

	Public API:
		BoardGraphService.Load(definition) -> ActionResult
		BoardGraphService.IsLoaded() -> boolean
		BoardGraphService.GetBoardId() -> string
		BoardGraphService.GetNode(nodeId) -> node or nil
		BoardGraphService.GetAllNodeIds() -> sorted array
		BoardGraphService.GetStartNodeId() -> nodeId
		BoardGraphService.GetCastleNodeIds() -> array
		BoardGraphService.IsCastle(nodeId) -> boolean
		BoardGraphService.GetFortType(nodeId) -> string or nil
		BoardGraphService.GetRequiredFortTypes() -> array
		BoardGraphService.GetRollRange() -> min, max
		BoardGraphService.GetExits(nodeId) -> array of { EdgeId, To }
		BoardGraphService.GetLegalExits(nodeId, cameFromNodeId) -> array
		BoardGraphService.GetTransport(nodeId) -> { To, TriggersOnPass } or nil
		BoardGraphService.AreAdjacent(a, b) -> boolean
		BoardGraphService.GetNodesInArea(areaId) -> array of nodeIds
		BoardGraphService.GetNodeIdByStudioNodeId(value) -> nodeId or nil
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local ActionResult = require(ReplicatedStorage.Shared.ActionResult)
local RulesConfig = require(ReplicatedStorage.Shared.RulesConfig)
local BoardDefinitionValidator = require(ServerScriptService.Systems.BoardDefinitionValidator)

local BoardGraphService = {}

-- Node types that relocate a token on entry. LandingWarp only fires when
-- movement ends on it; MandatoryWarp fires even when merely crossed. That
-- difference is the whole reason they are separate types.
local TRANSPORT_TRIGGERS_ON_PASS = {
	[Enums.NodeType.MandatoryWarp] = true,
	[Enums.NodeType.LandingWarp] = false,
}

local _definition = nil
local _nodes = {}
local _exits = {}
local _edges = {}
local _castleSet = {}
local _byStudioNodeId = {}
local _sortedNodeIds = {}

local function clear()
	_definition = nil
	_nodes = {}
	_exits = {}
	_edges = {}
	_castleSet = {}
	_byStudioNodeId = {}
	_sortedNodeIds = {}
end

-- Validation runs before indexing, never after: a board that fails is not
-- half-loaded, so a rejected board can never be walked.
function BoardGraphService.Load(definition)
	local validation = BoardDefinitionValidator.validate(definition)
	if not validation.Ok then
		return validation
	end

	clear()
	_definition = definition

	for _, node in ipairs(definition.Nodes) do
		_nodes[node.Id] = node
		_exits[node.Id] = {}
		table.insert(_sortedNodeIds, node.Id)

		if node.Type == Enums.NodeType.Castle then
			_castleSet[node.Id] = true
		end
		if node.StudioNodeId ~= nil then
			_byStudioNodeId[node.StudioNodeId] = node.Id
		end
		-- CurrentLoop predates the StudioNodeId name; accept the older key so
		-- the migration board keeps working without being rewritten.
		if node.StudioTileId ~= nil then
			_byStudioNodeId[node.StudioTileId] = node.Id
		end
	end
	table.sort(_sortedNodeIds)

	for _, edge in ipairs(definition.Edges) do
		_edges[edge.Id] = edge
		table.insert(_exits[edge.From], { EdgeId = edge.Id, To = edge.To })
	end

	-- Sorted so a junction always presents its options in the same order.
	-- Movement must be reproducible from a seed, and "which branch was
	-- offered first" is part of that.
	for _, exits in pairs(_exits) do
		table.sort(exits, function(a, b)
			return a.EdgeId < b.EdgeId
		end)
	end

	return ActionResult.ok({
		BoardId = definition.BoardId,
		NodeCount = #definition.Nodes,
		EdgeCount = #definition.Edges,
	})
end

function BoardGraphService.IsLoaded()
	return _definition ~= nil
end

function BoardGraphService.GetBoardId()
	return _definition and _definition.BoardId
end

function BoardGraphService.GetNode(nodeId)
	return _nodes[nodeId]
end

function BoardGraphService.GetAllNodeIds()
	local copy = {}
	for index, nodeId in ipairs(_sortedNodeIds) do
		copy[index] = nodeId
	end
	return copy
end

function BoardGraphService.GetStartNodeId()
	return _definition and _definition.StartNodeId
end

function BoardGraphService.GetCastleNodeIds()
	local copy = {}
	for index, nodeId in ipairs(_definition and _definition.CastleNodeIds or {}) do
		copy[index] = nodeId
	end
	return copy
end

function BoardGraphService.IsCastle(nodeId)
	return _castleSet[nodeId] == true
end

function BoardGraphService.GetFortType(nodeId)
	local node = _nodes[nodeId]
	if node == nil or node.Type ~= Enums.NodeType.Fort then
		return nil
	end
	return node.FortType
end

function BoardGraphService.GetRequiredFortTypes()
	local copy = {}
	for index, fortType in ipairs(_definition and _definition.RequiredFortTypes or {}) do
		copy[index] = fortType
	end
	return copy
end

function BoardGraphService.GetRollRange()
	local roll = _definition and _definition.Roll
	if roll == nil then
		return RulesConfig.Roll.DefaultMin, RulesConfig.Roll.DefaultMax
	end
	return roll.Min, roll.Max
end

function BoardGraphService.GetExits(nodeId)
	local copy = {}
	for index, exit in ipairs(_exits[nodeId] or {}) do
		copy[index] = { EdgeId = exit.EdgeId, To = exit.To }
	end
	return copy
end

-- The exits a token may actually take, given where it came from. Passing nil
-- for cameFromNodeId (a fresh move, a teleport) offers everything.
function BoardGraphService.GetLegalExits(nodeId, cameFromNodeId)
	local all = BoardGraphService.GetExits(nodeId)
	if cameFromNodeId == nil then
		return all
	end

	local node = _nodes[nodeId]
	if node ~= nil and node.AllowReversal then
		return all
	end

	local forward = {}
	for _, exit in ipairs(all) do
		if exit.To ~= cameFromNodeId then
			table.insert(forward, exit)
		end
	end

	-- A dead end: the way back is the only way on, so reversing stops being a
	-- choice and becomes the continuation.
	if #forward == 0 then
		return all
	end
	return forward
end

function BoardGraphService.GetTransport(nodeId)
	local node = _nodes[nodeId]
	if node == nil or node.TransportTo == nil then
		return nil
	end
	local triggersOnPass = TRANSPORT_TRIGGERS_ON_PASS[node.Type]
	if triggersOnPass == nil then
		return nil
	end
	return { To = node.TransportTo, TriggersOnPass = triggersOnPass }
end

function BoardGraphService.AreAdjacent(a, b)
	for _, exit in ipairs(_exits[a] or {}) do
		if exit.To == b then
			return true
		end
	end
	return false
end

function BoardGraphService.GetNodesInArea(areaId)
	local result = {}
	for _, nodeId in ipairs(_sortedNodeIds) do
		if _nodes[nodeId].Area == areaId then
			table.insert(result, nodeId)
		end
	end
	return result
end

function BoardGraphService.GetNodeIdByStudioNodeId(value)
	return _byStudioNodeId[value]
end

function BoardGraphService.GetEdge(edgeId)
	return _edges[edgeId]
end

return BoardGraphService

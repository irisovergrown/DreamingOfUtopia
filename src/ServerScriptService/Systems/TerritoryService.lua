--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > TerritoryService (ModuleScript)

	Purpose:
		Mutable territory state — who owns each node, what level it is, and
		which element it currently has — plus the territory commands that
		change those things.

		Replaces BoardService and TerraformService. Those split one concept
		across two modules and keyed it by a numeric tile id that existed only
		because the old board was a sorted ring. State is now keyed by NODE
		ID, the same key BoardGraphService uses, so there is one name for a
		place on the board instead of two that had to be kept in step.

	Seeded from the board definition, not from Parts:
		Element and BaseValue come from the loaded graph. BoardService used to
		read them off each Part's attributes at Init, which meant the runtime
		truth lived in Studio and the graph data was a copy that could silently
		disagree. The graph has been authoritative since Milestone 2; this
		finishes the job.

		The practical consequence: a Part's `Era`/`BaseValue` attributes are no
		longer read at runtime. They remain the authoring source, and a board
		definition has to reflect them — see README. That is also why no
		attribute migration was needed for the Era -> Element rename: the
		attribute simply stopped being load-bearing.

	Chains are area-scoped:
		A chain is same-element territories held by one player IN THE SAME
		AREA. Scoping matters on any board with more than one area, and
		getting it wrong inflates every toll on the board. The current
		single-area board cannot tell the difference, which is exactly why the
		rule is enforced here rather than "when we need it".

	Public API:
		TerritoryService.Init(deps)              -- deps.Graph, deps.Economy
		TerritoryService.GetTerritory(nodeId) -> snapshot or nil
		TerritoryService.GetAllTerritories() -> array, node-id sorted
		TerritoryService.GetOwnedBy(userId) -> array of nodeIds
		TerritoryService.SetOwner(nodeId, userIdOrNil)
		TerritoryService.GetChainSize(userId, element, areaId) -> number
		TerritoryService.GetLandValue(nodeId) -> integer
		TerritoryService.GetToll(nodeId) -> integer
		TerritoryService.GetDevelopmentCost(nodeId, targetLevel) -> integer
		TerritoryService.LevelUp(userId, nodeId, targetLevel) -> ActionResult
		TerritoryService.GetElementChangeCost(nodeId) -> integer
		TerritoryService.ChangeElement(userId, nodeId, element) -> ActionResult
		TerritoryService.ReleaseAllOwnedBy(userId)

	Signals:
		TerritoryService.OwnerChanged:Connect(function(nodeId, newOwnerUserId) end)
		TerritoryService.LevelChanged:Connect(function(nodeId, newLevel) end)
		TerritoryService.ElementChanged:Connect(function(nodeId, newElement) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local ActionResult = require(ReplicatedStorage.Shared.ActionResult)
local RulesConfig = require(ReplicatedStorage.Shared.RulesConfig)
local Signal = require(ReplicatedStorage.Shared.Signal)

local TerritoryService = {}

TerritoryService.OwnerChanged = Signal.new("Territory.OwnerChanged")
TerritoryService.LevelChanged = Signal.new("Territory.LevelChanged")
TerritoryService.ElementChanged = Signal.new("Territory.ElementChanged")

local _graph, _economy

-- nodeId -> { Element, BaseValue, AreaId, Level, Owner }
local _territories = {}
local _sortedNodeIds = {}

function TerritoryService.Init(deps)
	deps = deps or {}
	_graph = deps.Graph
	_economy = deps.Economy

	_territories = {}
	_sortedNodeIds = {}

	if _graph == nil or not _graph.IsLoaded() then
		return
	end

	for _, nodeId in ipairs(_graph.GetAllNodeIds()) do
		local node = _graph.GetNode(nodeId)
		if node.Type == Enums.NodeType.Territory then
			_territories[nodeId] = {
				Element = node.Element,
				BaseValue = node.BaseValue or RulesConfig.Land.DefaultBaseValue,
				AreaId = node.Area,
				Level = 1,
				Owner = nil,
			}
			table.insert(_sortedNodeIds, nodeId)
		end
	end
	table.sort(_sortedNodeIds)
end

-- A snapshot, not the live record: callers read territory state constantly
-- and must not be able to write it by accident.
function TerritoryService.GetTerritory(nodeId)
	local state = _territories[nodeId]
	if state == nil then
		return nil
	end
	return {
		NodeId = nodeId,
		Element = state.Element,
		BaseValue = state.BaseValue,
		AreaId = state.AreaId,
		Level = state.Level,
		Owner = state.Owner,
	}
end

function TerritoryService.GetAllTerritories()
	local all = {}
	for _, nodeId in ipairs(_sortedNodeIds) do
		table.insert(all, TerritoryService.GetTerritory(nodeId))
	end
	return all
end

function TerritoryService.GetOwnedBy(userId)
	local owned = {}
	for _, nodeId in ipairs(_sortedNodeIds) do
		if _territories[nodeId].Owner == userId then
			table.insert(owned, nodeId)
		end
	end
	return owned
end

function TerritoryService.SetOwner(nodeId, userId)
	local state = _territories[nodeId]
	if state == nil then
		return
	end
	state.Owner = userId
	TerritoryService.OwnerChanged:Fire(nodeId, userId)
end

-- Releasing a departing player's land rather than leaving it owned by a ghost.
-- Every chain those territories were part of shrinks, so this fires the same
-- signal an ordinary capture would and downstream valuation recomputes.
function TerritoryService.ReleaseAllOwnedBy(userId)
	for _, nodeId in ipairs(TerritoryService.GetOwnedBy(userId)) do
		TerritoryService.SetOwner(nodeId, nil)
	end
end

-- Same element, same owner, SAME AREA. A neutral territory has no element and
-- so never chains, however many of them one player holds.
function TerritoryService.GetChainSize(userId, element, areaId)
	if userId == nil or element == nil then
		return 0
	end

	local count = 0
	for _, nodeId in ipairs(_sortedNodeIds) do
		local state = _territories[nodeId]
		if state.Owner == userId and state.Element == element and state.AreaId == areaId then
			count += 1
		end
	end
	return count
end

function TerritoryService.GetLandValue(nodeId)
	local state = _territories[nodeId]
	if state == nil then
		return 0
	end
	local chainSize = TerritoryService.GetChainSize(state.Owner, state.Element, state.AreaId)
	return RulesConfig.getLandValue(state.BaseValue, state.Level, chainSize)
end

function TerritoryService.GetToll(nodeId)
	local state = _territories[nodeId]
	if state == nil or state.Owner == nil then
		return 0
	end
	local chainSize = TerritoryService.GetChainSize(state.Owner, state.Element, state.AreaId)
	return RulesConfig.getToll(state.BaseValue, state.Level, chainSize)
end

-- === Territory commands =====================================================

function TerritoryService.GetDevelopmentCost(nodeId, targetLevel)
	local state = _territories[nodeId]
	if state == nil then
		return 0
	end
	return RulesConfig.getDevelopmentCost(state.BaseValue, state.Level, targetLevel)
end

-- A player may jump to any level they can afford in one command, not only
-- climb one at a time. The cost is the cumulative unchained increase either
-- way, so a jump is never cheaper or dearer than the steps it replaces.
function TerritoryService.LevelUp(userId, nodeId, targetLevel)
	local state = _territories[nodeId]
	if state == nil then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "not a territory")
	end
	if state.Owner ~= userId then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "you do not own this territory")
	end

	if type(targetLevel) ~= "number" or targetLevel % 1 ~= 0 then
		return ActionResult.fail(Enums.RejectReason.IllegalAction, "level must be a whole number")
	end
	if targetLevel <= state.Level then
		return ActionResult.fail(Enums.RejectReason.IllegalAction, "that is not an increase")
	end
	if targetLevel > RulesConfig.Land.MaxLevel then
		return ActionResult.fail(
			Enums.RejectReason.IllegalAction,
			string.format("level %d is above the maximum of %d", targetLevel, RulesConfig.Land.MaxLevel)
		)
	end

	local cost = RulesConfig.getDevelopmentCost(state.BaseValue, state.Level, targetLevel)
	local paid, reason = _economy.SpendMagic(userId, cost)
	if not paid then
		return ActionResult.fail(Enums.RejectReason.InsufficientMagic, tostring(reason))
	end

	state.Level = targetLevel
	TerritoryService.LevelChanged:Fire(nodeId, targetLevel)

	return ActionResult.ok({ NodeId = nodeId, Level = targetLevel, Cost = cost })
end

-- level x 100, plus a surcharge when the land ALREADY has an element. The
-- surcharge is about what is being overwritten, not what it becomes.
function TerritoryService.GetElementChangeCost(nodeId)
	local state = _territories[nodeId]
	if state == nil then
		return 0
	end
	return RulesConfig.getTerrainChangeCost(state.Level, state.Element ~= nil)
end

-- Performed on your OWN occupied land. The previous implementation allowed it
-- only on unclaimed land, which was exactly backwards — a workaround for the
-- land bonus being baked into defender HP, which Milestone 4 fixed. The bonus
-- is now computed per battle from the tile's current element, so changing the
-- element under a defender is simply picked up by the next battle.
function TerritoryService.ChangeElement(userId, nodeId, element)
	local state = _territories[nodeId]
	if state == nil then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "not a territory")
	end
	if state.Owner ~= userId then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "you do not own this territory")
	end
	if element ~= nil and not Enums.isValid(Enums.Element, element) then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "unknown element " .. tostring(element))
	end
	if element == state.Element then
		return ActionResult.fail(Enums.RejectReason.IllegalAction, "already that element")
	end

	local cost = TerritoryService.GetElementChangeCost(nodeId)
	local paid, reason = _economy.SpendMagic(userId, cost)
	if not paid then
		return ActionResult.fail(Enums.RejectReason.InsufficientMagic, tostring(reason))
	end

	state.Element = element
	TerritoryService.ElementChanged:Fire(nodeId, element)

	return ActionResult.ok({ NodeId = nodeId, Element = element, Cost = cost })
end

return TerritoryService

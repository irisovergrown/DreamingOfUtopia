--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > EconomyService (ModuleScript)

	Purpose:
		The Current Magic ledger, and what happens when a player cannot pay
		something they owe.

		CM is spendable cash and nothing else. What a player is WORTH is Total
		Magic, which ValuationService computes from CM plus land and symbols.
		This module deliberately does not know about land values, chains or
		victory — it moved out of here in Milestone 5 precisely because a
		ledger that also decided who was winning had no clean seam.

	Mandatory payments and liquidation:
		A toll is not an offer. The old PayToll returned "Not enough Magic"
		and left the debt unpaid, which is not a state the rules have — the
		brief is explicit that an unaffordable mandatory payment enters
		LIQUIDATION rather than being rejected.

		So RequirePayment pays what it can and reports a shortfall. The caller
		drives liquidation: sell territories until the debt is covered, or the
		player runs out of assets and is bankrupt. Selling is here rather than
		in TerritoryService because the decision is a financial one — the
		territory module should not know why it is losing land.

	Lap bonus:
		Applied automatically on LapService.LapCompleted, since a lap bonus is
		unconditional. Uses the brief's formula through RulesConfig, and reads
		owned-territory count from TerritoryService rather than counting tiles
		itself.

	Public API:
		EconomyService.Init(deps)     -- deps.Territory, deps.Lap, deps.Graph
		EconomyService.RegisterPlayer(userId, startingMagic?)
		EconomyService.RemovePlayer(userId)
		EconomyService.GetBalance(userId) -> number or nil
		EconomyService.AddMagic(userId, amount) -> newBalance
		EconomyService.SpendMagic(userId, amount) -> success, newBalanceOrReason
		EconomyService.RequirePayment(userId, amount) -> { Paid, Shortfall }
		EconomyService.PayToll(payerUserId, nodeId) -> ActionResult
		EconomyService.GetLiquidationValue(nodeId) -> integer
		EconomyService.LiquidateTerritory(userId, nodeId) -> ActionResult
		EconomyService.ComputeLapBonus(userId) -> number

	Signals:
		EconomyService.BalanceChanged:Connect(function(userId, newBalance) end)
		EconomyService.PaymentShortfall:Connect(function(userId, shortfall) end)
		EconomyService.Bankrupted:Connect(function(userId) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local ActionResult = require(ReplicatedStorage.Shared.ActionResult)
local RulesConfig = require(ReplicatedStorage.Shared.RulesConfig)
local Signal = require(ReplicatedStorage.Shared.Signal)

local EconomyService = {}

EconomyService.BalanceChanged = Signal.new("Economy.BalanceChanged")
EconomyService.PaymentShortfall = Signal.new("Economy.PaymentShortfall")
EconomyService.Bankrupted = Signal.new("Economy.Bankrupted")

local _territory, _lap, _graph
local _balances = {}
-- userId -> outstanding debt that liquidation has not yet covered
local _debts = {}

function EconomyService.Init(deps)
	deps = deps or {}
	_territory = deps.Territory
	_lap = deps.Lap
	_graph = deps.Graph

	_balances = {}
	_debts = {}

	if _lap ~= nil then
		_lap.LapCompleted:Connect(function(userId)
			EconomyService.AddMagic(userId, EconomyService.ComputeLapBonus(userId))
		end, 0, "Economy.LapBonus")
	end
end

function EconomyService.RegisterPlayer(userId, startingMagic)
	_balances[userId] = startingMagic or RulesConfig.Match.DefaultStartingMagic
	_debts[userId] = nil
	EconomyService.BalanceChanged:Fire(userId, _balances[userId])
end

function EconomyService.RemovePlayer(userId)
	_balances[userId] = nil
	_debts[userId] = nil
end

function EconomyService.GetBalance(userId)
	return _balances[userId]
end

function EconomyService.AddMagic(userId, amount)
	if _balances[userId] == nil then
		return nil
	end
	_balances[userId] += amount
	EconomyService.BalanceChanged:Fire(userId, _balances[userId])
	return _balances[userId]
end

-- Optional spending: a summon, an item, a level-up. Refused outright when
-- unaffordable, because the player chose to do it and can choose not to.
function EconomyService.SpendMagic(userId, amount)
	local balance = _balances[userId]
	if balance == nil then
		return false, "player is not registered"
	end
	if balance < amount then
		return false, "Not enough Magic"
	end

	_balances[userId] = balance - amount
	EconomyService.BalanceChanged:Fire(userId, _balances[userId])
	return true, _balances[userId]
end

-- Mandatory payment: a toll. Takes everything available and reports what is
-- still owed, rather than refusing. A debt is a state the match has to resolve
-- through liquidation, not an error the caller can shrug off.
function EconomyService.RequirePayment(userId, amount)
	local balance = _balances[userId] or 0
	local paid = math.min(balance, amount)
	local shortfall = amount - paid

	if paid > 0 then
		_balances[userId] = balance - paid
		EconomyService.BalanceChanged:Fire(userId, _balances[userId])
	end

	if shortfall > 0 then
		_debts[userId] = (_debts[userId] or 0) + shortfall
		EconomyService.PaymentShortfall:Fire(userId, shortfall)
	end

	return { Paid = paid, Shortfall = shortfall }
end

function EconomyService.GetDebt(userId)
	return _debts[userId] or 0
end

-- What a territory is worth when sold under duress. Configurable because the
-- ruleset's conversion rate is a balance decision, not a law.
function EconomyService.GetLiquidationValue(nodeId)
	if _territory == nil then
		return 0
	end
	return math.floor(_territory.GetLandValue(nodeId) * RulesConfig.Liquidation.SaleRate)
end

-- Sells one territory toward an outstanding debt. Ownership is released, so
-- every chain it belonged to shrinks and the remaining land is worth less —
-- which is why a player in trouble tends to stay in trouble.
function EconomyService.LiquidateTerritory(userId, nodeId)
	if _territory == nil then
		return ActionResult.fail(Enums.RejectReason.IllegalAction, "no territory service")
	end

	local territory = _territory.GetTerritory(nodeId)
	if territory == nil or territory.Owner ~= userId then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "you do not own this territory")
	end

	local proceeds = EconomyService.GetLiquidationValue(nodeId)
	_territory.SetOwner(nodeId, nil)

	local debt = _debts[userId] or 0
	local towardDebt = math.min(proceeds, debt)
	local remainder = proceeds - towardDebt

	if towardDebt > 0 then
		_debts[userId] = debt - towardDebt
		if _debts[userId] <= 0 then
			_debts[userId] = nil
		end
	end
	if remainder > 0 then
		EconomyService.AddMagic(userId, remainder)
	end

	return ActionResult.ok({
		NodeId = nodeId,
		Proceeds = proceeds,
		AppliedToDebt = towardDebt,
		RemainingDebt = _debts[userId] or 0,
	})
end

-- No land left and still in debt: there is nothing further to sell.
function EconomyService.IsBankrupt(userId)
	if (_debts[userId] or 0) <= 0 then
		return false
	end
	return _territory == nil or #_territory.GetOwnedBy(userId) == 0
end

function EconomyService.DeclareBankrupt(userId)
	_debts[userId] = nil
	EconomyService.Bankrupted:Fire(userId)
end

function EconomyService.PayToll(payerUserId, nodeId)
	if _territory == nil then
		return ActionResult.fail(Enums.RejectReason.IllegalAction, "no territory service")
	end

	local territory = _territory.GetTerritory(nodeId)
	if territory == nil or territory.Owner == nil then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "no toll is owed here")
	end
	if territory.Owner == payerUserId then
		return ActionResult.fail(Enums.RejectReason.InvalidTarget, "you own this territory")
	end

	local toll = _territory.GetToll(nodeId)
	local payment = EconomyService.RequirePayment(payerUserId, toll)

	-- The owner is credited what was actually collected. A player who has
	-- left the match has no balance to credit, so the money simply leaves the
	-- economy rather than reviving a departed record.
	if payment.Paid > 0 and _balances[territory.Owner] ~= nil then
		EconomyService.AddMagic(territory.Owner, payment.Paid)
	end

	return ActionResult.ok({
		Toll = toll,
		Paid = payment.Paid,
		Shortfall = payment.Shortfall,
		OwnerUserId = territory.Owner,
	})
end

function EconomyService.ComputeLapBonus(userId)
	local lapNumber = _lap and _lap.GetLapCount(userId) or 1
	local ownedCount = _territory and #_territory.GetOwnedBy(userId) or 0
	local startingMagic = RulesConfig.Match.DefaultStartingMagic

	return RulesConfig.getLapBonus(startingMagic, lapNumber, ownedCount, 0)
end

return EconomyService

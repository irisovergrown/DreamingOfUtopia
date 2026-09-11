--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > SnapshotService (ModuleScript)

	Purpose:
		Builds the per-player view of match state that goes over the wire.

		The important word is per-player. A snapshot has a public part every
		client receives identically, and a private part only its recipient
		gets. Hands, books and hidden statuses live in the private part; the
		public part carries counts, so opponents can see that you hold four
		cards without learning which.

		This split exists NOW, before hands exist, on purpose. Secrecy added
		after a system already broadcasts everything is a leak hunt; secrecy
		built into the only path state takes to a client is a property that
		holds by construction. The tests assert an opponent's snapshot omits
		private identities, and that assertion stays meaningful as Milestone
		3 fills the private section in.

		Nothing here decides rules. It reads the services that own state and
		shapes it for transport. If a value is not in a snapshot, the client
		does not know it — which is the point.

	Public API:
		SnapshotService.Init(sources)
		SnapshotService.Build(userId) -> snapshot table
		SnapshotService.BuildPublic() -> the shared portion only

		`sources` injects the services this reads, so a test can build
		snapshots from stubs rather than a live match:
			{ Orchestrator, Validator, Territory, Valuation, Victory, Graph, Movement, Economy, Battle, Card }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)

local SnapshotService = {}

local _sources = {}

function SnapshotService.Init(sources)
	_sources = sources or {}
end

-- Every player's visible standing. Deliberately counts and totals only —
-- adding a field here makes it visible to every opponent, so anything
-- identity-revealing belongs in the private section instead.
local function buildStandings()
	local orchestrator = _sources.Orchestrator
	local economy = _sources.Economy
	local territory = _sources.Territory
	local valuation = _sources.Valuation
	local victory = _sources.Victory
	local movement = _sources.Movement

	local standings = {}
	for _, userId in ipairs(_sources.GetParticipants and _sources.GetParticipants() or {}) do
		table.insert(standings, {
			UserId = userId,
			-- Current Magic is what you can spend; Total Magic is what you are
			-- worth and what wins. Both are public — standings that showed only
			-- cash would rank a landowner last.
			CurrentMagic = economy and economy.GetBalance(userId) or 0,
			TotalMagic = valuation and valuation.GetTotalMagic(userId) or 0,
			LandValue = valuation and valuation.GetLandValue(userId) or 0,
			TerritoriesOwned = territory and #territory.GetOwnedBy(userId) or 0,
			-- A player on the goal-reached walk home is a public threat, and
			-- the other players need to see it to react.
			GoalReached = victory and victory.IsGoalReachedState(userId) or false,
			-- Both accept a bare userId; standings are built from participant
			-- ids and there is no Player instance to hand.
			NodeId = movement and movement.GetCurrentNodeId and movement.GetCurrentNodeId(userId) or nil,
			LapCount = movement and movement.GetLapCount and movement.GetLapCount(userId) or 0,
			IsActive = orchestrator and orchestrator.IsActivePlayer(userId) or false,
			-- Count, never contents. This is the line hands must not cross.
			HandCount = _sources.GetHandCount and _sources.GetHandCount(userId) or 0,
		})
	end

	table.sort(standings, function(a, b)
		if a.TotalMagic ~= b.TotalMagic then
			return a.TotalMagic > b.TotalMagic
		end
		return a.UserId < b.UserId
	end)
	return standings
end

function SnapshotService.BuildPublic()
	local orchestrator = _sources.Orchestrator

	return {
		Phase = orchestrator and orchestrator.GetPhase() or Enums.Phase.WaitingForPlayers,
		Turn = orchestrator and orchestrator.GetTurnNumber() or 0,
		Round = orchestrator and orchestrator.GetRoundNumber() or 0,
		ActivePlayerId = orchestrator and orchestrator.GetActivePlayerId() or nil,
		MatchComplete = orchestrator and orchestrator.IsMatchComplete() or false,
		Standings = buildStandings(),
	}
end

-- A tile's public facts. Ownership, level and element are all public in
-- Culdcept: the board is information everyone shares.
local function buildTileView(nodeId)
	local territory = _sources.Territory
	local graph = _sources.Graph
	local battle = _sources.Battle
	local card = _sources.Card
	if nodeId == nil then
		return nil
	end

	-- Not every node is a territory. A castle or a fort still deserves a view
	-- so the HUD can say where you are, it just has no ownership to report.
	local state = territory and territory.GetTerritory(nodeId)
	if state == nil then
		local node = graph and graph.GetNode(nodeId)
		if node == nil then
			return nil
		end
		return { NodeId = nodeId, NodeType = node.Type, Toll = 0 }
	end

	local view = {
		NodeId = nodeId,
		NodeType = Enums.NodeType.Territory,
		Element = state.Element,
		Level = state.Level,
		Owner = state.Owner,
		BaseValue = state.BaseValue,
		LandValue = territory.GetLandValue(nodeId),
		Toll = territory.GetToll(nodeId),
	}

	local defender = battle and battle.GetDefender(nodeId)
	if defender then
		local defenderCard = card and card.GetCard(defender.CardId)
		view.DefenderName = defenderCard and defenderCard.Name or nil
		view.DefenderHP = defender.CurrentHP
	end

	return view
end

-- Whose hand is on screen. Normally the active player's, but a battle's
-- defender item window belongs to the DEFENDER — and a defender who cannot see
-- their own hand cannot choose an item from it. So the spotlight follows
-- whoever is currently entitled to decide, which is the same rule as "the
-- player taking their turn sees their cards", stated generally enough to cover
-- the one phase where the decider is not the turn holder.
local function spotlightUserId()
	local orchestrator = _sources.Orchestrator
	if orchestrator == nil then
		return nil
	end

	local validator = _sources.Validator
	if validator ~= nil then
		local actor = validator.getExpectedActor(orchestrator.GetPhase())
		if actor == Enums.Actor.Defender then
			return _sources.GetDefenderId and _sources.GetDefenderId() or nil
		end
	end

	return orchestrator.GetActivePlayerId()
end

-- Exactly one hand is on screen at a time. Its owner sees it face up;
-- everyone else sees the same number of card backs in the same place.
--
-- The secrecy is server-side, not a client-side flip. Card identities are put
-- in this table only when the recipient owns them, so an opponent's client is
-- never sent the answer it would need to cheat — `Cards` is genuinely absent,
-- not merely hidden. `Count` is public because a hand size is public
-- information in Culdcept; the contents are not.
local function buildHandView(recipientUserId, ownerUserId)
	if ownerUserId == nil then
		return nil
	end

	local isOwner = recipientUserId == ownerUserId
	local view = {
		OwnerUserId = ownerUserId,
		IsFaceUp = isOwner,
		Count = _sources.GetHandCount and _sources.GetHandCount(ownerUserId) or 0,
	}

	if isOwner and _sources.GetHand then
		view.Cards = _sources.GetHand(ownerUserId)
	end

	return view
end

function SnapshotService.Build(userId)
	local snapshot = SnapshotService.BuildPublic()

	local orchestrator = _sources.Orchestrator
	local validator = _sources.Validator
	local movement = _sources.Movement
	local economy = _sources.Economy

	-- The private section: this player's own view, never replicated to
	-- anyone else. Everything identity-revealing belongs here.
	snapshot.You = {
		UserId = userId,
		CurrentMagic = economy and economy.GetBalance(userId) or 0,
		IsYourTurn = orchestrator and orchestrator.IsActivePlayer(userId) or false,
		NodeId = movement and movement.GetCurrentNodeId and movement.GetCurrentNodeId(userId) or nil,
		NodeId = movement and movement.GetCurrentNodeId and movement.GetCurrentNodeId(userId) or nil,
		-- Your own hand, always sent to you because it is yours. What is
		-- DISPLAYED is decided by HandView, which shows only the active
		-- player's hand — so on someone else's turn you see their backs
		-- rather than your own cards.
		Hand = _sources.GetHand and _sources.GetHand(userId) or {},
		BookCount = _sources.GetBookCount and _sources.GetBookCount(userId) or 0,
		DiscardCount = _sources.GetDiscardCount and _sources.GetDiscardCount(userId) or 0,
		LegalIntents = {},
	}

	-- The routes on offer when movement has paused at a branch. Only ever the
	-- recipient's own pending choice: another player's junction is not
	-- actionable by this client and does not belong in their snapshot.
	if movement and movement.GetPendingChoice then
		local pending = movement.GetPendingChoice(userId)
		if pending ~= nil then
			local options = {}
			for _, exit in ipairs(pending.Options) do
				table.insert(options, { EdgeId = exit.EdgeId, To = exit.To })
			end
			snapshot.You.PendingRoute = {
				NodeId = pending.NodeId,
				RemainingSteps = pending.RemainingSteps,
				Options = options,
			}
		end
	end

	if orchestrator and validator then
		snapshot.You.LegalIntents = validator.getLegalIntentsForPlayer({
			Phase = orchestrator.GetPhase(),
			ActivePlayerId = orchestrator.GetActivePlayerId(),
			DefenderId = _sources.GetDefenderId and _sources.GetDefenderId() or nil,
			Participants = _sources.GetParticipantSet and _sources.GetParticipantSet() or nil,
			RequesterId = userId,
		}, userId)
	end

	snapshot.CurrentTile = buildTileView(snapshot.You.NodeId)
	snapshot.HandView = buildHandView(userId, spotlightUserId())

	return snapshot
end

return SnapshotService

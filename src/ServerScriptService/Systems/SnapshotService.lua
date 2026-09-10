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
			{ Orchestrator, Validator, Board, Movement, Economy, Battle, Card }
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
	local board = _sources.Board
	local movement = _sources.Movement

	local standings = {}
	for _, userId in ipairs(_sources.GetParticipants and _sources.GetParticipants() or {}) do
		local ownedCount = 0
		if board then
			for _, tile in ipairs(board.GetAllTiles()) do
				if tile.Owner == userId then
					ownedCount += 1
				end
			end
		end

		table.insert(standings, {
			UserId = userId,
			CurrentMagic = economy and economy.GetBalance(userId) or 0,
			TerritoriesOwned = ownedCount,
			-- Both accept a bare userId; standings are built from participant
			-- ids and there is no Player instance to hand.
			TileId = movement and movement.GetCurrentTile and movement.GetCurrentTile(userId) or nil,
			LapCount = movement and movement.GetLapCount and movement.GetLapCount(userId) or 0,
			IsActive = orchestrator and orchestrator.IsActivePlayer(userId) or false,
			-- Count, never contents. This is the line hands must not cross.
			HandCount = _sources.GetHandCount and _sources.GetHandCount(userId) or 0,
		})
	end

	table.sort(standings, function(a, b)
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
local function buildTileView(tileId)
	local board = _sources.Board
	local battle = _sources.Battle
	local card = _sources.Card
	if board == nil or tileId == nil then
		return nil
	end

	local tile = board.GetTile(tileId)
	if tile == nil then
		return nil
	end

	local view = {
		TileId = tile.Id,
		TileType = tile.TileType,
		Element = tile.Era,
		Level = tile.Level,
		Owner = tile.Owner,
		Toll = (tile.TileType == "Property" and tile.Owner ~= nil) and board.GetToll(tileId) or 0,
	}

	local defender = battle and battle.GetDefender(tileId)
	if defender then
		local defenderCard = card and card.GetCard(defender.CardId)
		view.DefenderName = defenderCard and defenderCard.Name or nil
		view.DefenderHP = defender.CurrentHP
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
		TileId = movement and movement.GetCurrentTile and movement.GetCurrentTile(userId) or nil,
		NodeId = movement and movement.GetCurrentNodeId and movement.GetCurrentNodeId(userId) or nil,
		-- Populated in Milestone 3. Present now so the shape, and the
		-- guarantee that it is per-recipient, exist before there is anything
		-- secret to put in it.
		Hand = {},
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

	snapshot.CurrentTile = buildTileView(snapshot.You.TileId)

	return snapshot
end

return SnapshotService

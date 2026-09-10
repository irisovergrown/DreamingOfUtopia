--[[
	ModuleScript — server, test spec.

	Studio placement:
		ServerScriptService > Tests > Specs > SnapshotServiceSpec (ModuleScript)

	The brief's "opponent snapshots omit private hand identities" criterion,
	asserted now while the private section is still empty. Built from stubs
	rather than a live match, so these run without a board or players.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local ActionValidator = require(ServerScriptService.Systems.ActionValidator)
local SnapshotService = require(ServerScriptService.Systems.SnapshotService)

local Phase = Enums.Phase
local Intent = Enums.Intent
local ALICE, BOB = 101, 202

-- Minimal stand-ins for the services SnapshotService reads. Stubs rather
-- than the real singletons so a snapshot can be built without a match.
local function stubSources(overrides)
	local phase = (overrides or {}).Phase or Phase.RollReady
	local activeId = (overrides or {}).ActivePlayerId or ALICE

	local hands = {
		[ALICE] = { "Tape Gnome", "Signal Boost", "Laser Salamander" },
		[BOB] = { "Dewdrop Undine" },
	}

	local sources = {
		Orchestrator = {
			GetPhase = function() return phase end,
			GetTurnNumber = function() return 3 end,
			GetRoundNumber = function() return 1 end,
			GetActivePlayerId = function() return activeId end,
			IsMatchComplete = function() return false end,
			IsActivePlayer = function(userId) return userId == activeId end,
		},
		Validator = ActionValidator,
		Economy = {
			GetBalance = function(userId) return userId == ALICE and 500 or 320 end,
		},
		Board = {
			GetAllTiles = function()
				return {
					{ Id = 1, TileType = "Start", Level = 1 },
					{ Id = 2, TileType = "Property", Era = "Earth", Level = 2, Owner = ALICE },
					{ Id = 3, TileType = "Property", Era = "Fire", Level = 1, Owner = BOB },
				}
			end,
			GetTile = function(tileId)
				local tiles = {
					[2] = { Id = 2, TileType = "Property", Era = "Earth", Level = 2, Owner = ALICE },
					[3] = { Id = 3, TileType = "Property", Era = "Fire", Level = 1, Owner = BOB },
				}
				return tiles[tileId]
			end,
			GetToll = function() return 60 end,
		},
		Movement = {
			GetCurrentTile = function(userId) return userId == ALICE and 2 or 3 end,
			GetCurrentNodeId = function(userId) return userId == ALICE and "T2" or "T3" end,
			GetLapCount = function() return 1 end,
		},
		Battle = { GetDefender = function() return nil end },
		Card = { GetCard = function() return nil end },
		GetParticipants = function() return { ALICE, BOB } end,
		GetParticipantSet = function() return { [ALICE] = true, [BOB] = true } end,
		GetHandCount = function(userId) return #hands[userId] end,
		GetHand = function(userId)
			local hand = {}
			for index, name in ipairs(hands[userId]) do
				table.insert(hand, { InstanceId = string.format("%d-%d", userId, index), CardId = index, Name = name })
			end
			return hand
		end,
		GetBookCount = function() return 44 end,
		GetDiscardCount = function() return 2 end,
		GetDefenderId = function() return nil end,
	}

	for key, value in pairs(overrides or {}) do
		if sources[key] ~= nil then
			sources[key] = value
		end
	end
	return sources, hands
end

return {
	Name = "SnapshotService",
	Tests = {
		{ "the public section carries phase, turn and round", function(t)
			SnapshotService.Init(stubSources())
			local snapshot = SnapshotService.Build(ALICE)

			t:Equal(snapshot.Phase, Phase.RollReady)
			t:Equal(snapshot.Turn, 3)
			t:Equal(snapshot.Round, 1)
			t:Equal(snapshot.ActivePlayerId, ALICE)
			t:False(snapshot.MatchComplete)
		end },

		{ "standings list every participant with public totals", function(t)
			SnapshotService.Init(stubSources())
			local snapshot = SnapshotService.Build(ALICE)

			t:Equal(#snapshot.Standings, 2)
			local alice = snapshot.Standings[1]
			t:Equal(alice.UserId, ALICE)
			t:Equal(alice.CurrentMagic, 500)
			t:Equal(alice.TerritoriesOwned, 1)
			t:True(alice.IsActive)
			t:False(snapshot.Standings[2].IsActive)
		end },

		{ "standings expose hand SIZE but never hand contents", function(t)
			-- The line hands must not cross. Opponents may know you hold four
			-- cards; they may not learn which.
			SnapshotService.Init(stubSources())
			local snapshot = SnapshotService.Build(ALICE)

			for _, standing in ipairs(snapshot.Standings) do
				t:NotNil(standing.HandCount, "hand count is public")
				t:Nil(standing.Hand, "hand contents must not appear in standings")
			end
			t:Equal(snapshot.Standings[1].HandCount, 3, "Alice holds three")
			t:Equal(snapshot.Standings[2].HandCount, 1, "Bob holds one")
		end },

		{ "the private section is addressed to its recipient", function(t)
			SnapshotService.Init(stubSources())

			t:Equal(SnapshotService.Build(ALICE).You.UserId, ALICE)
			t:Equal(SnapshotService.Build(BOB).You.UserId, BOB)
		end },

		{ "a snapshot contains no other player's private section", function(t)
			-- Structural: there is exactly one You, and it is the recipient's.
			-- If a second private block ever appears, this fails.
			SnapshotService.Init(stubSources())
			local bobsView = SnapshotService.Build(BOB)

			t:Equal(bobsView.You.UserId, BOB)
			t:Equal(bobsView.You.CurrentMagic, 320, "Bob sees his own balance")
			t:Nil(rawget(bobsView, "Hands"), "no aggregate hand table")
			t:Nil(rawget(bobsView, "Books"), "no aggregate book table")
		end },

		{ "IsYourTurn is per recipient, not a shared flag", function(t)
			SnapshotService.Init(stubSources({ ActivePlayerId = ALICE }))

			t:True(SnapshotService.Build(ALICE).You.IsYourTurn)
			t:False(SnapshotService.Build(BOB).You.IsYourTurn)
		end },

		{ "legal intents are computed for the recipient", function(t)
			-- So each client renders its own buttons from its own snapshot,
			-- and a waiting player is offered nothing.
			SnapshotService.Init(stubSources({ Phase = Phase.RollReady, ActivePlayerId = ALICE }))

			t:Contains(SnapshotService.Build(ALICE).You.LegalIntents, Intent.Roll)
			t:Equal(#SnapshotService.Build(BOB).You.LegalIntents, 0, "Bob is offered nothing on Alice's turn")
		end },

		{ "your own hand is sent to you in full", function(t)
			SnapshotService.Init(stubSources())
			local snapshot = SnapshotService.Build(ALICE)

			t:Equal(#snapshot.You.Hand, 3, "Alice receives her three cards")
			t:NotNil(snapshot.You.Hand[1].InstanceId)
			t:Equal(snapshot.You.BookCount, 44)
			t:Equal(snapshot.You.DiscardCount, 2)
		end },

		{ "exactly one hand is shown, and it is the active player's", function(t)
			-- Culdcept shows a single hand in a single place. Whose it is
			-- follows the turn, so the board reads the same from every seat.
			SnapshotService.Init(stubSources({ ActivePlayerId = ALICE }))

			t:Equal(SnapshotService.Build(ALICE).HandView.OwnerUserId, ALICE)
			t:Equal(SnapshotService.Build(BOB).HandView.OwnerUserId, ALICE, "Bob also sees Alice's hand, not his own")
		end },

		{ "the active player sees their hand face up", function(t)
			SnapshotService.Init(stubSources({ ActivePlayerId = ALICE }))
			local view = SnapshotService.Build(ALICE).HandView

			t:True(view.IsFaceUp)
			t:Equal(#view.Cards, 3, "with the actual cards")
			t:Equal(view.Count, 3)
		end },

		{ "everyone else sees backs, and is never sent the faces", function(t)
			-- The security property. Card identities are ABSENT from the
			-- opponent's snapshot rather than merely flagged hidden, so a
			-- modified client has nothing to reveal.
			SnapshotService.Init(stubSources({ ActivePlayerId = ALICE }))
			local view = SnapshotService.Build(BOB).HandView

			t:False(view.IsFaceUp, "Bob sees backs")
			t:Equal(view.Count, 3, "he can count them")
			t:Nil(view.Cards, "but the identities are simply not in his snapshot")
		end },

		{ "the visible hand follows the turn", function(t)
			SnapshotService.Init(stubSources({ ActivePlayerId = BOB }))

			local bobsView = SnapshotService.Build(BOB).HandView
			t:True(bobsView.IsFaceUp, "on Bob's turn Bob sees his own")
			t:Equal(#bobsView.Cards, 1)

			local alicesView = SnapshotService.Build(ALICE).HandView
			t:False(alicesView.IsFaceUp, "and Alice now sees backs")
			t:Nil(alicesView.Cards)
			t:Equal(alicesView.Count, 1, "one back, because Bob holds one card")
		end },

		{ "no hand is shown before a turn has begun", function(t)
			SnapshotService.Init(stubSources({ ActivePlayerId = false }))
			-- `false` rather than nil: a nil override cannot be expressed in a
			-- Lua table literal, so the stub treats false as "nobody active".
			local sources = stubSources()
			sources.Orchestrator = {
				GetPhase = function() return Phase.WaitingForPlayers end,
				GetTurnNumber = function() return 0 end,
				GetRoundNumber = function() return 0 end,
				GetActivePlayerId = function() return nil end,
				IsMatchComplete = function() return false end,
				IsActivePlayer = function() return false end,
			}
			SnapshotService.Init(sources)

			t:Nil(SnapshotService.Build(ALICE).HandView, "nothing to show yet")
		end },

		{ "the current tile view reflects the recipient's own position", function(t)
			SnapshotService.Init(stubSources())

			t:Equal(SnapshotService.Build(ALICE).CurrentTile.TileId, 2)
			t:Equal(SnapshotService.Build(BOB).CurrentTile.TileId, 3)
		end },

		{ "tile views carry element, level, owner and toll", function(t)
			SnapshotService.Init(stubSources())
			local tile = SnapshotService.Build(ALICE).CurrentTile

			t:Equal(tile.Element, "Earth")
			t:Equal(tile.Level, 2)
			t:Equal(tile.Owner, ALICE)
			t:Equal(tile.Toll, 60)
		end },

		{ "BuildPublic contains no private section at all", function(t)
			SnapshotService.Init(stubSources())
			local public = SnapshotService.BuildPublic()

			t:Nil(public.You, "the shared portion has no recipient block")
			t:NotNil(public.Standings)
		end },

		{ "a snapshot survives missing sources rather than throwing", function(t)
			-- Snapshots are built on every state change; one absent service
			-- must not take the match down.
			SnapshotService.Init({})
			local snapshot = SnapshotService.Build(ALICE)

			t:Equal(snapshot.Phase, Phase.WaitingForPlayers)
			t:Equal(snapshot.Turn, 0)
			t:DeepEqual(snapshot.Standings, {})
			t:Equal(snapshot.You.UserId, ALICE)
			t:Nil(snapshot.CurrentTile)
		end },
	},
}

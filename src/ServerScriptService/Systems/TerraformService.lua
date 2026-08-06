--[[
	ModuleScript — server, part of the modular system architecture.

	Studio placement:
		ServerScriptService > Systems > TerraformService (ModuleScript)

	Purpose:
		Changing a Property tile's era for Magic, per the gameplay
		reference: cost scales with the tile's level, and costs more to
		terraform TO a specific era than to revert it to neutral (blank).
		All cost constants are placeholders, same tuning caveat as every
		other formula module.

		Deliberately restricted to UNCLAIMED tiles only. An owned tile has
		a defending creature (BattleService._defenders) whose cached
		CurrentHP already baked in the land bonus at summon time; changing
		the tile's era out from under that creature would leave that HP
		stale (BattleService recomputes on summon/challenge, not on a
		later era change). Fixing that needs touching BattleService's
		defender state deliberately, not as a side effect of this module —
		not done here. So: terraform before you claim, not after.

	Public API:
		TerraformService.GetTerraformCost(tileId, targetEra) -> number
		TerraformService.TerraformTile(player, tileId, targetEra) -> success, reason
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EraData = require(ReplicatedStorage.Shared.EraData)
local BoardService = require(ServerScriptService.Systems.BoardService)
local EconomyService = require(ServerScriptService.Systems.EconomyService)

local TerraformService = {}

local BASE_TERRAFORM_COST = 50
local COST_PER_LEVEL = 30
-- Committing to a specific (non-neutral) era costs more than reverting to neutral.
local FIXED_ERA_SURCHARGE = 50

function TerraformService.GetTerraformCost(tileId, targetEra)
	local tile = BoardService.GetTile(tileId)
	if tile == nil then
		return 0
	end

	local cost = BASE_TERRAFORM_COST + tile.Level * COST_PER_LEVEL
	if targetEra ~= nil then
		cost += FIXED_ERA_SURCHARGE
	end
	return cost
end

function TerraformService.TerraformTile(player, tileId, targetEra)
	if targetEra ~= nil and EraData.Eras[targetEra] == nil then
		return false, "Unknown era"
	end

	local tile = BoardService.GetTile(tileId)
	if tile == nil or tile.TileType ~= "Property" then
		return false, "Tile cannot be terraformed"
	end

	if tile.Owner ~= nil then
		return false, "Tile is already claimed — terraform it before claiming"
	end

	if tile.Era == targetEra then
		return false, "Tile is already that era"
	end

	local cost = TerraformService.GetTerraformCost(tileId, targetEra)
	local success, reason = EconomyService.SpendMagic(player, cost)
	if not success then
		return false, reason
	end

	BoardService.SetEra(tileId, targetEra)
	return true, nil
end

return TerraformService

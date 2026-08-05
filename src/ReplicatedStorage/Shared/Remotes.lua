--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > Remotes (ModuleScript)

	Purpose:
		The only client-server bridge in the project so far. Creates
		(server) or waits for (client) a fixed set of RemoteEvents under
		ReplicatedStorage > Remotes, and returns them as a lookup table so
		both sides reference the exact same instances by name instead of
		magic strings scattered across scripts.

		Server-authoritative by construction: request handlers on the
		server must read `player` from OnServerEvent's own first argument
		(the real invoking client, provided by Roblox and impossible for a
		client to spoof), never from a client-supplied argument — see how
		Main.server.lua uses these.

	Events:
		RollRequest       client -> server, no args
		SummonRequest     client -> server, (cardId: number)
		ChallengeRequest  client -> server, (cardId: number)
		PayTollRequest    client -> server, no args
		StateUpdated      server -> client, (state: table snapshot)
		ActionResult      server -> client, (message: string)

	Usage:
		local Remotes = require(game:GetService("ReplicatedStorage").Shared.Remotes)
		Remotes.RollRequest:FireServer() -- client
		Remotes.RollRequest.OnServerEvent:Connect(function(player) end) -- server
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_EVENT_NAMES = {
	"RollRequest",
	"SummonRequest",
	"ChallengeRequest",
	"PayTollRequest",
	"StateUpdated",
	"ActionResult",
}

local Remotes = {}

if RunService:IsServer() then
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage

	for _, name in ipairs(REMOTE_EVENT_NAMES) do
		local remoteEvent = Instance.new("RemoteEvent")
		remoteEvent.Name = name
		remoteEvent.Parent = folder
		Remotes[name] = remoteEvent
	end
else
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	for _, name in ipairs(REMOTE_EVENT_NAMES) do
		Remotes[name] = folder:WaitForChild(name)
	end
end

return Remotes

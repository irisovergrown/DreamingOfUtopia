--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > Remotes (ModuleScript)

	Purpose:
		The client-server bridge, now intent-shaped.

		This replaced eight action-shaped RemoteEvents (RollRequest,
		SummonRequest, ChallengeRequest, ...) with a single SubmitIntent
		channel. The old shape had one entry point per action, so every new
		action meant another remote and another hand-written turn check, and
		the checks drifted: EndTurnRequest was the one handler that forgot to
		verify whose turn it was.

		One channel means one validation path. Every request goes through the
		same phase check, the same actor check, and the same sequence check,
		so an action cannot be added that accidentally skips one.

		Server-authoritative by construction: handlers read the acting player
		from OnServerEvent's own first argument, which Roblox provides and a
		client cannot spoof. Nothing in the payload identifies who is asking.

	Why requests carry a sequence and an expected phase:
		Sequence — a double click, a laggy retry or a replayed packet
		produces two identical requests, and without an ordinal the server
		cannot tell a retry from a genuine second action. A sequence at or
		below the last accepted one is refused (see MatchOrchestrator).

		ExpectedPhase — the client states the phase it believed it was in.
		If the server has since moved on, the request is stale by definition:
		the player clicked based on a screen that no longer reflects reality.
		Checking it turns a race into a clean rejection rather than an action
		applied in the wrong phase.

	Events:
		SubmitIntent   client -> server, (intent: string, sequence: number,
		                                  expectedPhase: string, payload: table?)
		StateUpdated   server -> client, (snapshot: table)   -- per-player
		ActionResult   server -> client, (result: table)     -- typed outcome

	Usage:
		local Remotes = require(game:GetService("ReplicatedStorage").Shared.Remotes)
		Remotes.SubmitIntent:FireServer("Roll", 4, "RollReady")
		Remotes.SubmitIntent.OnServerEvent:Connect(function(player, intent, sequence, expectedPhase, payload) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_EVENT_NAMES = {
	"SubmitIntent",
	"StateUpdated",
	"ActionResult",
}

local Remotes = {}

if RunService:IsServer() then
	-- Reuse rather than blindly re-create: this module is required by several
	-- server scripts, and a second Folder would leave clients waiting on
	-- instances nothing ever fires.
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end

	for _, name in ipairs(REMOTE_EVENT_NAMES) do
		local remoteEvent = folder:FindFirstChild(name)
		if remoteEvent == nil then
			remoteEvent = Instance.new("RemoteEvent")
			remoteEvent.Name = name
			remoteEvent.Parent = folder
		end
		Remotes[name] = remoteEvent
	end

	-- Remove remotes from the previous action-shaped bridge, so a stale
	-- client cannot keep firing at an endpoint nothing listens to.
	for _, child in ipairs(folder:GetChildren()) do
		if Remotes[child.Name] == nil then
			child:Destroy()
		end
	end
else
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	for _, name in ipairs(REMOTE_EVENT_NAMES) do
		Remotes[name] = folder:WaitForChild(name)
	end
end

return Remotes

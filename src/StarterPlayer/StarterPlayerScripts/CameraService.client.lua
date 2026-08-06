--[[
	LocalScript — client, standalone (first slice of a future dedicated camera system).

	Studio placement:
		StarterPlayer > StarterPlayerScripts > CameraService (LocalScript)

	Purpose:
		Match-wide, turn-synced "stage" camera per the brief: a single
		angled top-down/side view that snaps to focus on whichever player
		currently has the turn — NOT free per-player camera control, and
		NOT "look at your own Cepter." Every client computes the same
		framing independently from the same server-pushed turn state
		(Remotes.StateUpdated's CurrentTurnUserId), so everyone sees the
		same thing at the same time without any camera-specific networking.

		Finds its target by reading the Cepter token Part Main.server.lua
		already spawns under Workspace ("Cepter_"..userId) — Workspace
		replicates to every client automatically, so no new server data is
		needed beyond the turn's userId. Once focused on a token, it
		listens to that token's own Position changes (also just normal
		replication, no new networking) so the camera keeps following it
		live as that player rolls and moves during their turn, not just
		once at turn-start.

		Decoupled from board geometry entirely: works the same whether
		tiles are procedural or hand-placed (see BoardService/Main.server.lua)
		since it only ever looks at a Cepter token's live Position, never
		tile data.

		Takes full manual control of the camera (Scriptable) — there's no
		free-roam gameplay in this game (all interaction is through the
		UIService HUD), so nothing is lost by not using the default
		follow-avatar camera. Player characters/avatars are untouched;
		only the camera is hijacked.

		Roblox can swap in a brand-new Camera instance under
		Workspace.CurrentCamera around character spawn — a reference grabbed
		once at script start can go stale, silently leaving the *new*
		camera in default follow mode while this script keeps driving the
		old, no-longer-active one. So `camera` is re-acquired (and
		re-forced Scriptable) every time Workspace.CurrentCamera changes,
		not just once at startup.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- Offset from the focused Cepter, angled top-down/side "stage" framing.
-- Placeholder values, same tuning caveat as every gameplay formula.
local CAMERA_OFFSET = Vector3.new(0, 22, 20)
local PAN_TIME = 0.6

local camera = nil
local currentTween = nil
local currentPositionConnection = nil
local lastTurnUserId = nil

local function claimCamera()
	camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
end

claimCamera()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(claimCamera)
print("[DreamingOfUtopia] CameraService active")

local function focusOn(targetPosition, instant)
	local goalCFrame = CFrame.lookAt(targetPosition + CAMERA_OFFSET, targetPosition)

	if currentTween ~= nil then
		currentTween:Cancel()
		currentTween = nil
	end

	if instant then
		camera.CFrame = goalCFrame
		return
	end

	currentTween = TweenService:Create(camera, TweenInfo.new(PAN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		CFrame = goalCFrame,
	})
	currentTween:Play()
end

local function trackToken(token)
	if currentPositionConnection ~= nil then
		currentPositionConnection:Disconnect()
		currentPositionConnection = nil
	end

	if token == nil then
		return
	end

	currentPositionConnection = token:GetPropertyChangedSignal("Position"):Connect(function()
		focusOn(token.Position, false)
	end)
end

-- Default framing before any turn state has arrived.
focusOn(Vector3.new(0, 0, 0), true)

Remotes.StateUpdated.OnClientEvent:Connect(function(state)
	local turnUserId = state.CurrentTurnUserId
	if turnUserId == nil or turnUserId == lastTurnUserId then
		return
	end
	lastTurnUserId = turnUserId

	local token = Workspace:FindFirstChild("Cepter_" .. turnUserId, true)
	if token == nil then
		warn("[DreamingOfUtopia] CameraService: no Cepter token found for turn user " .. turnUserId)
		return
	end

	print("[DreamingOfUtopia] CameraService focusing on Cepter_" .. turnUserId)
	trackToken(token)
	focusOn(token.Position, false)
end)

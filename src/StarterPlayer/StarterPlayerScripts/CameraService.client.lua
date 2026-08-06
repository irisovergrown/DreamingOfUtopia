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

		Finds its target by reading the Cepter token Model Main.server.lua
		clones under Workspace ("Cepter_"..userId, from a developer-authored
		R6 Character+Humanoid template under ReplicatedStorage.Models.Player
		— see Main.server.lua's header) — Workspace replicates to every
		client automatically, so no new server data is needed beyond the
		turn's userId. Once focused on a token, it reads its
		HumanoidRootPart child specifically and listens to that part's own
		Position changes (also just normal replication, no new networking)
		so the camera keeps following it live as that player rolls and
		moves during their turn, not just once at turn-start.

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

		Token lookup uses WaitForChild (with a timeout), not a one-shot
		FindFirstChild — the server fires StateUpdated right after creating
		a new Cepter token, but instance replication and RemoteEvent
		delivery aren't guaranteed to arrive in that order, so the token
		can genuinely not exist on the client yet for a brief moment.

		Setting CameraType = Scriptable once (or even re-setting it whenever
		CurrentCamera changes) isn't enough on its own — Roblox's own
		default camera control script, present in every place whether we
		added it or not, keeps re-asserting itself and will flip CameraType
		back to Custom on its own, which snaps the view straight back to
		following the character. RenderStepped below continuously re-claims
		Scriptable every frame so that reset never has a chance to stick.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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

RunService.RenderStepped:Connect(function()
	if camera ~= nil and camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
end)

print("[DreamingOfUtopia] CameraService active")

local cepterFolder = Workspace:WaitForChild("Cepters", 10)
if cepterFolder == nil then
	warn("[DreamingOfUtopia] CameraService: Workspace.Cepters folder never appeared")
end

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

local function trackToken(rootPart)
	if currentPositionConnection ~= nil then
		currentPositionConnection:Disconnect()
		currentPositionConnection = nil
	end

	if rootPart == nil then
		return
	end

	currentPositionConnection = rootPart:GetPropertyChangedSignal("Position"):Connect(function()
		focusOn(rootPart.Position, false)
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

	if cepterFolder == nil then
		return
	end

	local token = cepterFolder:WaitForChild("Cepter_" .. turnUserId, 5)
	if token == nil then
		warn("[DreamingOfUtopia] CameraService: no Cepter token found for turn user " .. turnUserId)
		return
	end

	local rootPart = token:WaitForChild("HumanoidRootPart", 5)
	if rootPart == nil then
		warn("[DreamingOfUtopia] CameraService: Cepter_" .. turnUserId .. " has no HumanoidRootPart")
		return
	end

	print("[DreamingOfUtopia] CameraService focusing on Cepter_" .. turnUserId)
	trackToken(rootPart)
	focusOn(rootPart.Position, false)
end)

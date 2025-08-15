-- StarterPlayer/StarterPlayerScripts/Controllers/AdminClient.lua
-- Listens for admin client commands (e.g., Fly toggle) and applies them locally.
-- This script runs on every client; only reacts when the server targets this client.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Remotes = RS:WaitForChild("Remotes")
local AdminFolder = Remotes:WaitForChild("Admin")
local ClientControl = AdminFolder:WaitForChild("ClientControl")

-- --- Fly controller ---
local flyEnabled = false
local flyConn : RBXScriptConnection? = nil
local bv : BodyVelocity? = nil
local bg : BodyGyro? = nil
local speedBase = 60

local keys = {
	W = false, A = false, S = false, D = false,
	Up = false, Down = false, Shift = false
}

local function getCharParts()
	local char = LocalPlayer.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	return char, hrp, hum
end

local function stopFly()
	flyEnabled = false
	if flyConn then flyConn:Disconnect(); flyConn = nil end
	if bg then bg:Destroy(); bg = nil end
	if bv then bv:Destroy(); bv = nil end
	local char, hrp, hum = getCharParts()
	if hum then hum.PlatformStand = false end
end

local function startFly()
	local char, hrp, hum = getCharParts()
	if not (char and hrp and hum) then return end

	-- Prep movers
	bg = Instance.new("BodyGyro")
	bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
	bg.P = 1e4
	bg.Parent = hrp

	bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bv.P = 1e4
	bv.Velocity = Vector3.new()
	bv.Parent = hrp

	hum.PlatformStand = true
	flyEnabled = true

	flyConn = RunService.RenderStepped:Connect(function(dt)
		if not flyEnabled then return end
		local camera = Workspace.CurrentCamera
		if not camera then return end

		local look = camera.CFrame.LookVector
		local right = camera.CFrame.RightVector

		local move = Vector3.new()
		if keys.W then move += look end
		if keys.S then move -= look end
		if keys.A then move -= right end
		if keys.D then move += right end
		if keys.Up then move += Vector3.new(0,1,0) end
		if keys.Down then move -= Vector3.new(0,1,0) end

		if move.Magnitude > 0 then move = move.Unit end
		local speed = speedBase * (keys.Shift and 2 or 1)
		bv.Velocity = move * speed
		bg.CFrame = CFrame.new(hrp.Position, hrp.Position + look)
	end)
end

-- Input tracking
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.W then keys.W = true end
	if input.KeyCode == Enum.KeyCode.A then keys.A = true end
	if input.KeyCode == Enum.KeyCode.S then keys.S = true end
	if input.KeyCode == Enum.KeyCode.D then keys.D = true end
	if input.KeyCode == Enum.KeyCode.Space then keys.Up = true end
	if input.KeyCode == Enum.KeyCode.LeftControl then keys.Down = true end
	if input.KeyCode == Enum.KeyCode.LeftShift then keys.Shift = true end
end)
UserInputService.InputEnded:Connect(function(input, gp)
	if input.KeyCode == Enum.KeyCode.W then keys.W = false end
	if input.KeyCode == Enum.KeyCode.A then keys.A = false end
	if input.KeyCode == Enum.KeyCode.S then keys.S = false end
	if input.KeyCode == Enum.KeyCode.D then keys.D = false end
	if input.KeyCode == Enum.KeyCode.Space then keys.Up = false end
	if input.KeyCode == Enum.KeyCode.LeftControl then keys.Down = false end
	if input.KeyCode == Enum.KeyCode.LeftShift then keys.Shift = false end
end)

-- Handle server commands
ClientControl.OnClientEvent:Connect(function(msg)
	if typeof(msg) ~= "table" then return end
	if msg.cmd == "fly" then
		if msg.enabled then
			if not flyEnabled then startFly() end
		else
			if flyEnabled then stopFly() end
		end
	end
end)

-- Safety: stop fly on respawn
LocalPlayer.CharacterAdded:Connect(function()
	if flyEnabled then stopFly() end
end)

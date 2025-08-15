-- ServerScriptService/Services/AdminService.lua
-- AdminService v5d (ToF-specific, fixes Remotes creation + implements givePrinter)
-- Uses EconomyService & Profiles directly. Adds printer via Profiles and rebuilds plot.
-- UI actions supported: addChips, setChips/reset, freeze, invisibility, noclip(+fly), teleports, givePrinter.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Ensure Remotes/Admin exists safely
local Remotes = RS:WaitForChild("Remotes")
local AdminFolder = Remotes:FindFirstChild("Admin")
if not AdminFolder then
	AdminFolder = Instance.new("Folder")
	AdminFolder.Name = "Admin"
	AdminFolder.Parent = Remotes
end

local AdminAction = AdminFolder:FindFirstChild("AdminAction")
if not AdminAction then
	AdminAction = Instance.new("RemoteFunction")
	AdminAction.Name = "AdminAction"
	AdminAction.Parent = AdminFolder
end

local ClientControl = AdminFolder:FindFirstChild("ClientControl")
if not ClientControl then
	ClientControl = Instance.new("RemoteEvent")
	ClientControl.Name = "ClientControl"
	ClientControl.Parent = AdminFolder
end

-- Project services & configs
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Economy  = require(script.Parent:WaitForChild("EconomyService"))
local ChairsCfg    = require(RS:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Chairs"))
local PrintersCfg  = require(RS.Shared.Config.Printers)
local Signals      = RS:WaitForChild("Signals")
local RebuildPlot  = Signals:WaitForChild("RebuildPlot")

-- Admin whitelist
local function loadWhitelist()
	local Config = RS.Shared.Config
	local m = require(Config.Admin)
	local list = {}
	if m and type(m.AdminUserIds) == "table" then
		for _, uid in ipairs(m.AdminUserIds) do
			if typeof(uid) == "number" then table.insert(list, uid) end
		end
	end
	return list
end
local function isAuthorized(player)
	for _,id in ipairs(loadWhitelist()) do if id == player.UserId then return true end end
	return false
end

-- Helpers
local function findPlayerByUserId(userId)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == userId then return p end
	end
	return nil
end

-- Movement helpers
local noclipLoops = {} -- [player] = RBXScriptConnection
local function enableNoClip(p)
	if noclipLoops[p] then return end
	local conn = RunService.Stepped:Connect(function()
		local char = p.Character; if not char then return end
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then part.CanCollide = false end
		end
	end)
	noclipLoops[p] = conn
end
local function disableNoClip(p)
	local conn = noclipLoops[p]; if conn then conn:Disconnect(); noclipLoops[p] = nil end
	local char = p.Character
	if char then for _,part in ipairs(char:GetDescendants()) do if part:IsA("BasePart") then part.CanCollide = true end end end
end
Players.PlayerRemoving:Connect(function(p) disableNoClip(p) end)

local function setInvisibility(targetPlayer, enabled)
	local char = targetPlayer and targetPlayer.Character; if not char then return false, "no character" end
	targetPlayer:SetAttribute("AdminInvisible", enabled and true or false)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "HumanoidRootPart" then d.Transparency = 1 else d.Transparency = enabled and 1 or 0 end
		elseif d:IsA("Decal") then
			d.Transparency = enabled and 1 or 0
		elseif d:IsA("ParticleEmitter") or d:IsA("Trail") then
			d.Enabled = not enabled
		end
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = enabled and Enum.HumanoidDisplayDistanceType.None or Enum.HumanoidDisplayDistanceType.Viewer
	end
	return true
end
local function setNoClipAndFly(targetPlayer, enabled)
	targetPlayer:SetAttribute("AdminNoClip", enabled and true or false)
	if enabled then enableNoClip(targetPlayer) else disableNoClip(targetPlayer) end
	ClientControl:FireClient(targetPlayer, { cmd = "fly", enabled = enabled })
	return true
end
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function()
		if p:GetAttribute("AdminInvisible") then setInvisibility(p, true) end
		if p:GetAttribute("AdminNoClip") then enableNoClip(p); ClientControl:FireClient(p, { cmd = "fly", enabled = true }) end
	end)
end)

-- CHIP ACTIONS (canonical for this project)
local function addChipsImpl(p, amount)
	amount = math.floor(tonumber(amount) or 0); if amount == 0 then return true end
	return Economy.AddChips(p, amount, (amount>0 and "AdminGive") or "AdminTake")
end
local function setChipsImpl(p, amount)
	amount = math.floor(tonumber(amount) or 0)
	local profile = Profiles.Get(p); if not profile then return false, "no profile" end
	local cur = math.floor(tonumber(profile.Data.Chips) or 0)
	local delta = amount - cur
	return Economy.AddChips(p, delta, "AdminSet")
end

-- Give printer
local function givePrinterImpl(p, printerId)
	local profile = Profiles.Get(p); if not profile then return false, "no profile" end
	local d = profile.Data; d.Printers = d.Printers or {}
	local chair = d.Chair or { Tier = 0 }
	local tier = tonumber(chair.Tier) or 0
	local slotCap = (ChairsCfg[tier] and ChairsCfg[tier].Slots) or 1
	if #d.Printers >= slotCap then
		return false, "no free slots"
	end
	local cfg = PrintersCfg[printerId]
	if not cfg then return false, "unknown printer" end
	local rec = {
		Id = printerId,
		PPS = cfg.PPS,
		Capacity = cfg.Capacity,
		Stored = 0,
		LastTick = os.clock(),
	}
	table.insert(d.Printers, rec)
	-- spawn the machine
	pcall(function() RebuildPlot:Fire(p.UserId) end)
	return true
end

-- ACTIONS
local function okStub() return true end
local ACTIONS = {
	ping = function(caller) return true end,

	-- Movement & visibility
	freeze = function(caller, payload)
		local p = findPlayerByUserId(tonumber(payload.userId)); if not p then return false, "player not found" end
		local char = p.Character; if not char then return false, "no character" end
		local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return false, "no humanoid" end
		hum.WalkSpeed = payload.enabled and 0 or 16
		hum.JumpPower = payload.enabled and 0 or 50
		return true
	end,
	invisibility = function(caller, payload)
		local p = findPlayerByUserId(tonumber(payload.userId)); if not p then return false, "player not found" end
		return setInvisibility(p, payload.enabled and true or false)
	end,
	noclip = function(caller, payload)
		local p = findPlayerByUserId(tonumber(payload.userId)); if not p then return false, "player not found" end
		return setNoClipAndFly(p, payload.enabled and true or false)
	end,
	tpToPlayer = function(caller, payload)
		local target = findPlayerByUserId(tonumber(payload.userId)); if not target then return false, "player not found" end
		local hrp1 = caller.Character and caller.Character:FindFirstChild("HumanoidRootPart")
		local hrp2 = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		if not hrp1 or not hrp2 then return false, "hrp missing" end
		hrp1.CFrame = hrp2.CFrame + Vector3.new(0,3,0); return true
	end,
	tpToMe = function(caller, payload)
		local target = findPlayerByUserId(tonumber(payload.userId)); if not target then return false, "player not found" end
		local hrp1 = caller.Character and caller.Character:FindFirstChild("HumanoidRootPart")
		local hrp2 = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		if not hrp1 or not hrp2 then return false, "hrp missing" end
		hrp2.CFrame = hrp1.CFrame + Vector3.new(0,3,0); return true
	end,

	-- Economy
	addChips = function(caller, payload)
		local uid = tonumber(payload.userId); local amt = tonumber(payload.amount); if not uid or not amt then return false, "bad args" end
		local p = findPlayerByUserId(uid); if not p then return false, "player not found" end
		return addChipsImpl(p, amt)
	end,
	setChips = function(caller, payload)
		local uid = tonumber(payload.userId); local amt = tonumber(payload.amount); if not uid or amt==nil then return false, "bad args" end
		local p = findPlayerByUserId(uid); if not p then return false, "player not found" end
		return setChipsImpl(p, amt)
	end,
	resetChips = function(caller, payload)
		local uid = tonumber(payload.userId); if not uid then return false, "bad args" end
		local p = findPlayerByUserId(uid); if not p then return false, "player not found" end
		return setChipsImpl(p, 0)
	end,

	-- Utilities
	givePrinter = function(caller, payload)
		local uid = tonumber(payload.userId); local id = tostring(payload.printerId or "")
		if not uid or id == "" then return false, "bad args" end
		local p = findPlayerByUserId(uid); if not p then return false, "player not found" end
		return givePrinterImpl(p, id)
	end,
	giveItem = okStub, startEvent = okStub, giveKey = okStub,
	banTemp = okStub, banPerm = okStub, unban = okStub,
}

AdminAction.OnServerInvoke = function(player, action, payload)
	if not isAuthorized(player) then return { ok=false, err="not authorized" } end
	local fn = ACTIONS[action]; if not fn then return { ok=false, err="unknown action: "..tostring(action) } end
	local ok, resOrErr = fn(player, payload or {})
	if ok == true then return { ok=true, data=resOrErr } else return { ok=false, err=resOrErr or "error" } end
end

return true

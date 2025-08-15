-- ServerScriptService/Services/WorldService.lua
-- Builds a minimal but clean world + a ring of plot pads.
-- Assigns each player a pad and teleports them onto it on spawn.
-- Exposes Signals/GetPlotOrigin (BindableFunction) returning a CFrame for a given userId.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Config = require(RS.Shared.Config.Map)

-- Ensure Signals folder + GetPlotOrigin function exist
local Signals = RS:FindFirstChild("Signals") or Instance.new("Folder")
Signals.Name = "Signals"
Signals.Parent = RS
local GetPlotOriginBF = Signals:FindFirstChild("GetPlotOrigin")
if not GetPlotOriginBF then
	GetPlotOriginBF = Instance.new("BindableFunction")
	GetPlotOriginBF.Name = "GetPlotOrigin"
	GetPlotOriginBF.Parent = Signals
end

-- Map containers
local MapFolder = WS:FindFirstChild("Map") or Instance.new("Folder")
MapFolder.Name = "Map"
MapFolder.Parent = WS

local PadsFolder = MapFolder:FindFirstChild("PlotPads") or Instance.new("Folder")
PadsFolder.Name = "PlotPads"
PadsFolder.Parent = MapFolder

-- Simple plaza base
local function ensureBase()
	local base = MapFolder:FindFirstChild("Plaza")
	if not base then
		base = Instance.new("Part")
		base.Name = "Plaza"
		base.Anchored = true
		base.Size = Vector3.new(1000, 2, 1000)
		base.Position = Vector3.new(0, Config.BaseHeight, 0)
		base.Material = Enum.Material.SmoothPlastic
		base.Color = Config.BaseColor
		base.TopSurface = Enum.SurfaceType.Smooth
		base.BottomSurface = Enum.SurfaceType.Smooth
		base.Parent = MapFolder
	end
	return base
end

-- Create plot pads in a ring
local function buildPads()
	-- If pads already exist and count matches, keep them
	local existing = PadsFolder:GetChildren()
	if #existing >= Config.NumPads then return end

	for i=#existing+1, Config.NumPads do
		local pad = Instance.new("Part")
		pad.Name = ("PlotPad_%02d"):format(i)
		pad.Anchored = true
		pad.Size = Config.PadSize
		pad.Material = Enum.Material.SmoothPlastic
		pad.Color = Config.PadColor
		pad.TopSurface = Enum.SurfaceType.Smooth
		pad.BottomSurface = Enum.SurfaceType.Smooth
		-- Position around a ring
		local theta = (i-1) * (2*math.pi/Config.NumPads)
		local x = math.cos(theta) * Config.Radius
		local z = math.sin(theta) * Config.Radius
		pad.CFrame = CFrame.new(x, Config.BaseHeight + Config.PadSize.Y/2, z)
		-- small bevel/rounded look via corner insets (visual only)
		local ui = Instance.new("UICorner"); ui.CornerRadius = UDim.new(0, 12); ui.Parent = pad
		pad.Parent = PadsFolder

		-- Attachment used as the plot origin
		local origin = Instance.new("Attachment")
		origin.Name = "PlotOrigin"
		origin.Position = Vector3.new(0, Config.PadSize.Y/2 + 0.1, 0) -- a hair above pad
		origin.Parent = pad

		-- Optional label
		if Config.LabelPlots then
			local bb = Instance.new("BillboardGui")
			bb.Name = "PadLabel"
			bb.Size = UDim2.new(0, 120, 0, 28)
			bb.StudsOffset = Vector3.new(0, 6, 0)
			bb.AlwaysOnTop = true
			bb.Parent = pad
			local tl = Instance.new("TextLabel")
			tl.BackgroundTransparency = 1
			tl.Size = UDim2.new(1,0,1,0)
			tl.Font = Enum.Font.GothamBold
			tl.TextSize = 16
			tl.Text = ("Pad %d"):format(i)
			tl.TextColor3 = Color3.fromRGB(240, 246, 255)
			tl.TextStrokeTransparency = 0.65
			tl.Parent = bb
		end

		-- tag for debugging/tools
		pcall(function() CollectionService:AddTag(pad, "PlotPad") end)
		pad:SetAttribute("PadIndex", i)
	end
end

ensureBase()
buildPads()

-- Track pad assignments
local PadAssignments : {[number]: number} = {} -- userId -> padIndex
local function findFreePad()
	local used = {}
	for _,idx in pairs(PadAssignments) do used[idx] = true end
	for i=1, Config.NumPads do
		if not used[i] then return i end
	end
	return nil
end

local function getPad(index)
	return PadsFolder:FindFirstChild(("PlotPad_%02d"):format(index))
end

local function getPadOriginCFrame(index)
	local pad = getPad(index)
	if not pad then return nil end
	local att = pad:FindFirstChild("PlotOrigin")
	if att then
		return att.WorldCFrame
	end
	return pad.CFrame + Vector3.new(0, pad.Size.Y/2 + 0.1, 0)
end

local function assignPad(player)
	-- Keep previous assignment if still valid
	local current = PadAssignments[player.UserId]
	if current and getPad(current) then return current end

	local idx = findFreePad()
	if not idx then return nil end
	PadAssignments[player.UserId] = idx
	return idx
end

local function unassignPad(userId)
	PadAssignments[userId] = nil
end

-- Expose origin to other services via Signal
GetPlotOriginBF.OnInvoke = function(userId:number)
	local idx = PadAssignments[userId]
	if not idx then return nil end
	return getPadOriginCFrame(idx)
end

-- Teleport players to their pad on spawn (optional)
local function moveToPad(player)
	if not Config.SpawnAtPad then return end
	local idx = assignPad(player); if not idx then return end
	local cf = getPadOriginCFrame(idx); if not cf then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = cf + Vector3.new(0, 3, 0)
	end
end

Players.PlayerAdded:Connect(function(p)
	assignPad(p)
	p.CharacterAdded:Connect(function()
		task.defer(moveToPad, p)
	end)
end)

Players.PlayerRemoving:Connect(function(p)
	unassignPad(p.UserId)
end)

return true

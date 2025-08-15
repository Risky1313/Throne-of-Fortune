-- ServerScriptService/BaseSpawnService.server.lua
-- v1.9 — Throne at fixed Y=6.0, yaw=270° + centered sit + E to Sit/Stand
-- Path: Workspace/Map/Bases
-- What this does:
--   • Clone throne from Workspace/Assets/"Wooden Chair"
--   • Place at Base#/Throne anchor (X/Z from anchor), with Y=6.0 and yaw=270°
--   • Create an invisible anchored Seat ("ThroneSeat") centered on the throne
--       - Seat offsets can be tuned via attributes on Base#/Throne:
--           SeatYOffset (default 0.7), SeatForwardOffset (default 0.0)
--   • Add a ProximityPrompt ("ThronePrompt_E") on Base#/Throne:
--       - Press E to Sit; press E again to Stand
--       - Faces the same direction as the throne (seat inherits throne yaw)
--   • Update Base sign + thumbnail
-- Keep only ONE BaseSpawn script active.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local WS      = game:GetService("Workspace")

print("[BaseSpawn v1.9] Booting...")

-- CONFIG ----------------------------------------------------------------------
local THRONE_NAME        = "Wooden Chair"
local FIXED_Y            = 6.0
local FIXED_YAW_DEG      = 270
local DEFAULT_SEAT_Y_OFF = 0.7     -- Fine-tune per your mesh
local DEFAULT_SEAT_F_OFF = 0.0     -- Negative pulls seat backward (toward chair back)

-- Signals
local Signals = RS:FindFirstChild("Signals") or Instance.new("Folder")
Signals.Name = "Signals"
Signals.Parent = RS
local GetPlotOrigin = Signals:FindFirstChild("GetPlotOrigin") or Instance.new("BindableFunction")
GetPlotOrigin.Name = "GetPlotOrigin"
GetPlotOrigin.Parent = Signals

-- Resolve Bases
local Map = WS:FindFirstChild("Map") or WS:WaitForChild("Map", 10)
local BasesFolder = Map and (Map:FindFirstChild("Bases") or Map:WaitForChild("Bases", 10))
if not BasesFolder then
	warn("[BaseSpawn v1.9] Workspace/Map/Bases missing."); return
end

-- Build ordered list
local BASES = {}
for _, inst in ipairs(BasesFolder:GetChildren()) do
	if inst:IsA("Model") or inst:IsA("Folder") then
		local idx = inst:GetAttribute("BaseIndex")
		if typeof(idx) ~= "number" then
			local suffix = string.match(inst.Name, "[Bb]ase%s*(%d+)$")
			idx = tonumber(suffix)
		end
		if idx then
			local spFolder = inst:FindFirstChild("Spawn")
			local sp = spFolder and spFolder:FindFirstChild("SpawnPoint")
			if sp then
				table.insert(BASES, {model=inst, spawn=sp, index=idx})
			end
		end
	end
end
table.sort(BASES, function(a,b) return a.index < b.index end)

print(("[BaseSpawn v1.9] Discovered %d bases."):format(#BASES))
if #BASES == 0 then return end

local ASSIGN = {}

-- Helpers --------------------------------------------------------------------
local function findDesc(parent, pathArray)
	local node = parent
	for _, name in ipairs(pathArray) do
		if not node then return nil end
		node = node:FindFirstChild(name)
	end
	return node
end

local function originFor(rec)
	if not rec then return nil end
	local att = rec.model:FindFirstChild("PlotOrigin", true)
	if att and att:IsA("Attachment") then
		return att.WorldCFrame
	end
	return rec.spawn.CFrame
end

local function setAnchored(inst, value)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = value end
	end
	if inst:IsA("BasePart") then inst.Anchored = value end
end

local function placeThroneFixed(throneInst, anchor)
	-- World placement: X/Z from anchor, Y fixed, rotation yaw fixed
	local aPos = anchor.Position
	local targetCF = CFrame.new(aPos.X, FIXED_Y, aPos.Z) * CFrame.Angles(0, math.rad(FIXED_YAW_DEG), 0)

	if throneInst:IsA("Model") then
		if not throneInst.PrimaryPart then
			local pp = throneInst:FindFirstChildWhichIsA("BasePart", true)
			if pp then throneInst.PrimaryPart = pp end
		end
		if throneInst.PrimaryPart then
			throneInst:PivotTo(targetCF)
		else
			-- fallback: pivot by shifting parts
			local pivot = throneInst:GetPivot()
			for _, p in ipairs(throneInst:GetDescendants()) do
				if p:IsA("BasePart") then
					local rel = pivot:ToObjectSpace(p.CFrame)
					p.CFrame = targetCF * rel
				end
			end
		end
	elseif throneInst:IsA("BasePart") then
		throneInst.CFrame = targetCF
	end
end

local function ensureThronePrompt(baseModel, anchor, seat)
	local prompt = anchor:FindFirstChild("ThronePrompt_E")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ThronePrompt_E"
		prompt.ActionText = "Sit / Stand"
		prompt.ObjectText = "Throne"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = anchor
	end

	-- Handler: toggle sit/stand
	prompt.Triggered:Connect(function(plr)
		local char = plr.Character
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum then return end

		if hum.Sit and hum.SeatPart then
			-- Stand up
			hum.Sit = false
			-- small step forward to avoid immediate re-seat
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = hrp.CFrame + hrp.CFrame.LookVector * 2
			end
			return
		end

		-- Sit: use Seat:Sit for a clean weld
		if seat and seat:IsA("Seat") then
			seat:Sit(hum)
		end
	end)
end

local function ensureSeat(baseModel, anchorCF, throneClone)
	-- Read offsets from anchor attributes if present
	local anchor = baseModel:FindFirstChild("Throne", true)
	local yOff = (anchor and anchor:GetAttribute("SeatYOffset")) or DEFAULT_SEAT_Y_OFF
	local fOff = (anchor and anchor:GetAttribute("SeatForwardOffset")) or DEFAULT_SEAT_F_OFF

	-- Create/find the seat under the throne clone
	local seat = throneClone:FindFirstChild("ThroneSeat", true)
	if not seat then
		seat = Instance.new("Seat")
		seat.Name = "ThroneSeat"
		seat.Anchored = true
		seat.CanCollide = false
		seat.Size = Vector3.new(2, 1, 2)
		seat.Transparency = 1
		seat.Parent = throneClone
	end

	-- Align seat with throne yaw, centered, with offsets
	local seatCF = anchorCF * CFrame.Angles(0, math.rad(FIXED_YAW_DEG), 0) * CFrame.new(0, yOff, fOff)
	seat.CFrame = seatCF

	return seat
end

local function cloneThroneIntoBase(baseModel)
	local assets = WS:FindFirstChild("Assets")
	local src = assets and assets:FindFirstChild(THRONE_NAME)
	if not src then
		warn("[BaseSpawn v1.9] Assets/"..THRONE_NAME.." not found"); return nil end

	local anchor = baseModel:FindFirstChild("Throne", true)
	if not (anchor and anchor:IsA("BasePart")) then
		warn("[BaseSpawn v1.9] "..baseModel.Name.." missing 'Throne' anchor"); return nil end

	-- Clear previous
	for _, ch in ipairs(baseModel:GetChildren()) do
		if ch:GetAttribute("IsThrone") then ch:Destroy() end
	end

	local clone = src:Clone()
	clone.Name = THRONE_NAME
	clone.Parent = baseModel
	setAnchored(clone, true)

	placeThroneFixed(clone, anchor)

	clone:SetAttribute("IsThrone", true)

	-- Seat
	local anchorCF = CFrame.new(anchor.Position.X, FIXED_Y, anchor.Position.Z)
	local seat = ensureSeat(baseModel, anchorCF, clone)

	-- Prompt
	ensureThronePrompt(baseModel, anchor, seat)

	return clone, seat
end

local function updateThroneText(baseModel, t)
	local tf = findDesc(baseModel, {"Throne","TextHolder","TextFrame"})
	if not tf then return end
	local label = tf:FindFirstChild("ThroneText")
	if label and label:IsA("TextLabel") then
		label.Text = t
	end
end

local function styleBaseForPlayer(plr, rec)
	local throneClone = cloneThroneIntoBase(rec.model)
	updateThroneText(rec.model, THRONE_NAME)

	-- Update sign
	local surfGui = findDesc(rec.model, {"Signs","SignsPart","PlayerNameBase","SurfaceGui"})
	if surfGui then
		local nameLabel = surfGui:FindFirstChild("TextLabel")
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = string.format("%s (%s)", plr.DisplayName, plr.Name)
		end
		local thumb = surfGui:FindFirstChild("Thumbnail")
		if thumb and (thumb:IsA("ImageLabel") or thumb:IsA("ImageButton")) then
			local ok, content = pcall(function()
				return Players:GetUserThumbnailAsync(plr.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
			end)
			if ok and typeof(content) == "string" then
				thumb.Image = content
			end
		end
	end

	rec.model:SetAttribute("OwnerUserId", plr.UserId)
end

-- Expose
GetPlotOrigin.OnInvoke = function(userId)
	for idx, rec in ipairs(BASES) do
		if rec.model:GetAttribute("OwnerUserId") == userId then
			return (rec.spawn.CFrame)
		end
	end
	return nil
end

-- Assign/teleport -------------------------------------------------------------
local function assignIndex(userId)
	if ASSIGN[userId] and BASES[ASSIGN[userId]] then return ASSIGN[userId] end
	local used = {}
	for _, i in pairs(ASSIGN) do used[i] = true end
	for i=1, math.min(8, #BASES) do
		if not used[i] then ASSIGN[userId] = i; return i end
	end
	return nil
end

local function moveTo(plr)
	local i = assignIndex(plr.UserId)
	if not i then
		plr:Kick("This server is full (8 bases). Please try another server.")
		return
	end
	local rec = BASES[i]
	local cf = rec.spawn.CFrame
	local char = plr.Character or plr.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if hrp and cf then
		hrp.CFrame = cf + Vector3.new(0,3,0)
	end
	plr:SetAttribute("AssignedBaseIndex", i)
	plr:SetAttribute("AssignedBaseName", rec.model.Name)

	styleBaseForPlayer(plr, rec)
end

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function()
		task.defer(moveTo, plr)
	end)
end)

Players.PlayerRemoving:Connect(function(plr)
	local i = ASSIGN[plr.UserId]
	if i and BASES[i] then
		BASES[i].model:SetAttribute("OwnerUserId", nil)
	end
	ASSIGN[plr.UserId] = nil
end)

print("[BaseSpawn v1.9] Ready.")

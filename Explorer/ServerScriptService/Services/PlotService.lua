-- ServerScriptService/Services/PlotService.lua
-- v2.0 — World-stand printers + starter printer
-- Requirements:
--   • Workspace/Assets/CoinPrinter  (Model or BasePart) — used for all printer tiers
--   • Bases: Workspace/Map/Bases/Base#/Platforms/Left/Stand1..4/PlaceHolder
--            Workspace/Map/Bases/Base#/Platforms/Right/Stand5..8/PlaceHolder
--      (If your Right stands are actually 1..4, this script will fall back automatically)
-- Behavior:
--   • On first join (no printers), grants 1 lowest-tier printer.
--   • For each owned printer, clones CoinPrinter into its slot stand and adds UI + prompt.
--   • Cleans up previous clones safely between rebuilds.
--   • Keeps labels fresh every ~1.5s.
-- Notes:
--   • Cloned instances are tagged with Attribute IsPrinterClone=true.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local WS      = game:GetService("Workspace")

local Profiles    = require(script.Parent.Profiles)
local PrintersCfg = require(RS.Shared.Config.Printers)

local Signals = RS:WaitForChild("Signals")
local RebuildPlotBE = Signals:WaitForChild("RebuildPlot")

-- --------------- Helpers ----------------

local function getBaseModelFor(plr)
	local idx = plr:GetAttribute("AssignedBaseIndex")
	if not idx then return nil end
	local map = WS:FindFirstChild("Map"); if not map then return nil end
	local bases = map:FindFirstChild("Bases"); if not bases then return nil end
	return bases:FindFirstChild(("Base%d"):format(idx))
end

local function findStandFolder(baseModel, slot)
	if not baseModel then return nil, nil end
	local platforms = baseModel:FindFirstChild("Platforms"); if not platforms then return nil, nil end
	local side, standName
	if slot <= 4 then
		side = "Left";  standName = ("Stand%d"):format(slot)
	else
		side = "Right"; standName = ("Stand%d"):format(slot)
	end
	local sideFolder = platforms:FindFirstChild(side)
	if not sideFolder then return nil, nil end

	local stand = sideFolder:FindFirstChild(standName)

	-- Fallback: if Right/Stand5..8 don't exist, try Right/Stand1..4 for slots 5..8
	if not stand and slot > 4 then
		standName = ("Stand%d"):format(slot - 4)
		stand = sideFolder:FindFirstChild(standName)
	end
	if not stand then return nil, nil end

	local holder = stand:FindFirstChild("PlaceHolder") or stand:FindFirstChild("Placeholder") or stand
	return stand, holder
end

local function getCoinPrinterAsset()
	local assets = WS:FindFirstChild("Assets"); if not assets then return nil end
	return assets:FindFirstChild("CoinPrinter")
end

local function setAnchoredRecursive(inst, value)
	if inst:IsA("BasePart") then inst.Anchored = value end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = value end
	end
end

local function primaryPartOrAny(modelish)
	if modelish:IsA("Model") then
		local m = modelish
		if m.PrimaryPart then return m.PrimaryPart end
		local pp = m:FindFirstChild("Root") or m:FindFirstChild("Main")
		if pp and pp:IsA("BasePart") then m.PrimaryPart = pp; return pp end
		local any = m:FindFirstChildWhichIsA("BasePart", true)
		if any then m.PrimaryPart = any; return any end
	elseif modelish:IsA("BasePart") then
		return modelish
	end
	return nil
end

local function clearSlot(baseModel, slot)
	local stand, _ = findStandFolder(baseModel, slot)
	if not stand then return end
	for _, ch in ipairs(stand:GetChildren()) do
		if ch:GetAttribute("IsPrinterClone") then
			ch:Destroy()
		end
	end
end

local function attachUIAndPrompt(part, slot, cfg, stored, capacity)
	-- Clean previous
	for _, ch in ipairs(part:GetChildren()) do
		if ch:IsA("BillboardGui") or ch:IsA("ProximityPrompt") then
			ch:Destroy()
		end
	end

	part:SetAttribute("Slot", slot)

	-- Billboard
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 200, 0, 50)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = part
	bb.Parent = part

	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.new(1, 0, 1, 0)
	tl.Font = Enum.Font.GothamBold
	tl.TextScaled = true
	tl.TextColor3 = Color3.new(1,1,1)
	tl.TextStrokeTransparency = 0.6
	tl.Text = ("%s | %d/%d"):format(cfg.Display or cfg.Name or ("P"..slot), math.floor(stored or 0), capacity or 0)
	tl.Parent = bb

	-- ProximityPrompt (sell on hold R; HUD handles E collect while visible)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PrinterInteract"
	prompt.ActionText = "Collect (Press E) / Sell (Hold R)"
	prompt.ObjectText = cfg.Display or (cfg.Name or ("Printer "..tostring(slot)))
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt.HoldDuration = 4
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
end

local function spawnPrinterAtSlot(baseModel, slot, pr)
	local stand, holder = findStandFolder(baseModel, slot)
	if not stand or not holder then return end

	local asset = getCoinPrinterAsset()
	if not asset then return end

	-- Clean old
	clearSlot(baseModel, slot)

	-- Clone + place
	local clone = asset:Clone()
	clone.Name = "CoinPrinter_Clone_Slot"..slot
	clone:SetAttribute("IsPrinterClone", true)
	clone.Parent = stand

	setAnchoredRecursive(clone, true)

	local anchorCF
	if holder:IsA("BasePart") then
		anchorCF = holder.CFrame
	else
		if stand:IsA("Model") then
			anchorCF = stand:GetModelCFrame()
		else
			anchorCF = holder.CFrame or stand.CFrame
		end
	end

	if clone:IsA("Model") then
		local pp = primaryPartOrAny(clone)
		if pp then
			clone:PivotTo(anchorCF)
			attachUIAndPrompt(pp, slot, PrintersCfg[pr.Id] or pr or {}, pr.Stored or 0, pr.Capacity or (PrintersCfg[pr.Id] and PrintersCfg[pr.Id].Capacity) or 0)
		end
	elseif clone:IsA("BasePart") then
		clone.CFrame = anchorCF
		attachUIAndPrompt(clone, slot, PrintersCfg[pr.Id] or pr or {}, pr.Stored or 0, pr.Capacity or (PrintersCfg[pr.Id] and PrintersCfg[pr.Id].Capacity) or 0)
	end
end

-- --------------- Business logic ----------------

local function lowestTierId()
	-- If your config has an explicit order, replace this with that logic.
	-- For now, pick the first key encountered.
	for id, _ in pairs(PrintersCfg) do
		return id
	end
	return nil
end

local function ensureDefaultPrinter(profile)
	local d = profile.Data
	d.Printers = d.Printers or {}
	if #d.Printers == 0 then
		local id = lowestTierId()
		if id == nil then return end
		local cfg = PrintersCfg[id] or {}
		table.insert(d.Printers, {
			Id = id,
			Stored = 0,
			Capacity = cfg.Capacity or 100,
		})
		if profile.Save then
			pcall(function() profile:Save() end)
		end
	end
end

local function rebuildFor(plr)
	local profile = Profiles.Get(plr); if not profile or not profile.Data then return end
	local d = profile.Data

	ensureDefaultPrinter(profile)

	local baseModel = getBaseModelFor(plr); if not baseModel then return end

	-- Clear all 8 slots
	for slot = 1, 8 do
		clearSlot(baseModel, slot)
	end

	-- Spawn sequentially
	for i, pr in ipairs(d.Printers) do
		if i >= 1 and i <= 8 then
			spawnPrinterAtSlot(baseModel, i, pr)
		end
	end
end

local function updateLabels(plr)
	local profile = Profiles.Get(plr); if not profile or not profile.Data then return end
	local d = profile.Data
	local baseModel = getBaseModelFor(plr); if not baseModel then return end

	for i, pr in ipairs(d.Printers) do
		local stand, holder = findStandFolder(baseModel, i)
		if stand then
			for _, ch in ipairs(stand:GetChildren()) do
				if ch:GetAttribute("IsPrinterClone") then
					local part = primaryPartOrAny(ch) or (ch:IsA("BasePart") and ch) or nil
					if part then
						local bb = part:FindFirstChildOfClass("BillboardGui")
						if bb then
							local tl = bb:FindFirstChildOfClass("TextLabel")
							if tl then
								local cfg = PrintersCfg[pr.Id] or {}
								tl.Text = ("%s | %d/%d"):format(cfg.Display or pr.Id, math.floor(pr.Stored or 0), pr.Capacity or 0)
							end
						end
					end
				end
			end
		end
	end
end

-- --------------- Hooks ----------------

Players.PlayerAdded:Connect(function(plr)
	task.defer(function() rebuildFor(plr) end)
end)

Players.PlayerRemoving:Connect(function(plr)
	-- world clones persist; next owner rebuild clears
end)

RebuildPlotBE.Event:Connect(function(userId)
	local plr = Players:GetPlayerByUserId(userId)
	if plr then rebuildFor(plr) end
end)

task.spawn(function()
	while true do
		task.wait(1.5)
		for _, plr in ipairs(Players:GetPlayers()) do
			updateLabels(plr)
		end
	end
end)

return {}

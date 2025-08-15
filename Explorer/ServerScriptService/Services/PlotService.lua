-- ServerScriptService/Services/PlotService.lua
-- v1.3 — world-slot printers (no runtime base/throne)
-- Printers are attached to pre-made stand placeholders inside the player's assigned base:
--   Workspace/Map/Bases/Base#/Platforms/(Left|Right)/Stand#/PlaceHolder/PrinterPlatform/CoinPrinter
-- Slots 1..4 -> Left/Stand1..4, Slots 5..8 -> Right/Stand1..4.
-- We attach label + ProximityPrompt directly onto the CoinPrinter part.
-- On rebuild, we clear prompts/labels on all stands, then reapply for owned printers.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local WS      = game:GetService("Workspace")

local Profiles    = require(script.Parent.Profiles)
local PrintersCfg = require(RS.Shared.Config.Printers)

local Signals = RS:WaitForChild("Signals")
local RebuildPlotBE = Signals:WaitForChild("RebuildPlot") :: BindableEvent

-- Utility: find the base model for a player via AssignedBaseIndex attribute
local function getBaseModelFor(plr)
	local idx = plr:GetAttribute("AssignedBaseIndex")
	if not idx then return nil end
	local map = WS:FindFirstChild("Map"); if not map then return nil end
	local bases = map:FindFirstChild("Bases"); if not bases then return nil end
	return bases:FindFirstChild(("Base%d"):format(idx))
end

local function findStandPart(baseModel, slot)
	if not baseModel then return nil end
	local side; local sidx
	if slot <= 4 then side="Left"; sidx=slot else side="Right"; sidx=slot-4 end
	local platforms = baseModel:FindFirstChild("Platforms")
	if not platforms then return nil end
	local sideFolder = platforms:FindFirstChild(side); if not sideFolder then return nil end
	local stand = sideFolder:FindFirstChild(("Stand%d"):format(sidx)); if not stand then return nil end
	local holder = stand:FindFirstChild("PlaceHolder"); if not holder then return nil end
	local plat = holder:FindFirstChild("PrinterPlatform"); if not plat then return nil end
	local coin = plat:FindFirstChild("CoinPrinter")
	if coin and coin:IsA("BasePart") then return coin end
	return nil
end

local function clearPrinterUI(coinPart)
	if not coinPart then return end
	for _, ch in ipairs(coinPart:GetChildren()) do
		if ch:IsA("BillboardGui") or ch:IsA("ProximityPrompt") then
			ch:Destroy()
		end
	end
	coinPart:SetAttribute("Slot", nil)
end

local function ensurePrinterUI(coinPart, slot, cfg, stored, capacity)
	if not coinPart then return end
	coinPart:SetAttribute("Slot", slot)
	-- Billboard
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 200, 0, 50)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = coinPart
	bb.Parent = coinPart
	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.new(1, 0, 1, 0)
	tl.Font = Enum.Font.GothamBold
	tl.TextScaled = true
	tl.TextColor3 = Color3.new(1,1,1)
	tl.TextStrokeTransparency = 0.6
	tl.Text = ("%s | %d/%d"):format(cfg.Display or cfg.Name or ("P"..slot), math.floor(stored or 0), capacity or 0)
	tl.Parent = bb

	-- Prompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PrinterInteract"
	prompt.ActionText = "Collect (Press E) / Sell (Hold R)"
	prompt.ObjectText = cfg.Display or (cfg.Name or ("Printer "..tostring(slot)))
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt.HoldDuration = 4
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = coinPart
end

local function rebuildFor(plr)
	local profile = Profiles.Get(plr); if not profile or not profile.Data then return end
	local d = profile.Data
	d.Printers = d.Printers or {}

	local baseModel = getBaseModelFor(plr); if not baseModel then return end

	-- Clear UI from all 8 stands first
	for slot=1,8 do
		clearPrinterUI(findStandPart(baseModel, slot))
	end

	-- Re-apply UI for owned printers in order
	for i, pr in ipairs(d.Printers) do
		local slot = i -- sequential mapping (future: drag to any free stand)
		if slot >= 1 and slot <= 8 then
			local coin = findStandPart(baseModel, slot)
			local cfg = PrintersCfg[pr.Id] or { Display = pr.Id, Capacity = pr.Capacity }
			ensurePrinterUI(coin, slot, cfg, pr.Stored or 0, pr.Capacity or cfg.Capacity or 0)
		end
	end
end

-- Label updater (only touches existing stands with Slot attribute)
local function updateLabels(plr)
	local profile = Profiles.Get(plr); if not profile or not profile.Data then return end
	local d = profile.Data
	local baseModel = getBaseModelFor(plr); if not baseModel then return end

	for i, pr in ipairs(d.Printers) do
		local coin = findStandPart(baseModel, i)
		if coin then
			local bb = coin:FindFirstChildOfClass("BillboardGui")
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

-- Hooks -----------------------------------------------------------------------
Players.PlayerAdded:Connect(function(plr)
	task.defer(function() rebuildFor(plr) end)
end)

Players.PlayerRemoving:Connect(function(plr)
	-- No cleanup; world stands persist.
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

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local PrintersCfg = require(RS.Shared.Config.Printers)
local ChairsCfg = require(RS.Shared.Config.Chairs)
local Profiles = require(script.Parent.Profiles)
local Economy = require(script.Parent.EconomyService)
local EventService = require(script.Parent.EventService)

-- Ticking printers server-side
local TICK_INTERVAL = 1

-- Collect a specific printer slot
local Remotes = RS:WaitForChild("Remotes")
local Collect = Instance.new("RemoteEvent")
Collect.Name = "CollectPrinter"
Collect.Parent = Remotes

local Place = Instance.new("RemoteFunction")
Place.Name = "PlacePrinter"
Place.Parent = Remotes

-- PPS calculation
local function calcPPS(basePPS, chairMult, eventMult)
	return basePPS * (chairMult or 1) * (eventMult or 1)
end

-- Heartbeat loop
task.spawn(function()
	local acc = 0
	game:GetService("RunService").Heartbeat:Connect(function(dt)
		acc += dt
		if acc < TICK_INTERVAL then return end
		acc = 0
		for _, plr in ipairs(Players:GetPlayers()) do
			local profile = Profiles.Get(plr)
			if profile and profile.Data then
				local d = profile.Data
				local chair = ChairsCfg[d.Chair.Tier] or ChairsCfg[0]
				local chairMult = chair.Multiplier or 1
				local eventMult = (EventService.State.Modifiers and EventService.State.Modifiers.PrinterPPS) or 1
				for _, p in ipairs(d.Printers) do
					if p.Stored < p.Capacity then
						local pps = calcPPS(p.PPS, chairMult, eventMult)
						p.Stored = math.min(p.Capacity, p.Stored + pps * TICK_INTERVAL)
					end
				end
			end
		end
	end)
end)

Collect.OnServerEvent:Connect(function(plr, slotIndex)
	local profile = Profiles.Get(plr); if not profile then return end
	local d = profile.Data
	local p = d.Printers[slotIndex]
	if not p then return end
	local amt = math.floor(p.Stored)
	if amt <= 0 then return end
	p.Stored = 0
	Economy.AddChips(plr, amt, "PrinterCollect")
end)

Place.OnServerInvoke = function(plr, printerId)
	local profile = Profiles.Get(plr); if not profile then return {ok=false, err="No profile"} end
	local cfg = PrintersCfg[printerId]; if not cfg then return {ok=false, err="Unknown printer"} end
	local d = profile.Data
	if #d.Printers >= (d.SlotsUnlocked or 1) then
		return {ok=false, err="No free slots. Upgrade chair."}
	end
	if d.Chips < cfg.Cost then
		return {ok=false, err="Not enough Chips"}
	end
	Economy.AddChips(plr, -cfg.Cost, "BuyPrinter")
	table.insert(d.Printers, {
		Id=printerId, PPS=cfg.PPS, Capacity=cfg.Capacity, Stored=0, Slot=#d.Printers+1, LastTick=os.time(),
	})
	return {ok=true, slot=#d.Printers}
end

return {}

-- ServerScriptService/Services/PrinterService

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local PrintersCfg  = require(RS.Shared.Config.Printers)
local ChairsCfg    = require(RS.Shared.Config.Chairs)
local Profiles     = require(script.Parent.Profiles)
local Economy      = require(script.Parent.EconomyService)
local EventService = require(script.Parent.EventService)
local Monet        = require(RS.Shared.Config.Monetization)
local _adminLoad = pcall(function() return require(script.Parent.AdminService) end)

-- Safe requires (fallback to no-ops if missing)
local function tryRequire(inst)
	local ok, mod = pcall(require, inst)
	if ok and mod ~= nil then return mod end
	return nil
end

local Guard        = require(RS.Shared.Util.RemotesGuard)
local Anti         = require(script.Parent.AntiExploitService)

local Remotes         = RS:WaitForChild("Remotes")
local CollectEvent    = Remotes:WaitForChild("CollectPrinter")        -- RemoteEvent
local PlaceRF         = Remotes:WaitForChild("PlacePrinter")          -- RemoteFunction
local GetPrintersRF   = Remotes:WaitForChild("GetPrinters")           -- RemoteFunction
local SellPrinterRF   = Remotes:WaitForChild("SellPrinter")           -- RemoteFunction
local CollectAllRF    = Remotes:WaitForChild("CollectAllPrinters")    -- RemoteFunction
local EnableAutoRF    = Remotes:WaitForChild("EnableAutoCollect")     -- RemoteFunction
local AutoStatusRF    = Remotes:WaitForChild("GetAutoCollectStatus")  -- RemoteFunction

-- RebuildPlot signal (for world visuals)
local Signals       = RS:WaitForChild("Signals")
local RebuildPlotBE = Signals:WaitForChild("RebuildPlot") :: BindableEvent
local function Rebuild(plr) if plr then RebuildPlotBE:Fire(plr.UserId) end end

local TICK_INTERVAL = 1
local SELLBACK = 0.6 -- 60% refund

-- ----- Helpers -----

local function chairMult(profileData)
	local tier = 0
	if profileData.Chair and type(profileData.Chair.Tier) == "number" then
		tier = profileData.Chair.Tier
	end
	local cfg = ChairsCfg[tier] or ChairsCfg[0]
	local m = (cfg and cfg.Multiplier) or 1
	local e = 1
	if EventService.State and EventService.State.Modifiers and type(EventService.State.Modifiers.PrinterPPS) == "number" then
		e = EventService.State.Modifiers.PrinterPPS
	end
	return m * e
end

-- server check for gamepass (cached)
local ownsCache = {}
local function ownsPass(userId, gamepassId)
	if not gamepassId or gamepassId == 0 then return false end
	local key = userId .. "_" .. gamepassId
	if ownsCache[key] ~= nil then return ownsCache[key] end
	local ok, res = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, userId, gamepassId)
	ownsCache[key] = ok and res or false
	return ownsCache[key]
end

-- Reusable collect-all
local function DoCollectAll(plr, reason)
	local profile = Profiles.Get(plr); if not profile then return 0 end
	local d = profile.Data; d.Printers = d.Printers or {}
	local total = 0
	for _, p in ipairs(d.Printers) do
		local amt = math.floor(tonumber(p.Stored) or 0)
		if amt > 0 then
			total += amt
			p.Stored = 0
		end
	end
	if total > 0 then
		Economy.AddChips(plr, total, reason or "PrinterCollectAll")
	end
	return total
end

-- ----- Server ticking for printers -----

task.spawn(function()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < TICK_INTERVAL then return end
		acc = 0
		for _, plr in ipairs(Players:GetPlayers()) do
			local profile = Profiles.Get(plr)
			if not profile or not profile.Data then continue end
			local d = profile.Data
			d.Printers = d.Printers or {}
			local mult = chairMult(d)
			for _, p in ipairs(d.Printers) do
				p.PPS      = tonumber(p.PPS) or 0
				p.Capacity = tonumber(p.Capacity) or 0
				p.Stored   = tonumber(p.Stored) or 0
				if p.Stored < p.Capacity and p.PPS > 0 then
					p.Stored = math.min(p.Capacity, p.Stored + p.PPS * mult * TICK_INTERVAL)
				end
			end
		end
	end)
end)


-- Validation helpers
local function validSlot(plr, slotIndex)
	local profile = Profiles.Get(plr); if not profile or not profile.Data then return false, "No profile" end
	local d = profile.Data
	d.Printers = d.Printers or {}
	local n = #d.Printers
	local idx = Guard.int(slotIndex, 1, n)
	if not idx then return false, "Bad slot" end
	return true, idx
end
-- ----- Handlers -----

-- Collect one slot (kept for flexibility)
CollectEvent.OnServerEvent:Connect(function(plr, slotIndex)
	if not Anti.rateLimit(plr, 'printer_collect_one', 8, 1.0) then return end
	local ok, idxOrErr = validSlot(plr, slotIndex); if not ok then Anti.log(plr,'invalid_param','collect_one',{slot=slotIndex}); return end
	slotIndex = idxOrErr
	local profile = Profiles.Get(plr); if not profile then return end
	local d = profile.Data
	d.Printers = d.Printers or {}
	local p = d.Printers[slotIndex]
	if not p then return end
	local amt = math.floor(tonumber(p.Stored) or 0)
	if amt <= 0 then return end
	p.Stored = 0
	Economy.AddChips(plr, amt, "PrinterCollect")
	-- refresh labels
	Rebuild(plr)
end)

-- Buy/place a printer
PlaceRF.OnServerInvoke = function(plr, printerId)
	if not Anti.rateLimit(plr, 'printer_place', 3, 5.0) then return { ok=false, err='Rate limited' } end
	if not PrintersCfg[printerId] then Anti.log(plr,'invalid_param','place',{id=printerId}); return { ok=false, err='Bad id' } end
	local profile = Profiles.Get(plr); if not profile then return {ok=false, err="No profile"} end
	local d = profile.Data
	d.Printers = d.Printers or {}

	local cfg = PrintersCfg[printerId]
	if not cfg then return {ok=false, err="Unknown printer"} end

	local slots = tonumber(d.SlotsUnlocked) or 1
	if #d.Printers >= slots then
		return {ok=false, err="No free slots. Upgrade chair."}
	end

	if (tonumber(d.Chips) or 0) < cfg.Cost then
		return {ok=false, err="Not enough Chips"}
	end

	Economy.AddChips(plr, -cfg.Cost, "BuyPrinter")
	table.insert(d.Printers, {
		Id = printerId,
		PPS = cfg.PPS,
		Capacity = cfg.Capacity,
		Stored = 0,
		Slot = #d.Printers + 1,
		LastTick = os.time(),
	})

	-- rebuild world (new printer pad)
	Rebuild(plr)

	return {ok=true, slot=#d.Printers}
end

-- List owned printers (+ effective PPS)
GetPrintersRF.OnServerInvoke = function(plr)
	local profile = Profiles.Get(plr); if not profile then return {ok=false, err="No profile"} end
	local d = profile.Data
	d.Printers = d.Printers or {}

	local mult = chairMult(d)
	local out = {}
	for i, p in ipairs(d.Printers) do
		local cfg = PrintersCfg[p.Id]
		table.insert(out, {
			slot     = i,
			id       = p.Id,
			name     = (cfg and cfg.Display) or p.Id,
			pps      = p.PPS,
			effPPS   = (p.PPS or 0) * mult,
			capacity = p.Capacity,
			stored   = math.floor(p.Stored or 0),
			cost     = cfg and cfg.Cost or 0,
		})
	end
	return {
		ok = true,
		slotsUnlocked = tonumber(d.SlotsUnlocked) or 1,
		owned = out,
	}
end

-- Sell a printer (auto-collect, refund %, reindex)
SellPrinterRF.OnServerInvoke = function(plr, slotIndex)
	if not Anti.rateLimit(plr, 'printer_sell', 3, 1.5) then return { ok=false, err='Rate limited' } end
	local ok, idxOrErr = validSlot(plr, slotIndex); if not ok then Anti.log(plr,'invalid_param','sell',{slot=slotIndex}); return { ok=false, err='Bad slot' } end
	slotIndex = idxOrErr
	slotIndex = tonumber(slotIndex) or -1
	if slotIndex < 1 then return {ok=false, err="Invalid slot"} end

	local profile = Profiles.Get(plr); if not profile then return {ok=false, err="No profile"} end
	local d = profile.Data
	d.Printers = d.Printers or {}
	local p = d.Printers[slotIndex]
	if not p then return {ok=false, err="No printer in that slot"} end

	local stored = math.floor(tonumber(p.Stored) or 0)
	if stored > 0 then
		Economy.AddChips(plr, stored, "PrinterAutoCollectOnSell")
	end

	local cfg = PrintersCfg[p.Id]
	local refund = 0
	if cfg and cfg.Cost then
		refund = math.floor(cfg.Cost * SELLBACK + 0.5)
		if refund > 0 then
			Economy.AddChips(plr, refund, "SellPrinterRefund")
		end
	end

	table.remove(d.Printers, slotIndex)
	for i, entry in ipairs(d.Printers) do entry.Slot = i end

	-- rebuild world (removed printer)
	Rebuild(plr)

	return {ok=true, refund=refund, collected=stored}
end

-- Collect All (FREE) with simple cooldown
local lastCollectAll = {} -- [userId] = os.clock()
CollectAllRF.OnServerInvoke = function(plr)
	if not Anti.rateLimit(plr, 'printer_collect_all', 1, 2.5) then return { ok=false, err='Rate limited' } end
	local now, prev = os.clock(), (lastCollectAll[plr.UserId] or 0)
	if now - prev < 1.0 then return { ok=false, err="Too fast" } end
	lastCollectAll[plr.UserId] = now

	local total = DoCollectAll(plr, "PrinterCollectAll")
	if total > 0 then
		-- refresh labels after mass collect
		Rebuild(plr)
	end
	return { ok=true, total = total }
end

-- ----- Permanent Auto-Collect (Game Pass) -----

local autoLoops = {} -- [userId] = running?

local function startAutoLoop(plr)
	if autoLoops[plr.UserId] then return end
	local interval = Monet.AutoCollectIntervalSec or 10
	if interval <= 0 then return end
	autoLoops[plr.UserId] = true
	task.spawn(function()
		while autoLoops[plr.UserId] and plr.Parent do
			task.wait(interval)
			local total = DoCollectAll(plr, "PrinterAutoCollect")
			if total > 0 then
				-- keep world labels in sync on passive collect
				Rebuild(plr)
			end
		end
	end)
end

Players.PlayerAdded:Connect(function(plr)
	if ownsPass(plr.UserId, Monet.AutoCollectGamepassId) then
		startAutoLoop(plr)
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	autoLoops[plr.UserId] = nil
end)

AutoStatusRF.OnServerInvoke = function(plr)
	if not Anti.rateLimit(plr, 'printer_auto_status', 5, 2.0) then return { ok=false, err='Rate limited' } end
	return {
		ok = true,
		owned = ownsPass(plr.UserId, Monet.AutoCollectGamepassId),
		interval = Monet.AutoCollectIntervalSec or 10,
	}
end

EnableAutoRF.OnServerInvoke = function(plr)
	if not Anti.rateLimit(plr, 'printer_enable_auto', 2, 10.0) then return { ok=false, err='Rate limited' } end
	if not ownsPass(plr.UserId, Monet.AutoCollectGamepassId) then
		return { ok=false, err="Not owned" }
	end
	startAutoLoop(plr)
	return { ok=true }
end

return {}

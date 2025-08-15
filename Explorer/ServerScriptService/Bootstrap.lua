-- ServerScriptService/Bootstrap
local RS  = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

-- Helpers ---------------------------------------------------------------------
local function ensureFolder(parent, name)
	assert(parent and parent:IsA("Instance"), "ensureFolder parent is nil for "..tostring(name))
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function ensureInstance(parent, className, name)
	assert(parent and parent:IsA("Instance"), "ensureInstance parent is nil for "..tostring(name))
	local inst = parent:FindFirstChild(name)
	if not inst or inst.ClassName ~= className then
		if inst then inst:Destroy() end
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = parent
	end
	return inst
end

local function assertClass(parent, name, class)
	local inst = parent:FindFirstChild(name)
	assert(inst and inst:IsA(class), ("Remote %s must be %s"):format(name, class))
end

-- Build Remotes (ONE place only) ---------------------------------------------
local Remotes = ensureFolder(RS, "Remotes")

-- CoinFlip folder + endpoints
local CF = ensureFolder(Remotes, "CoinFlip")
ensureInstance(CF, "RemoteFunction", "GetCommit")
ensureInstance(CF, "RemoteFunction", "PlaceBet")
ensureInstance(CF, "RemoteEvent",   "RoundStarted")
ensureInstance(CF, "RemoteEvent",   "RoundResolved")
-- If you add client-visible limits later, uncomment:
-- ensureInstance(CF, "RemoteFunction", "GetLimits")

-- Wheel folder + endpoints
local WH = ensureFolder(Remotes, "Wheel")
ensureInstance(WH, "RemoteFunction", "GetCommit")
ensureInstance(WH, "RemoteFunction", "PlaceBet")
ensureInstance(WH, "RemoteEvent",    "RoundStarted")
ensureInstance(WH, "RemoteEvent",    "RoundResolved")

-- Economy/Printers/Thrones/AutoCollect endpoints (flat under Remotes)
ensureInstance(Remotes, "RemoteFunction", "PlacePrinter")
ensureInstance(Remotes, "RemoteEvent",    "CollectPrinter")
ensureInstance(Remotes, "RemoteFunction", "GetPrinters")
ensureInstance(Remotes, "RemoteFunction", "SellPrinter")
ensureInstance(Remotes, "RemoteFunction", "CollectAllPrinters")
ensureInstance(Remotes, "RemoteFunction", "UpgradeThrones")
ensureInstance(Remotes, "RemoteFunction", "EnableAutoCollect")
ensureInstance(Remotes, "RemoteFunction", "GetAutoCollectStatus")

-- Class sanity checks (fast fail if anything mismatches) ----------------------
assertClass(CF, "GetCommit", "RemoteFunction")
assertClass(CF, "PlaceBet", "RemoteFunction")
assertClass(CF, "RoundStarted", "RemoteEvent")
assertClass(CF, "RoundResolved", "RemoteEvent")

assertClass(WH, "GetCommit", "RemoteFunction")
assertClass(WH, "PlaceBet", "RemoteFunction")
assertClass(WH, "RoundStarted", "RemoteEvent")
assertClass(WH, "RoundResolved", "RemoteEvent")

assertClass(Remotes, "PlacePrinter", "RemoteFunction")
assertClass(Remotes, "CollectPrinter", "RemoteEvent")
assertClass(Remotes, "GetPrinters", "RemoteFunction")
assertClass(Remotes, "SellPrinter", "RemoteFunction")
assertClass(Remotes, "CollectAllPrinters", "RemoteFunction")
assertClass(Remotes, "UpgradeThrones", "RemoteFunction")
assertClass(Remotes, "EnableAutoCollect", "RemoteFunction")
assertClass(Remotes, "GetAutoCollectStatus", "RemoteFunction")

-- Signals (BindableEvents for intra-server decoupling) ------------------------
local Signals = RS:FindFirstChild("Signals")
if not Signals then
	Signals = Instance.new("Folder")
	Signals.Name = "Signals"
	Signals.Parent = RS
end

local function ensureBindable(name)
	local b = Signals:FindFirstChild(name)
	if not b then
		b = Instance.new("BindableEvent")
		b.Name = name
		b.Parent = Signals
	end
	return b
end

ensureBindable("RebuildPlot") -- args: userId

-- Load services (order matters) ----------------------------------------------
local Services = SSS:WaitForChild("Services")

-- Profiles first (others depend on it)
require(Services:WaitForChild("Profiles"))

-- Core systems
require(Services:WaitForChild("EconomyService"))
require(Services:WaitForChild("EventService"))
require(Services:WaitForChild("RNGService"))
require(Services:WaitForChild("PlotService"))

-- Gameplay services
require(Services:WaitForChild("ThroneService"))
require(Services:WaitForChild("PrinterService"))
require(Services:WaitForChild("CoinFlipService"))
require(Services:WaitForChild("WheelService"))

print("[Bootstrap] Throne of Fortune MVP loaded.")

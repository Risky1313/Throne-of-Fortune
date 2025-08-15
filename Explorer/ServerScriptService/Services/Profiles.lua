-- ServerScriptService/Services/Profiles

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

-- Bump to wipe old test data and start with 5,000 Chips
local STORE_NAME = "ToF_Profiles_v5"

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

local defaultProfile = {
	Chips = 5000,
	Crowns = 0,
	Thrones = {Tier = 0, Skin = "BrokenWood"},
	Printers = {
		{Id="WoodenPress", PPS=5, Capacity=300, Stored=0, Slot=1, LastTick=os.time()},
	},
	SlotsUnlocked = 1,
	Upgrades = { AutoCollectInterval = 0 },
	Cosmetics = {Owned={}, Equipped={Frame=nil, Aura=nil, Trail=nil}},
	Stats = {NetChipsEarned=0, BiggestWin=0, RoundsPlayed=0, CoinFlipWins=0, CoinFlipLosses=0},
	Cooldowns = {TimeChestAt=0, DailyAt=0},
	Titles = {Owned={}, Equipped=nil},
	Version = 1,
}

local function deepcopy(t)
	local n = {}
	for k, v in pairs(t) do
		if type(v) == "table" then n[k] = deepcopy(v) else n[k] = v end
	end
	return n
end

local Profiles = {}
local live = {} -- [player] = { Data=table, leaderstats={chips=IntValue, tier=IntValue} }

local function loadProfile(userId)
	if not store then return deepcopy(defaultProfile) end
	local key = ("u_%d"):format(userId)
	local ok, data = pcall(function() return store:GetAsync(key) end)
	if ok and type(data) == "table" then
		return data
	else
		return deepcopy(defaultProfile)
	end
end

local function saveProfile(userId, data)
	if not store then return end
	local key = ("u_%d"):format(userId)
	pcall(function() store:SetAsync(key, data) end)
end

local function setupLeaderstats(plr, data)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	ls.Parent = plr

	local chips = Instance.new("IntValue")
	chips.Name = "Chips"
	chips.Value = data.Chips or 0
	chips.Parent = ls

	local tier = Instance.new("IntValue")
	tier.Name = "ThronesTier"
	tier.Value = (data.Thrones and data.Thrones.Tier) or 0
	tier.Parent = ls

	return { chips = chips, tier = tier }
end

local function onPlayerAdded(plr)
	local data = loadProfile(plr.UserId)
	live[plr] = { Data = data }
	live[plr].leaderstats = setupLeaderstats(plr, data)
end

local function onPlayerRemoving(plr)
	local p = live[plr]
	if p then
		saveProfile(plr.UserId, p.Data)
		live[plr] = nil
	end
end

-- Connect and cover players already present
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, plr in ipairs(Players:GetPlayers()) do
	onPlayerAdded(plr)
end

-- Autosave every 60s
task.spawn(function()
	while true do
		task.wait(60)
		for plr, p in pairs(live) do
			saveProfile(plr.UserId, p.Data)
		end
	end
end)

function Profiles.Get(plr)
	return live[plr]
end

function Profiles.SyncLeaderstats(plr)
	local p = live[plr]
	if not p or not p.leaderstats then return end
	p.leaderstats.chips.Value = p.Data.Chips or 0
	p.leaderstats.tier.Value  = (p.Data.Thrones and p.Data.Thrones.Tier) or 0
end

return Profiles

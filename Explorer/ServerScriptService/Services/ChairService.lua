-- ServerScriptService/Services/ChairService.lua
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local Profiles   = require(script.Parent.Profiles)
local Economy    = require(script.Parent.EconomyService)
local ChairsCfg  = require(RS.Shared.Config.Chairs)

local Remotes    = RS:WaitForChild("Remotes")
local UpgradeRF  = Remotes:WaitForChild("UpgradeChair") :: RemoteFunction

local Signals       = RS:WaitForChild("Signals")
local RebuildPlotBE = Signals:WaitForChild("RebuildPlot") :: BindableEvent

-- simple per-player upgrade lock
local busy = {}  -- [userId] = true

-- Ensure SlotsUnlocked is at least the tier's slots (safety on join)
local function reconcileSlotsUnlocked(d)
	local tier = (d.Chair and d.Chair.Tier) or 0
	local cfg  = ChairsCfg[tier]
	if not cfg then return end
	local want = tonumber(cfg.Slots) or 1
	if (tonumber(d.SlotsUnlocked) or 1) < want then
		d.SlotsUnlocked = want
	end
end

-- Optional: reconcile on join (harmless if Profiles already does this)
Players.PlayerAdded:Connect(function(plr)
	task.defer(function()
		local profile = Profiles.Get(plr)
		if profile and profile.Data then
			profile.Data.Chair = profile.Data.Chair or { Tier = 0 }
			reconcileSlotsUnlocked(profile.Data)
			-- keep leaderstats in sync if present
			local ls = plr:FindFirstChild("leaderstats")
			if ls then
				local lt = ls:FindFirstChild("ChairTier")
				if lt and lt:IsA("IntValue") then lt.Value = profile.Data.Chair.Tier end
			end
		end
	end)
end)

local function upgradeChairInternal(plr)
	local profile = Profiles.Get(plr)
	if not profile or not profile.Data then
		return { ok = false, msg = "No profile" }
	end
	local d = profile.Data
	d.Chair = d.Chair or { Tier = 0 }

	local currentTier = tonumber(d.Chair.Tier) or 0
	local nextTier    = currentTier + 1
	local nextCfg     = ChairsCfg[nextTier]

	if not nextCfg then
		return { ok = false, msg = "Max tier reached" }
	end

	local cost  = tonumber(nextCfg.Cost) or 0
	local chips = tonumber(d.Chips) or 0
	if chips < cost then
		return { ok = false, msg = ("Not enough Chips (need %d)"):format(cost - chips) }
	end

	-- charge
	Economy.AddChips(plr, -cost, "ChairUpgrade")

	-- apply
	d.Chair.Tier = nextTier
	reconcileSlotsUnlocked(d)

	-- leaderstats sync
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		local lt = ls:FindFirstChild("ChairTier")
		if lt and lt:IsA("IntValue") then lt.Value = nextTier end
	end

	-- rebuild plot visuals (throne color/label, etc.)
	RebuildPlotBE:Fire(plr.UserId)

	-- compose message about what's next
	local n2 = ChairsCfg[nextTier + 1]
	local msg
	if n2 then
		msg = ("Upgraded to Tier %d! Next: %s  Cost: %d  Mult: x%.2f  Slots: %d")
			:format(
				nextTier,
				n2.Name or ("Tier " .. (nextTier + 1)),
				tonumber(n2.Cost) or 0,
				tonumber(n2.Multiplier) or 1,
				tonumber(n2.Slots) or 1
			)
	else
		msg = ("Upgraded to Tier %d! Max tier reached."):format(nextTier)
	end

	return { ok = true, newTier = nextTier, msg = msg }
end

UpgradeRF.OnServerInvoke = function(plr)
	if not plr or not plr.UserId then
		return { ok = false, msg = "Invalid player" }
	end
	if busy[plr.UserId] then
		return { ok = false, msg = "Please wait..." }
	end
	busy[plr.UserId] = true
	local ok, result = pcall(upgradeChairInternal, plr)
	busy[plr.UserId] = nil

	if not ok then
		warn("[ChairService] Upgrade error:", result)
		return { ok = false, msg = "Upgrade failed" }
	end
	return result
end

return {}

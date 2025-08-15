local RS = game:GetService("ReplicatedStorage")
local RNG = require(script.Parent.RNGService)
local WheelCfg = require(RS.Shared.Config.Wheel)
local EventService = require(script.Parent.EventService)
local Profiles = require(script.Parent.Profiles)
local Economy = require(script.Parent.EconomyService)
local Betting = require(RS.Shared.Config.Betting)

-- Safe requires (fallback to no-ops if missing)
local function tryRequire(inst)
	local ok, mod = pcall(require, inst)
	if ok and mod ~= nil then return mod end
	return nil
end

local Guard = tryRequire(RS.Shared.Util:FindFirstChild("RemotesGuard")) or {
	int=function(n,min,max) n=tonumber(n); if not n then return nil end; n=math.floor(n); if min and n<min then return nil end; if max and n>max then return nil end; return n end,
	num=function(n,min,max) n=tonumber(n); if not n then return nil end; if min and n<min then return nil end; if max and n>max then return nil end; return n end,
}

local Anti = tryRequire(script.Parent:FindFirstChild("AntiExploitService")) or {
	rateLimit=function() return true end,
	log=function() end,
	getSummary=function() return {} end
}

local Remotes = RS.Remotes.Wheel
local GetCommit = Remotes.GetCommit
local PlaceBet = Remotes.PlaceBet
local RoundStarted = Remotes.RoundStarted
local RoundResolved = Remotes.RoundResolved

local Active = {} -- per-player seed/commit/nonce/busy

local function getState(userId)
	local s = Active[userId]
	if not s then
		local seed, hash = RNG.NewCommit()
		s = { seed = seed, hash = hash, nonce = 0, busy = false }
		Active[userId] = s
	end
	return s
end

GetCommit.OnServerInvoke = function(plr)
	if not Anti.rateLimit(plr, 'wheel_getcommit', 3, 2.0) then return { ok=false, err='Rate limited' } end
	local s = getState(plr.UserId)
	return { hash = s.hash, nonce = s.nonce }
end

PlaceBet.OnServerInvoke = function(plr, betAmount)
	if not Anti.rateLimit(plr, 'wheel_bet', 1, 1.5) then return { ok=false, err='Rate limited' } end
	betAmount = Guard.int(betAmount, 1)
	if not betAmount then Anti.log(plr,'invalid_param','wheel_bet',{bet=betAmount}); return { ok=false, err='Bad bet' } end
	local minBet = Betting.MinBet or 1
	local maxBet = Betting.MaxBet
	if betAmount < minBet then return { ok=false, err=('Min bet '..tostring(minBet)) } end
	if maxBet and betAmount > maxBet then return { ok=false, err=('Max bet '..tostring(maxBet)) } end
	local profile = Profiles.Get(plr)
	if not profile or not profile.Data then return { ok=false, err='No profile' } end
	local chips = tonumber(profile.Data.Chips) or 0
	if chips < betAmount then return { ok=false, err='Insufficient Chips' } end
	if not Anti.rateLimit(plr, 'wheel_bet', 1, 1.5) then return { ok=false, err='Rate limited' } end
	betAmount = Guard.int(betAmount, 1)
	if not betAmount then Anti.log(plr,'invalid_param','wheel_bet',{bet=betAmount}); return { ok=false, err='Bad bet' } end
	local minBet = Betting.MinBet or 1
	local maxBet = Betting.MaxBet
	if betAmount < minBet then return { ok=false, err=('Min bet '..tostring(minBet)) } end
	if maxBet and betAmount > maxBet then return { ok=false, err=('Max bet '..tostring(maxBet)) } end
	local profile = Profiles.Get(plr)
	if not profile or not profile.Data then return { ok=false, err='No profile' } end
	local chips = tonumber(profile.Data.Chips) or 0
	if chips < betAmount then return { ok=false, err='Insufficient Chips' } end
	if not Anti.rateLimit(plr, 'wheel_bet', 1, 1.5) then return { ok=false, err='Rate limited' } end
	betAmount = Guard.int(betAmount, 1)
	if not betAmount then Anti.log(plr,'invalid_param','wheel_bet',{bet=betAmount}); return { ok=false, err='Bad bet' } end
	local minBet = Betting.MinBet or 1
	local maxBet = Betting.MaxBet
	if betAmount < minBet then return { ok=false, err=('Min bet '..tostring(minBet)) } end
	if maxBet and betAmount > maxBet then return { ok=false, err=('Max bet '..tostring(maxBet)) } end
	local profile = Profiles.Get(plr)
	if not profile or not profile.Data then return { ok=false, err='No profile' } end
	local chips = tonumber(profile.Data.Chips) or 0
	if chips < betAmount then return { ok=false, err='Insufficient Chips' } end
	-- NOTE: you said you already added the same bet guard as CoinFlip. Keep that in your file
	-- if you prefer; the minimal checks below are just a fallback safety net.
	betAmount = math.floor(tonumber(betAmount) or 0)
	local profile = Profiles.Get(plr); if not profile or not profile.Data then return {ok=false, err="No profile"} end
	if betAmount <= 0 then return {ok=false, err="Invalid bet"} end
	if (profile.Data.Chips or 0) < betAmount then return {ok=false, err="Insufficient Chips"} end

	local s = getState(plr.UserId)
	if s.busy then return {ok=false, err="Round in progress"} end
	s.busy = true
	s.nonce += 1

	-- Debit first, then start round
	Economy.AddChips(plr, -betAmount, "WheelBet")
	RoundStarted:FireClient(plr, { hash = s.hash, nonce = s.nonce })

	-- Pick slot
	local slots = WheelCfg.Slots or {}
	local n = #slots
	if n < 1 then
		s.busy = false
		return { ok=false, err="Wheel config empty" }
	end

	-- If your RNGService has weighted selection, RNG.PickIndex handles repeats fine too.
	-- (Our provided WheelCfg uses repeated entries for probability weights.)
	local idx = RNG.PickIndex(s.seed, plr.UserId, s.nonce, slots)
	if type(idx) ~= "number" or idx < 1 or idx > n then
		-- Fallback to uniform if your RNGService returns nil
		idx = (math.abs(string.byte(tostring(s.seed), 1) + s.nonce + (plr.UserId % 97)) % n) + 1
	end
	local slot = slots[idx] or { Mult = 0 }

	-- Payout calculation with safe event multiplier
	local baseMult = tonumber(slot.Mult) or tonumber(slot.mult) or tonumber(slot.payout) or 0
	local eventMult = 1.0
	if EventService.State and EventService.State.Modifiers and type(EventService.State.Modifiers.WheelPayout) == "number" then
		eventMult = EventService.State.Modifiers.WheelPayout
	end
	local finalMult = baseMult * eventMult
	local payout = math.floor(betAmount * finalMult + 0.5)

	-- Credit & stats
	profile.Data.Stats = profile.Data.Stats or {}
	if payout > 0 then
		Economy.AddChips(plr, payout, "WheelWin")
		profile.Data.Stats.BiggestWin   = math.max(profile.Data.Stats.BiggestWin or 0, payout)
		profile.Data.Stats.WheelWins    = (profile.Data.Stats.WheelWins or 0) + 1
	else
		profile.Data.Stats.WheelLosses  = (profile.Data.Stats.WheelLosses or 0) + 1
	end

	-- Reveal + rotate commit
	local reveal = s.seed
	local newSeed, newHash = RNG.NewCommit()
	s.seed, s.hash = newSeed, newHash
	s.busy = false

	RoundResolved:FireClient(plr, {
		slotIndex = idx,
		payout = payout,
		serverSeed = reveal,
		nextHash = s.hash,
	})
	return { ok = true, slotIndex = idx, payout = payout, reveal = reveal, nextHash = s.hash }
end

return {}
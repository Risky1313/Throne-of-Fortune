-- ServerScriptService/Services/CoinFlipService.lua
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local RNG            = require(script.Parent.RNGService)
local CoinFlipConfig = require(RS.Shared.Config.CoinFlip)
local EventService   = require(script.Parent.EventService)
local Profiles       = require(script.Parent.Profiles)
local Economy        = require(script.Parent.EconomyService)
local Betting        = require(RS.Shared.Config.Betting) -- optional limits (min/exposure/hard cap)
local Guard          = require(RS.Shared.Util.RemotesGuard)
local Anti           = require(script.Parent.AntiExploitService)

local Remotes       = RS.Remotes.CoinFlip
local GetCommit     = Remotes.GetCommit
local PlaceBet      = Remotes.PlaceBet
local RoundStarted  = Remotes.RoundStarted
local RoundResolved = Remotes.RoundResolved

local Active = {} -- [userId] = {seed, hash, nonce, lastFlipAt, inFlight}

-- per-player commit state
local function getState(userId)
	local s = Active[userId]
	if not s then
		local seed, hash = RNG.NewCommit()
		s = { seed = seed, hash = hash, nonce = 0, lastFlipAt = 0, inFlight = false }
		Active[userId] = s
	end
	return s
end

GetCommit.OnServerInvoke = function(plr)
	if not Anti.rateLimit(plr, 'coinflip_getcommit', 3, 2.0) then return { ok=false, err='Rate limited' } end
	local s = getState(plr.UserId)
	return { hash = s.hash, nonce = s.nonce }
end

-- Sanitize bet against config (min, dynamic exposure %, optional hard cap)
local function sanitizeBet(plr, rawBet)
	local cfg = (Betting and Betting.CoinFlip) or {}
	local minBet  = tonumber(cfg.MinBet) or tonumber(CoinFlipConfig.MinBet) or 1
	local hardCap = tonumber(cfg.MaxBet) or 0    -- 0 = no fixed hard cap
	local expo    = tonumber(cfg.ExposureCap) or 0

	local profile = Profiles.Get(plr)
	if not profile or not profile.Data then
		return nil, "No profile"
	end

	local chips = tonumber(profile.Data.Chips) or 0
	local bet = math.floor(tonumber(rawBet) or 0)

	if bet < minBet then
		return nil, ("Min bet %d"):format(minBet)
	end
	if bet > chips then
		return nil, "Insufficient Chips"
	end

	-- Dynamic cap based on current balance
	local cap = chips
	if expo > 0 then
		cap = math.min(cap, math.floor(chips * expo))
	end
	-- Optional fixed cap
	if hardCap > 0 then
		cap = math.min(cap, hardCap)
	end

	-- If you also want per-tier caps, uncomment:
	-- local tier = (profile.Data.Throne and profile.Data.Throne.Tier) or 0
	-- cap = math.min(cap, (CoinFlipConfig.MaxBetByTier and CoinFlipConfig.MaxBetByTier(tier)) or cap)

	if bet > cap then
		return nil, ("Max bet right now is %d"):format(cap)
	end

	return bet
end

PlaceBet.OnServerInvoke = function(plr, betAmount, side)
	if not Anti.rateLimit(plr, 'coinflip_bet', 1, 1.5) then return { ok=false, err='Rate limited' } end
	betAmount = Guard.int(betAmount, 1)
	if not betAmount then Anti.log(plr,'invalid_param','coinflip_bet',{bet=betAmount}); return { ok=false, err='Bad bet' } end
	local minBet = Betting.MinBet or 1
	local maxBet = Betting.MaxBet
	if betAmount < minBet then return { ok=false, err=('Min bet '..tostring(minBet)) } end
	if maxBet and betAmount > maxBet then return { ok=false, err=('Max bet '..tostring(maxBet)) } end
	local profile = Profiles.Get(plr)
	if not profile or not profile.Data then return { ok=false, err='No profile' } end
	local chips = tonumber(profile.Data.Chips) or 0
	if chips < betAmount then return { ok=false, err='Insufficient Chips' } end
	if side ~= 0 and side ~= 1 then
		return { ok = false, err = "Invalid side" }
	end

	-- Limits (no hidden hard cap; driven by Betting and/or CoinFlipConfig)
	local bet, err = sanitizeBet(plr, betAmount)
	if not bet then
		return { ok = false, err = err }
	end

	local profile = Profiles.Get(plr)
	if not profile or not profile.Data then
		return { ok = false, err = "No profile" }
	end
	profile.Data.Stats = profile.Data.Stats or {}

	local s = getState(plr.UserId)
	local now = os.clock()
	if s.inFlight then
		return { ok = false, err = "Previous flip busy" }
	end
	if now - s.lastFlipAt < (CoinFlipConfig.PerPlayerRateLimit or 0) then
		return { ok = false, err = "Too fast" }
	end
	s.inFlight = true
	s.lastFlipAt = now
	s.nonce += 1

	-- Debit first (atomic)
	Economy.AddChips(plr, -bet, "CoinFlipBet")
	RoundStarted:FireClient(plr, { hash = s.hash, nonce = s.nonce })

	-- Resolve (0=heads, 1=tails)
	local result = RNG.Coin(s.seed, plr.UserId, s.nonce)
	local win = (result == side)

	-- 0% house edge baseline: BasePayout should be 2.0 (stake + profit).
	-- Keep event multiplier if you want promos; set to 1.0 in EventService to disable.
	local baseMult = tonumber(CoinFlipConfig.BasePayout) or 2.0
	local eventMult = 1.0
	if EventService.State and EventService.State.Modifiers
		and type(EventService.State.Modifiers.CoinFlipPayout) == "number" then
		eventMult = EventService.State.Modifiers.CoinFlipPayout
	end

	local credit = win and math.floor(bet * baseMult * eventMult + 0.5) or 0  -- total credited back
	local profit = win and math.max(0, credit - bet) or 0                     -- net winnings (excludes stake)

	if credit > 0 then
		Economy.AddChips(plr, credit, "CoinFlipWin")
		profile.Data.Stats.BiggestWin   = math.max(profile.Data.Stats.BiggestWin or 0, profit)
		profile.Data.Stats.CoinFlipWins = (profile.Data.Stats.CoinFlipWins or 0) + 1
	else
		profile.Data.Stats.CoinFlipLosses = (profile.Data.Stats.CoinFlipLosses or 0) + 1
	end

	-- Reveal & rotate commit
	local reveal = s.seed
	local newSeed, newHash = RNG.NewCommit()
	s.seed, s.hash = newSeed, newHash
	s.inFlight = false

	local payload = {
		win        = win,
		serverSeed = reveal,
		result     = result,
		payout     = credit,   -- total credited (includes stake)
		profit     = profit,   -- net winnings (what the player actually made)
		bet        = bet,
		nextHash   = s.hash,
	}
	RoundResolved:FireClient(plr, payload)
	return { ok = true, reveal = reveal, nextHash = s.hash, win = win, payout = credit, profit = profit }
end

Players.PlayerRemoving:Connect(function(plr)
	Active[plr.UserId] = nil
end)

return {}

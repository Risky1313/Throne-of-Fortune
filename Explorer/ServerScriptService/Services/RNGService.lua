local HttpService = game:GetService("HttpService")
local Hash = require(game.ReplicatedStorage.Shared.Util.Hash)

local RNGService = {}

function RNGService.NewCommit()
	local seed = HttpService:GenerateGUID(false) .. ":" .. tostring(os.clock())
	local hash = Hash.digest(seed)
	return seed, hash
end

-- Convert first 8 hex chars to a 32-bit integer
local function hex32(hex)
	return tonumber(string.sub(hex, 1, 8), 16) or 0
end

-- Deterministic float in [0,1)
local function hashToFloat(hex)
	return (hex32(hex) % 4294967296) / 4294967296
end

function RNGService.Coin(seed, userId, nonce)
	local msg = string.format("%s:%d:%d", seed, userId, nonce)
	local h = Hash.digest(msg)
	local f = hashToFloat(h)
	return (f < 0.5) and 0 or 1 -- 0=heads, 1=tails
end

-- Picks an index from 'slots' deterministically.
-- Supports either:
--  • Repeated entries (no weights) -> uniform over indices
--  • Weighted entries -> Weight/weight/Prob/prob/Chance/chance; missing/invalid defaults to 1
function RNGService.PickIndex(seed, userId, nonce, slots)
	if type(slots) ~= "table" or #slots == 0 then
		return 1
	end

	local msg = string.format("%s:%d:%d:wheel", seed, userId, nonce)
	local h = Hash.digest(msg)
	local n32 = hex32(h)

	-- Detect if any weight-like field exists
	local hasExplicit = false
	for i = 1, #slots do
		local slot = slots[i]
		if type(slot) == "table" then
			local w = slot.Weight or slot.weight or slot.Prob or slot.prob or slot.Chance or slot.chance
			if w ~= nil then
				hasExplicit = true
				break
			end
		end
	end

	if not hasExplicit then
		-- Uniform over indices (works perfectly with repeated entries)
		return (n32 % #slots) + 1
	end

	-- Weighted pick; treat missing/invalid weights as 1
	local total = 0
	for i = 1, #slots do
		local slot = slots[i]
		local w = 1
		if type(slot) == "table" then
			local v = slot.Weight or slot.weight or slot.Prob or slot.prob or slot.Chance or slot.chance
			w = tonumber(v) or 1
		end
		if w > 0 then total = total + w end
	end

	if total <= 0 then
		-- Degenerate weights -> fallback to uniform
		return (n32 % #slots) + 1
	end

	local r = (n32 % total) + 1
	local acc = 0
	for i = 1, #slots do
		local slot = slots[i]
		local w = 1
		if type(slot) == "table" then
			local v = slot.Weight or slot.weight or slot.Prob or slot.prob or slot.Chance or slot.chance
			w = tonumber(v) or 1
		end
		if w > 0 then
			acc = acc + w
			if r <= acc then
				return i
			end
		end
	end

	-- Shouldn't reach here, but just in case
	return #slots
end

return RNGService

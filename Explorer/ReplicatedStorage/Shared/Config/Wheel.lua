-- ReplicatedStorage/Shared/Config/Wheel.lua
-- Balanced 36-slot wheel (uniform index selection).
-- Targets RTP ˜ 0.894 (89.4%) and hit rate ˜ 44% (16 wins / 36).
-- Construction via repeats keeps it tidy.

local function rep(proto, n)
	local t = {}
	for i = 1, n do
		local c = {}
		for k, v in pairs(proto) do c[k] = v end
		t[#t+1] = c
	end
	return t
end

-- Palette is just for UI if you ever render it; change freely.
local COLORS = {
	MISS   = Color3.fromRGB(80, 80, 80),
	SMALL  = Color3.fromRGB(72, 143, 242),
	MEDIUM = Color3.fromRGB(112, 204, 138),
	BIG    = Color3.fromRGB(229, 173, 71),
	JP     = Color3.fromRGB(214, 88, 88),
}

-- Distribution:
--  20x MISS   -> 0.0x (no payout)
--  10x SMALL  -> 1.2x
--   4x MEDIUM -> 1.8x
--   1x BIG    -> 5.0x
--   1x JACKPOT-> 8.0x
-- EV = (10*1.2 + 4*1.8 + 1*5 + 1*8) / 36 = 32.2 / 36 = 0.894

local Slots = {}

-- Misses (no payout)
for _, s in ipairs(rep({ Name = "Miss", Mult = 0.0, Color = COLORS.MISS }, 20)) do
	Slots[#Slots+1] = s
end

-- Small wins (frequent, low)
for _, s in ipairs(rep({ Name = "x1.2", Mult = 1.2, Color = COLORS.SMALL }, 10)) do
	Slots[#Slots+1] = s
end

-- Medium wins
for _, s in ipairs(rep({ Name = "x1.8", Mult = 1.8, Color = COLORS.MEDIUM }, 4)) do
	Slots[#Slots+1] = s
end

-- Big and Jackpot
Slots[#Slots+1] = { Name = "x5", Mult = 5.0, Color = COLORS.BIG }
Slots[#Slots+1] = { Name = "x8", Mult = 8.0, Color = COLORS.JP }

return {
	-- If you run event boosts, WheelService should multiply by EventService.State.Modifiers.WheelPayout or 1.
	Slots = Slots,
}

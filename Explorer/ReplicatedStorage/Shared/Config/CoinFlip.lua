local CoinFlip = {}

CoinFlip.MinBet = 50
CoinFlip.BasePayout = 2.0        -- true even-money: stake + profit (no house edge)
CoinFlip.PerPlayerRateLimit = 0.5 -- seconds

function CoinFlip.MaxBetByTier(chairTier)
	return math.floor(2000 * (1 + 0.15 * (chairTier or 0)))
end

return CoinFlip

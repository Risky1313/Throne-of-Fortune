return {
	CoinFlip = {
		MinBet      = 100,    -- floor
		MaxBet      = 1000000,    -- 0 = no fixed hard cap
		ExposureCap = 0.75, -- dynamic cap: <=25% of current Chips; set 0 to disable
	},
	Wheel = {
		MinBet      = 100,
		MaxBet      = 1000000,
		ExposureCap = 0.75,
	}
}
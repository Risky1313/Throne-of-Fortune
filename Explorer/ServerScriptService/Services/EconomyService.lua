local Profiles = require(script.Parent.Profiles)

local Economy = {}

function Economy.AddChips(plr, amount, reason)
	local profile = Profiles.Get(plr); if not profile then return false end
	local d = profile.Data
	d.Chips = math.max(0, (d.Chips or 0) + amount)
	if amount > 0 then
		d.Stats.NetChipsEarned = (d.Stats.NetChipsEarned or 0) + amount
	end
	Profiles.SyncLeaderstats(plr)
	-- TODO: analytics log (reason, delta, newBalance)
	return true
end

return Economy

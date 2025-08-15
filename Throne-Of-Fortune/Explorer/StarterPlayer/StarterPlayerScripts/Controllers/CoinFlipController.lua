local RS = game:GetService("ReplicatedStorage")
local RemotesRoot = RS:WaitForChild("Remotes")
local CoinFlipFolder = RemotesRoot:WaitForChild("CoinFlip")

local GetCommit    = CoinFlipFolder:WaitForChild("GetCommit")
local PlaceBet     = CoinFlipFolder:WaitForChild("PlaceBet")
local RoundStarted = CoinFlipFolder:WaitForChild("RoundStarted")
local RoundResolved= CoinFlipFolder:WaitForChild("RoundResolved")

local Hash = require(RS.Shared.Util.Hash)

local UI
local M = {}
function M.SetUI(u) UI = u end

local state = { hash = nil, lastBet = 0 }

local function refreshCommit()
	local r = GetCommit:InvokeServer()
	if r then
		state.hash = r.hash
		if UI and UI.SetCoinFlipHash then UI.SetCoinFlipHash(state.hash) end
	end
end

function M.RequestFlip(side, bet)
	bet = tonumber(bet) or 0
	state.lastBet = bet
	if not state.hash then refreshCommit() end
	local reply = PlaceBet:InvokeServer(bet, side)
	if not reply or not reply.ok then
		local msg = reply and reply.err or "Flip failed"
		if UI and UI.Error then UI.Error(msg) else warn("[CoinFlip] "..msg) end
	end
end

RoundStarted.OnClientEvent:Connect(function(payload)
	if UI and UI.CoinFlipStart then UI.CoinFlipStart(payload.hash) end
end)

RoundResolved.OnClientEvent:Connect(function(res)
	local verified = (Hash.digest(res.serverSeed) == state.hash)
	if UI and UI.CoinFlipResult then
		UI.CoinFlipResult(res, verified, state.lastBet)
	else
		if res.win then warn(("[CoinFlip] WIN +%d"):format(res.payout or 0)) else warn("[CoinFlip] Loss") end
	end
	state.hash = res.nextHash
	if UI and UI.SetCoinFlipHash then UI.SetCoinFlipHash(state.hash) end
end)

function M.RefreshCommit() refreshCommit() end
return M

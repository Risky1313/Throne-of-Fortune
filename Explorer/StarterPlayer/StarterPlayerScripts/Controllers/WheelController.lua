local RS = game:GetService("ReplicatedStorage")
local RemotesRoot = RS:WaitForChild("Remotes")
local WheelFolder  = RemotesRoot:WaitForChild("Wheel")

local GetCommit    = WheelFolder:WaitForChild("GetCommit")
local PlaceBet     = WheelFolder:WaitForChild("PlaceBet")
local RoundStarted = WheelFolder:WaitForChild("RoundStarted")
local RoundResolved= WheelFolder:WaitForChild("RoundResolved")

local Hash = require(RS.Shared.Util.Hash)
local WheelCfg = require(RS.Shared.Config.Wheel)

local UI
local M = {}
function M.SetUI(u) UI = u end

local wheelHash, lastBet = nil, 0

local function refreshCommit()
	local r = GetCommit:InvokeServer()
	if r then
		wheelHash = r.hash
		if UI and UI.SetWheelHash then UI.SetWheelHash(wheelHash) end
	end
end

function M.RequestSpin(bet)
	bet = tonumber(bet) or 0
	lastBet = bet
	local reply = PlaceBet:InvokeServer(bet)
	if not reply or not reply.ok then
		local msg = reply and reply.err or "Spin failed"
		if UI and UI.Error then UI.Error(msg) else warn("[Wheel] "..msg) end
	end
end

RoundStarted.OnClientEvent:Connect(function(payload)
	if UI and UI.WheelStart then UI.WheelStart(payload.hash) end
end)

RoundResolved.OnClientEvent:Connect(function(res)
	local verified = (Hash.digest(res.serverSeed) == (wheelHash or ""))
	local slot = WheelCfg.Slots[res.slotIndex]
	if UI and UI.WheelResult then
		UI.WheelResult(res.slotIndex, slot, res.payout, verified, res.nextHash, lastBet)
	else
		warn(("[Wheel] payout=%d"):format(res.payout or 0))
	end
	wheelHash = res.nextHash
	if UI and UI.SetWheelHash then UI.SetWheelHash(wheelHash) end
end)

function M.RefreshCommit() refreshCommit() end
return M

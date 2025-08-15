-- StarterPlayer/StarterPlayerScripts/HUD.client.lua
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")


local CoinFlipCtl = require(script.Parent.Controllers.CoinFlipController)
local WheelCtl    = require(script.Parent.Controllers.WheelController)
local PrintersCfg = require(RS.Shared.Config.Printers)
local ThronesCfg   = require(RS.Shared.Config.Thrones)
local WheelCfg    = require(RS.Shared.Config.Wheel)
local Monet       = require(RS.Shared.Config.Monetization)
local SFX         = require(RS.Shared.Util.SFX)

-- Preload sounds (safe: SFX silences bad IDs)
SFX.Preload({
	"UI.Click","UI.Success","UI.Error",
	"Game.Collect","Game.Flip","Game.SpinStart","Game.SpinStop",
	"Game.WinSmall","Game.WinBig","Game.Lose",
})

-- Remotes
local Remotes            = RS:WaitForChild("Remotes")
local PlacePrinter       = Remotes:WaitForChild("PlacePrinter")           :: RemoteFunction
local CollectPrinter     = Remotes:WaitForChild("CollectPrinter")         :: RemoteEvent
local CollectAllRF       = Remotes:WaitForChild("CollectAllPrinters")     :: RemoteFunction
local GetPrintersRF      = Remotes:WaitForChild("GetPrinters")            :: RemoteFunction
local SellPrinterRF      = Remotes:WaitForChild("SellPrinter")            :: RemoteFunction
local UpgradeRF          = Remotes:WaitForChild("UpgradeThrones")           :: RemoteFunction
local EnableAutoRF       = Remotes:WaitForChild("EnableAutoCollect")      :: RemoteFunction
local AutoStatusRF       = Remotes:WaitForChild("GetAutoCollectStatus")   :: RemoteFunction

-- Animation remotes (listen directly so we don't need controller edits)
local CF_RoundStarted   = Remotes.CoinFlip.RoundStarted
local CF_RoundResolved  = Remotes.CoinFlip.RoundResolved
local WH_RoundStarted   = Remotes.Wheel.RoundStarted
local WH_RoundResolved  = Remotes.Wheel.RoundResolved

local plr = Players.LocalPlayer
local pg  = plr:WaitForChild("PlayerGui")

-- UI helpers -----------------------------------------------------------------
local function mkScreen(name)
	local g = Instance.new("ScreenGui")
	g.Name = name; g.ResetOnSpawn = false; g.Parent = pg
	return g
end
local function mkFrame(parent, pos, size)
	local f = Instance.new("Frame")
	f.Size = size; f.Position = pos; f.BackgroundTransparency = 0.15; f.Parent = parent
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
	return f
end
local function mkButton(parent, text, posY, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -16, 0, 32); b.Position = UDim2.new(0, 8, 0, posY)
	b.Text = text; b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	if cb then b.MouseButton1Click:Connect(function() SFX.Play("UI.Click"); cb() end) end
	return b
end
local function mkLabel(parent, text, posY)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, -16, 0, 24); t.Position = UDim2.new(0, 8, 0, posY)
	t.BackgroundTransparency = 1; t.TextXAlignment = Enum.TextXAlignment.Left; t.Text = text
	t.Parent = parent
	return t
end
local function mkTextbox(parent, placeholder, posY, def)
	local tb = Instance.new("TextBox")
	tb.PlaceholderText = placeholder; tb.Text = def or ""
	tb.Size = UDim2.new(1, -16, 0, 28); tb.Position = UDim2.new(0, 8, 0, posY)
	tb.Parent = parent; Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 6)
	return tb
end
local function formatNumber(n)
	n = math.floor(tonumber(n) or 0)
	local s, k = tostring(n), nil
	while true do s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2"); if k == 0 then break end end
	return s
end

-- Compact coin formatter: 1,234 -> 1.23K, 125,000 -> 125K, 2,000,000 -> 2M
local SUFFIXES = {"","K","M","B","T","Qa","Qi","Sx","Sp","Oc","No","Dc"}
local function formatCoins(n)
	n = tonumber(n) or 0
	local neg = n < 0
	local v = math.abs(n)
	local i = 1
	while v >= 1000 and i < #SUFFIXES do
		v /= 1000
		i += 1
	end
	local s
	if i == 1 then
		s = tostring(math.floor(v + 0.5))                 -- < 1K
	elseif v >= 100 then
		s = string.format("%d%s", math.floor(v + 0.5), SUFFIXES[i])
	elseif v >= 10 then
		s = string.format("%.1f%s", v, SUFFIXES[i]):gsub("%.0([A-Z]+)$","%1")
	else
		s = string.format("%.2f%s", v, SUFFIXES[i]):gsub("0([A-Z]+)$","%1"):gsub("%.([A-Z]+)$","%1")
	end
	if neg then s = "-" .. s end
	return s
end

-- Toasts (win/loss/passive) ---------------------------------------------------
local COLORS = {
	win     = Color3.fromRGB(64, 200, 120),
	loss    = Color3.fromRGB(220, 80, 80),
	passive = Color3.fromRGB(235, 193, 52),
}
local ui  = mkScreen("ToF_HUD")
local toastRoot = Instance.new("Frame")
toastRoot.Name = "Toasts"
toastRoot.BackgroundTransparency = 1
toastRoot.Size = UDim2.new(1, 0, 1, 0)
toastRoot.Parent = ui

-- Prompt hint (Collect/Sell) -------------------------------------------------
local promptRoot = Instance.new("Frame")
promptRoot.Name = "PromptHint"
promptRoot.BackgroundTransparency = 1
promptRoot.Size = UDim2.new(0, 340, 0, 70)
promptRoot.Position = UDim2.new(0, 10, 1, -84)
promptRoot.Parent = ui
promptRoot.Visible = false

local bg = Instance.new("Frame")
bg.Size = UDim2.new(1, 0, 1, 0)
bg.BackgroundTransparency = 0.15
bg.Parent = promptRoot
Instance.new("UICorner", bg).CornerRadius = UDim.new(0,10)
local st = Instance.new("UIStroke", bg); st.Thickness = 1; st.Color = Color3.fromRGB(0,0,0); st.Transparency = 0.6

local lbl = Instance.new("TextLabel"); lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.GothamBold; lbl.TextScaled = true
lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Size = UDim2.new(1, -16, 0, 28); lbl.Position = UDim2.new(0, 8, 0, 4); lbl.Parent = promptRoot
lbl.Text = "Printer: Ready"

local row = Instance.new("Frame"); row.BackgroundTransparency = 1; row.Size = UDim2.new(1, -16, 0, 28); row.Position = UDim2.new(0, 8, 0, 36); row.Parent = promptRoot
local c1 = Instance.new("TextLabel"); c1.BackgroundTransparency = 1; c1.Font = Enum.Font.Gotham; c1.TextScaled = true; c1.TextXAlignment = Enum.TextXAlignment.Left
c1.Size = UDim2.new(0.5, -8, 1, 0); c1.Position = UDim2.new(0, 0, 0, 0); c1.Parent = row; c1.Text = "Collect (Press E)"
local c2 = Instance.new("TextLabel"); c2.BackgroundTransparency = 1; c2.Font = Enum.Font.Gotham; c2.TextScaled = true; c2.TextXAlignment = Enum.TextXAlignment.Left
c2.Size = UDim2.new(0.5, -8, 1, 0); c2.Position = UDim2.new(0.5, 8, 0, 0); c2.Parent = row; c2.Text = "Sell (Hold R)"

-- Progress bar for R-hold
local prog = Instance.new("Frame"); prog.BackgroundTransparency = 0.2; prog.Size = UDim2.new(1, -16, 0, 6); prog.Position = UDim2.new(0, 8, 1, -10); prog.Parent = promptRoot
Instance.new("UICorner", prog).CornerRadius = UDim.new(0,4)
local fill = Instance.new("Frame"); fill.Size = UDim2.new(0,0,1,0); fill.BackgroundTransparency = 0; fill.Parent = prog
Instance.new("UICorner", fill).CornerRadius = UDim.new(0,4)

local activePrompt = nil
local activeSlot = nil
local holdStart = nil
local holdDur = 0

local function setFill(alpha)
	alpha = math.clamp(alpha or 0, 0, 1)
	fill.Size = UDim2.new(alpha, 0, 1, 0)
end

local function showPrompt(p)
	activePrompt = p
	promptRoot.Visible = true
	fill.Size = UDim2.new(0,0,1,0)
	local objText = p.ObjectText ~= "" and p.ObjectText or "Printer"
	lbl.Text = objText
	activeSlot = nil
	local parent = p.Parent
	if parent and parent:GetAttribute("Slot") then activeSlot = parent:GetAttribute("Slot") end
	holdDur = p.HoldDuration or 0
end

local function hidePrompt(p)
	if activePrompt == p then
		activePrompt = nil
		promptRoot.Visible = false
		setFill(0)
	end
end

-- Drive progress using actual prompt hold events
ProximityPromptService.PromptShown:Connect(function(p, inputType)
	if p and p.Name == "PrinterInteract" then showPrompt(p) end
end)
ProximityPromptService.PromptHidden:Connect(function(p)
	hidePrompt(p)
end)
ProximityPromptService.PromptButtonHoldBegan:Connect(function(p, plr)
	local me = Players.LocalPlayer
	if p == activePrompt and plr == me then
		holdStart = time()
		-- update bar each frame
		local conn; conn = RunService.RenderStepped:Connect(function()
			if not activePrompt or not holdStart then conn:Disconnect(); return end
			local alpha = (time() - holdStart) / math.max(holdDur, 0.001)
			setFill(alpha)
			if alpha >= 1 then conn:Disconnect() end
		end)
	end
end)
ProximityPromptService.PromptButtonHoldEnded:Connect(function(p, plr)
	local me = Players.LocalPlayer
	if p == activePrompt and plr == me then
		holdStart = nil
		setFill(0)
	end
end)
ProximityPromptService.PromptTriggered:Connect(function(p, plr)
	local me = Players.LocalPlayer
	if p == activePrompt and plr == me and activeSlot then
		-- SELL after successful hold
		local ok, res = pcall(function() return SellPrinterRF:InvokeServer(activeSlot) end)
		-- Bar will reset via PromptHidden shortly
	end
end)

-- E to collect while prompt visible
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if not activePrompt or not activeSlot then return end
	if input.KeyCode == Enum.KeyCode.E then
		SFX.Play("Game.Collect")
		CollectPrinter:FireServer(activeSlot)
	end
end)


local activeToasts = {}
local function relayoutToasts()
	for i, t in ipairs(activeToasts) do
		local target = UDim2.new(0.5, -160, 0, 12 + (i-1)*52)
		TweenService:Create(t, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = target}):Play()
	end
end

local function showToast(kind, amount, prefix)
	amount = math.floor(tonumber(amount) or 0)
	local sign = (amount >= 0) and "+" or ""
	local txt  = string.format("%s %s%s Chips", prefix or "", sign, formatCoins(amount))
	local f = Instance.new("Frame")
	f.BackgroundColor3 = COLORS[kind] or Color3.fromRGB(90,90,90)
	f.BackgroundTransparency = 0.1
	f.Size = UDim2.new(0, 320, 0, 44)
	f.Position = UDim2.new(0.5, -160, 0, -60)
	f.Parent = toastRoot
	f.BorderSizePixel = 0
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
	local s = Instance.new("UIStroke", f); s.Thickness = 1; s.Color = Color3.fromRGB(0,0,0); s.Transparency = 0.6

	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = Color3.new(1,1,1)
	l.Text = txt
	l.Size = UDim2.new(1, -16, 1, -10)
	l.Position = UDim2.new(0, 8, 0, 5)
	l.Parent = f

	table.insert(activeToasts, f); relayoutToasts()
	f.Size = UDim2.new(0, 320, 0, 0)
	TweenService:Create(f, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = UDim2.new(0,320,0,44)}):Play()

	task.delay(1.7, function()
		local fade = TweenService:Create(f, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {BackgroundTransparency = 1})
		fade:Play()
		TweenService:Create(l, TweenInfo.new(0.25), {TextTransparency = 1}):Play()
		fade.Completed:Wait()
		for i, t in ipairs(activeToasts) do if t == f then table.remove(activeToasts, i) break end end
		f:Destroy()
		relayoutToasts()
	end)
end

-- HUD (chips/tier + toggles) --------------------------------------------------
local hud = mkFrame(ui, UDim2.new(0,10,0,10), UDim2.new(0,280,0,80))
local chipsL = mkLabel(hud, "Chips: 0", 8)
local tierL  = mkLabel(hud, "Thrones Tier: 0", 32)

local printersPanel, ThronesPanel, coinPanel, wheelPanel
mkButton(hud, "Printers",      52, function() if printersPanel then printersPanel.Visible = not printersPanel.Visible end end)
mkButton(hud, "Thrones Upgrade", 86, function() if ThronesPanel    then ThronesPanel.Visible    = not ThronesPanel.Visible    end end)
mkButton(hud, "Coin Flip",    120, function() if coinPanel     then coinPanel.Visible     = not coinPanel.Visible     end end)
mkButton(hud, "Wheel",        154, function() if wheelPanel    then wheelPanel.Visible    = not wheelPanel.Visible    end end)
hud.Size = UDim2.new(0,280,0,190)

local function bindLeaderstats()
	local ls = plr:WaitForChild("leaderstats", 5); if not ls then return end
	local chips = ls:WaitForChild("Chips", 5)
	local tier  = ls:WaitForChild("ThronesTier", 5)
	if chips then
		chips:GetPropertyChangedSignal("Value"):Connect(function()
			chipsL.Text = "Chips: " .. formatCoins(chips.Value)
		end)
		chipsL.Text = "Chips: " .. formatCoins(chips.Value)
	end
	if tier then
		tier:GetPropertyChangedSignal("Value"):Connect(function()
			tierL.Text = "Thrones Tier: " .. tostring(tier.Value)
		end)
		tierL.Text = "Thrones Tier: " .. tostring(tier.Value)
	end
end
bindLeaderstats()

-- PRINTERS PANEL --------------------------------------------------------------
printersPanel = mkFrame(ui, UDim2.new(0,10,0,210), UDim2.new(0,420,0,340)); printersPanel.Visible=false
mkLabel(printersPanel, "Printers", 8)

local slotsL        = mkLabel(printersPanel, "Slots: 0/0", 28)
local refreshBtn    = mkButton(printersPanel, "Refresh", 52, nil)
refreshBtn.Size, refreshBtn.Position = UDim2.new(0,100,0,28), UDim2.new(0,8,0,52)
local collectableL  = mkLabel(printersPanel, "Collectable: 0", 80)
local collectAllBtn = mkButton(printersPanel, "Collect All", 52, nil)
collectAllBtn.Size, collectAllBtn.Position = UDim2.new(0,120,0,28), UDim2.new(0,120,0,52)

local autoL  = mkLabel(printersPanel, "Auto-Collect: --", 106)
local autoBtn = mkButton(printersPanel, "Get Auto-Collect", 130, nil)
autoBtn.Size, autoBtn.Position = UDim2.new(0,160,0,28), UDim2.new(0,8,0,130)

local ownedTitle = mkLabel(printersPanel, "Owned:", 166)

local ownedList = Instance.new("ScrollingFrame")
ownedList.Size = UDim2.new(1, -16, 0, 140)
ownedList.Position = UDim2.new(0, 8, 0, 190)
ownedList.BackgroundTransparency = 1
ownedList.ScrollBarThickness = 6
ownedList.CanvasSize = UDim2.new(0, 0, 0, 0)
ownedList.Parent = printersPanel

local listLayout = ownedList:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = ownedList

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	local h = 0
	local ok, res = pcall(function() return listLayout.AbsoluteContentSize.Y end)
	if ok and typeof(res) == "number" then h = res end
	ownedList.CanvasSize = UDim2.new(0, 0, 0, h + 8)
end)

-- Live counter prediction
local predict, lastT = {}, time()
local nv = Instance.new("NumberValue")
nv.Value = 0
nv.Changed:Connect(function(v) collectableL.Text = "Collectable: " .. formatCoins(v) end)

local function row(pr)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, -6, 0, 40); f.BackgroundTransparency = 0.1
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, -120, 1, 0); name.Position = UDim2.new(0, 8, 0, 0)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = string.format("Slot %d  %s  | PPS %d  | %d/%d", pr.slot, pr.name, pr.pps, pr.stored, pr.capacity)
	name.Parent = f

	local sell = Instance.new("TextButton")
	sell.Size = UDim2.new(0, 110, 0, 28); sell.Position = UDim2.new(1, -118, 0, 6)
	sell.Text = "Sell (+" .. formatCoins(math.floor((pr.cost or 0) * 0.6 + 0.5)) .. ")"
	sell.Parent = f; Instance.new("UICorner", sell).CornerRadius = UDim.new(0, 6)
	sell.MouseButton1Click:Connect(function()
		local r = SellPrinterRF:InvokeServer(pr.slot)
		if not r or not r.ok then
			SFX.Play("UI.Error")
			warn("Sell failed:", r and r.err)
		else
			SFX.Play("UI.Success")
			refreshOwned()
		end
	end)

	return f
end

local function updateAutoUI()
	local st = AutoStatusRF:InvokeServer()
	if st and st.ok then
		if st.owned then
			autoL.Text = ("Auto-Collect: every %ds  (OWNED)"):format(st.interval or 10)
			autoBtn.Visible = false
		else
			autoL.Text = "Auto-Collect: OFF"
			autoBtn.Visible = true
			autoBtn.Text = "Get Auto-Collect"
		end
	else
		autoL.Text = "Auto-Collect: --"
	end
end

autoBtn.MouseButton1Click:Connect(function()
	if Monet.AutoCollectGamepassId and Monet.AutoCollectGamepassId ~= 0 then
		MarketplaceService:PromptGamePassPurchase(plr, Monet.AutoCollectGamepassId)
	else
		warn("AutoCollect gamepass id not set in Monetization config.")
	end
end)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if player == plr and wasPurchased and passId == Monet.AutoCollectGamepassId then
		EnableAutoRF:InvokeServer()
		updateAutoUI()
	end
end)

function refreshOwned()
	local r = GetPrintersRF:InvokeServer()
	if not r or not r.ok then
		warn("GetPrinters failed")
		return
	end

	for _, c in ipairs(ownedList:GetChildren()) do
		if c:IsA("Frame") or c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
	end

	local used = #r.owned
	local unlocked = r.slotsUnlocked or 0
	slotsL.Text = ("Slots: %d/%d"):format(used, unlocked)

	for _, pr in ipairs(r.owned) do
		row(pr).Parent = ownedList
	end

	predict = {}
	for _, pr in ipairs(r.owned) do
		predict[pr.slot] = {
			stored   = pr.stored or 0,
			pps      = pr.effPPS or 0,
			capacity = pr.capacity or 0,
		}
	end
	lastT = time()
end

refreshBtn.MouseButton1Click:Connect(function() SFX.Play("UI.Click"); refreshOwned() end)

collectAllBtn.MouseButton1Click:Connect(function()
	local r = CollectAllRF:InvokeServer()
	if not r or not r.ok then
		SFX.Play("UI.Error")
		warn("CollectAll failed:", r and r.err)
	else
		if (r.total or 0) > 0 then
			SFX.Play("Game.Collect")
			showToast("passive", r.total, "Collected")
		else
			SFX.Play("UI.Success")
		end
		refreshOwned()
	end
end)

-- Buy area
mkLabel(printersPanel, "Buy:", 336)
local y = 360
for id, cfg in pairs(PrintersCfg) do
	local txt = string.format("%s  (Cost %s)  PPS %d  Cap %d",
		(cfg.Display or id), formatCoins(cfg.Cost), cfg.PPS, cfg.Capacity)
	mkButton(printersPanel, txt, y, function()
		local r = PlacePrinter:InvokeServer(id)
		if not r or not r.ok then
			SFX.Play("UI.Error")
			warn("Buy failed:", r and r.err)
		else
			SFX.Play("UI.Success")
			task.defer(refreshOwned)
		end
	end)
	y += 34
end
printersPanel.Size = UDim2.new(0, 420, 0, y + 8)

-- Live collectable counter
task.spawn(function()
	while true do
		task.wait(0.5)
		local dt = time() - lastT
		lastT = time()
		local total = 0
		for _, s in pairs(predict) do
			if s.pps and s.capacity then
				s.stored = math.min(s.capacity, (s.stored or 0) + (s.pps or 0) * dt)
				total += math.floor(s.stored)
			end
		end
		TweenService:Create(nv, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = total }):Play()
	end
end)

refreshOwned(); updateAutoUI()

-- Thrones PANEL -----------------------------------------------------------------
ThronesPanel = mkFrame(ui, UDim2.new(0,300,0,10), UDim2.new(0,240,0,140)); ThronesPanel.Visible=false
local ThronesInfo = mkLabel(ThronesPanel, "Next: --", 8)
mkButton(ThronesPanel, "Upgrade Thrones", 36, function()
	local r = UpgradeRF:InvokeServer()
	if r and r.msg then
		SFX.Play(r.ok and "UI.Success" or "UI.Error")
		ThronesInfo.Text = r.msg
	end
end)
local function updateNext()
	local ls = plr:FindFirstChild("leaderstats"); if not ls then return end
	local tier = ls:FindFirstChild("ThronesTier"); if not tier then return end
	local nextCfg = ThronesCfg[tier.Value + 1]
	if nextCfg then
		ThronesInfo.Text = ("Next: %s  Cost: %s  Mult: x%.2f  Slots: %d")
			:format(nextCfg.Name or ("Tier " .. (tier.Value + 1)),
				formatCoins(nextCfg.Cost or 0),
				nextCfg.Multiplier or 1,
				nextCfg.Slots or 1)
	else
		ThronesInfo.Text = "Max tier reached"
	end
end
task.spawn(function() while true do task.wait(1) updateNext() end end)

-- COIN FLIP -------------------------------------------------------------------
coinPanel = mkFrame(ui, UDim2.new(0,300,0,160), UDim2.new(0,240,0,200)); coinPanel.Visible=false
local side, sideBtn = 0, nil
sideBtn = mkButton(coinPanel, "Side: Heads (toggle)", 8, function()
	side = (side == 0) and 1 or 0
	sideBtn.Text = (side == 0) and "Side: Heads (toggle)" or "Side: Tails (toggle)"
end)
local coinBet = mkTextbox(coinPanel, "Bet amount", 48, "100")
mkButton(coinPanel, "Flip!", 84, function()
	SFX.Play("Game.Flip")
	CoinFlipCtl.RequestFlip(side, tonumber(coinBet.Text) or 0)
end)

-- COIN VISUAL
local coinVis = Instance.new("Frame")
coinVis.Size = UDim2.new(0, 96, 0, 96)
coinVis.Position = UDim2.new(0, 70, 0, 110)
coinVis.BackgroundColor3 = Color3.fromRGB(255, 229, 94)
coinVis.BorderSizePixel = 0
coinVis.Parent = coinPanel
local coinCorner = Instance.new("UICorner", coinVis); coinCorner.CornerRadius = UDim.new(1,0)
local coinStroke = Instance.new("UIStroke", coinVis); coinStroke.Thickness = 2; coinStroke.Color = Color3.fromRGB(210, 180, 60)

local coinText = Instance.new("TextLabel")
coinText.BackgroundTransparency = 1
coinText.Size = UDim2.new(1,0,1,0)
coinText.Font = Enum.Font.GothamBold
coinText.TextScaled = true
coinText.TextColor3 = Color3.fromRGB(60, 45, 15)
coinText.Text = "?"
coinText.Parent = coinVis

local coinSpinActive = false
local coinMinEndTime = 0

CF_RoundStarted.OnClientEvent:Connect(function()
	coinSpinActive = true
	coinMinEndTime = time() + 0.8
	coinText.Text = "?"
	-- spin loop
	task.spawn(function()
		while coinSpinActive do
			local tw = TweenService:Create(coinVis, TweenInfo.new(0.35, Enum.EasingStyle.Linear), {Rotation = coinVis.Rotation + 360})
			tw:Play(); tw.Completed:Wait()
		end
	end)
end)

CF_RoundResolved.OnClientEvent:Connect(function(payload)
	local delayTime = math.max(0, coinMinEndTime - time())
	task.delay(delayTime, function()
		coinSpinActive = false
		coinVis.Rotation = 0
		coinText.Text = (payload and payload.result == 0) and "H" or "T"
		-- bounce
		local big = UDim2.new(0, 112, 0, 112)
		local small = UDim2.new(0, 96, 0, 96)
		local t1 = TweenService:Create(coinVis, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = big})
		local t2 = TweenService:Create(coinVis, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Size = small})
		t1:Play(); t1.Completed:Wait(); t2:Play()
	end)
end)

-- WHEEL -----------------------------------------------------------------------
wheelPanel = mkFrame(ui, UDim2.new(0,300,0,370), UDim2.new(0,240,0,200)); wheelPanel.Visible=false
local wheelBet = mkTextbox(wheelPanel, "Bet amount", 8, "100")
mkButton(wheelPanel, "Spin!", 44, function()
	SFX.Play("Game.SpinStart")
	WheelCtl.RequestSpin(tonumber(wheelBet.Text) or 0)
end)

-- WHEEL VISUAL (horizontal tape + center pointer)
local W = {}
W.ITEM_W = 80
W.ITEM_H = 60
W.PAD    = 6
W.REPEATS= 8

local wheelFrame = Instance.new("Frame")
wheelFrame.Size = UDim2.new(0, 220, 0, W.ITEM_H + 16)
wheelFrame.Position = UDim2.new(0, 10, 0, 88)
wheelFrame.BackgroundTransparency = 0.1
wheelFrame.Parent = wheelPanel
wheelFrame.ClipsDescendants = true
Instance.new("UICorner", wheelFrame).CornerRadius = UDim.new(0,6)

local tape = Instance.new("ScrollingFrame")
tape.Size = UDim2.new(1, -20, 1, -20)
tape.Position = UDim2.new(0, 10, 0, 10)
tape.BackgroundTransparency = 1
tape.ScrollBarThickness = 0
tape.ScrollingEnabled = false
tape.CanvasSize = UDim2.new(0, 0, 0, 0)
tape.Parent = wheelFrame

local tapeLayout = Instance.new("UIListLayout", tape)
tapeLayout.FillDirection = Enum.FillDirection.Horizontal
tapeLayout.SortOrder = Enum.SortOrder.LayoutOrder
tapeLayout.Padding = UDim.new(0, W.PAD)
tapeLayout.VerticalAlignment = Enum.VerticalAlignment.Center

local pointer = Instance.new("Frame")
pointer.Size = UDim2.new(0, 2, 1, 0)
pointer.Position = UDim2.new(0.5, 0, 0, 0)
pointer.AnchorPoint = Vector2.new(0.5,0)
pointer.BackgroundColor3 = Color3.fromRGB(255,255,255)
pointer.BorderSizePixel = 0
pointer.Parent = wheelFrame

local slotCount = #WheelCfg.Slots
local totalItems = slotCount * W.REPEATS
local STEP = W.ITEM_W + W.PAD

local function slotLabel(slot)
	-- Prefer a human label if present, otherwise show payout
	if slot.label and slot.label ~= "" then
		return slot.label
	else
		local mult = tonumber(slot.payout) or 0
		if mult == math.floor(mult) then
			return ("x%d"):format(mult)
		else
			return ("x%.2f"):format(mult)
		end
	end
end

local wheelBuilt = false
local function buildWheel()
	if wheelBuilt then return end
	for r = 1, W.REPEATS do
		for i, slot in ipairs(WheelCfg.Slots) do
			local f = Instance.new("Frame")
			f.Size = UDim2.new(0, W.ITEM_W, 0, W.ITEM_H)
			f.BackgroundTransparency = 0.15
			Instance.new("UICorner", f).CornerRadius = UDim.new(0,6)
			local st = Instance.new("UIStroke", f); st.Thickness = 1; st.Color = Color3.fromRGB(0,0,0); st.Transparency = 0.6

			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = UDim2.new(1,0,1,0)
			l.Text = slotLabel(slot)
			l.Font = Enum.Font.GothamBold
			l.TextScaled = true
			l.TextColor3 = Color3.new(1,1,1)
			l.Parent = f

			-- subtle color hint by payout
			local p = tonumber(slot.payout) or 0
			if p >= 5 then
				f.BackgroundColor3 = Color3.fromRGB(180, 110, 220)
			elseif p >= 2 then
				f.BackgroundColor3 = Color3.fromRGB(90, 140, 220)
			else
				f.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
			end

			f.Parent = tape
		end
	end
	tape.CanvasSize = UDim2.new(0, totalItems * STEP - W.PAD, 0, 0)
	tape.CanvasPosition = Vector2.new(0,0)
	wheelBuilt = true
end
buildWheel()

-- Spin loop + landing
local wheelSpinActive = false
local wheelMinEndTime = 0
local wheelSpeed = 380 -- px/sec during free spin
local wheelConn : RBXScriptConnection? = nil

local function pointerOffsetX()
	return wheelFrame.AbsoluteSize.X / 2
end

local function indexCenterX(j)
	return (j - 1) * STEP + (W.ITEM_W / 2)
end

local function currentCanvasX()
	return tape.CanvasPosition.X
end

local function setCanvasX(x)
	local maxX = math.max(0, tape.CanvasSize.X.Offset - wheelFrame.AbsoluteSize.X)
	tape.CanvasPosition = Vector2.new(math.clamp(x, 0, maxX), 0)
end

WH_RoundStarted.OnClientEvent:Connect(function()
	buildWheel()
	wheelSpinActive = true
	wheelMinEndTime = time() + 1.0
	-- drive via RenderStepped so it's buttery
	if wheelConn then wheelConn:Disconnect() wheelConn = nil end
	wheelConn = RunService.RenderStepped:Connect(function(dt)
		if not wheelSpinActive then return end
		setCanvasX(currentCanvasX() + wheelSpeed * dt)
	end)
end)

WH_RoundResolved.OnClientEvent:Connect(function(payload)
	local idx = payload and payload.slotIndex
	if type(idx) ~= "number" then
		-- fail-safe: stop gently
		task.delay(math.max(0, wheelMinEndTime - time()), function()
			wheelSpinActive = false
			if wheelConn then wheelConn:Disconnect(); wheelConn = nil end
			SFX.Play("Game.SpinStop")
		end)
		return
	end

	-- Compute the next occurrence of idx ahead of pointer after at least 2 full cycles
	local pointerX = pointerOffsetX()
	local cx = currentCanvasX() + pointerX
	local jFloat = cx / STEP + 0.5 -- approx item index aligned with pointer
	local base = math.floor(jFloat) + (slotCount * 2)
	local rem = ((idx - 1) - ((base - 1) % slotCount))
	if rem < 0 then rem = rem + slotCount end
	local jTarget = base + rem
	local finalX = indexCenterX(jTarget) - pointerX

	local function stopSpinAndTween()
		wheelSpinActive = false
		if wheelConn then wheelConn:Disconnect(); wheelConn = nil end
		local dist = math.max(0, finalX - currentCanvasX())
		local dur = math.clamp(dist / 600, 0.6, 1.4)
		local tw = TweenService:Create(tape, TweenInfo.new(dur, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {CanvasPosition = Vector2.new(finalX, 0)})
		tw:Play()
		tw.Completed:Connect(function()
			SFX.Play("Game.SpinStop")
		end)
	end

	local delayTime = math.max(0, wheelMinEndTime - time())
	task.delay(delayTime, stopSpinAndTween)
end)

-- Bind controllers to show toasts on resolve (unchanged)
local Binder = {}
function Binder.Error(msg) showToast("loss", 0, msg or "Error") end
function Binder.CoinFlipResult(res, verified, lastBet)
	local payout = tonumber(res and res.payout) or 0
	local profit = tonumber(res and res.profit)
	local bet = tonumber(lastBet) or tonumber(res and res.bet) or 0
	if profit == nil then profit = math.max(0, payout - bet) end
	if profit > 0 then
		SFX.Play(profit >= (bet * 2) and "Game.WinBig" or "Game.WinSmall")
		showToast("win", profit, "Coin Flip")
	else
		SFX.Play("Game.Lose")
		showToast("loss", -bet, "Coin Flip")
	end
end

function Binder.WheelResult(slotIndex, slot, payout, verified, nextHash, lastBet)
	payout = tonumber(payout) or 0
	if payout > 0 then
		SFX.Play(payout >= ((tonumber(lastBet) or 0) * 3) and "Game.WinBig" or "Game.WinSmall")
		showToast("win", payout, "Wheel")
	else
		SFX.Play("Game.Lose")
		showToast("loss", -(tonumber(lastBet) or 0), "Wheel")
	end
end

CoinFlipCtl.SetUI(Binder)
WheelCtl.SetUI(Binder)

-- Prime fairness commits once
CoinFlipCtl.RefreshCommit()
WheelCtl.RefreshCommit()

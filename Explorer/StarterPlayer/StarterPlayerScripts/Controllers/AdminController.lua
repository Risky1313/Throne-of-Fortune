-- StarterPlayer/StarterPlayerScripts/Controllers/AdminController.lua
-- Admin UI v5.9
-- Change: Freeze / Invisibility / NoClip are now true toggle SWITCHES with a sliding knob.
-- They animate and reflect state without extra text. Non-toggle buttons keep dark contrast.
-- All other v5.7 features (grids, presets, dropdowns) retained.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Remotes = RS:WaitForChild("Remotes", 10)
local AdminFolder = Remotes and Remotes:FindFirstChild("Admin")
if Remotes then Remotes.ChildAdded:Connect(function(ch) if ch.Name=="Admin" then AdminFolder=ch end end) end
local function AdminAction() return AdminFolder and AdminFolder:FindFirstChild("AdminAction") or nil end

-- Colors
local COLOR_ON   = Color3.fromRGB(46, 204, 113)   -- green
local COLOR_OFF  = Color3.fromRGB(231, 76, 60)    -- red
local COLOR_BTN  = Color3.fromRGB(64, 68, 82)     -- dark slate for default buttons
local COLOR_TEXT = Color3.fromRGB(255,255,255)

-- RPC helper
local function call(action, payload)
	local rf = AdminAction(); if not rf then return false, "AdminAction not available" end
	local ok, res = pcall(function() return rf:InvokeServer(action, payload) end)
	if not ok then return false, tostring(res) end
	if typeof(res) == "table" and res.ok == false then return false, tostring(res.err or "error") end
	return true, res
end

-- GUI shell
local pg = LocalPlayer:WaitForChild("PlayerGui")
local existing = pg:FindFirstChild("ToF_Admin"); if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name="ToF_Admin"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true; gui.DisplayOrder=1000; gui.Enabled=false; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.Parent=pg

-- Floating layer for dropdown portals (renders above scrollers)
local dropdownLayer = Instance.new("Frame")
dropdownLayer.Name = "DropdownLayer"
dropdownLayer.BackgroundTransparency = 1
dropdownLayer.Size = UDim2.fromScale(1,1)
dropdownLayer.ZIndex = 500
dropdownLayer.Parent = gui

local adminBtn = Instance.new("TextButton")
adminBtn.Name="AdminButton"; adminBtn.Text="Admin"; adminBtn.Font=Enum.Font.GothamMedium; adminBtn.TextSize=16; adminBtn.AutoButtonColor=true
adminBtn.Size=UDim2.fromOffset(96,36); adminBtn.Position=UDim2.new(1,-108,1,-48); adminBtn.BackgroundTransparency=0.15; adminBtn.Parent=gui
do local c=Instance.new("UICorner",adminBtn); c.CornerRadius=UDim.new(0,12); local s=Instance.new("UIStroke",adminBtn); s.Thickness=1; s.Transparency=0.6 end

local overlay=Instance.new("Frame"); overlay.BackgroundColor3=Color3.new(0,0,0); overlay.BackgroundTransparency=1; overlay.Visible=false; overlay.Size=UDim2.fromScale(1,1); overlay.Parent=gui; overlay.Active=true
local modal=Instance.new("Frame"); modal.AnchorPoint=Vector2.new(0.5,0.5); modal.Position=UDim2.fromScale(0.5,0.5); modal.Size=UDim2.fromOffset(860,560); modal.BackgroundTransparency=0.04; modal.Parent=overlay
do local c=Instance.new("UICorner",modal); c.CornerRadius=UDim.new(0,14); local s=Instance.new("UIStroke",modal); s.Transparency=0.4
	local sc=Instance.new("UISizeConstraint",modal); sc.MinSize=Vector2.new(620,460); sc.MaxSize=Vector2.new(1200,800) end

local header=Instance.new("Frame"); header.Name="Header"; header.Parent=modal; header.Size=UDim2.new(1,0,0,56); header.BackgroundTransparency=1
local title=Instance.new("TextLabel"); title.BackgroundTransparency=1; title.Parent=header; title.TextXAlignment=Enum.TextXAlignment.Left; title.Position=UDim2.new(0,20,0,10)
title.Size=UDim2.new(1,-120,1,-10); title.Font=Enum.Font.GothamBold; title.TextScaled=true; title.Text="Admin Tools"
local closeBtn=Instance.new("TextButton"); closeBtn.Parent=header; closeBtn.Text="?"; closeBtn.Font=Enum.Font.GothamBold; closeBtn.TextSize=18; closeBtn.Size=UDim2.fromOffset(36,36)
closeBtn.Position=UDim2.new(1,-48,0,10); closeBtn.BackgroundTransparency=0.1; do local c=Instance.new("UICorner",closeBtn); c.CornerRadius=UDim.new(0,10); local s=Instance.new("UIStroke",closeBtn); s.Transparency=0.7 end
local divider=Instance.new("Frame"); divider.Parent=modal; divider.BackgroundTransparency=0.7; divider.Size=UDim2.new(1,-40,0,1); divider.Position=UDim2.new(0,20,0,56)

local tabBar=Instance.new("Frame"); tabBar.Parent=modal; tabBar.BackgroundTransparency=1; tabBar.Position=UDim2.new(0,20,0,64); tabBar.Size=UDim2.new(1,-40,0,36)
local tabList=Instance.new("UIListLayout",tabBar); tabList.FillDirection=Enum.FillDirection.Horizontal; tabList.Padding=UDim.new(0,8); tabList.SortOrder=Enum.SortOrder.LayoutOrder
local content=Instance.new("Frame"); content.Parent=modal; content.BackgroundTransparency=1; content.Position=UDim2.new(0,20,0,104); content.Size=UDim2.new(1,-40,1,-132)

local function mkTabContent()
	local scroller=Instance.new("ScrollingFrame"); scroller.Size=UDim2.fromScale(1,1); scroller.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroller.CanvasSize=UDim2.new(); scroller.ScrollBarThickness=6; scroller.BackgroundTransparency=1
	local lay=Instance.new("UIListLayout",scroller); lay.Padding=UDim.new(0,12); lay.SortOrder=Enum.SortOrder.LayoutOrder; return scroller
end

local function mkCard(parent, titleText, height)
	local card=Instance.new("Frame"); card.Parent=parent; card.BackgroundTransparency=0.06; card.Size=UDim2.new(1,0,0,height or 100)
	do local c=Instance.new("UICorner",card); c.CornerRadius=UDim.new(0,10); local s=Instance.new("UIStroke",card); s.Transparency=0.7 end
	local head=Instance.new("TextLabel"); head.BackgroundTransparency=1; head.Parent=card; head.Text=titleText; head.Font=Enum.Font.GothamMedium; head.TextSize=16; head.TextXAlignment=Enum.TextXAlignment.Left
	head.Position=UDim2.new(0,12,0,10); head.Size=UDim2.new(1,-24,0,18)
	return card
end

local function mkTab(name)
	local tBtn=Instance.new("TextButton"); tBtn.Parent=tabBar; tBtn.Text=name; tBtn.Size=UDim2.new(0,130,1,0); tBtn.BackgroundTransparency=0.1
	do local c=Instance.new("UICorner",tBtn); c.CornerRadius=UDim.new(0,8); local st=Instance.new("UIStroke",tBtn); st.Transparency=0.7 end
	local page=mkTabContent(); page.Visible=false; page.Parent=content
	return tBtn, page
end

-- Button factory (solid dark by default)
local function mkBtn(parent, text, w, onClick)
	local b=Instance.new("TextButton"); b.Parent=parent; b.Text=text; b.Size=UDim2.new(0, w or 140, 0, 32)
	b.BackgroundTransparency=0; b.BackgroundColor3 = COLOR_BTN; b.TextColor3 = COLOR_TEXT; b.AutoButtonColor=true
	local c=Instance.new("UICorner",b); c.CornerRadius=UDim.new(0,8); local st=Instance.new("UIStroke",b); st.Transparency=0.7
	if onClick then b.MouseButton1Click:Connect(onClick) end
	return b
end

-- SWITCH factory (label + animated slider)
local function mkSwitch(parent, labelText, initial, onToggle)
	local holder = Instance.new("Frame"); holder.Parent = parent; holder.BackgroundTransparency = 1; holder.Size = UDim2.new(0, 220, 0, 36)

	local label = Instance.new("TextLabel"); label.Parent=holder; label.BackgroundTransparency=1; label.TextXAlignment=Enum.TextXAlignment.Left
	label.Text = labelText; label.Font = Enum.Font.GothamMedium; label.TextSize = 14; label.Position = UDim2.new(0, 0, 0, 8); label.Size = UDim2.new(1, -80, 1, -8)

	local track = Instance.new("Frame"); track.Parent = holder; track.Size = UDim2.new(0, 56, 0, 24); track.Position = UDim2.new(1, -70, 0.5, -12)
	track.BackgroundTransparency = 0; do local c=Instance.new("UICorner",track); c.CornerRadius=UDim.new(0, 12); local st=Instance.new("UIStroke",track); st.Transparency=0.5 end

	local knob = Instance.new("Frame"); knob.Parent = track; knob.Size = UDim2.new(0, 20, 0, 20); knob.Position = UDim2.new(0, 2, 0, 2)
	knob.BackgroundColor3 = Color3.new(1,1,1); do local c=Instance.new("UICorner",knob); c.CornerRadius=UDim.new(1, 0) end

	local hit = Instance.new("TextButton"); hit.Parent = track; hit.Text = ""; hit.BackgroundTransparency = 1; hit.Size = UDim2.fromScale(1,1)

	local busy = false
	local state = initial and true or false

	local function apply(v, animate)
		state = v and true or false
		track.BackgroundColor3 = state and COLOR_ON or COLOR_OFF
		local target = state and UDim2.new(1, -22, 0, 2) or UDim2.new(0, 2, 0, 2)
		if animate then
			local ti = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(knob, ti, { Position = target }):Play()
		else
			knob.Position = target
		end
	end
	apply(state, false)

	hit.MouseButton1Click:Connect(function()
		if busy then return end
		busy = true
		local want = not state
		local ok = true
		if onToggle then
			local success, res = pcall(function()
				return onToggle(want)
			end)
			ok = success and (res ~= false)
		end
		if ok then apply(want, true) end
		busy = false
	end)

	return holder, { get = function() return state end, set = function(v) apply(v, true) end }
end

-- Tabs
local tabs = {}; local currentTab=nil
local function selectTab(name) if currentTab then currentTab.page.Visible=false; currentTab.button.AutoButtonColor=true end; currentTab=tabs[name]; if currentTab then currentTab.page.Visible=true; currentTab.button.AutoButtonColor=false end end
local function addTab(name) local b,p = mkTab(name); tabs[name]={button=b,page=p}; b.MouseButton1Click:Connect(function() selectTab(name) end); return tabs[name] end

-- Overview
local tOverview=addTab("Overview")
do
	local card=mkCard(tOverview.page,"Anti-Exploit Summary",90)
	local out = Instance.new("TextLabel",card); out.Name="Out"; out.BackgroundTransparency=1; out.TextXAlignment=Enum.TextXAlignment.Left; out.Position=UDim2.new(0,144,0,40); out.Size=UDim2.new(1,-156,0,24); out.Text="—"
	local btnRefresh=mkBtn(card,"Refresh",120,function()
		local ok,res=call("getExploitSummary"); if not ok then out.Text="Error: "..tostring(res) return end
		local d=res.data or {}; out.Text=string.format("logs=%d  users=%d", d.totalLogs or 0, #(d.users or {}))
	end); btnRefresh.Position=UDim2.new(0,12,0,36)
	local btnPrint=mkBtn(card,"Print to Output",140,function()
		local ok,res=call("getExploitSummary"); if not ok then warn(res) return end
		local d=res.data or {}; print("[Admin] Exploit Summary:", d.totalLogs or 0, "logs")
	end); btnPrint.Position=UDim2.new(0,140+12+8,0,36)
end

-- Players
local tPlayers=addTab("Players")
local selectedUserId=nil

-- player picker card
local function buildPlayerPicker(parent)
	local pick=mkCard(parent,"Pick Player (type Username or DisplayName)",160)
	local box=Instance.new("TextBox"); box.Parent=pick; box.PlaceholderText="Search players..."; box.ClearTextOnFocus=false; box.Size=UDim2.new(1,-24,0,28); box.Position=UDim2.new(0,12,0,36)
	do local c=Instance.new("UICorner",box); c.CornerRadius=UDim.new(0,8); local st=Instance.new("UIStroke",box); st.Transparency=0.7 end
	local list=Instance.new("ScrollingFrame"); list.Parent=pick; list.Size=UDim2.new(1,-24,0,70); list.Position=UDim2.new(0,12,0,68); list.AutomaticCanvasSize=Enum.AutomaticSize.Y; list.ScrollBarThickness=6; list.BackgroundTransparency=0.3
	local ll=Instance.new("UIListLayout",list); ll.Padding=UDim.new(0,4)
	local hint=Instance.new("TextLabel"); hint.Parent=pick; hint.BackgroundTransparency=1; hint.TextXAlignment=Enum.TextXAlignment.Left; hint.Position=UDim2.new(0,12,0,140); hint.Size=UDim2.new(1,-24,0,18); hint.Text="—"
	local function clear() for _,ch in ipairs(list:GetChildren()) do if ch:IsA("GuiObject") and ch~=ll then ch:Destroy() end end end
	local function addOpt(label, uid) local b=mkBtn(list, label, 260, function() selectedUserId=uid; box.Text=label end); b.TextXAlignment=Enum.TextXAlignment.Left; b:SetAttribute("userId",uid) end
	local function refresh(q) q=string.lower(q or ""); clear(); local cands={}
		for _,p in ipairs(Players:GetPlayers()) do local uname=p.Name or ""; local dname=p.DisplayName or ""; local label=string.format("%s  (%s)", dname, uname)
			if q=="" or uname:lower():find(q,1,true) or dname:lower():find(q,1,true) then table.insert(cands,{label=label,uid=p.UserId}) end end
		table.sort(cands,function(a,b) return a.label:lower()<b.label:lower() end); for _,c in ipairs(cands) do addOpt(c.label,c.uid) end
		hint.Text=(#cands>0) and "Tip: TAB selects first match" or "No in-game matches."
	end
	refresh(""); Players.PlayerAdded:Connect(function() refresh(box.Text) end); Players.PlayerRemoving:Connect(function() refresh(box.Text) end); box:GetPropertyChangedSignal("Text"):Connect(function() refresh(box.Text) end)
	box.InputBegan:Connect(function(input,gp) if not gp and input.KeyCode==Enum.KeyCode.Tab then for _,ch in ipairs(list:GetChildren()) do if ch:IsA("TextButton") then selectedUserId=ch:GetAttribute("userId"); box.Text=ch.Text; break end end end end)
	return pick
end

local picker = buildPlayerPicker(tPlayers.page)

-- Movement & Visibility (switches + teleports)
do
	local card=mkCard(tPlayers.page,"Movement & Visibility",170)
	local container = Instance.new("Frame", card); container.BackgroundTransparency=1; container.Position=UDim2.new(0,12,0,36); container.Size=UDim2.new(1,-24,1,-48)
	local grid=Instance.new("UIGridLayout", container); grid.CellPadding=UDim2.new(0,8,0,8); grid.CellSize=UDim2.new(0,220,0,36)
	grid.FillDirection = Enum.FillDirection.Horizontal; grid.SortOrder = Enum.SortOrder.LayoutOrder; grid.StartCorner = Enum.StartCorner.TopLeft

	local function requireSelection()
		return selectedUserId ~= nil
	end

	-- Freeze
	mkSwitch(container, "Freeze", false, function(enabled)
		if not requireSelection() then return false end
		local ok = select(1, call("freeze", { userId = selectedUserId, enabled = enabled }))
		return ok
	end)

	-- Invisibility
	mkSwitch(container, "Invisibility", false, function(enabled)
		if not requireSelection() then return false end
		local ok = select(1, call("invisibility", { userId = selectedUserId, enabled = enabled }))
		return ok
	end)

	-- NoClip (+Fly)
	mkSwitch(container, "NoClip", false, function(enabled)
		if not requireSelection() then return false end
		local ok = select(1, call("noclip", { userId = selectedUserId, enabled = enabled }))
		return ok
	end)

	-- Teleports (regular dark buttons)
	mkBtn(container, "TP to Player", 180, function() if not requireSelection() then return end; call("tpToPlayer", { userId = selectedUserId }) end)
	mkBtn(container, "TP to Me", 180, function() if not requireSelection() then return end; call("tpToMe", { userId = selectedUserId }) end)
end

-- Economy tab
local tEconomy=addTab("Economy")
do
	-- Give Money presets
	local card=mkCard(tEconomy.page,"Give Chips",200)
	local container=Instance.new("Frame",card); container.BackgroundTransparency=1; container.Position=UDim2.new(0,12,0,36); container.Size=UDim2.new(1,-24,0,100)
	local grid=Instance.new("UIGridLayout",container); grid.CellPadding=UDim2.new(0,8,0,8); grid.CellSize=UDim2.new(0,150,0,36); grid.FillDirection=Enum.FillDirection.Horizontal; grid.SortOrder=Enum.SortOrder.LayoutOrder
	local function give(amount) if not selectedUserId then return end; call("addChips",{ userId=selectedUserId, amount=amount }) end
	mkBtn(container, "+100K", 150, function() give(100000) end)
	mkBtn(container, "+1M", 150, function() give(1000000) end)
	mkBtn(container, "+1B", 150, function() give(1000000000) end)
	mkBtn(container, "+1T", 150, function() give(1000000000000) end)

	-- Custom amount row
	local row = Instance.new("Frame", card); row.BackgroundTransparency=1; row.Position = UDim2.new(0,12,0,36+100+8); row.Size = UDim2.new(1,-24,0,36)
	local tb = Instance.new("TextBox", row); tb.Text=""; tb.PlaceholderText = "Type Amount Here"; tb.ClearTextOnFocus=false; tb.Size = UDim2.new(0, 260, 0, 28); tb.Position = UDim2.new(0,0,0,4); tb.BackgroundTransparency = 0.1
	do local c=Instance.new("UICorner",tb); c.CornerRadius=UDim.new(0,8); local st=Instance.new("UIStroke",tb); st.Thickness=1.8; st.Color = Color3.fromRGB(110,116,128); st.Transparency=0.15 end
	local giveBtn = mkBtn(row, "Give Custom Coins", 170, function() local amt = tonumber(tb.Text); if amt and selectedUserId then call("addChips",{ userId=selectedUserId, amount=math.floor(amt) }) end end)
	giveBtn.Position = UDim2.new(0, 280, 0, 4)

	-- Reset Chips single button
	local card2=mkCard(tEconomy.page,"Reset Chips",80)
	local resetBtn=mkBtn(card2,"Reset",180,function() if not selectedUserId then return end; call("setChips",{ userId=selectedUserId, amount=0 }) end)
	resetBtn.Position=UDim2.new(0,12,0,36)
end

-- Moderation
local tMod=addTab("Moderation")
do
	local card=mkCard(tMod.page,"Ban Controls",140)
	local reason=Instance.new("TextBox",card); reason.PlaceholderText="Reason (optional)"; reason.ClearTextOnFocus=false; reason.Size=UDim2.new(1,-24,0,28); reason.Position=UDim2.new(0,12,0,36)
	do local c=Instance.new("UICorner",reason); c.CornerRadius=UDim.new(0,8); local st=Instance.new("UIStroke",reason); st.Transparency=0.7 end
	local container=Instance.new("Frame",card); container.BackgroundTransparency=1; container.Position=UDim2.new(0,12,0,72); container.Size=UDim2.new(1,-24,0,50)
	local grid=Instance.new("UIGridLayout",container); grid.CellPadding=UDim2.new(0,8,0,8); grid.CellSize=UDim2.new(0,160,0,36)
	mkBtn(container,"Ban Temp (1h)",160,function() if not selectedUserId then return end; call("banTemp",{ userId=selectedUserId, seconds=3600, reason=reason.Text }) end)
	mkBtn(container,"Ban Perm",160,function() if not selectedUserId then return end; call("banPerm",{ userId=selectedUserId, reason=reason.Text }) end)
	mkBtn(container,"Unban",160,function() if not selectedUserId then return end; call("unban",{ userId=selectedUserId }) end)
end

-- Utilities
local tUtil=addTab("Utilities")

-- generic dropdown helper

local function mkDropdown(parent, labelText, options, onChanged)
	local card = mkCard(parent, labelText, 120)

	-- Anchor/select button stays inside the card
	local selectBtn = mkBtn(card, "Select…", 220, nil); selectBtn.Position=UDim2.new(0,12,0,36); selectBtn.ZIndex = 199

	-- Floating dropdown "portal" (so it won't be clipped by scrolling frames)
	local portal = Instance.new("Frame", dropdownLayer)
	portal.Visible = false
	portal.Size = UDim2.fromOffset(260, 160)
	portal.BackgroundTransparency = 0.05
	portal.ZIndex = 520
	portal.ClipsDescendants = true
	do
		local c = Instance.new("UICorner", portal); c.CornerRadius = UDim.new(0, 8)
		local st = Instance.new("UIStroke", portal); st.Transparency = 0.15; st.Thickness = 1.6
	end

	local list = Instance.new("ScrollingFrame", portal)
	list.Size = UDim2.new(1, -12, 1, -12)
	list.Position = UDim2.new(0, 6, 0, 6)
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.ZIndex = 521
	local ll = Instance.new("UIListLayout", list); ll.Padding = UDim.new(0,4)

	local selectedValue = nil

	local function rebuild()
		for _,ch in ipairs(list:GetChildren()) do
			if ch:IsA("TextButton") or ch:IsA("Frame") then ch:Destroy() end
		end
		for _,opt in ipairs(options) do
			local b = mkBtn(list, tostring(opt.label or opt), 220, function()
				selectedValue = opt.value or opt
				selectBtn.Text = "Selected: " .. tostring(opt.label or opt)
				portal.Visible = false
				if onChanged then onChanged(selectedValue) end
			end)
			b.ZIndex = 522
		end
	end
	rebuild()

	-- Position portal near the select button
	local function positionPortal()
		local absPos = selectBtn.AbsolutePosition
		local absSize = selectBtn.AbsoluteSize
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1920,1080)
		local w = portal.AbsoluteSize.X; local h = portal.AbsoluteSize.Y
		local px = math.clamp(absPos.X, 8, vp.X - w - 8)
		local py = math.clamp(absPos.Y + absSize.Y + 6, 8, vp.Y - h - 8)
		portal.Position = UDim2.fromOffset(px, py)
	end

	selectBtn.MouseButton1Click:Connect(function()
		if portal.Visible then
			portal.Visible = false
		else
			positionPortal()
			portal.Visible = true
		end
	end)

	-- Hide when clicking outside or closing overlay
	overlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			portal.Visible = false
		end
	end)
	overlay:GetPropertyChangedSignal("Visible"):Connect(function()
		if overlay.Visible == false then portal.Visible = false end
	end)

	-- Reposition on resize/scroll
	selectBtn:GetPropertyChangedSignal("AbsolutePosition"):Connect(positionPortal)
	selectBtn:GetPropertyChangedSignal("AbsoluteSize"):Connect(positionPortal)

	return {
		card = card,
		setOptions = function(newOpts) options = newOpts; rebuild() end,
		getValue = function() return selectedValue end,
		setValue = function(v, label) selectedValue=v; selectBtn.Text = "Selected: "..(label or tostring(v)) end,
		getButton = function() return selectBtn end,
	}
end


do
	-- Give Item: single button; auto-pick if only one Tool in ReplicatedStorage; else tiny picker.
	local card = mkCard(tUtil.page, "Give Item (Tool in ReplicatedStorage)", 100)
	local giveBtn = mkBtn(card, "Give Item", 180, nil); giveBtn.Position=UDim2.new(0,12,0,36)

	local function gatherTools()
		local items = {}
		for _, inst in ipairs(RS:GetDescendants()) do
			if inst:IsA("Tool") then table.insert(items, inst.Name) end
		end
		table.sort(items)
		return items
	end

	local picker -- lazy
	local toolsCache = gatherTools()

	local function runGive(selectedName)
		if not selectedUserId then return end
		if not selectedName then return end
		call("giveItem", { userId = selectedUserId, itemName = selectedName })
	end

	giveBtn.MouseButton1Click:Connect(function()
		if #toolsCache == 0 then
			warn("[Admin] No Tools found in ReplicatedStorage")
			return
		elseif #toolsCache == 1 then
			runGive(toolsCache[1])
		else
			if not picker then
				picker = Instance.new("Frame", card); picker.Size=UDim2.new(0, 260, 0, 140); picker.Position=UDim2.new(0, 12, 0, 36+36+6)
				picker.BackgroundTransparency=0.1; do local c=Instance.new("UICorner",picker); c.CornerRadius=UDim.new(0,8); local st=Instance.new("UIStroke",picker); st.Transparency=0.7 end
				local list = Instance.new("ScrollingFrame", picker); list.Size=UDim2.new(1, -12, 1, -12); list.Position=UDim2.new(0,6,0,6); list.ScrollBarThickness=6; list.AutomaticCanvasSize=Enum.AutomaticSize.Y; list.BackgroundTransparency=1
				local ll = Instance.new("UIListLayout", list); ll.Padding=UDim.new(0,4)
				for _,name in ipairs(toolsCache) do mkBtn(list, name, 220, function() runGive(name); picker.Visible=false end) end
			end
			picker.Visible = not picker.Visible
		end
	end)
end

do
	-- Give Printer: dropdown from Config.Printers
	local okPrinters, printerList = pcall(function()
		local cfg = require(RS:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Printers"))
		local out = {}
		if typeof(cfg) == "table" then
			for id, data in pairs(cfg) do
				local label = tostring(data.name or data.Name or ("Printer "..tostring(id)))
				table.insert(out, { label = label, value = id })
			end
			table.sort(out, function(a,b) return tostring(a.label) < tostring(b.label) end)
		end
		return out
	end)
	if not okPrinters then printerList = { {label="Basic Printer", value=1}, {label="Pro Printer", value=2} } end

	local dd = mkDropdown(tUtil.page, "Give Printer", printerList, nil)
	local giveBtn = mkBtn(dd.card, "Send", 120, function()
		if not selectedUserId then return end
		local v = dd.getValue(); if not v then return end
		call("givePrinter", { userId = selectedUserId, printerId = v })
	end); giveBtn.Position=UDim2.new(0, 12+220+8, 0, 36)
end

do
	-- Start Event: dropdown (placeholder list)
	local eventOptions = {
		{ label = "DoubleChips (2m)", value = "DoubleChips2m" },
		{ label = "PrinterRain (30s)", value = "PrinterRain30s" },
		{ label = "Fireworks (cosmetic)", value = "Fireworks" },
	}
	local dd = mkDropdown(tUtil.page, "Start Event", eventOptions, nil)
	local startBtn = mkBtn(dd.card, "Start", 120, function()
		local v = dd.getValue(); if not v then return end
		call("startEvent", { key = v })
	end); startBtn.Position=UDim2.new(0, 12+220+8, 0, 36)
end

do
	-- Give Key: dropdown (placeholder names), Send to ALL / Selected
	local keyOptions = {
		{ label = "Bronze Key", value = "BronzeKey" },
		{ label = "Silver Key", value = "SilverKey" },
		{ label = "Gold Key", value = "GoldKey" },
	}
	local dd = mkDropdown(tUtil.page, "Give Key (placeholder)", keyOptions, nil)
	local toAll = mkBtn(dd.card, "Send to ALL", 140, function()
		local v = dd.getValue(); if not v then return end
		call("giveKey", { toAll = true, keyName = v })
	end); toAll.Position=UDim2.new(0, 12+220+8, 0, 36)
	local toSel = mkBtn(dd.card, "Send to Selected", 160, function()
		if not selectedUserId then return end
		local v = dd.getValue(); if not v then return end
		call("giveKey", { userId = selectedUserId, keyName = v })
	end); toSel.Position=UDim2.new(0, 12+220+8+140+8, 0, 36)
end

-- Open/close
local function openModal() overlay.Visible=true; overlay.BackgroundTransparency=1; modal.Size=UDim2.fromOffset(820,520); local ti=TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(overlay, ti, { BackgroundTransparency = 0.35 }):Play(); TweenService:Create(modal, ti, { Size = UDim2.fromOffset(860, 560) }):Play() end
local function closeModal() local ti=TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(overlay, ti, { BackgroundTransparency = 1 }):Play(); TweenService:Create(modal, ti, { Size = UDim2.fromOffset(820, 520) }):Play(); task.delay(0.16, function() overlay.Visible=false end) end
adminBtn.MouseButton1Click:Connect(function() if not overlay.Visible then openModal() else closeModal() end end)
closeBtn.MouseButton1Click:Connect(closeModal)
overlay.InputBegan:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 then local abs=modal.AbsolutePosition; local size=modal.AbsoluteSize; local pos=input.Position
		if pos.X<abs.X or pos.X>abs.X+size.X or pos.Y<abs.Y or pos.Y>abs.Y+size.Y then closeModal() end end end)
UserInputService.InputBegan:Connect(function(input,gp) if gp then return end; if input.KeyCode==Enum.KeyCode.F8 then if not overlay.Visible then openModal() else closeModal() end
	elseif input.KeyCode==Enum.KeyCode.Escape and overlay.Visible then closeModal() end end)

-- Authorization
local authorized=false
local function refreshAuth() local ok=select(1,call("ping")); authorized = ok and true or false; gui.Enabled = authorized end
refreshAuth(); task.delay(3, refreshAuth); task.delay(8, refreshAuth); task.spawn(function() while not authorized do task.wait(15); refreshAuth() end end)

-- Default tab
selectTab("Players")
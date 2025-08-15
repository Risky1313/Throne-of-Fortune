local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local Sounds = require(RS.Shared.Config.Sounds)

local SFX = {}
local cache: {[string]: Sound} = {}
local bad: {[string]: boolean} = {}

local function resolve(key: string)
	local t: any = Sounds
	for seg in string.gmatch(key, "[^%.]+") do
		if typeof(t) ~= "table" then return nil end
		t = t[seg]
	end
	return t
end

local function getSound(key: string): Sound?
	if bad[key] then return nil end
	if cache[key] then return cache[key] end
	local id = resolve(key)
	if type(id) ~= "string" or id == "" then
		bad[key] = true
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = key
	s.SoundId = id
	s.Volume = 0.7
	s.RollOffMaxDistance = 0
	s.Parent = SoundService
	cache[key] = s
	return s
end

function SFX.Preload(keys: {string})
	if not RunService:IsClient() then return end
	local insts = {}
	for _, key in ipairs(keys) do
		local s = getSound(key)
		if s then table.insert(insts, s) end
	end
	if #insts > 0 then
		local ok = pcall(function() ContentProvider:PreloadAsync(insts) end)
		if not ok then
			-- if preload fails (403), mark keys bad so we stop trying
			for _, s in ipairs(insts) do bad[s.Name] = true end
		end
	end
end

function SFX.Play(key: string, volume: number?)
	if not RunService:IsClient() then return end
	if bad[key] then return end
	local s = getSound(key)
	if not s then return end
	if typeof(volume) == "number" then s.Volume = volume end
	local ok = pcall(function()
		if SoundService.PlayLocalSound then
			SoundService:PlayLocalSound(s)
		else
			s:Play()
		end
	end)
	if not ok then
		bad[key] = true -- silence future attempts on forbidden/missing assets
	end
end

return SFX

-- ReplicatedStorage/Shared/Config/Map.lua
-- Basic world layout config (can be arted up later)
return {
	NumPads = 12,               -- number of player plots around the ring
	Radius = 180,               -- distance from world center to pad center (studs)
	PadSize = Vector3.new(90,3,90),
	BaseHeight = 0,             -- Y of the plaza base
	PadColor = Color3.fromRGB(24, 28, 34),
	BaseColor = Color3.fromRGB(18, 22, 28),
	AccentColor = Color3.fromRGB(0, 168, 255),
	SpawnAtPad = true,          -- teleport players to their pad on spawn
	LabelPlots = true,          -- draw a small label on each pad
}
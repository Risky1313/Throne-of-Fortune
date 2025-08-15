-- ReplicatedStorage/Shared/Util/RemotesGuard.lua
-- Small helpers shared by client/server. Avoid server-only state here.

local Guard = {}

function Guard.isFinite(n)
	return typeof(n) == "number" and n == n and n > -math.huge and n < math.huge
end

function Guard.int(n, min, max)
	n = tonumber(n)
	if not Guard.isFinite(n) then return nil end
	n = math.floor(n + 0.0)
	if min ~= nil and n < min then return nil end
	if max ~= nil and n > max then return nil end
	return n
end

function Guard.num(n, min, max)
	n = tonumber(n)
	if not Guard.isFinite(n) then return nil end
	if min ~= nil and n < min then return nil end
	if max ~= nil and n > max then return nil end
	return n
end

return Guard

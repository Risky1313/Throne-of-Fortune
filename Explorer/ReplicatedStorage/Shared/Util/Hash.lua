-- ReplicatedStorage/Shared/Util/Hash  (SHA-256)
local bit = bit32
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift = bit.lshift, bit.rshift

local function rrotate(x, n)
	n = n % 32
	return bor(rshift(x, n), lshift(x, 32 - n)) % 4294967296
end

local K = {
	0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
	0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
	0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
	0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
	0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
	0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
	0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
	0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}

local function tohex(x) return string.format("%08x", x) end

local function preprocess(msg)
	local len = #msg
	local bitlen_hi = math.floor((len * 8) / 2^32)
	local bitlen_lo = (len * 8) % 2^32

	-- bytes ? table of bytes
	local bytes = table.create(len + 72)
	for i = 1, len do bytes[i] = string.byte(msg, i) end
	bytes[len + 1] = 0x80

	local newLen = len + 1
	while (newLen % 64) ~= 56 do
		bytes[newLen + 1] = 0x00
		newLen += 1
	end

	-- append 64-bit big-endian length
	bytes[newLen + 1] = rshift(bitlen_hi, 24) % 256
	bytes[newLen + 2] = rshift(bitlen_hi, 16) % 256
	bytes[newLen + 3] = rshift(bitlen_hi, 8) % 256
	bytes[newLen + 4] = bitlen_hi % 256
	bytes[newLen + 5] = rshift(bitlen_lo, 24) % 256
	bytes[newLen + 6] = rshift(bitlen_lo, 16) % 256
	bytes[newLen + 7] = rshift(bitlen_lo, 8) % 256
	bytes[newLen + 8] = bitlen_lo % 256
	return bytes
end

local function digest(msg)
	local H0,H1,H2,H3 = 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a
	local H4,H5,H6,H7 = 0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19

	local bytes = preprocess(tostring(msg))
	local W = table.create(64, 0)

	for i = 1, #bytes, 64 do
		for t = 0, 15 do
			local j = i + t*4
			W[t] = bor(lshift(bytes[j] or 0, 24), lshift(bytes[j+1] or 0, 16),
				lshift(bytes[j+2] or 0, 8), (bytes[j+3] or 0)) % 4294967296
		end
		for t = 16, 63 do
			local s0 = bxor(rrotate(W[t-15],7), rrotate(W[t-15],18), rshift(W[t-15],3))
			local s1 = bxor(rrotate(W[t-2],17), rrotate(W[t-2],19), rshift(W[t-2],10))
			W[t] = (W[t-16] + s0 + W[t-7] + s1) % 4294967296
		end

		local a,b,c,d,e,f,g,h = H0,H1,H2,H3,H4,H5,H6,H7
		for t = 0,63 do
			local S1 = bxor(rrotate(e,6), rrotate(e,11), rrotate(e,25))
			local ch = bxor(band(e,f), band(bnot(e), g))
			local T1 = (h + S1 + ch + K[t+1] + W[t]) % 4294967296
			local S0 = bxor(rrotate(a,2), rrotate(a,13), rrotate(a,22))
			local maj = bxor(band(a,b), band(a,c), band(b,c))
			local T2 = (S0 + maj) % 4294967296

			h = g; g = f; f = e
			e = (d + T1) % 4294967296
			d = c; c = b; b = a
			a = (T1 + T2) % 4294967296
		end

		H0 = (H0 + a) % 4294967296
		H1 = (H1 + b) % 4294967296
		H2 = (H2 + c) % 4294967296
		H3 = (H3 + d) % 4294967296
		H4 = (H4 + e) % 4294967296
		H5 = (H5 + f) % 4294967296
		H6 = (H6 + g) % 4294967296
		H7 = (H7 + h) % 4294967296
	end

	return (tohex(H0)..tohex(H1)..tohex(H2)..tohex(H3)..
		tohex(H4)..tohex(H5)..tohex(H6)..tohex(H7))
end

local Hash = {}
function Hash.digest(s) return digest(s) end
return Hash

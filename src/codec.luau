--[[
	LAYER 1: LOW-LEVEL BINARY CODEC
	
	Provides primitive encode/decode functions for:
	- IEEE 754 doubles (d2b/b2d)
	- Fixed-width integers (i2b/b2i, i642b/b2i64)
	- Vector3 (v32b/b2v3)
	- Length-prefixed strings (s2b/b2s)
	- Tagged "Any" type (a2b/b2a)
]]

local codec = {}

-- ============================================================================
-- HELPER: Byte manipulation
-- ============================================================================

local function bytes_to_num(b1, b2, b3, b4, b5, b6, b7, b8)
	local val = 0
	val = bit32.bor(val, bit32.lshift(b1, 0))
	val = bit32.bor(val, bit32.lshift(b2, 8))
	val = bit32.bor(val, bit32.lshift(b3, 16))
	val = bit32.bor(val, bit32.lshift(b4, 24))
	if b5 then
		local hi = 0
		hi = bit32.bor(hi, bit32.lshift(b5, 0))
		hi = bit32.bor(hi, bit32.lshift(b6, 8))
		hi = bit32.bor(hi, bit32.lshift(b7, 16))
		hi = bit32.bor(hi, bit32.lshift(b8, 24))
		return val, hi
	end
	return val
end

local function num_to_bytes(val, is_64)
	if is_64 then
		error("64-bit conversion requires separate handling")
	end
	local b1 = bit32.band(val, 0xFF)
	local b2 = bit32.band(bit32.rshift(val, 8), 0xFF)
	local b3 = bit32.band(bit32.rshift(val, 16), 0xFF)
	local b4 = bit32.band(bit32.rshift(val, 24), 0xFF)
	return b1, b2, b3, b4
end

-- ============================================================================
-- IEEE 754 DOUBLE (64-bit float)
-- ============================================================================

local function d2b(value)
	--[[
		Encode IEEE 754 double-precision float to 8 bytes (little-endian)
		Handles: inf, -inf, NaN, subnormals, zero
	]]
	local buf = {}
	
	if value == 0 then
		-- Check for negative zero
		local is_negative = 1 / value < 0
		if is_negative then
			return {0, 0, 0, 0, 0, 0, 0, 128}
		else
			return {0, 0, 0, 0, 0, 0, 0, 0}
		end
	end
	
	if value ~= value then
		-- NaN: quiet NaN with all payload bits set
		return {0, 0, 0, 0, 0, 0, 248, 127}
	end
	
	if value == math.huge then
		-- Positive infinity
		return {0, 0, 0, 0, 0, 0, 240, 127}
	end
	
	if value == -math.huge then
		-- Negative infinity
		return {0, 0, 0, 0, 0, 0, 240, 255}
	end
	
	-- For regular doubles, use string.pack
	-- (Luau's math.frexp and math.ldexp can help, but direct bit manipulation is safer)
	local sign = value < 0 and 1 or 0
	local abs_val = math.abs(value)
	
	-- Extract exponent and mantissa using frexp
	local mantissa, exponent = math.frexp(abs_val)
	
	-- frexp returns mantissa in [0.5, 1), we need to convert to IEEE format
	-- mantissa * 2 is in [1, 2) for normalized numbers
	mantissa = mantissa * 2
	exponent = exponent - 1
	
	-- Convert to IEEE 754 format
	-- Add bias of 1023 to exponent
	local biased_exp = exponent + 1023
	
	-- Handle subnormals
	if biased_exp <= 0 then
		-- Subnormal number
		mantissa = mantissa * math.pow(2, exponent + 1022)
		biased_exp = 0
	elseif biased_exp >= 2047 then
		-- Overflow to infinity
		return sign == 0 and {0, 0, 0, 0, 0, 0, 240, 127} or {0, 0, 0, 0, 0, 0, 240, 255}
	end
	
	-- Mantissa has 52 bits of precision (plus implicit leading 1)
	local mant_bits = (mantissa - 1) * math.pow(2, 52)
	mant_bits = math.floor(mant_bits + 0.5) -- Round to nearest
	
	-- Split into low 32 bits and high 20 bits + 11 exponent bits + 1 sign bit
	local low32 = math.floor(mant_bits) % 0x100000000
	local high32 = math.floor(mant_bits / 0x100000000)
	
	-- Combine high mantissa (20 bits), exponent (11 bits), and sign (1 bit)
	high32 = bit32.bor(high32, bit32.lshift(biased_exp, 20))
	high32 = bit32.bor(high32, bit32.lshift(sign, 31))
	
	-- Convert to bytes (little-endian)
	local b1, b2, b3, b4 = num_to_bytes(low32)
	local b5, b6, b7, b8 = num_to_bytes(high32)
	
	return {b1, b2, b3, b4, b5, b6, b7, b8}
end

local function b2d(buf, offset)
	--[[
		Decode 8 bytes to IEEE 754 double-precision float (little-endian)
		Returns: (value, newOffset)
	]]
	offset = offset or 1
	if offset + 7 > #buf then
		error("Buffer underflow: not enough bytes for double")
	end
	
	local b1 = buf[offset]
	local b2 = buf[offset + 1]
	local b3 = buf[offset + 2]
	local b4 = buf[offset + 3]
	local b5 = buf[offset + 4]
	local b6 = buf[offset + 5]
	local b7 = buf[offset + 6]
	local b8 = buf[offset + 7]
	
	local low32 = bytes_to_num(b1, b2, b3, b4)
	local high32 = bytes_to_num(b5, b6, b7, b8)
	
	-- Extract sign, exponent, and mantissa
	local sign = bit32.rshift(high32, 31)
	local exp = bit32.band(bit32.rshift(high32, 20), 0x7FF)
	local mant = bit32.band(high32, 0xFFFFF)
	
	-- Combine with low32
	mant = bit32.bor(bit32.lshift(mant, 32), low32)
	
	-- Handle special cases
	if exp == 0x7FF then
		if mant == 0 then
			-- Infinity
			return (sign == 0 and math.huge or -math.huge), offset + 8
		else
			-- NaN
			return 0/0, offset + 8
		end
	end
	
	if exp == 0 and mant == 0 then
		-- Zero
		return (sign == 0 and 0 or -0), offset + 8
	end
	
	-- Reconstruct value
	local value
	if exp == 0 then
		-- Subnormal
		value = math.ldexp(mant / math.pow(2, 52), -1022)
	else
		-- Normal
		value = math.ldexp((1 + mant / math.pow(2, 52)), exp - 1023)
	end
	
	if sign == 1 then
		value = -value
	end
	
	return value, offset + 8
end

-- ============================================================================
-- FIXED-WIDTH INTEGERS (32-bit and 64-bit)
-- ============================================================================

local function i2b(value)
	--[[ Encode 32-bit signed integer to 4 bytes (little-endian) ]]
	-- Handle as unsigned for bit operations
	if value < 0 then
		value = value + 0x100000000
	end
	return {
		bit32.band(value, 0xFF),
		bit32.band(bit32.rshift(value, 8), 0xFF),
		bit32.band(bit32.rshift(value, 16), 0xFF),
		bit32.band(bit32.rshift(value, 24), 0xFF),
	}
end

local function b2i(buf, offset)
	--[[ Decode 4 bytes to 32-bit signed integer (little-endian) ]]
	offset = offset or 1
	if offset + 3 > #buf then
		error("Buffer underflow: not enough bytes for int32")
	end
	
	local val = bytes_to_num(buf[offset], buf[offset + 1], buf[offset + 2], buf[offset + 3])
	
	-- Convert to signed
	if val >= 0x80000000 then
		val = val - 0x100000000
	end
	
	return val, offset + 4
end

local function i642b(value)
	--[[ Encode 64-bit signed integer to 8 bytes (little-endian) ]]
	-- Lua uses double, so we need careful handling
	local lo = value % 0x100000000
	local hi = math.floor(value / 0x100000000)
	
	if lo < 0 then
		lo = lo + 0x100000000
	end
	if hi < 0 then
		hi = hi + 0x100000000
	end
	
	local b1, b2, b3, b4 = num_to_bytes(lo)
	local b5, b6, b7, b8 = num_to_bytes(hi)
	
	return {b1, b2, b3, b4, b5, b6, b7, b8}
end

local function b2i64(buf, offset)
	--[[ Decode 8 bytes to 64-bit signed integer (little-endian) ]]
	offset = offset or 1
	if offset + 7 > #buf then
		error("Buffer underflow: not enough bytes for int64")
	end
	
	local lo = bytes_to_num(buf[offset], buf[offset + 1], buf[offset + 2], buf[offset + 3])
	local hi = bytes_to_num(buf[offset + 4], buf[offset + 5], buf[offset + 6], buf[offset + 7])
	
	local val = lo + hi * 0x100000000
	
	-- Convert to signed
	if hi >= 0x80000000 then
		val = val - 0x10000000000000000
	end
	
	return val, offset + 8
end

-- ============================================================================
-- VECTOR3 (three packed doubles)
-- ============================================================================

local function v32b(vec)
	--[[ Encode Vector3 to 24 bytes (three doubles) ]]
	local buf = {}
	local dx = d2b(vec.X)
	local dy = d2b(vec.Y)
	local dz = d2b(vec.Z)
	
	for i = 1, 8 do
		table.insert(buf, dx[i])
		table.insert(buf, dy[i])
		table.insert(buf, dz[i])
	end
	
	return buf
end

local function b2v3(buf, offset)
	--[[ Decode 24 bytes to Vector3 ]]
	offset = offset or 1
	if offset + 23 > #buf then
		error("Buffer underflow: not enough bytes for Vector3")
	end
	
	local x, _ = b2d(buf, offset)
	local y, _ = b2d(buf, offset + 8)
	local z, _ = b2d(buf, offset + 16)
	
	return Vector3.new(x, y, z), offset + 24
end

-- ============================================================================
-- LENGTH-PREFIXED STRINGS
-- ============================================================================

local function s2b(str)
	--[[ Encode length-prefixed string (4-byte length + UTF-8 bytes) ]]
	local len = #str
	local buf = i2b(len)
	
	for i = 1, len do
		table.insert(buf, string.byte(str, i))
	end
	
	return buf
end

local function b2s(buf, offset)
	--[[ Decode length-prefixed string ]]
	offset = offset or 1
	if offset + 3 > #buf then
		error("Buffer underflow: not enough bytes for string length")
	end
	
	local len, next_offset = b2i(buf, offset)
	
	if len < 0 or next_offset + len - 1 > #buf then
		error("Buffer underflow: invalid string length")
	end
	
	local str = ""
	for i = next_offset, next_offset + len - 1 do
		str = str .. string.char(buf[i])
	end
	
	return str, next_offset + len
end

-- ============================================================================
-- TAGGED "ANY" TYPE
-- ============================================================================

local TAG_NULL = 0
local TAG_BOOL = 1
local TAG_NUMBER = 2
local TAG_STRING = 3
local TAG_TABLE = 4 -- Not directly encoded; used for schema-driven encoding

local function a2b(value)
	--[[ Encode tagged "Any" value (1 byte tag + payload) ]]
	local buf = {}
	
	if value == nil then
		table.insert(buf, TAG_NULL)
	elseif type(value) == "boolean" then
		table.insert(buf, TAG_BOOL)
		table.insert(buf, value and 1 or 0)
	elseif type(value) == "number" then
		table.insert(buf, TAG_NUMBER)
		local dbuf = d2b(value)
		for _, b in ipairs(dbuf) do
			table.insert(buf, b)
		end
	elseif type(value) == "string" then
		table.insert(buf, TAG_STRING)
		local sbuf = s2b(value)
		for _, b in ipairs(sbuf) do
			table.insert(buf, b)
		end
	else
		error("Cannot encode value of type " .. type(value) .. " as Any")
	end
	
	return buf
end

local function b2a(buf, offset)
	--[[ Decode tagged "Any" value ]]
	offset = offset or 1
	if offset > #buf then
		error("Buffer underflow: not enough bytes for Any tag")
	end
	
	local tag = buf[offset]
	offset = offset + 1
	
	if tag == TAG_NULL then
		return nil, offset
	elseif tag == TAG_BOOL then
		if offset > #buf then
			error("Buffer underflow: not enough bytes for boolean")
		end
		return buf[offset] ~= 0, offset + 1
	elseif tag == TAG_NUMBER then
		return b2d(buf, offset)
	elseif tag == TAG_STRING then
		return b2s(buf, offset)
	else
		error("Unknown Any tag: " .. tag)
	end
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

codec.d2b = d2b
codec.b2d = b2d

codec.i2b = i2b
codec.b2i = b2i

codec.i642b = i642b
codec.b2i64 = b2i64

codec.v32b = v32b
codec.b2v3 = b2v3

codec.s2b = s2b
codec.b2s = b2s

codec.a2b = a2b
codec.b2a = b2a

codec.TAG_NULL = TAG_NULL
codec.TAG_BOOL = TAG_BOOL
codec.TAG_NUMBER = TAG_NUMBER
codec.TAG_STRING = TAG_STRING
codec.TAG_TABLE = TAG_TABLE

return codec

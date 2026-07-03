-- LAYER 1: LOW-LEVEL BINARY CODEC
-- IEEE 754 double-precision floats, fixed-width integers, Vector3, strings, and tagged Any type

local codec = {}

-- Utility: Convert number to 8 bytes (little-endian doubles)
local function double_to_bytes(value: number): string
	if value ~= value then
		-- NaN
		return string.char(0, 0, 0, 0, 0, 0, 0xF8, 0x7F)
	elseif value == math.huge then
		-- +inf
		return string.char(0, 0, 0, 0, 0, 0, 0xF0, 0x7F)
	elseif value == -math.huge then
		-- -inf
		return string.char(0, 0, 0, 0, 0, 0, 0xF0, 0xFF)
	elseif value == 0 then
		-- Handle signed zero
		if 1 / value < 0 then
			-- Negative zero
			return string.char(0, 0, 0, 0, 0, 0, 0, 0x80)
		else
			-- Positive zero
			return string.char(0, 0, 0, 0, 0, 0, 0, 0)
		end
	else
		-- Standard IEEE 754 encoding
		local bytes = ""
		local mantissa, exp = math.frexp(value)
		exp = exp + 1022
		
		-- Sign bit
		local sign = value < 0 and 1 or 0
		
		-- Normalize mantissa (remove implicit leading 1)
		mantissa = (math.abs(mantissa) * 2 - 1) * 0x10000000000000
		
		-- Combine: sign (1 bit) + exponent (11 bits) + mantissa (52 bits)
		local high = bit32.bor(
			bit32.lshift(sign, 31),
			bit32.lshift(bit32.band(exp, 0x7FF), 20),
			bit32.band(bit32.rshift(mantissa, 32), 0xFFFFF)
		)
		local low = bit32.band(mantissa, 0xFFFFFFFF)
		
		-- Convert to little-endian bytes
		for i = 0, 3 do
			bytes = bytes .. string.char(bit32.band(bit32.rshift(low, i * 8), 0xFF))
		end
		for i = 0, 3 do
			bytes = bytes .. string.char(bit32.band(bit32.rshift(high, i * 8), 0xFF))
		end
		
		return bytes
	end
end

local function bytes_to_double(bytes: string, offset: number): number
	offset = offset or 1
	
	local low = 0
	for i = 0, 3 do
		low = bit32.bor(low, bit32.lshift(string.byte(bytes, offset + i), i * 8))
	end
	
	local high = 0
	for i = 0, 3 do
		high = bit32.bor(high, bit32.lshift(string.byte(bytes, offset + 4 + i), i * 8))
	end
	
	local sign = bit32.band(bit32.rshift(high, 31), 1)
	local exp = bit32.band(bit32.rshift(high, 20), 0x7FF)
	local mantissa = bit32.bor(bit32.lshift(bit32.band(high, 0xFFFFF), 32), low)
	
	if exp == 0x7FF then
		if mantissa == 0 then
			return sign == 0 and math.huge or -math.huge
		else
			return 0 / 0 -- NaN
		end
	elseif exp == 0 then
		return sign == 0 and 0 or -0
	else
		local value = (mantissa / 0x10000000000000 + 1) * math.ldexp(1, exp - 1023)
		return sign == 0 and value or -value
	end
end

-- Encode double (IEEE 754)
function codec.d2b(value: number): string
	return double_to_bytes(value)
end

-- Decode double
function codec.b2d(bytes: string, offset: number?): (number, number)
	offset = offset or 1
	return bytes_to_double(bytes, offset), offset + 8
end

-- Encode 4-byte integer (little-endian)
function codec.i2b(value: number): string
	value = bit32.band(value, 0xFFFFFFFF)
	local bytes = ""
	for i = 0, 3 do
		bytes = bytes .. string.char(bit32.band(bit32.rshift(value, i * 8), 0xFF))
	end
	return bytes
end

-- Decode 4-byte integer
function codec.b2i(bytes: string, offset: number?): (number, number)
	offset = offset or 1
	local value = 0
	for i = 0, 3 do
		value = bit32.bor(value, bit32.lshift(string.byte(bytes, offset + i), i * 8))
	end
	return value, offset + 4
end

-- Encode 8-byte integer (little-endian, as two 32-bit parts)
function codec.i642b(value: number): string
	-- Luau's number is IEEE 754 double, so we split it
	local high = math.floor(value / 0x100000000)
	local low = bit32.band(value, 0xFFFFFFFF)
	return codec.i2b(low) .. codec.i2b(high)
end

-- Decode 8-byte integer
function codec.b2i64(bytes: string, offset: number?): (number, number)
	offset = offset or 1
	local low, _ = codec.b2i(bytes, offset)
	local high, _ = codec.b2i(bytes, offset + 4)
	return low + high * 0x100000000, offset + 8
end

-- Encode Vector3 (three doubles)
function codec.v32b(vec: Vector3): string
	return codec.d2b(vec.X) .. codec.d2b(vec.Y) .. codec.d2b(vec.Z)
end

-- Decode Vector3
function codec.b2v3(bytes: string, offset: number?): (Vector3, number)
	offset = offset or 1
	local x, offset = codec.b2d(bytes, offset)
	local y, offset = codec.b2d(bytes, offset)
	local z, offset = codec.b2d(bytes, offset)
	return Vector3.new(x, y, z), offset
end

-- Encode length-prefixed string (4-byte length + raw bytes)
function codec.s2b(str: string): string
	local len = #str
	return codec.i2b(len) .. str
end

-- Decode length-prefixed string
function codec.b2s(bytes: string, offset: number?): (string, number)
	offset = offset or 1
	local len, offset = codec.b2i(bytes, offset)
	local str = string.sub(bytes, offset, offset + len - 1)
	return str, offset + len
end

-- Encode tagged Any type (1 byte tag + payload)
-- Tags: 0=nil, 1=boolean, 2=number, 3=string, 4=Vector3, 5=table
function codec.any2b(value: any): string
	if value == nil then
		return string.char(0)
	elseif type(value) == "boolean" then
		return string.char(1) .. string.char(value and 1 or 0)
	elseif type(value) == "number" then
		return string.char(2) .. codec.d2b(value)
	elseif type(value) == "string" then
		return string.char(3) .. codec.s2b(value)
	elseif typeof(value) == "Vector3" then
		return string.char(4) .. codec.v32b(value)
	else
		error("Cannot encode value of type " .. type(value))
	end
end

-- Decode tagged Any type
function codec.b2any(bytes: string, offset: number?): (any, number)
	offset = offset or 1
	local tag = string.byte(bytes, offset)
	offset = offset + 1
	
	if tag == 0 then
		return nil, offset
	elseif tag == 1 then
		local val = string.byte(bytes, offset) ~= 0
		return val, offset + 1
	elseif tag == 2 then
		return codec.b2d(bytes, offset)
	elseif tag == 3 then
		return codec.b2s(bytes, offset)
	elseif tag == 4 then
		return codec.b2v3(bytes, offset)
	else
		error("Unknown tag " .. tostring(tag))
	end
end

return codec

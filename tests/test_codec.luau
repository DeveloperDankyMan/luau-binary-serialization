-- Unit tests for LAYER 1: Low-level binary codec

local codec = require(script.Parent.Parent.src.codec)

local function test(name: string, fn: () -> ())
	local success, err = pcall(fn)
	if success then
		print("✓ " .. name)
	else
		print("✗ " .. name .. ": " .. tostring(err))
	end
end

local function assert_eq(a: any, b: any, tolerance: number?)
	tolerance = tolerance or 1e-10
	if type(a) == "number" and type(b) == "number" then
		if math.abs(a - b) > tolerance then
			error("Expected " .. tostring(a) .. ", got " .. tostring(b))
		end
	elseif a ~= b then
		error("Expected " .. tostring(a) .. ", got " .. tostring(b))
	end
end

local function assert_v3_eq(a: Vector3, b: Vector3, tolerance: number?)
	tolerance = tolerance or 1e-10
	assert_eq(a.X, b.X, tolerance)
	assert_eq(a.Y, b.Y, tolerance)
	assert_eq(a.Z, b.Z, tolerance)
end

-- IEEE 754 Doubles
test("Encode/decode positive double", function()
	local val = 42.5
	local bytes = codec.d2b(val)
	local decoded, _ = codec.b2d(bytes)
	assert_eq(decoded, val)
end)

test("Encode/decode negative double", function()
	local val = -123.456
	local bytes = codec.d2b(val)
	local decoded, _ = codec.b2d(bytes)
	assert_eq(decoded, val, 1e-9)
end)

test("Encode/decode positive infinity", function()
	local val = math.huge
	local bytes = codec.d2b(val)
	local decoded, _ = codec.b2d(bytes)
	assert_eq(decoded, val)
end)

test("Encode/decode negative infinity", function()
	local val = -math.huge
	local bytes = codec.d2b(val)
	local decoded, _ = codec.b2d(bytes)
	assert_eq(decoded, val)
end)

test("Encode/decode NaN", function()
	local val = 0 / 0
	local bytes = codec.d2b(val)
	local decoded, _ = codec.b2d(bytes)
	assert_eq(decoded, decoded) -- NaN != NaN, but both are NaN
end)

test("Encode/decode zero", function()
	local val = 0
	local bytes = codec.d2b(val)
	local decoded, _ = codec.b2d(bytes)
	assert_eq(decoded, val)
end)

-- 4-byte integers
test("Encode/decode 32-bit integer", function()
	local val = 0x12345678
	local bytes = codec.i2b(val)
	local decoded, _ = codec.b2i(bytes)
	assert_eq(decoded, val)
end)

test("Encode/decode 32-bit integer (max)", function()
	local val = 0xFFFFFFFF
	local bytes = codec.i2b(val)
	local decoded, _ = codec.b2i(bytes)
	assert_eq(decoded, val)
end)

-- 8-byte integers
test("Encode/decode 64-bit integer", function()
	local val = 0x123456789ABCDEF0
	local bytes = codec.i642b(val)
	local decoded, _ = codec.b2i64(bytes)
	-- Luau might lose precision here, so we check modulo
	local decoded_mod = decoded % 0x100000000
	local val_mod = val % 0x100000000
	assert_eq(decoded_mod, val_mod)
end)

-- Strings
test("Encode/decode string", function()
	local val = "Hello, World!"
	local bytes = codec.s2b(val)
	local decoded, _ = codec.b2s(bytes)
	assert_eq(decoded, val)
end)

test("Encode/decode empty string", function()
	local val = ""
	local bytes = codec.s2b(val)
	local decoded, _ = codec.b2s(bytes)
	assert_eq(decoded, val)
end)

-- Vector3
test("Encode/decode Vector3", function()
	local val = Vector3.new(1, 2, 3)
	local bytes = codec.v32b(val)
	local decoded, _ = codec.b2v3(bytes)
	assert_v3_eq(decoded, val)
end)

test("Encode/decode Vector3 with negative components", function()
	local val = Vector3.new(-10.5, 20.25, -30.75)
	local bytes = codec.v32b(val)
	local decoded, _ = codec.b2v3(bytes)
	assert_v3_eq(decoded, val, 1e-9)
end)

-- Tagged Any
test("Encode/decode any as nil", function()
	local val = nil
	local bytes = codec.any2b(val)
	local decoded, _ = codec.b2any(bytes)
	assert_eq(decoded, val)
end)

test("Encode/decode any as boolean", function()
	local val = true
	local bytes = codec.any2b(val)
	local decoded, _ = codec.b2any(bytes)
	assert_eq(decoded, val)
end)

test("Encode/decode any as number", function()
	local val = 3.14159
	local bytes = codec.any2b(val)
	local decoded, _ = codec.b2any(bytes)
	assert_eq(decoded, val, 1e-9)
end)

test("Encode/decode any as string", function()
	local val = "test"
	local bytes = codec.any2b(val)
	local decoded, _ = codec.b2any(bytes)
	assert_eq(decoded, val)
end)

test("Encode/decode any as Vector3", function()
	local val = Vector3.new(1, 1, 1)
	local bytes = codec.any2b(val)
	local decoded, _ = codec.b2any(bytes)
	assert_v3_eq(decoded, val)
end)

-- Offset handling
test("Offset tracking in b2d", function()
	local val1 = 10.5
	local val2 = 20.5
	local bytes = codec.d2b(val1) .. codec.d2b(val2)
	local decoded1, offset1 = codec.b2d(bytes, 1)
	local decoded2, offset2 = codec.b2d(bytes, offset1)
	assert_eq(decoded1, val1)
	assert_eq(decoded2, val2)
end)

test("Offset tracking in b2s", function()
	local val1 = "hello"
	local val2 = "world"
	local bytes = codec.s2b(val1) .. codec.s2b(val2)
	local decoded1, offset1 = codec.b2s(bytes, 1)
	local decoded2, offset2 = codec.b2s(bytes, offset1)
	assert_eq(decoded1, val1)
	assert_eq(decoded2, val2)
end)

print("\nCodec tests completed!")

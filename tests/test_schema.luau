-- Unit tests for LAYER 2: Schema DSL

local Schema = require(script.Parent.Parent.src.schema)
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

local function serialize(obj: any, format: any): string
	local buffer = {}
	Schema.save(buffer, obj, format)
	return table.concat(buffer)
end

local function deserialize(bytes: string, format: any): any
	local obj, _ = Schema.load(bytes, 1, format)
	return obj
end

-- Primitive types
test("Serialize/deserialize f64", function()
	local val = 42.5
	local bytes = serialize(val, "f64")
	local decoded = deserialize(bytes, "f64")
	assert_eq(decoded, val)
end)

test("Serialize/deserialize i32", function()
	local val = 12345
	local bytes = serialize(val, "i32")
	local decoded = deserialize(bytes, "i32")
	assert_eq(decoded, val)
end)

test("Serialize/deserialize string", function()
	local val = "Hello"
	local bytes = serialize(val, "string")
	local decoded = deserialize(bytes, "string")
	assert_eq(decoded, val)
end)

test("Serialize/deserialize bool", function()
	local val = true
	local bytes = serialize(val, "bool")
	local decoded = deserialize(bytes, "bool")
	assert_eq(decoded, val)
end)

test("Serialize/deserialize v3", function()
	local val = Vector3.new(1, 2, 3)
	local bytes = serialize(val, "v3")
	local decoded = deserialize(bytes, "v3")
	assert_eq(decoded.X, val.X)
	assert_eq(decoded.Y, val.Y)
	assert_eq(decoded.Z, val.Z)
end)

-- Struct
test("Serialize/deserialize struct", function()
	local format = Schema.struct({
		x = "f64",
		y = "i32",
		name = "string",
	})
	local obj = { x = 3.14, y = 42, name = "test" }
	local bytes = serialize(obj, format)
	local decoded = deserialize(bytes, format)
	assert_eq(decoded.x, obj.x, 1e-9)
	assert_eq(decoded.y, obj.y)
	assert_eq(decoded.name, obj.name)
end)

-- List
test("Serialize/deserialize list", function()
	local format = Schema.list("i32")
	local obj = { 1, 2, 3, 4, 5 }
	local bytes = serialize(obj, format)
	local decoded = deserialize(bytes, format)
	for i, v in ipairs(obj) do
		assert_eq(decoded[i], v)
	end
end)

test("Serialize/deserialize empty list", function()
	local format = Schema.list("string")
	local obj = {}
	local bytes = serialize(obj, format)
	local decoded = deserialize(bytes, format)
	assert_eq(#decoded, 0)
end)

-- Array
test("Serialize/deserialize array", function()
	local format = Schema.array(3, "f64")
	local obj = { 1.5, 2.5, 3.5 }
	local bytes = serialize(obj, format)
	local decoded = deserialize(bytes, format)
	for i = 1, 3 do
		assert_eq(decoded[i], obj[i], 1e-9)
	end
end)

-- Map
test("Serialize/deserialize map", function()
	local format = Schema.map("string", "i32")
	local obj = { a = 1, b = 2, c = 3 }
	local bytes = serialize(obj, format)
	local decoded = deserialize(bytes, format)
	assert_eq(decoded.a, obj.a)
	assert_eq(decoded.b, obj.b)
	assert_eq(decoded.c, obj.c)
end)

-- Nested struct
test("Serialize/deserialize nested struct", function()
	local innerFormat = Schema.struct({ x = "f64", y = "f64" })
	local outerFormat = Schema.struct({
		name = "string",
		pos = innerFormat,
	})
	local obj = { name = "point", pos = { x = 1.0, y = 2.0 } }
	local bytes = serialize(obj, outerFormat)
	local decoded = deserialize(bytes, outerFormat)
	assert_eq(decoded.name, obj.name)
	assert_eq(decoded.pos.x, obj.pos.x, 1e-9)
	assert_eq(decoded.pos.y, obj.pos.y, 1e-9)
end)

-- Konst
test("Serialize/deserialize konst (serialized)", function()
	local format = Schema.struct({
		magic = Schema.konst(0xDEADBEEF, "i32", true),
		data = "i32",
	})
	local obj = { magic = 0xDEADBEEF, data = 42 }
	local bytes = serialize(obj, format)
	local decoded = deserialize(bytes, format)
	assert_eq(decoded.magic, obj.magic)
	assert_eq(decoded.data, obj.data)
end)

test("Serialize/deserialize konst (not serialized)", function()
	local format = Schema.struct({
		magic = Schema.konst(0xDEADBEEF, "i32", false),
		data = "i32",
	})
	local obj = { magic = 0xDEADBEEF, data = 42 }
	local bytes = serialize(obj, format)
	local decoded = deserialize(bytes, format)
	assert_eq(decoded.magic, obj.magic)
	assert_eq(decoded.data, obj.data)
	-- Bytes should be shorter when not serialized
end)

-- Save (context)
test("Save/restore context", function()
	local format = Schema.struct({
		count = Schema.save("count", "i32"),
		items = Schema.list("i32"),
	})
	local obj = { count = 3, items = { 10, 20, 30 } }
	local bytes = serialize(obj, format)
	local decoded = deserialize(bytes, format)
	assert_eq(decoded.count, 3)
	assert_eq(decoded.items[1], 10)
end)

-- Enable_if
test("Enable_if with true condition", function()
	local format = Schema.struct({
		has_data = "bool",
		data = Schema.enable_if(true, "i32"),
	})
	local obj = { has_data = true, data = 42 }
	local bytes = serialize(obj, format)
	local decoded = deserialize(bytes, format)
	assert_eq(decoded.data, 42)
end)

test("Enable_if with false condition", function()
	local format = Schema.struct({
		has_data = "bool",
		data = Schema.enable_if(false, "i32"),
	})
	local obj = { has_data = false, data = 42 }
	local bytes = serialize(obj, format)
	local decoded = deserialize(bytes, format)
	assert_eq(decoded.data, nil)
end)

-- Compat (version gating)
test("Compat with version gate (newer)", function()
	local format = Schema.struct({
		version = "i32",
		data = Schema.GE_VER(2, "i64", "i32"),
	})
	local obj = { version = 2, data = 12345 }
	local context = { version = 2 }
	local buffer = {}
	Schema.save(buffer, obj, format, context)
	local bytes = table.concat(buffer)
	local decoded = Schema.load(bytes, 1, format, { version = 2 })
	assert_eq(decoded.data, obj.data)
end)

test("Compat with version gate (older)", function()
	local format = Schema.struct({
		version = "i32",
		data = Schema.GE_VER(2, "i64", "i32"),
	})
	local obj = { version = 1, data = 12345 }
	local context = { version = 1 }
	local buffer = {}
	Schema.save(buffer, obj, format, context)
	local bytes = table.concat(buffer)
	local decoded = Schema.load(bytes, 1, format, { version = 1 })
	assert_eq(decoded.data, obj.data)
end)

print("\nSchema tests completed!")

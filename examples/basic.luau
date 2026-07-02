--[[
	BASIC EXAMPLES: Low-level codec usage and simple schemas
]]

local codec = require(script.Parent.Parent.src.codec)
local Schema = require(script.Parent.Parent.src.schema)

-- ============================================================================
-- LAYER 1: LOW-LEVEL CODEC EXAMPLES
-- ============================================================================

print("=== LAYER 1: CODEC EXAMPLES ===")

-- Float encoding
local pi = 3.14159265359
local encoded_pi = codec.d2b(pi)
print("Encoded π:", table.concat(encoded_pi, ","))

local decoded_pi, _ = codec.b2d(encoded_pi, 1)
print("Decoded π:", decoded_pi)
print("Match:", math.abs(decoded_pi - pi) < 1e-10)

-- Special float values
print("\nSpecial floats:")
local inf_bytes = codec.d2b(math.huge)
print("  +inf:", table.concat(inf_bytes, ","))

local neg_inf_bytes = codec.d2b(-math.huge)
print("  -inf:", table.concat(neg_inf_bytes, ","))

local nan_bytes = codec.d2b(0/0)
print("  NaN:", table.concat(nan_bytes, ","))

-- Integer encoding
local value = 42
local encoded_int = codec.i2b(value)
print("\nEncoded 42:", table.concat(encoded_int, ","))

local decoded_int, _ = codec.b2i(encoded_int, 1)
print("Decoded 42:", decoded_int)

-- 64-bit integer
local big_value = 9223372036854775000
local encoded_i64 = codec.i642b(big_value)
print("\nEncoded i64:", table.concat(encoded_i64, ","))

local decoded_i64, _ = codec.b2i64(encoded_i64, 1)
print("Decoded i64:", decoded_i64)

-- String encoding
local msg = "Hello, Luau!"
local encoded_str = codec.s2b(msg)
print("\nEncoded string length:", #encoded_str, "bytes")

local decoded_str, _ = codec.b2s(encoded_str, 1)
print("Decoded string:", decoded_str)

-- Vector3 encoding
local vec = Vector3.new(1.5, 2.5, 3.5)
local encoded_vec = codec.v32b(vec)
print("\nEncoded Vector3 length:", #encoded_vec, "bytes (should be 24)")

local decoded_vec, _ = codec.b2v3(encoded_vec, 1)
print("Decoded Vector3:", decoded_vec)

-- Tagged "Any" type
print("\nTagged Any type:")
local any_int_bytes = codec.a2b(42)
local decoded_any_int, _ = codec.b2a(any_int_bytes, 1)
print("  Encoded/decoded 42 as Any:", decoded_any_int)

local any_str_bytes = codec.a2b("test")
local decoded_any_str, _ = codec.b2a(any_str_bytes, 1)
print("  Encoded/decoded 'test' as Any:", decoded_any_str)

-- ============================================================================
-- LAYER 2: SIMPLE SCHEMA EXAMPLES
-- ============================================================================

print("\n=== LAYER 2: SIMPLE SCHEMA EXAMPLES ===")

-- Example 1: Simple struct
local PersonSchema = Schema.struct{
	{name = "name", schema = Schema.string()},
	{name = "age", schema = Schema.i32()},
	{name = "height", schema = Schema.f64()},
}

local person = {
	name = "Alice",
	age = 30,
	height = 5.7,
}

print("\nEncoding person:", person.name, "age", person.age)
local person_buffer = Schema.encode(person, PersonSchema)
print("Encoded size:", #person_buffer, "bytes")

local decoded_person = Schema.decode(person_buffer, PersonSchema)
print("Decoded:", decoded_person.name, "age", decoded_person.age, "height", decoded_person.height)

-- Example 2: List of numbers
local NumberListSchema = Schema.list(Schema.f64())
local numbers = {1.1, 2.2, 3.3, 4.4, 5.5}

print("\nEncoding list of", #numbers, "numbers")
local list_buffer = Schema.encode(numbers, NumberListSchema)
print("Encoded size:", #list_buffer, "bytes")

local decoded_list = Schema.decode(list_buffer, NumberListSchema)
print("Decoded list:", table.concat(decoded_list, ", "))

-- Example 3: Fixed-length array
local IntArraySchema = Schema.array(5, Schema.i32())
local int_array = {10, 20, 30, 40, 50}

print("\nEncoding fixed array of", #int_array, "ints")
local array_buffer = Schema.encode(int_array, IntArraySchema)
print("Encoded size:", #array_buffer, "bytes (should be 20)")

local decoded_array = Schema.decode(array_buffer, IntArraySchema)
print("Decoded array:", table.concat(decoded_array, ", "))

-- Example 4: Map (key-value pairs)
local StringMapSchema = Schema.map(Schema.string(), Schema.i32())
local color_map = {
	red = 255,
	green = 128,
	blue = 64,
}

print("\nEncoding map with", 3, "entries")
local map_buffer = Schema.encode(color_map, StringMapSchema)
print("Encoded size:", #map_buffer, "bytes")

local decoded_map = Schema.decode(map_buffer, StringMapSchema)
print("Decoded map:")
for k, v in pairs(decoded_map) do
	print("  ", k, "=", v)
end

-- Example 5: Nested struct
local AddressSchema = Schema.struct{
	{name = "street", schema = Schema.string()},
	{name = "city", schema = Schema.string()},
	{name = "zip", schema = Schema.i32()},
}

local EmployeeSchema = Schema.struct{
	{name = "name", schema = Schema.string()},
	{name = "id", schema = Schema.i32()},
	{name = "address", schema = AddressSchema},
}

local employee = {
	name = "Bob",
	id = 12345,
	address = {
		street = "123 Main St",
		city = "Boston",
		zip = 02101,
	},
}

print("\nEncoding nested employee struct")
local employee_buffer = Schema.encode(employee, EmployeeSchema)
print("Encoded size:", #employee_buffer, "bytes")

local decoded_employee = Schema.decode(employee_buffer, EmployeeSchema)
print("Decoded employee:", decoded_employee.name)
print("  Address:", decoded_employee.address.street, ",", decoded_employee.address.city)

print("\n=== Examples complete ===")

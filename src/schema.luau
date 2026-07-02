--[[
	LAYER 2: DECLARATIVE SCHEMA DSL
	
	Provides constructors that describe SHAPES of data:
	- Schema.struct{ {fieldName = type}, ... }
	- Schema.list(elementType)
	- Schema.array(len, elementType)
	- Schema.map(keyType, valueType)
	- Schema.union(...)
	- Schema.konst(value, type, isSerialized)
	- Schema.save(name, type)
	- Schema.compat(fn)
	- Schema.enable_if(cond, type)
	- Schema.ref(indexTable, type)
]]

local codec = require(script.Parent.codec)

local Schema = {}
local SchemaType = {}
SchemaType.__index = SchemaType

-- ============================================================================
-- SCHEMA CONSTRUCTORS
-- ============================================================================

local function make_schema(type_name, props)
	local s = setmetatable({
		type = type_name,
		__props = props or {}
	}, SchemaType)
	return s
end

function Schema.struct(fields)
	--[[ Ordered fields: { {fieldName = type}, ... } ]]
	local ordered = {}
	for k, v in pairs(fields) do
		table.insert(ordered, {name = k, schema = v})
	end
	return make_schema("struct", {fields = ordered})
end

function Schema.list(elementType)
	--[[ Length-prefixed sequence (4-byte count prefix) ]]
	return make_schema("list", {element = elementType})
end

function Schema.array(len, elementType)
	--[[ Fixed-length sequence ]]
	return make_schema("array", {length = len, element = elementType})
end

function Schema.map(keyType, valueType)
	--[[ Key/value pairs with count prefix ]]
	return make_schema("map", {key = keyType, value = valueType})
end

function Schema.union(...)
	--[[ Sequential composition of formats ]]
	local members = {...}
	return make_schema("union", {members = members})
end

function Schema.konst(value, typeSchema, isSerialized)
	--[[ Constant field, optionally written to stream ]]
	isSerialized = isSerialized or false
	return make_schema("konst", {value = value, schema = typeSchema, serialized = isSerialized})
end

function Schema.save(name, typeSchema)
	--[[ Save a value into context table for later reference ]]
	return make_schema("save", {name = name, schema = typeSchema})
end

function Schema.compat(fn)
	--[[ Version-gated format selection ]]
	--[[ fn(context) -> schema ]]
	return make_schema("compat", {selector = fn})
end

function Schema.enable_if(cond, typeSchema)
	--[[ Conditionally read/write a field ]]
	--[[ cond(context) -> bool ]]
	return make_schema("enable_if", {condition = cond, schema = typeSchema})
end

function Schema.ref(indexTable, typeSchema)
	--[[ Indexed back-reference (serialize ID, resolve during load) ]]
	--[[ indexTable is a table mapping values to IDs ]]
	return make_schema("ref", {index = indexTable, schema = typeSchema})
end

-- Primitive schemas
function Schema.f64()
	return make_schema("f64")
end

function Schema.i32()
	return make_schema("i32")
end

function Schema.i64()
	return make_schema("i64")
end

function Schema.string()
	return make_schema("string")
end

function Schema.bool()
	return make_schema("bool")
end

function Schema.vector3()
	return make_schema("vector3")
end

function Schema.any()
	return make_schema("any")
end

-- ============================================================================
-- PRIMITIVE TYPE METHODS: :save and :load
-- ============================================================================

local function primitive_save(prim_type, buffer, value)
	if prim_type == "f64" then
		local bytes = codec.d2b(value)
		for _, b in ipairs(bytes) do
			table.insert(buffer, b)
		end
	elseif prim_type == "i32" then
		local bytes = codec.i2b(value)
		for _, b in ipairs(bytes) do
			table.insert(buffer, b)
		end
	elseif prim_type == "i64" then
		local bytes = codec.i642b(value)
		for _, b in ipairs(bytes) do
			table.insert(buffer, b)
		end
	elseif prim_type == "string" then
		local bytes = codec.s2b(value)
		for _, b in ipairs(bytes) do
			table.insert(buffer, b)
		end
	elseif prim_type == "bool" then
		table.insert(buffer, value and 1 or 0)
	elseif prim_type == "vector3" then
		local bytes = codec.v32b(value)
		for _, b in ipairs(bytes) do
			table.insert(buffer, b)
		end
	elseif prim_type == "any" then
		local bytes = codec.a2b(value)
		for _, b in ipairs(bytes) do
			table.insert(buffer, b)
		end
	else
		error("Unknown primitive type: " .. prim_type)
	end
end

local function primitive_load(prim_type, buffer, cursor)
	if prim_type == "f64" then
		return codec.b2d(buffer, cursor)
	elseif prim_type == "i32" then
		return codec.b2i(buffer, cursor)
	elseif prim_type == "i64" then
		return codec.b2i64(buffer, cursor)
	elseif prim_type == "string" then
		return codec.b2s(buffer, cursor)
	elseif prim_type == "bool" then
		if cursor > #buffer then
			error("Buffer underflow: not enough bytes for bool")
		end
		return buffer[cursor] ~= 0, cursor + 1
	elseif prim_type == "vector3" then
		return codec.b2v3(buffer, cursor)
	elseif prim_type == "any" then
		return codec.b2a(buffer, cursor)
	else
		error("Unknown primitive type: " .. prim_type)
	end
end

-- ============================================================================
-- RUNTIME RECURSION: save and load
-- ============================================================================

local function save_schema(buffer, value, schema, context)
	--[[ Recursively save a value according to schema ]]
	context = context or {}
	
	if schema.type == "f64" or schema.type == "i32" or schema.type == "i64" 
	   or schema.type == "string" or schema.type == "bool" 
	   or schema.type == "vector3" or schema.type == "any" then
		primitive_save(schema.type, buffer, value)
	
	elseif schema.type == "struct" then
		for _, field in ipairs(schema.__props.fields) do
			local fname = field.name
			local fschema = field.schema
			save_schema(buffer, value[fname], fschema, context)
		end
	
	elseif schema.type == "list" then
		-- Length prefix (i32)
		local bytes = codec.i2b(#value)
		for _, b in ipairs(bytes) do
			table.insert(buffer, b)
		end
		-- Elements
		for _, elem in ipairs(value) do
			save_schema(buffer, elem, schema.__props.element, context)
		end
	
	elseif schema.type == "array" then
		-- Fixed-length, no prefix
		local len = schema.__props.length
		for i = 1, len do
			save_schema(buffer, value[i], schema.__props.element, context)
		end
	
	elseif schema.type == "map" then
		-- Count prefix (i32)
		local keys = {}
		for k in pairs(value) do
			table.insert(keys, k)
		end
		local bytes = codec.i2b(#keys)
		for _, b in ipairs(bytes) do
			table.insert(buffer, b)
		end
		-- Key-value pairs
		for _, k in ipairs(keys) do
			save_schema(buffer, k, schema.__props.key, context)
			save_schema(buffer, value[k], schema.__props.value, context)
		end
	
	elseif schema.type == "union" then
		-- Save each member in sequence
		for _, member_schema in ipairs(schema.__props.members) do
			save_schema(buffer, value, member_schema, context)
		end
	
	elseif schema.type == "konst" then
		if schema.__props.serialized then
			save_schema(buffer, schema.__props.value, schema.__props.schema, context)
		end
	
	elseif schema.type == "save" then
		local name = schema.__props.name
		save_schema(buffer, value, schema.__props.schema, context)
		context[name] = value
	
	elseif schema.type == "enable_if" then
		if schema.__props.condition(context) then
			save_schema(buffer, value, schema.__props.schema, context)
		end
	
	elseif schema.type == "compat" then
		local selected = schema.__props.selector(context)
		save_schema(buffer, value, selected, context)
	
	elseif schema.type == "ref" then
		-- Serialize the index ID instead of the value
		local index = schema.__props.index
		local id = index[value]
		if id == nil then
			error("Value not found in ref index")
		end
		save_schema(buffer, id, schema.__props.schema, context)
	
	else
		error("Unknown schema type: " .. schema.type)
	end
end

local function load_schema(buffer, cursor, schema, context)
	--[[ Recursively load a value according to schema ]]
	context = context or {}
	
	if schema.type == "f64" or schema.type == "i32" or schema.type == "i64" 
	   or schema.type == "string" or schema.type == "bool" 
	   or schema.type == "vector3" or schema.type == "any" then
		return primitive_load(schema.type, buffer, cursor)
	
	elseif schema.type == "struct" then
		local obj = {}
		for _, field in ipairs(schema.__props.fields) do
			local fname = field.name
			local fschema = field.schema
			obj[fname], cursor = load_schema(buffer, cursor, fschema, context)
		end
		return obj, cursor
	
	elseif schema.type == "list" then
		-- Read count
		local count, new_cursor = codec.b2i(buffer, cursor)
		cursor = new_cursor
		local list = {}
		for i = 1, count do
			local elem
			elem, cursor = load_schema(buffer, cursor, schema.__props.element, context)
			table.insert(list, elem)
		end
		return list, cursor
	
	elseif schema.type == "array" then
		-- Fixed-length
		local len = schema.__props.length
		local arr = {}
		for i = 1, len do
			local elem
			elem, cursor = load_schema(buffer, cursor, schema.__props.element, context)
			table.insert(arr, elem)
		end
		return arr, cursor
	
	elseif schema.type == "map" then
		-- Read count
		local count, new_cursor = codec.b2i(buffer, cursor)
		cursor = new_cursor
		local map = {}
		for i = 1, count do
			local key, val
			key, cursor = load_schema(buffer, cursor, schema.__props.key, context)
			val, cursor = load_schema(buffer, cursor, schema.__props.value, context)
			map[key] = val
		end
		return map, cursor
	
	elseif schema.type == "union" then
		-- Load each member in sequence, returning first
		local result
		for _, member_schema in ipairs(schema.__props.members) do
			result, cursor = load_schema(buffer, cursor, member_schema, context)
		end
		return result, cursor
	
	elseif schema.type == "konst" then
		if schema.__props.serialized then
			return load_schema(buffer, cursor, schema.__props.schema, context)
		else
			return schema.__props.value, cursor
		end
	
	elseif schema.type == "save" then
		local name = schema.__props.name
		local value
		value, cursor = load_schema(buffer, cursor, schema.__props.schema, context)
		context[name] = value
		return value, cursor
	
	elseif schema.type == "enable_if" then
		if schema.__props.condition(context) then
			return load_schema(buffer, cursor, schema.__props.schema, context)
		else
			return nil, cursor
		end
	
	elseif schema.type == "compat" then
		local selected = schema.__props.selector(context)
		return load_schema(buffer, cursor, selected, context)
	
	elseif schema.type == "ref" then
		-- Load the index ID and resolve from reverse index
		local id
		id, cursor = load_schema(buffer, cursor, schema.__props.schema, context)
		-- The context should have a reverse index set up by the caller
		local reverse_index = context._reverse_index
		if not reverse_index or not reverse_index[id] then
			error("Ref index not found for ID: " .. tostring(id))
		end
		return reverse_index[id], cursor
	
	else
		error("Unknown schema type: " .. schema.type)
	end
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

Schema.save = save_schema
Schema.load = load_schema

-- Convenience functions for top-level serialization
function Schema.encode(value, schema, context)
	--[[ Encode a value to a byte buffer ]]
	local buffer = {}
	save_schema(buffer, value, schema, context or {})
	return buffer
end

function Schema.decode(buffer, schema, context)
	--[[ Decode a byte buffer to a value ]]
	local value, _ = load_schema(buffer, 1, schema, context or {})
	return value
end

return Schema

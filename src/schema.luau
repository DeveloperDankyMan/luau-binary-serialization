-- LAYER 2: DECLARATIVE SCHEMA DSL
-- Describes data shapes for serialization/deserialization

local codec = require(script.Parent.codec)

local Schema = {}
Schema.__index = Schema

-- Helper: Create a schema node
local function make_schema(ty: string, data: table?): table
	return setmetatable({
		type = ty,
		_data = data or {},
	}, Schema)
end

-- ============================================================================
-- STRUCT: Ordered fields
-- ============================================================================
function Schema.struct(fields: {[string]: any}): table
	local field_list = {}
	for k, v in pairs(fields) do
		table.insert(field_list, { name = k, format = v })
	end
	return make_schema("struct", { fields = field_list })
end

-- ============================================================================
-- LIST: Length-prefixed variable-length sequences
-- ============================================================================
function Schema.list(elementType: any): table
	return make_schema("list", { elementType = elementType })
end

-- ============================================================================
-- ARRAY: Fixed-length sequences
-- ============================================================================
function Schema.array(len: number, elementType: any): table
	return make_schema("array", { len = len, elementType = elementType })
end

-- ============================================================================
-- MAP: Key/value pairs with count prefix
-- ============================================================================
function Schema.map(keyType: any, valueType: any): table
	return make_schema("map", { keyType = keyType, valueType = valueType })
end

-- ============================================================================
-- UNION: Sequential composition (try formats in order)
-- ============================================================================
function Schema.union(...: any): table
	local formats = { ... }
	return make_schema("union", { formats = formats })
end

-- ============================================================================
-- KONST: Constant fields, optionally written to stream
-- ============================================================================
function Schema.konst(value: any, ty: any, isSerialized: boolean?): table
	isSerialized = isSerialized ~= false -- default true
	return make_schema("konst", {
		value = value,
		type = ty,
		isSerialized = isSerialized,
	})
end

-- ============================================================================
-- SAVE: Store a value in context for later reference
-- ============================================================================
function Schema.save(name: string, ty: any): table
	return make_schema("save", { name = name, type = ty })
end

-- ============================================================================
-- COMPAT: Version-gated format selection
-- ============================================================================
function Schema.GE_VER(version: number, formatIfNewer: any, formatIfOlder: any): table
	return make_schema("compat", {
		version = version,
		formatIfNewer = formatIfNewer,
		formatIfOlder = formatIfOlder,
	})
end

-- ============================================================================
-- ENABLE_IF: Conditionally read/write a field
-- ============================================================================
function Schema.enable_if(cond: boolean | (context: table) -> boolean, ty: any): table
	local pred = type(cond) == "function" and cond or function() return cond end
	return make_schema("enable_if", { predicate = pred, type = ty })
end

-- ============================================================================
-- REF: Indexed back-reference
-- ============================================================================
function Schema.ref(name: string): table
	return make_schema("ref", { name = name })
end

-- ============================================================================
-- PRIMITIVE TYPES: Match against type name strings
-- ============================================================================
function Schema.f64(): table
	return make_schema("f64")
end

function Schema.i32(): table
	return make_schema("i32")
end

function Schema.i64(): table
	return make_schema("i64")
end

function Schema.string(): table
	return make_schema("string")
end

function Schema.v3(): table
	return make_schema("v3")
end

function Schema.any(): table
	return make_schema("any")
end

function Schema.bool(): table
	return make_schema("bool")
end

-- ============================================================================
-- SAVE: Write data to buffer using a schema
-- ============================================================================
function Schema.save(buffer: table, obj: any, format: any, context: table?): table
	context = context or {}
	
	if type(format) == "string" then
		-- Primitive type by name
		if format == "f64" then
			table.insert(buffer, codec.d2b(obj))
		elseif format == "i32" then
			table.insert(buffer, codec.i2b(obj))
		elseif format == "i64" then
			table.insert(buffer, codec.i642b(obj))
		elseif format == "string" then
			table.insert(buffer, codec.s2b(obj))
		elseif format == "v3" then
			table.insert(buffer, codec.v32b(obj))
		elseif format == "any" then
			table.insert(buffer, codec.any2b(obj))
		elseif format == "bool" then
			table.insert(buffer, string.char(obj and 1 or 0))
		else
			error("Unknown format: " .. format)
		end
		return buffer
	end
	
	if not format or not format.type then
		error("Invalid format")
	end
	
	local ty = format.type
	
	-- Struct: save each field in order
	if ty == "struct" then
		for _, field in ipairs(format._data.fields) do
			local value = obj[field.name]
			Schema.save(buffer, value, field.format, context)
		end
	
	-- List: save count, then each element
	elseif ty == "list" then
		table.insert(buffer, codec.i2b(#obj))
		for _, elem in ipairs(obj) do
			Schema.save(buffer, elem, format._data.elementType, context)
		end
	
	-- Array: save fixed count of elements
	elseif ty == "array" then
		for i = 1, format._data.len do
			Schema.save(buffer, obj[i], format._data.elementType, context)
		end
	
	-- Map: save count, then key/value pairs
	elseif ty == "map" then
		local count = 0
		for _ in pairs(obj) do count = count + 1 end
		table.insert(buffer, codec.i2b(count))
		for k, v in pairs(obj) do
			Schema.save(buffer, k, format._data.keyType, context)
			Schema.save(buffer, v, format._data.valueType, context)
		end
	
	-- Union: try each format in order (save with first that matches)
	elseif ty == "union" then
		-- For now, save with first format; could add type detection
		Schema.save(buffer, obj, format._data.formats[1], context)
	
	-- Konst: save value if isSerialized flag is set
	elseif ty == "konst" then
		if format._data.isSerialized then
			Schema.save(buffer, format._data.value, format._data.type, context)
		end
	
	-- Save: store value in context, then save with type format
	elseif ty == "save" then
		Schema.save(buffer, obj, format._data.type, context)
		context[format._data.name] = obj
	
	-- Compat: select format based on context version
	elseif ty == "compat" then
		local version = context.version or 0
		local chosen = version >= format._data.version and format._data.formatIfNewer or format._data.formatIfOlder
		Schema.save(buffer, obj, chosen, context)
	
	-- Enable_if: conditionally save
	elseif ty == "enable_if" then
		local pred = format._data.predicate
		if pred(context) then
			Schema.save(buffer, obj, format._data.type, context)
		end
	
	-- Ref: save reference ID (index into context table)
	elseif ty == "ref" then
		local name = format._data.name
		local refs = context._refs or {}
		if not refs[name] then
			refs[name] = {}
			context._refs = refs
		end
		table.insert(refs[name], obj)
		table.insert(buffer, codec.i2b(#refs[name] - 1)) -- 0-indexed
	
	else
		error("Unknown format type: " .. ty)
	end
	
	return buffer
end

-- ============================================================================
-- LOAD: Read data from buffer using a schema
-- ============================================================================
function Schema.load(buffer: string, cursor: number, format: any, context: table?): (any, number)
	context = context or {}
	
	if type(format) == "string" then
		-- Primitive type by name
		if format == "f64" then
			return codec.b2d(buffer, cursor)
		elseif format == "i32" then
			return codec.b2i(buffer, cursor)
		elseif format == "i64" then
			return codec.b2i64(buffer, cursor)
		elseif format == "string" then
			return codec.b2s(buffer, cursor)
		elseif format == "v3" then
			return codec.b2v3(buffer, cursor)
		elseif format == "any" then
			return codec.b2any(buffer, cursor)
		elseif format == "bool" then
			local val = string.byte(buffer, cursor) ~= 0
			return val, cursor + 1
		else
			error("Unknown format: " .. format)
		end
	end
	
	if not format or not format.type then
		error("Invalid format")
	end
	
	local ty = format.type
	local result
	
	-- Struct: load each field in order
	if ty == "struct" then
		result = {}
		for _, field in ipairs(format._data.fields) do
			result[field.name], cursor = Schema.load(buffer, cursor, field.format, context)
		end
	
	-- List: load count, then each element
	elseif ty == "list" then
		result = {}
		local count
		count, cursor = codec.b2i(buffer, cursor)
		for _ = 1, count do
			local elem
			elem, cursor = Schema.load(buffer, cursor, format._data.elementType, context)
			table.insert(result, elem)
		end
	
	-- Array: load fixed count of elements
	elseif ty == "array" then
		result = {}
		for _ = 1, format._data.len do
			local elem
			elem, cursor = Schema.load(buffer, cursor, format._data.elementType, context)
			table.insert(result, elem)
		end
	
	-- Map: load count, then key/value pairs
	elseif ty == "map" then
		result = {}
		local count
		count, cursor = codec.b2i(buffer, cursor)
		for _ = 1, count do
			local k, v
			k, cursor = Schema.load(buffer, cursor, format._data.keyType, context)
			v, cursor = Schema.load(buffer, cursor, format._data.valueType, context)
			result[k] = v
		end
	
	-- Union: try each format in order (load with first available)
	elseif ty == "union" then
		-- For now, load with first format
		result, cursor = Schema.load(buffer, cursor, format._data.formats[1], context)
	
	-- Konst: return constant value without reading
	elseif ty == "konst" then
		result = format._data.value
		if format._data.isSerialized then
			-- Skip the bytes that were written
			_, cursor = Schema.load(buffer, cursor, format._data.type, context)
		end
	
	-- Save: load value, store in context
	elseif ty == "save" then
		result, cursor = Schema.load(buffer, cursor, format._data.type, context)
		context[format._data.name] = result
	
	-- Compat: select format based on context version
	elseif ty == "compat" then
		local version = context.version or 0
		local chosen = version >= format._data.version and format._data.formatIfNewer or format._data.formatIfOlder
		result, cursor = Schema.load(buffer, cursor, chosen, context)
	
	-- Enable_if: conditionally load
	elseif ty == "enable_if" then
		local pred = format._data.predicate
		if pred(context) then
			result, cursor = Schema.load(buffer, cursor, format._data.type, context)
		else
			result = nil
		end
	
	-- Ref: load reference ID and resolve from context
	elseif ty == "ref" then
		local name = format._data.name
		local idx
		idx, cursor = codec.b2i(buffer, cursor)
		local refs = context._refs and context._refs[name] or {}
		result = refs[idx + 1] -- 1-indexed in Lua
	
	else
		error("Unknown format type: " .. ty)
	end
	
	return result, cursor
end

return Schema

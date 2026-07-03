# Luau Binary Serialization Library

A pure Luau implementation of a two-layer binary serialization system with deterministic wire format and version compatibility support.

## Overview

### Layer 1: Low-Level Binary Codec

Primitive encoders/decoders for:

- **IEEE 754 Double Precision** (`d2b` / `b2d`)
  - Handles infinities, NaN, subnormals, signed zeros
  - 8-byte little-endian format

- **Fixed-Width Integers**
  - 4-byte: `i2b` / `b2i`
  - 8-byte: `i642b` / `b2i64`
  - Little-endian byte order

- **Vector3** (`v32b` / `b2v3`)
  - Three packed IEEE 754 doubles (X, Y, Z)

- **Length-Prefixed Strings** (`s2b` / `b2s`)
  - 4-byte length prefix + raw UTF-8 bytes

- **Tagged Any Type** (`any2b` / `b2any`)
  - 1-byte type tag + payload
  - Tags: nil, boolean, number, string, Vector3

### Layer 2: Declarative Schema DSL

Describe data shapes using composable schema constructors:

#### Basic Structures

```lua
local schema = Schema.struct({
    x = "f64",
    y = "f64",
    label = "string",
})

local obj = { x = 1.5, y = 2.5, label = "point" }
local buffer = {}
Schema.save(buffer, obj, schema)
local bytes = table.concat(buffer)
```

#### Collections

- **List** (variable-length, length-prefixed)
  ```lua
  Schema.list("i32")  -- vec<i32>
  ```

- **Array** (fixed-length)
  ```lua
  Schema.array(3, "f64")  -- [f64; 3]
  ```

- **Map** (key/value with count prefix)
  ```lua
  Schema.map("string", "i32")  -- map<string, i32>
  ```

#### Advanced Features

- **Constants** (optional serialization)
  ```lua
  Schema.konst(0xDEADBEEF, "i32", true)  -- write magic number
  ```

- **Context Save** (store value for later reference)
  ```lua
  Schema.save("count", "i32")  -- save to context["count"]
  ```

- **Version Gating** (conditional format selection)
  ```lua
  Schema.GE_VER(2, "i64", "i32")  -- use i64 if version >= 2, else i32
  ```

- **Conditional Fields** (if-then-serialize)
  ```lua
  Schema.enable_if(pred, format)  -- only save/load if pred(context) is true
  ```

- **References** (back-references for recursive structures)
  ```lua
  Schema.ref("name")  -- serialize reference ID instead of full object
  ```

#### Primitive Types

- `"f64"` — IEEE 754 double
- `"i32"` — 32-bit integer
- `"i64"` — 64-bit integer
- `"string"` — length-prefixed UTF-8
- `"v3"` — Vector3
- `"bool"` — boolean (1 byte)
- `"any"` — tagged Any type

### Runtime API

```lua
-- Serialize
local buffer = {}
Schema.save(buffer, object, schema, context)
local bytes = table.concat(buffer)

-- Deserialize
local object, cursor = Schema.load(bytes, startCursor, schema, context)
```

The mutable `context` table is threaded through save/load operations, enabling:
- Dependent formats (sized arrays based on earlier fields)
- Version-aware deserialization
- Reference resolution

## Example: Version-Aware Struct

```lua
local GameState = Schema.struct({
    version = Schema.save("version", "i32"),
    player_count = "i32",
    extended_data = Schema.GE_VER(2, Schema.struct({
        difficulty = "i32",
        seed = "i64",
    }), Schema.konst(nil, "any", false)),
})

local data = {
    version = 2,
    player_count = 4,
    extended_data = { difficulty = 3, seed = 12345 },
}

local buffer = {}
local context = { version = 2 }
Schema.save(buffer, data, GameState, context)
local bytes = table.concat(buffer)

-- Load with version awareness
local loaded = Schema.load(bytes, 1, GameState, { version = 2 })
```

## Wire Format Properties

- **Deterministic**: Same input always produces identical bytes
- **Versionable**: `compat()` gates allow safe format evolution
- **Little-Endian**: All multi-byte integers and floats
- **Self-Describing**: Tagged Any type and length prefixes support dynamic structures
- **Recursive**: Supports arbitrarily nested schemas and self-referential types

## Testing

Run unit tests:

```bash
lua tests/test_codec.luau
lua tests/test_schema.luau
```

Both test suites verify:
- Encoding/decoding of all primitive types
- Special cases (infinity, NaN, zero, negative values)
- Nested and composite structures
- Context threading and version gating
- Offset tracking through multi-field serialization

## Constraints

- ✅ Pure Luau, no external libraries
- ✅ Deterministic wire format
- ✅ Version compatibility via `compat()`
- ✅ Recursive and self-referential structures
- ✅ Luau standard library only (bit32, math, string, table)

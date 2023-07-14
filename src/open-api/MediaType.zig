const std = @import("std");

const schema_tools = @import("schema-tools.zig");
const Encoding = @import("Encoding.zig");
const ExampleOrRef = @import("example-or-ref.zig").ExampleOrRef;
const Schema = @import("Schema.zig");

const MediaType = @This();
schema: ?Schema = null,
example: ?std.json.Value = null,
examples: ?std.json.ArrayHashMap(ExampleOrRef) = null,
encoding: ?std.json.ArrayHashMap(Encoding) = null,

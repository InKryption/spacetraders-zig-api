const std = @import("std");
const assert = std.debug.assert;

const util = @import("util");

const schema_tools = @import("schema-tools.zig");
const PathItem = @import("PathItem.zig");
const Reference = @import("Reference.zig");

const Webhooks = @This();
fields: Fields = .{},

// technically the value is defined as being `Path Item Object | Reference Object`,
// but the former is already a superset of the latter, so just use that here
pub const Fields = std.json.ArrayHashMap(PathItem);

comptime {
    const JsonToZigFnm = schema_tools.JsonToZigFieldNameMap;
    const PathItemJsonToZig = JsonToZigFnm(PathItem, PathItem.json_field_names);
    const ReferenceJsonToZig = JsonToZigFnm(Reference, Reference.json_field_names);

    for (@typeInfo(ReferenceJsonToZig).Struct.fields) |ref_field| {
        if (!@hasField(PathItemJsonToZig, ref_field.name)) @compileError( //
            @typeName(PathItem) ++ " was expected to be a strict superset of " ++
            @typeName(Reference) ++ ", but is missing field " ++ ref_field.name //
        );
    }
}

pub fn deinit(wh: *Webhooks, allocator: std.mem.Allocator) void {
    schema_tools.deinitArrayHashMap(allocator, PathItem, &wh.fields);
}

pub fn jsonStringify(
    wh: Webhooks,
    options: std.json.StringifyOptions,
    writer: anytype,
) @TypeOf(writer).Error!void {
    try wh.fields.jsonStringify(options, writer);
}

pub fn jsonParseRealloc(
    result: *Webhooks,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    try schema_tools.jsonParseInPlaceArrayHashMapTemplate(
        PathItem,
        &result.fields,
        allocator,
        source,
        options,
    );
}

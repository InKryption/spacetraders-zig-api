const std = @import("std");
const assert = std.debug.assert;

const util = @import("util");

const schema_tools = @import("schema-tools.zig");

const Paths = @This();
fields: Fields = .{},

pub const Item = @import("paths/Item.zig");
pub const Fields = std.json.ArrayHashMap(Item);

pub fn deinit(paths: *Paths, allocator: std.mem.Allocator) void {
    schema_tools.deinitArrayHashMap(allocator, Item, &paths.fields);
}

pub fn jsonStringify(
    paths: Paths,
    options: std.json.StringifyOptions,
    writer: anytype,
) @TypeOf(writer).Error!void {
    try paths.fields.jsonStringify(options, writer);
}

pub fn jsonParseRealloc(
    result: *Paths,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    try schema_tools.jsonParseInPlaceArrayHashMapTemplate(
        Item,
        &result.fields,
        allocator,
        source,
        options,
    );
}

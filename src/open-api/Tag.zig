const std = @import("std");
const assert = std.debug.assert;

const schema_tools = @import("schema-tools.zig");
const ExternalDocs = @import("ExternalDocs.zig");

const Tag = @This();
name: []const u8 = "",
description: ?[]const u8 = null,
external_docs: ?ExternalDocs = null,

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Tag, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Tag){
    .external_docs = "externalDocs",
};

pub fn deinit(tags: *Tag, allocator: std.mem.Allocator) void {
    for (tags.set.keys()) |str|
        allocator.free(str);
    tags.set.deinit(allocator);
}

pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(
    Tag,
    Tag.json_field_names,
);

pub fn jsonParseRealloc(
    result: *Tag,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    _ = result;
    _ = allocator;
    _ = options;
}

pub const ArrayHashCtx = struct {
    pub fn hash(self: @This(), tag: Tag) u32 {
        _ = self;
        return Adapted.hash(.{}, tag.name);
    }
    pub fn eql(self: @This(), a: Tag, b: Tag, b_index: usize) bool {
        _ = self;
        return Adapted.eql(.{}, a.name, b, b_index);
    }

    pub const Adapted = struct {
        pub fn hash(self: @This(), name: []const u8) u32 {
            _ = self;
            return std.array_hash_map.hashString(name);
        }
        pub fn eql(self: @This(), a_name: []const u8, b: Tag, b_index: usize) bool {
            _ = self;
            _ = b_index;
            return std.mem.eql(u8, a_name, b.name);
        }
    };
};

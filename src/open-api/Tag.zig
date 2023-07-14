const std = @import("std");
const assert = std.debug.assert;

const schema_tools = @import("schema-tools.zig");
const ExternalDocs = @import("ExternalDocs.zig");

const Tag = @This();
name: []const u8 = "",
description: ?[]const u8 = null,
external_docs: ?ExternalDocs = null,

pub const empty = Tag{};

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Tag, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Tag){
    .external_docs = "externalDocs",
};

pub fn deinit(tags: *Tag, allocator: std.mem.Allocator) void {
    allocator.free(tags.name);
    allocator.free(tags.description orelse "");
    if (tags.external_docs) |*docs| {
        docs.deinit(allocator);
    }
}

pub const jsonStringify = schema_tools.generateMappedStringify(Tag, json_field_names);

pub fn jsonParseRealloc(
    result: *Tag,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    var field_set = schema_tools.FieldEnumSet(Tag).initEmpty();
    try schema_tools.jsonParseInPlaceTemplate(Tag, result, allocator, source, options, &field_set, Tag.parseFieldValue);
}

pub inline fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(Tag),
    field_ptr: anytype,
    is_new: bool,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) !void {
    _ = is_new;
    switch (field_tag) {
        .name, .description => {
            var new_str = std.ArrayList(u8).fromOwnedSlice(allocator, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
            defer new_str.deinit();

            new_str.clearRetainingCapacity();
            field_ptr.* = "";

            try schema_tools.jsonParseReallocString(&new_str, source, options);
            field_ptr.* = try new_str.toOwnedSlice();
        },
        .external_docs => {},
    }
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

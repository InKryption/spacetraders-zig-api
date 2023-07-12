const std = @import("std");

const schema_tools = @import("schema-tools.zig");

const ExternalDocs = @This();
description: ?[]const u8 = null,
url: []const u8 = "",

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(ExternalDocs, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(ExternalDocs){};

pub fn deinit(docs: ExternalDocs, allocator: std.mem.Allocator) void {
    allocator.free(docs.description orelse "");
    allocator.free(docs.url);
}

pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(
    ExternalDocs,
    ExternalDocs.json_field_names,
);

pub fn jsonParseRealloc(
    result: *ExternalDocs,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    var field_set = schema_tools.FieldEnumSet(ExternalDocs).initEmpty();
    try schema_tools.jsonParseInPlaceTemplate(
        ExternalDocs,
        result,
        allocator,
        source,
        options,
        &field_set,
        ExternalDocs.parseFieldValue,
    );
}

pub inline fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(ExternalDocs),
    field_ptr: anytype,
    is_new: bool,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) !void {
    _ = is_new;
    _ = field_tag;
    var new_str = std.ArrayList(u8).fromOwnedSlice(allocator, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
    defer new_str.deinit();

    new_str.clearRetainingCapacity();
    field_ptr.* = "";

    try schema_tools.jsonParseReallocString(&new_str, source, options);
    field_ptr.* = try new_str.toOwnedSlice();
}

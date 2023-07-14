const std = @import("std");

const schema_tools = @import("schema-tools.zig");

const Reference = @This();
ref: []const u8 = "",
summary: ?[]const u8 = null,
description: ?[]const u8 = null,

pub const empty = Reference{};

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Reference, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Reference){
    .ref = "$ref",
};

pub fn deinit(ref: Reference, allocator: std.mem.Allocator) void {
    allocator.free(ref.ref);
    allocator.free(ref.summary orelse "");
    allocator.free(ref.description orelse "");
}

pub const jsonStringify = schema_tools.generateMappedStringify(Reference, json_field_names);

pub fn jsonParseRealloc(
    result: *Reference,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    try schema_tools.jsonParseInPlaceTemplate(Reference, result, allocator, source, options, Reference.parseFieldValue);
}
pub inline fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(Reference),
    field_ptr: anytype,
    is_new: bool,
    ally: std.mem.Allocator,
    src: anytype,
    json_opt: std.json.ParseOptions,
) !void {
    _ = is_new;
    _ = field_tag;
    var new_str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
    defer new_str.deinit();
    field_ptr.* = "";
    try schema_tools.jsonParseReallocString(&new_str, src, json_opt);
    field_ptr.* = try new_str.toOwnedSlice();
}

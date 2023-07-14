const std = @import("std");

const schema_tools = @import("schema-tools.zig");
const Parameter = @import("Parameter.zig");

/// The Header Object follows the structure of the Parameter Object with the following changes:
///
///   1. name MUST NOT be specified, it is given in the corresponding headers map.
///   2. in MUST NOT be specified, it is implicitly in header.
///   3. All traits that are affected by the location MUST be applicable to a location of header (for example, style).
const Header = @This();
description: ?[]const u8 = null,
required: ?bool = null,
deprecated: ?bool = null,
allow_empty_value: ?bool = null,

pub const empty = Header{};

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Header, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Header){
    .allow_empty_value = Parameter.json_field_names.allow_empty_value,
};

pub fn deinit(header: Header, allocator: std.mem.Allocator) void {
    allocator.free(header.description orelse "");
}

pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(
    Header,
    Header.json_field_names,
);

pub fn jsonParseRealloc(
    result: *Header,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    var field_set = schema_tools.FieldEnumSet(Header).initEmpty();
    try schema_tools.jsonParseInPlaceTemplate(
        Header,
        result,
        allocator,
        source,
        options,
        &field_set,
    );
}

pub inline fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(Header),
    field_ptr: *std.meta.FieldType(Header, field_tag),
    is_new: bool,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) !void {
    _ = is_new;

    switch (field_tag) {
        .description => {
            var new_str = std.ArrayList(u8).fromOwnedSlice(allocator, @constCast(field_ptr.* orelse ""));
            defer new_str.deinit();

            new_str.clearRetainingCapacity();
            field_ptr.* = null;

            try schema_tools.jsonParseReallocString(&new_str, source, options);
            field_ptr.* = try new_str.toOwnedSlice();
        },
        .required,
        .deprecated,
        .allow_empty_value,
        => {
            field_ptr.* = switch (try source.next()) {
                .true => true,
                .false => false,
                else => return error.UnexpectedToken,
            };
        },
    }
}

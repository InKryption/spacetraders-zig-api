const std = @import("std");

const schema_tools = @import("schema-tools.zig");

const Discriminator = @This();
property_name: []const u8 = "",
mapping: ?std.json.ArrayHashMap([]const u8) = null,

pub const empty = Discriminator{};

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Discriminator, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Discriminator){
    .property_name = "propertyName",
};

pub fn deinit(discriminator: *Discriminator, allocator: std.mem.Allocator) void {
    allocator.free(discriminator.property_name);
    if (discriminator.mapping) |*mapping| {
        for (mapping.map.keys(), mapping.map.values()) |key, value| {
            allocator.free(key);
            allocator.free(value);
        }
        mapping.deinit(allocator);
    }
}

pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(
    Discriminator,
    Discriminator.json_field_names,
);

pub fn jsonParseRealloc(
    result: *Discriminator,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    var field_set = schema_tools.FieldEnumSet(Discriminator).initEmpty();
    try schema_tools.jsonParseInPlaceTemplate(
        Discriminator,
        result,
        allocator,
        source,
        options,
        &field_set,
        Discriminator.parseFieldValue,
    );
}

pub inline fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(Discriminator),
    field_ptr: *std.meta.FieldType(Discriminator, field_tag),
    is_new: bool,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) !void {
    _ = is_new;
    switch (field_tag) {
        .property_name => {
            var new_str = std.ArrayList(u8).fromOwnedSlice(allocator, @constCast(field_ptr.*));
            defer new_str.deinit();

            new_str.clearRetainingCapacity();
            field_ptr.* = "";

            try schema_tools.jsonParseReallocString(&new_str, source, options);
            field_ptr.* = try new_str.toOwnedSlice();
        },
        .mapping => {},
    }
}

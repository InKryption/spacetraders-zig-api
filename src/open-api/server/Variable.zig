const std = @import("std");

const schema_tools = @import("../schema-tools.zig");

const Variable = @This();
enumeration: ?Enum = .{},
default: []const u8 = "",
description: ?[]const u8 = null,

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Variable, .{});
pub const json_field_names = .{
    .enumeration = "enum",
};

pub const Enum = std.ArrayHashMapUnmanaged(
    []const u8,
    void,
    std.array_hash_map.StringContext,
    true,
);

pub fn deinit(variable: *Variable, allocator: std.mem.Allocator) void {
    if (variable.enumeration) |*enumeration| {
        for (enumeration.keys()) |value| {
            allocator.free(value);
        }
        enumeration.deinit(allocator);
    }
}

pub fn jsonStringify(
    server: Variable,
    options: std.json.StringifyOptions,
    writer: anytype,
) @TypeOf(writer).Error!void {
    const simpler = .{
        .enumeration = if (server.enumeration) |enumeration| enumeration.keys() else null,
        .default = server.default,
        .description = server.description,
    };
    const generatedStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(@TypeOf(simpler), Variable.json_field_names);
    try generatedStringify(simpler, options, writer);
}

pub inline fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Variable {
    var result: Variable = Variable.empty;
    errdefer result.deinit(allocator);
    try Variable.jsonParseRealloc(&result, allocator, source, options);
    return result;
}
pub fn jsonParseRealloc(
    result: *Variable,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    try schema_tools.jsonParseInPlaceTemplate(Variable, result, allocator, source, options, Variable.parseFieldValue);
}

pub inline fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(Variable),
    field_ptr: *std.meta.FieldType(Variable, field_tag),
    is_new: bool,
    ally: std.mem.Allocator,
    src: anytype,
    json_opt: std.json.ParseOptions,
) !void {
    _ = field_ptr;
    _ = json_opt;
    _ = src;
    _ = ally;
    _ = is_new;
    @panic("TODO");
}

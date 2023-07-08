const std = @import("std");

const schema_tools = @import("schema-tools.zig");

const Server = @This();
url: []const u8 = "",
description: ?[]const u8 = null,
variables: ?VariableMap = null,

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Server, .{});
pub const json_field_names = schema_tools.JsonStringifyFieldNameMap(Server){};
pub fn jsonStringify(
    server: Server,
    options: std.json.StringifyOptions,
    writer: anytype,
) @TypeOf(writer).Error!void {
    try writer.writeByte('{');
    var child_options = options;
    child_options.whitespace.indent_level += 1;

    try child_options.whitespace.outputIndent(writer);

    try std.json.stringify(@as([]const u8, "url"), options, writer);
    try writer.writeByte(':');
    if (child_options.whitespace.separator) {
        try writer.writeByte(' ');
    }
    try std.json.stringify(server.url, options, writer);

    if (server.description) |description| {
        try writer.writeByte(',');
        try std.json.stringify(@as([]const u8, "description"), options, writer);
        try writer.writeByte(':');
        if (child_options.whitespace.separator) {
            try writer.writeByte(' ');
        }
        try std.json.stringify(description, options, writer);
    }

    if (server.variables) |*variables| {
        try writer.writeByte(',');
        try std.json.stringify(@as([]const u8, "variables"), options, writer);
        try writer.writeByte(':');
        if (child_options.whitespace.separator) {
            try writer.writeByte(' ');
        }
        try jsonStringifyVariableMap(variables, child_options, writer);
    }

    try options.whitespace.outputIndent(writer);
    try writer.writeByte('}');
}

pub fn deinit(server: *Server, allocator: std.mem.Allocator) void {
    allocator.free(server.url);
    allocator.free(server.description orelse "");
    if (server.variables) |*variables| {
        for (variables.keys(), variables.values()) |key, *value| {
            allocator.free(key);
            value.deinit(allocator);
        }
        variables.deinit(allocator);
    }
}

pub inline fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Server {
    var result: Server = .{};
    errdefer result.deinit(allocator);
    try Server.jsonParseRealloc(&result, allocator, source, options);
    return result;
}
pub fn jsonParseRealloc(
    result: *Server,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    const helper = struct {};
    _ = helper;

    try schema_tools.jsonParseInPlaceTemplate(Server, result, allocator, source, options, Server.parseFieldValue);
}
inline fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(Server),
    field_ptr: *std.meta.FieldType(Server, field_tag),
    is_new: bool,
    ally: std.mem.Allocator,
    src: anytype,
    json_opt: std.json.ParseOptions,
) !void {
    _ = is_new;
    switch (field_tag) {
        .url, .description => {
            var str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
            defer str.deinit();
            field_ptr.* = "";
            try schema_tools.jsonParseReallocString(&str, src, json_opt);
            field_ptr.* = try str.toOwnedSlice();
        },
        .variables => {
            if (field_ptr.* == null) {
                field_ptr.* = .{};
            }
            const variables: *VariableMap = &field_ptr.*.?;
            for (variables.keys(), variables.values()) |key, *value| {
                ally.free(key);
                value.deinit(ally);
            }
            variables.clearRetainingCapacity();

            if (try src.next() != .array_begin) {
                return error.UnexpectedToken;
            }

            while (true) {}

            unreachable;
        },
    }
}

pub const VariableMap = std.ArrayHashMapUnmanaged([]const u8, Variable, std.array_hash_map.StringContext, true);
pub const Variable = struct {
    /// [string]
    /// An enumeration of string values to be used if the substitution options are from a limited set.
    /// The array MUST NOT be empty.
    ///
    /// real name: 'enum'
    enumeration: ?Enum,
    /// string
    ///
    /// REQUIRED.
    ///
    /// The default value to use for substitution,
    /// which SHALL be sent if an alternate value is not supplied.
    /// Note this behavior is different than the Schema Object’s treatment of default values,
    /// because in those cases parameter values are optional.
    /// If the enum is defined, the value MUST exist in the enum’s values.
    default: []const u8,
    /// string
    ///
    /// An optional description for the server variable.
    /// CommonMark syntax MAY be used for rich text representation.
    description: ?[]const u8,

    pub const empty = Variable{
        .enumeration = null,
        .default = "",
        .description = null,
    };
    pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Variable, .{});
    pub const json_field_names = .{
        .enumeration = "enum",
    };
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

    pub fn deinit(variable: *Variable, allocator: std.mem.Allocator) void {
        if (variable.enumeration) |*enumeration| {
            for (enumeration.keys()) |value| {
                allocator.free(value);
            }
            enumeration.deinit(allocator);
        }
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
    inline fn parseFieldValue(
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
        unreachable;
    }

    pub const Enum = std.ArrayHashMapUnmanaged([]const u8, void, std.array_hash_map.StringContext, true);
};

fn jsonStringifyVariableMap(
    variables: *const VariableMap,
    options: std.json.StringifyOptions,
    writer: anytype,
) !void {
    try writer.writeByte('{');
    var field_output = false;
    var child_options = options;
    child_options.whitespace.indent_level += 1;

    for (variables.keys(), variables.values(), 0..) |key, value, i| {
        if (i != 0 and field_output) {
            try writer.writeByte(',');
        } else {
            field_output = true;
        }
        try child_options.whitespace.outputIndent(writer);

        try std.json.stringify(key, options, writer);
        try writer.writeByte(':');
        if (child_options.whitespace.separator) {
            try writer.writeByte(' ');
        }
        try std.json.stringify(value, child_options, writer);
    }
    if (field_output) {
        try options.whitespace.outputIndent(writer);
    }
    try writer.writeByte('}');
}

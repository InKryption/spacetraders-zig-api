const std = @import("std");

const schema_tools = @import("schema-tools.zig");

const Server = @This();
url: []const u8 = "",
description: ?[]const u8 = null,
variables: ?VariableMap = null,

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Server, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Server){};

pub const Variable = @import("server/Variable.zig");
pub const VariableMap = std.json.ArrayHashMap(Variable);

pub fn deinit(server: *Server, allocator: std.mem.Allocator) void {
    allocator.free(server.url);
    allocator.free(server.description orelse "");
    if (server.variables) |*variables| {
        schema_tools.deinitArrayHashMap(allocator, Variable, variables);
    }
}

pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(
    Server,
    Server.json_field_names,
);

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
    var field_set = schema_tools.FieldEnumSet(Server).initEmpty();
    try schema_tools.jsonParseInPlaceTemplate(Server, result, allocator, source, options, &field_set, Server.parseFieldValue);
}

pub inline fn parseFieldValue(
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
            try schema_tools.jsonParseInPlaceArrayHashMapTemplate(
                Variable,
                &field_ptr.*.?,
                ally,
                src,
                json_opt,
            );
        },
    }
}

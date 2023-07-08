//! OpenAPI Specification Version 3.1.0
const std = @import("std");
const assert = std.debug.assert;
const util = @import("util");

const schema_tools = @import("schema-tools.zig");
pub const Paths = @import("Paths.zig");
pub const Info = @import("Info.zig");
pub const Server = @import("Server.zig");

const Schema = @This();
openapi: []const u8 = "",
info: Info = .{},
json_schema_dialect: ?[]const u8 = null,
servers: ?[]const Server = null,
paths: ?Paths = null,
// webhooks: ?Webhooks,
// components: ?Components,
// security: ?Security,

// /// [Tag Object]
// ///  A list of tags used by the document with additional metadata. The order of the tags can be used to reflect on their order by the parsing tools. Not all tags that are used by the Operation Object must be declared. The tags that are not declared MAY be organized randomly or based on the tools’ logic. Each tag name in the list MUST be unique.
// tags,

// /// External Documentation Object
// ///  Additional external documentation.
// externalDocs,

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Schema, .{});
pub const json_field_names = schema_tools.JsonStringifyFieldNameMap(Schema){
    .json_schema_dialect = "jsonSchemaDialect",
};
pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(Schema, Schema.json_field_names);

pub fn deinit(self: Schema, allocator: std.mem.Allocator) void {
    allocator.free(self.openapi);
    self.info.deinit(allocator);
    allocator.free(self.json_schema_dialect orelse "");
    if (self.servers) |servers| {
        for (servers) |*server| {
            @constCast(server).deinit(allocator);
        }
        allocator.free(servers);
    }
}

pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Schema {
    var result: Schema = .{};
    errdefer result.deinit(allocator);
    try jsonParseRealloc(&result, allocator, source, options);
    return result;
}
pub fn jsonParseRealloc(
    result: *Schema,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    try schema_tools.jsonParseInPlaceTemplate(Schema, result, allocator, source, options, Schema.parseFieldValue);
}
inline fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(Schema),
    field_ptr: anytype,
    is_new: bool,
    ally: std.mem.Allocator,
    src: anytype,
    json_opt: std.json.ParseOptions,
) !void {
    _ = is_new;
    switch (field_tag) {
        inline .openapi, .json_schema_dialect => {
            var str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
            defer str.deinit();
            field_ptr.* = "";
            try schema_tools.jsonParseReallocString(&str, src, json_opt);
            field_ptr.* = try str.toOwnedSlice();
        },
        .info => try Info.jsonParseRealloc(field_ptr, ally, src, json_opt),
        .servers => {
            var list = std.ArrayListUnmanaged(Server).fromOwnedSlice(@constCast(field_ptr.* orelse &.{}));
            defer {
                for (list.items) |*server|
                    server.deinit(ally);
                list.deinit(ally);
            }
            field_ptr.* = null;
            try schema_tools.jsonParseInPlaceArrayListTemplate(Server, &list, ally, src, json_opt);
            field_ptr.* = try list.toOwnedSlice(ally);
        },
        .paths => {
            if (field_ptr.* == null) {
                field_ptr.* = .{};
            }
            try Paths.jsonParseRealloc(&field_ptr.*.?, ally, src, json_opt);
        },
    }
}

test Schema {
    const src =
        @embedFile("../../SpaceTraders.json")
    // \\{
    // \\    "openapi": "3.0.0",
    // \\    "info": {
    // \\        "title": "foo",
    // \\        "version": "1.0.1"
    // \\    },
    // \\    "jsonSchemaDialect": "example schema"
    // \\}
    ;

    var scanner = std.json.Scanner.initCompleteInput(std.testing.allocator, src);
    defer scanner.deinit();

    // const expected_src: []const u8 = blk: {
    //     const parsed = try std.json.parseFromTokenSource(std.json.Value, std.testing.allocator, &scanner, .{});
    //     defer parsed.deinit();
    //     break :blk try std.json.stringifyAlloc(std.testing.allocator, parsed.value, .{ .whitespace = .{} });
    // };
    // defer std.testing.allocator.free(expected_src);

    scanner.deinit();
    scanner = std.json.Scanner.initCompleteInput(std.testing.allocator, src);
    var diag = std.json.Diagnostics{};
    scanner.enableDiagnostics(&diag);

    const openapi_json = std.json.parseFromTokenSourceLeaky(Schema, std.testing.allocator, &scanner, std.json.ParseOptions{ .ignore_unknown_fields = true }) catch |err| {
        const start = std.mem.lastIndexOfScalar(u8, src[0 .. std.mem.lastIndexOfScalar(u8, src[0..diag.getByteOffset()], '\n') orelse 0], '\n') orelse 0;
        const end = std.mem.indexOfScalarPos(u8, src[0..], diag.getByteOffset(), '\n') orelse src.len;

        std.log.err("{s} at {d}:{d}:\n{s}", .{ @errorName(err), diag.getLine(), diag.getColumn(), src[start..end] });
        return err;
    };
    defer openapi_json.deinit(std.testing.allocator);
    // try std.testing.expectFmt(expected_src, "{}", .{util.json.fmtStringify(openapi_json, .{ .whitespace = .{} })});
}

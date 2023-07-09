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
// webhooks: ?Webhooks = null,
// components: ?Components = null,
// security: ?Security = null,

// /// [Tag Object]
// ///  A list of tags used by the document with additional metadata. The order of the tags can be used to reflect on their order by the parsing tools. Not all tags that are used by the Operation Object must be declared. The tags that are not declared MAY be organized randomly or based on the tools’ logic. Each tag name in the list MUST be unique.
// tags: ?Tags = null,

// /// External Documentation Object
// ///  Additional external documentation.
// externalDocs: ?ExternalDocs = null,

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Schema, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Schema){
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
    if (self.paths) |paths| {
        var copy = paths;
        copy.deinit(allocator);
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
            str.clearRetainingCapacity();
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
    const src = @embedFile("SpaceTraders.json")
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

    scanner.deinit();
    scanner = std.json.Scanner.initCompleteInput(std.testing.allocator, src);

    var diag = std.json.Diagnostics{};
    scanner.enableDiagnostics(&diag);
    const openapi_json: Schema = std.json.parseFromTokenSourceLeaky(
        Schema,
        std.testing.allocator,
        &scanner,
        std.json.ParseOptions{
            .ignore_unknown_fields = true,
        },
    ) catch |err| {
        const start = std.mem.lastIndexOfScalar(u8, src[0 .. std.mem.lastIndexOfScalar(u8, src[0..diag.getByteOffset()], '\n') orelse 0], '\n') orelse 0;
        const end = std.mem.indexOfScalarPos(u8, src[0..], diag.getByteOffset(), '\n') orelse src.len;

        std.log.err("{s} at {d}:{d}:\n{s}", .{ @errorName(err), diag.getLine(), diag.getColumn(), src[start..end] });
        return err;
    };
    defer openapi_json.deinit(std.testing.allocator);

    try expectEqualJson(src, openapi_json, .{});
}

fn expectEqualJson(a: anytype, b: anytype, options: std.json.ParseOptions) (error{TestExpectedEqual} || std.json.ParseError(std.json.Scanner))!void {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    if (A != std.json.Value) {
        if (comptime !std.meta.trait.isZigString(A)) {
            const a_str = std.json.stringifyAlloc(std.testing.allocator, a, .{}) catch |err| @panic(@errorName(err));
            defer std.testing.allocator.free(a_str);
            return expectEqualJson(a_str, b, options);
        }
        const a_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, a, options);
        defer a_json.deinit();
        return expectEqualJson(a_json.value, b, options);
    }

    if (B != std.json.Value) {
        if (comptime !std.meta.trait.isZigString(B)) {
            const b_str = std.json.stringifyAlloc(std.testing.allocator, b, .{}) catch |err| @panic(@errorName(err));
            defer std.testing.allocator.free(b_str);
            return expectEqualJson(a, b_str, options);
        }
        const b_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, b, options);
        defer b_json.deinit();
        return expectEqualJson(a, b_json.value, options);
    }
    const expected_tag: @typeInfo(std.json.Value).Union.tag_type.? = a;

    try std.testing.expectEqual(expected_tag, b);
    switch (a) {
        .null => {},
        inline //
        .bool,
        .integer,
        .float,
        => |expected, tag| try std.testing.expectEqual(expected, @field(b, @tagName(tag))),

        inline //
        .number_string,
        .string,
        => |expected, tag| try std.testing.expectEqualStrings(expected, @field(b, @tagName(tag))),

        .array => |expected| {
            try std.testing.expectEqual(expected.items.len, b.array.items.len);
            for (expected.items, b.array.items, 0..) |expected_item, actual_item, i| {
                errdefer std.log.err("Difference occurred between elements at index {d}", .{i});
                try expectEqualJson(expected_item, actual_item, options);
            }
        },

        .object => |expected| {
            try std.testing.expectEqual(expected.count(), b.object.count());
            var iter = expected.iterator();
            var i: usize = 0;
            while (iter.next()) |expected_entry| : (i += 1) {
                errdefer std.log.err("Difference occurred between elements on iteration {d}", .{i});
                const actual_entry = b.object.getEntry(expected_entry.key_ptr.*) orelse
                    return if (std.testing.expectEqual(@as(?@TypeOf(expected_entry), expected_entry), null)) |_|
                    unreachable
                else |err|
                    err;
                try std.testing.expectEqualStrings(expected_entry.key_ptr.*, actual_entry.key_ptr.*);
                try expectEqualJson(expected_entry.value_ptr.*, actual_entry.value_ptr.*, options);
            }
        },
    }
}

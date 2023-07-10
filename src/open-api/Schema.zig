//! OpenAPI Specification Version 3.1.0
const std = @import("std");
const util = @import("util");

const schema_tools = @import("schema-tools.zig");
pub const Info = @import("Info.zig");
pub const Paths = @import("Paths.zig");
pub const Server = @import("Server.zig");
pub const Parameter = @import("Parameter.zig");
pub const Reference = @import("Reference.zig");
pub const Webhooks = @import("Webhooks.zig");
pub const SecurityRequirement = @import("SecurityRequirement.zig");
pub const Tag = @import("Tag.zig");
pub const ExternalDocs = @import("ExternalDocs.zig");

const Schema = @This();
openapi: []const u8 = "",
info: Info = .{},
json_schema_dialect: ?[]const u8 = null,
servers: ?[]const Server = null,
paths: ?Paths = null,
webhooks: ?Webhooks = null,
// components: ?Components = null,
security: ?[]const SecurityRequirement = null,
tags: ?[]const Tag = null,
external_docs: ?ExternalDocs = null,

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Schema, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Schema){
    .json_schema_dialect = "jsonSchemaDialect",
    .external_docs = "externalDocs",
};

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

    if (self.security) |security| {
        for (@constCast(security)) |*secreq| {
            secreq.deinit(allocator);
        }
        allocator.free(security);
    }
}

pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(
    Schema,
    Schema.json_field_names,
);

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
    var field_set = schema_tools.FieldEnumSet(Schema).initEmpty();
    try schema_tools.jsonParseInPlaceTemplate(
        Schema,
        result,
        allocator,
        source,
        options,
        &field_set,
        Schema.parseFieldValue,
    );
}

pub inline fn parseFieldValue(
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
        .webhooks => {
            if (field_ptr.* == null) {
                field_ptr.* = .{};
            }
            try Webhooks.jsonParseRealloc(&field_ptr.*.?, ally, src, json_opt);
        },

        .security => {
            var list = std.ArrayListUnmanaged(SecurityRequirement).fromOwnedSlice(@constCast(field_ptr.* orelse &.{}));
            defer {
                for (list.items) |*security|
                    security.deinit(ally);
                list.deinit(ally);
            }
            field_ptr.* = null;
            try schema_tools.jsonParseInPlaceArrayListTemplate(SecurityRequirement, &list, ally, src, json_opt);
            field_ptr.* = try list.toOwnedSlice(ally);
        },
        .tags => @panic("TODO"),
        .external_docs => @panic("TODO"),
    }
}

pub const Tags = struct {
    set: Set = .{},

    pub const Set = std.ArrayHashMapUnmanaged(
        Tag,
        void,
        Tag.ArrayHashCtx,
        true,
    );

    pub fn deinit(tags: *Tags, allocator: std.mem.Allocator) void {
        for (tags.set.keys()) |*tag|
            tag.deinit(allocator);
        tags.set.deinit(allocator);
    }

    pub fn jsonStringify(
        tags: Tags,
        options: std.json.StringifyOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        try std.json.stringify(@as([]const Tag, tags.set.values()), options, writer);
    }

    pub fn jsonParseRealloc(
        result: *Paths,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!void {
        _ = options;
        _ = allocator;
        _ = result;
    }
};

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
            .ignore_unknown_fields = false,
        },
    ) catch |err| {
        const start = std.mem.lastIndexOfScalar(u8, src[0 .. std.mem.lastIndexOfScalar(u8, src[0..diag.getByteOffset()], '\n') orelse 0], '\n') orelse 0;
        const end = std.mem.indexOfScalarPos(u8, src[0..], diag.getByteOffset(), '\n') orelse src.len;

        std.log.err("{s} at {d}:{d}:\n{s}", .{ @errorName(err), diag.getLine(), diag.getColumn(), src[start..end] });
        return err;
    };
    defer openapi_json.deinit(std.testing.allocator);

    try util.json.expectEqual(src, openapi_json, .{});
}

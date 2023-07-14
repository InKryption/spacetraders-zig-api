//! OpenAPI Specification Version 3.1.0
const std = @import("std");
const assert = std.debug.assert;

const util = @import("util");

const schema_tools = @import("schema-tools.zig");
pub const Components = @import("Components.zig");
pub const Info = @import("Info.zig");
pub const PathItem = @import("PathItem.zig");
pub const Server = @import("Server.zig");
pub const Parameter = @import("Parameter.zig");
pub const Reference = @import("Reference.zig");
pub const SecurityRequirement = @import("SecurityRequirement.zig");
pub const Tag = @import("Tag.zig");
pub const ExternalDocs = @import("ExternalDocs.zig");

const OpenAPI = @This();
openapi: []const u8 = "",
info: Info = .{},
json_schema_dialect: ?[]const u8 = null,
servers: ?[]const Server = null,
paths: ?std.json.ArrayHashMap(PathItem) = null,
webhooks: ?std.json.ArrayHashMap(PathItem) = null,
components: ?Components = null,
security: ?[]const SecurityRequirement = null,
tags: ?Tags = null,
external_docs: ?ExternalDocs = null,

const json_field_names = schema_tools.ZigToJsonFieldNameMap(OpenAPI){
    .json_schema_dialect = "jsonSchemaDialect",
    .external_docs = "externalDocs",
};

pub fn deinit(self: OpenAPI, allocator: std.mem.Allocator) void {
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
        schema_tools.deinitArrayHashMap(allocator, PathItem, &copy);
    }
    if (self.components) |components| {
        var copy = components;
        copy.deinit(allocator);
    }
    if (self.security) |security| {
        for (@constCast(security)) |*secreq| {
            secreq.deinit(allocator);
        }
        allocator.free(security);
    }
    if (self.tags) |tags| {
        var copy = tags;
        copy.deinit(allocator);
    }
}

pub const jsonStringify = schema_tools.generateMappedStringify(OpenAPI, json_field_names);

pub fn jsonParse(
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!OpenAPI {
    var result: OpenAPI = .{};
    errdefer result.deinit(allocator);

    var field_set = schema_tools.FieldEnumSet(OpenAPI).initEmpty();
    try schema_tools.parseObjectMappedTemplate(
        OpenAPI,
        &result,

        allocator,
        source,
        options,

        &field_set,
        json_field_names,
        parseFieldValue,
    );
    if (!field_set.supersetOf(schema_tools.requiredFieldSetBasedOnOptionals(OpenAPI, .{}))) {
        return error.MissingField;
    }

    return result;
}

pub inline fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(OpenAPI),
    field_ptr: anytype,
    is_new: bool,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) !void {
    _ = is_new;
    switch (field_tag) {
        inline .openapi, .json_schema_dialect => {
            var str = std.ArrayList(u8).fromOwnedSlice(allocator, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
            defer str.deinit();
            str.clearRetainingCapacity();
            field_ptr.* = "";
            try schema_tools.jsonParseReallocString(&str, source, options);
            field_ptr.* = try str.toOwnedSlice();
        },
        .info => try Info.jsonParseRealloc(field_ptr, allocator, source, options),
        .servers => {
            var list = std.ArrayListUnmanaged(Server).fromOwnedSlice(@constCast(field_ptr.* orelse &.{}));
            defer {
                for (list.items) |*server|
                    server.deinit(allocator);
                list.deinit(allocator);
            }
            field_ptr.* = null;
            try schema_tools.jsonParseInPlaceArrayListTemplate(Server, &list, allocator, source, options);
            field_ptr.* = try list.toOwnedSlice(allocator);
        },
        .paths,
        .webhooks,
        => {
            if (field_ptr.* == null) {
                field_ptr.* = .{};
            }
            // try Paths.jsonParseRealloc(&field_ptr.*.?, allocator, source, options);
            var hm = std.json.ArrayHashMap(PathItem){
                .map = if (field_ptr.*) |*ptr| ptr.map.move() else .{},
            };
            defer hm.deinit(allocator);
            try schema_tools.jsonParseInPlaceArrayHashMapTemplate(
                PathItem,
                &hm,
                allocator,
                source,
                options,
                schema_tools.ParseArrayHashMapInPlaceObjCtx(PathItem),
            );
            field_ptr.* = .{ .map = hm.map.move() };
        },
        .components => {
            if (field_ptr.* == null) {
                field_ptr.* = .{};
            }
            try Components.jsonParseRealloc(&field_ptr.*.?, allocator, source, options);
        },
        .security => {
            var list = std.ArrayListUnmanaged(SecurityRequirement).fromOwnedSlice(@constCast(field_ptr.* orelse &.{}));
            defer {
                for (list.items) |*security|
                    security.deinit(allocator);
                list.deinit(allocator);
            }
            field_ptr.* = null;
            try schema_tools.jsonParseInPlaceArrayListTemplate(SecurityRequirement, &list, allocator, source, options);
            field_ptr.* = try list.toOwnedSlice(allocator);
        },
        .tags => {
            var tags: Tags = field_ptr.* orelse Tags{};
            errdefer tags.deinit(allocator);
            field_ptr.* = null;
            try tags.jsonParseRealloc(allocator, source, options);
            field_ptr.* = tags;
        },
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
        try std.json.stringify(@as([]const Tag, tags.set.keys()), options, writer);
    }

    pub fn jsonParseRealloc(
        result: *Tags,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!void {
        var old_set = result.set.move();
        defer for (old_set.keys()) |*tag| {
            tag.deinit(allocator);
        } else old_set.deinit(allocator);

        var new_set = Set{};
        defer for (new_set.keys()) |*tag| {
            tag.deinit(allocator);
        } else new_set.deinit(allocator);
        try new_set.ensureUnusedCapacity(allocator, old_set.count());

        if (try source.next() != .array_begin) {
            return error.UnexpectedToken;
        }

        while (true) {
            switch (try source.peekNextTokenType()) {
                .array_end => {
                    assert(try source.next() == .array_end);
                    break;
                },
                else => {},
            }

            try new_set.ensureUnusedCapacity(allocator, 1);
            var tag: Tag = if (old_set.popOrNull()) |old| old.key else Tag{};
            errdefer tag.deinit(allocator);
            try tag.jsonParseRealloc(allocator, source, options);
            new_set.putAssumeCapacity(tag, {});
        }

        result.set = new_set.move();
    }
};

test OpenAPI {
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

    const openapi_json: OpenAPI = std.json.parseFromTokenSourceLeaky(
        OpenAPI,
        std.testing.allocator,
        &scanner,
        std.json.ParseOptions{
            .ignore_unknown_fields = false,
        },
    ) catch |err| {
        const start = if (std.mem.lastIndexOfScalar(u8, src[0..diag.getByteOffset()], '\n')) |idx| idx + 1 else 0;
        const end = std.mem.indexOfScalarPos(u8, src, diag.getByteOffset(), '\n') orelse src.len;
        const cursor = struct {
            col: u64,
            pub fn format(
                cursor: @This(),
                comptime fmt_str: []const u8,
                options: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                _ = options;
                _ = fmt_str;
                try writer.writeByteNTimes('~', cursor.col - 1);
                try writer.writeByte('^');
            }
        }{ .col = diag.getColumn() };

        std.log.err("{[err]s} at {[line]d}:{[col]d}:" ++
            \\```
            \\{[snippet]s}
            \\{[cursor]}
            \\```
        , .{
            .err = @errorName(err),
            .line = diag.getLine(),
            .col = diag.getColumn(),
            .snippet = src[start..end],
            .cursor = cursor,
        });
        return err;
    };
    defer openapi_json.deinit(std.testing.allocator);

    var val = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, src, .{});
    defer val.deinit();

    try util.json.expectEqual(val.value, openapi_json, .{});
}

//! OpenAPI Specification Version 3.1.0
const std = @import("std");
const assert = std.debug.assert;

const util = @import("util");

const schema_tools = @import("schema-tools.zig");
pub const Components = @import("Components.zig");
pub const Info = @import("Info.zig");
pub const Paths = @import("Paths.zig");
pub const Server = @import("Server.zig");
pub const Parameter = @import("Parameter.zig");
pub const Reference = @import("Reference.zig");
pub const Webhooks = @import("Webhooks.zig");
pub const SecurityRequirement = @import("SecurityRequirement.zig");
pub const Tag = @import("Tag.zig");
pub const ExternalDocs = @import("ExternalDocs.zig");

const OpenAPI = @This();
openapi: []const u8 = "",
info: Info = .{},
json_schema_dialect: ?[]const u8 = null,
servers: ?[]const Server = null,
paths: ?Paths = null,
webhooks: ?Webhooks = null,
components: ?Components = null,
security: ?[]const SecurityRequirement = null,
tags: ?Tags = null,
external_docs: ?ExternalDocs = null,

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(OpenAPI, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(OpenAPI){
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
        copy.deinit(allocator);
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

pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(
    OpenAPI,
    OpenAPI.json_field_names,
);

pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !OpenAPI {
    var result: OpenAPI = .{};
    errdefer result.deinit(allocator);
    try jsonParseRealloc(&result, allocator, source, options);
    return result;
}

pub fn jsonParseRealloc(
    result: *OpenAPI,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    var field_set = schema_tools.FieldEnumSet(OpenAPI).initEmpty();
    try schema_tools.jsonParseInPlaceTemplate(
        OpenAPI,
        result,
        allocator,
        source,
        options,
        &field_set,
        OpenAPI.parseFieldValue,
    );
}

pub inline fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(OpenAPI),
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
        .components => {
            if (field_ptr.* == null) {
                field_ptr.* = .{};
            }
            try Components.jsonParseRealloc(&field_ptr.*.?, ally, src, json_opt);
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
        .tags => {
            var tags: Tags = field_ptr.* orelse Tags{};
            errdefer tags.deinit(ally);
            field_ptr.* = null;
            try tags.jsonParseRealloc(ally, src, json_opt);
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
            .ignore_unknown_fields = true,
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

const std = @import("std");

const schema_tools = @import("schema-tools.zig");
const HeaderOrRef = @import("header_or_ref.zig").HeaderOrRef;
const LinkOrRef = @import("link_or_ref.zig").LinkOrRef;
const MediaType = @import("MediaType.zig");

const Response = @This();
description: []const u8 = "",
headers: ?std.json.ArrayHashMap(HeaderOrRef) = null,
content: ?std.json.ArrayHashMap(MediaType) = null,
links: ?std.json.ArrayHashMap(LinkOrRef) = null,

pub const empty = Response{};

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Response, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Response){};

pub fn deinit(resp: *Response, allocator: std.mem.Allocator) void {
    allocator.free(resp.description);
    if (resp.headers) |*headers| headers.deinit(allocator);
    if (resp.content) |*content| content.deinit(allocator);
}

pub fn jsonStringify(
    resp: Response,
    options: std.json.StringifyOptions,
    writer: anytype,
) @TypeOf(writer).Error!void {
    _ = options;
    _ = resp;
    @panic("TODO");
}

pub fn jsonParseRealloc(
    result: *Response,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    var field_set = schema_tools.FieldEnumSet(Response).initEmpty();
    try schema_tools.jsonParseInPlaceTemplate(
        Response,
        result,
        allocator,
        source,
        options,
        &field_set,
        Response.parseFieldValue,
    );
}

pub fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(Response),
    field_ptr: *std.meta.FieldType(Response, field_tag),
    is_new: bool,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) !void {
    _ = is_new;
    switch (field_tag) {
        .description => {
            var new_str = std.ArrayList(u8).fromOwnedSlice(allocator, @constCast(field_ptr.*));
            defer new_str.deinit();

            new_str.clearRetainingCapacity();
            field_ptr.* = "";

            try schema_tools.jsonParseReallocString(&new_str, source, options);
            field_ptr.* = try new_str.toOwnedSlice();
        },
        .headers,
        .content,
        .links,
        => {
            const T = comptime switch (field_tag) {
                .headers => HeaderOrRef,
                .content => MediaType,
                .links => LinkOrRef,
                else => unreachable,
            };
            if (field_ptr.* == null) {
                field_ptr.* = .{};
            }
            try schema_tools.jsonParseInPlaceArrayHashMapTemplate(
                T,
                &field_ptr.*.?,
                allocator,
                source,
                options,
                schema_tools.ParseArrayHashMapInPlaceObjCtx(T),
            );
        },
    }
}

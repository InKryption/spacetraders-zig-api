const std = @import("std");

const schema_tools = @import("schema-tools.zig");

const Response = @This();

pub fn deinit(resp: Response, allocator: std.mem.Allocator) void {
    _ = allocator;
    _ = resp;
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
    _ = options;
    _ = allocator;
    _ = result;
    @panic("TODO");
}

const std = @import("std");

const schema_tools = @import("schema-tools.zig");
const ResponseOrRef = @import("response_or_ref.zig").ResponseOrRef;

const Responses = @This();
default: ?ResponseOrRef = null,
http_responses: ?HttpResponses = null,

pub const HttpResponses = std.ArrayHashMapUnmanaged(std.http.Status, ResponseOrRef, HttpStatusCodeHashCtx, true);
pub const HttpStatusCodeHashCtx = struct {
    pub fn hash(ctx: HttpStatusCodeHashCtx, key: std.http.Status) u32 {
        _ = ctx;
        return @intFromEnum(key);
    }
    pub fn eql(ctx: HttpStatusCodeHashCtx, a: std.http.Status, b: std.http.Status, b_index: usize) bool {
        _ = b_index;
        _ = ctx;
        return a == b;
    }
};

pub fn deinit(responses: *Responses, allocator: std.mem.Allocator) void {
    if (responses.default) |*default|
        default.deinit(allocator);
    if (responses.http_responses) |*http_responses| {
        for (http_responses.values()) |*resp|
            resp.deinit(allocator);
        http_responses.deinit(allocator);
    }
}

pub fn jsonStringify(
    resp: Responses,
    options: std.json.StringifyOptions,
    writer: anytype,
) @TypeOf(writer).Error!void {
    _ = options;
    _ = resp;
    @panic("TODO");
}

pub fn jsonParseRealloc(
    result: *Responses,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    _ = options;
    _ = allocator;
    _ = result;
    @panic("TODO");
}

const std = @import("std");

const schema_tools = @import("schema-tools.zig");
const Response = @import("Response.zig");
const Reference = @import("Reference.zig");

pub const ResponseOrRef = union(enum) {
    response: Response,
    reference: Reference,

    pub const empty = ResponseOrRef{ .reference = .{} };

    pub fn deinit(resp: *ResponseOrRef, allocator: std.mem.Allocator) void {
        switch (resp.*) {
            inline else => |*ptr| ptr.deinit(allocator),
        }
    }

    pub fn jsonStringify(
        resp: ResponseOrRef,
        options: std.json.StringifyOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        try switch (resp) {
            inline else => |val| val.jsonStringify(options, writer),
        };
    }

    pub fn jsonParseRealloc(
        result: *ResponseOrRef,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!void {
        _ = options;
        _ = allocator;
        _ = result;
        @panic("TODO");
    }
};

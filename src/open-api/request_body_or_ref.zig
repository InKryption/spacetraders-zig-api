const std = @import("std");
const assert = std.debug.assert;

const util = @import("util");

const schema_tools = @import("schema-tools.zig");
const RequestBody = @import("RequestBody.zig");
const Reference = @import("Reference.zig");

pub const RequestBodyOrRef = union(enum) {
    request_body: RequestBody,
    reference: Reference,

    pub fn deinit(reqbody: *RequestBody, allocator: std.mem.Allocator) void {
        switch (reqbody.*) {
            inline else => |*ptr| ptr.deinit(allocator),
        }
    }

    pub fn jsonStringify(
        reqbody: RequestBodyOrRef,
        options: std.json.StringifyOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        try switch (reqbody) {
            inline else => |val| val.jsonStringify(options, writer),
        };
    }

    pub fn jsonParseRealloc(
        result: *RequestBodyOrRef,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!void {
        _ = options;
        _ = allocator;
        _ = result;
    }
};

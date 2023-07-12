const std = @import("std");

const schema_tools = @import("schema-tools.zig");
const SecurityScheme = @import("SecurityScheme.zig");
const Reference = @import("Reference.zig");

pub const SecuritySchemeOrRef = union(enum) {
    security_scheme: SecurityScheme,
    reference: Reference,

    pub const empty = SecuritySchemeOrRef{ .reference = .{} };

    pub fn deinit(param: *SecuritySchemeOrRef, allocator: std.mem.Allocator) void {
        switch (param.*) {
            inline else => |*ptr| ptr.deinit(allocator),
        }
    }

    pub fn jsonStringify(
        param: SecuritySchemeOrRef,
        options: std.json.StringifyOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        try switch (param) {
            inline else => |val| val.jsonStringify(options, writer),
        };
    }

    pub fn jsonParseRealloc(
        result: *SecuritySchemeOrRef,
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

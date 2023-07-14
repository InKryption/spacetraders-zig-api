const std = @import("std");

const schema_tools = @import("schema-tools.zig");
const Header = @import("Header.zig");
const Reference = @import("Reference.zig");

pub const HeaderOrRef = union(enum) {
    header: Header,
    reference: Reference,

    pub const empty = HeaderOrRef{ .reference = Reference.empty };

    pub fn deinit(hdr: *HeaderOrRef, allocator: std.mem.Allocator) void {
        switch (hdr.*) {
            inline else => |*ptr| ptr.deinit(allocator),
        }
    }

    pub fn jsonStringify(
        hdr: HeaderOrRef,
        options: std.json.StringifyOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        try switch (hdr) {
            inline else => hdr.jsonStringify(options, writer),
        };
    }

    pub fn jsonParseRealloc(
        result: *HeaderOrRef,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !void {
        _ = options;
        _ = source;
        _ = allocator;
        _ = result;
        @panic("TODO");
    }
};

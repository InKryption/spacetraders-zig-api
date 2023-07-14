const std = @import("std");

const schema_tools = @import("schema-tools.zig");

const Encoding = @This();

pub fn deinit(encoding: *Encoding, allocator: std.mem.Allocator) void {
    _ = allocator;
    _ = encoding;
}

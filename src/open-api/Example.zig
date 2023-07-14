const std = @import("std");

const schema_tools = @import("schema-tools.zig");

const Example = @This();

pub fn deinit(encoding: *Example, allocator: std.mem.Allocator) void {
    _ = allocator;
    _ = encoding;
}

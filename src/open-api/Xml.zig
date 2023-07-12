const std = @import("std");

const schema_tools = @import("schema-tools.zig");

const Xml = @This();

pub fn deinit(xml: *Xml, allocator: std.mem.Allocator) void {
    _ = allocator;
    _ = xml;
}

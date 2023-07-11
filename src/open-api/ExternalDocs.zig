const std = @import("std");

const ExternalDocs = @This();

pub fn deinit(docs: ExternalDocs, allocator: std.mem.Allocator) void {
    _ = allocator;
    _ = docs;
}

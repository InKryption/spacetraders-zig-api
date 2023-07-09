const std = @import("std");
const assert = std.debug.assert;
const util = @import("util");

const schema_tools = @import("schema-tools.zig");

const Server = @import("Server.zig");
const Parameter = @import("Parameter.zig");
const Reference = @import("Reference.zig");

const Paths = @This();
fields: Fields = .{},

pub const Item = @import("paths/Item.zig");
pub const Fields = std.ArrayHashMapUnmanaged(
    []const u8,
    Item,
    std.array_hash_map.StringContext,
    true,
);

pub fn deinit(paths: *Paths, allocator: std.mem.Allocator) void {
    for (paths.fields.keys(), paths.fields.values()) |path, *item| {
        allocator.free(path);
        item.deinit(allocator);
    }
    paths.fields.deinit(allocator);
}

pub fn jsonStringify(
    paths: Paths,
    options: std.json.StringifyOptions,
    writer: anytype,
) !void {
    try writer.writeByte('{');
    var field_output = false;
    var child_options = options;
    child_options.whitespace.indent_level += 1;

    var iter = paths.fields.iterator();
    while (iter.next()) |entry| {
        if (field_output) {
            try writer.writeByte(',');
        } else field_output = true;

        try child_options.whitespace.outputIndent(writer);

        try std.json.stringify(entry.key_ptr.*, options, writer);
        try writer.writeByte(':');
        if (child_options.whitespace.separator) {
            try writer.writeByte(' ');
        }
        try std.json.stringify(entry.value_ptr.*, child_options, writer);
    }
    if (field_output) {
        try options.whitespace.outputIndent(writer);
    }
    try writer.writeByte('}');
}

pub fn jsonParseRealloc(
    result: *Paths,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    if (try source.next() != .object_begin) return error.UnexpectedToken;

    var old_fields = result.fields.move();
    defer {
        for (old_fields.keys(), old_fields.values()) |path, *item| {
            allocator.free(path);
            item.deinit(allocator);
        }
        old_fields.deinit(allocator);
    }

    var new_fields = Fields{};
    defer {
        for (new_fields.keys(), new_fields.values()) |path, *item| {
            allocator.free(path);
            item.deinit(allocator);
        }
        new_fields.deinit(allocator);
    }
    try new_fields.ensureUnusedCapacity(allocator, old_fields.count());

    var path_buffer = std.ArrayList(u8).init(allocator);
    defer path_buffer.deinit();

    while (true) {
        switch (try source.peekNextTokenType()) {
            else => unreachable,
            .object_end => {
                _ = try source.next();
                break;
            },
            .string => {},
        }

        path_buffer.clearRetainingCapacity();
        const new_path: []const u8 = (try source.allocNextIntoArrayListMax(
            &path_buffer,
            .alloc_if_needed,
            options.max_value_len orelse std.json.default_max_value_len,
        )) orelse path_buffer.items;

        const gop = try new_fields.getOrPut(allocator, new_path);
        gop.key_ptr.* = undefined;

        if (gop.found_existing) {
            assert(!old_fields.contains(new_path));
            switch (options.duplicate_field_behavior) {
                .@"error" => return error.DuplicateField,
                .use_first => {
                    try source.skipValue();
                    continue;
                },
                .use_last => {},
            }
        } else if (old_fields.fetchSwapRemove(new_path)) |old| {
            gop.key_ptr.* = old.key;
            gop.value_ptr.* = old.value;
        } else {
            gop.key_ptr.* = try allocator.dupe(u8, new_path);
            gop.value_ptr.* = .{};
        }

        try gop.value_ptr.jsonParseRealloc(allocator, source, options);
    }
    result.fields = new_fields.move();
}

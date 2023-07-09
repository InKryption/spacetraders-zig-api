const std = @import("std");
const assert = std.debug.assert;

const schema_tools = @import("schema-tools.zig");

const SecurityRequirement = @This();
fields: Fields = .{},

pub const Fields = std.ArrayHashMapUnmanaged(
    []const u8,
    []const []const u8,
    std.array_hash_map.StringContext,
    true,
);

pub fn deinit(secreq: *SecurityRequirement, allocator: std.mem.Allocator) void {
    var iter = secreq.fields.iterator();
    while (iter.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        freeFieldValue(allocator, entry.value_ptr.*);
    }
    secreq.fields.deinit(allocator);
}

pub fn jsonStringify(
    secreq: SecurityRequirement,
    options: std.json.StringifyOptions,
    writer: anytype,
) !void {
    _ = secreq;
    _ = options;
    _ = writer;
    @panic("TODO");
}

pub fn jsonParse(
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) !SecurityRequirement {
    var result = SecurityRequirement{};
    errdefer result.deinit(allocator);
    try result.jsonParseRealloc(allocator, source, options);
    return result;
}

pub fn jsonParseRealloc(
    result: *SecurityRequirement,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) !void {
    if (try source.next() != .object_begin) {
        return error.UnexpectedToken;
    }

    var old_fields = result.fields.move();
    defer {
        for (old_fields.keys(), old_fields.values()) |name, value| {
            allocator.free(name);
            freeFieldValue(allocator, value);
        }
        old_fields.deinit(allocator);
    }

    var new_fields = Fields{};
    defer {
        for (new_fields.keys(), new_fields.values()) |name, value| {
            allocator.free(name);
            freeFieldValue(allocator, value);
        }
        new_fields.deinit(allocator);
    }
    try new_fields.ensureUnusedCapacity(allocator, old_fields.count());

    var name_buffer = std.ArrayList(u8).init(allocator);
    defer name_buffer.deinit();

    while (true) {
        switch (try source.peekNextTokenType()) {
            else => unreachable,
            .object_end => {
                _ = try source.next();
                break;
            },
            .string => {},
        }

        name_buffer.clearRetainingCapacity();
        const new_name: []const u8 = (try source.allocNextIntoArrayListMax(
            &name_buffer,
            .alloc_if_needed,
            options.max_value_len orelse std.json.default_max_value_len,
        )) orelse name_buffer.items;

        const gop = try new_fields.getOrPut(allocator, new_name);
        gop.key_ptr.* = undefined;

        if (gop.found_existing) {
            assert(!old_fields.contains(new_name));
            switch (options.duplicate_field_behavior) {
                .@"error" => return error.DuplicateField,
                .use_first => {
                    try source.skipValue();
                    continue;
                },
                .use_last => {},
            }
        } else if (old_fields.fetchSwapRemove(new_name)) |old| {
            gop.key_ptr.* = old.key;
            gop.value_ptr.* = old.value;
        } else {
            gop.key_ptr.* = try allocator.dupe(u8, new_name);
            gop.value_ptr.* = &.{};
        }

        var list = std.ArrayList([]const u8).fromOwnedSlice(allocator, @constCast(gop.value_ptr.*));
        defer {
            for (list.items) |str|
                allocator.free(str);
            list.deinit();
        }
        gop.value_ptr.* = &.{};

        var overwritten_count: usize = 0;
        const overwritable_count = list.items.len;

        if (try source.next() != .array_begin) {
            return error.UnexpectedToken;
        }
        while (true) {
            switch (try source.peekNextTokenType()) {
                else => return error.UnexpectedToken,
                .array_end => {
                    assert(try source.next() == .array_end);
                    break;
                },
                .string => {},
            }
            if (overwritten_count < overwritable_count) {
                var new_str = std.ArrayList(u8).fromOwnedSlice(allocator, @constCast(list.items[overwritten_count]));
                defer new_str.deinit();
                list.items[overwritten_count] = "";
                try schema_tools.jsonParseReallocString(&new_str, source, options);
                list.items[overwritten_count] = try new_str.toOwnedSlice();
                overwritten_count += 1;
                continue;
            }
        }
        if (overwritten_count < overwritable_count) {
            for (list.items[overwritten_count..]) |left_over| {
                allocator.free(left_over);
            }
            list.shrinkRetainingCapacity(overwritten_count);
        }

        gop.value_ptr.* = try list.toOwnedSlice();
    }
    result.fields = new_fields.move();
}

inline fn freeFieldValue(allocator: std.mem.Allocator, value: []const []const u8) void {
    for (value) |str|
        allocator.free(str);
    allocator.free(value);
}

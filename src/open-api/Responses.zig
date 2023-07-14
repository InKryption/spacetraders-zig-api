const std = @import("std");
const assert = std.debug.assert;

const schema_tools = @import("schema-tools.zig");
const ResponseOrRef = @import("response_or_ref.zig").ResponseOrRef;

const Responses = @This();
default: ?ResponseOrRef,
http_responses: ?HttpResponses,

pub const empty = Responses{
    .default = null,
    .http_responses = null,
};

pub const HttpResponses = std.ArrayHashMapUnmanaged(
    std.http.Status,
    ResponseOrRef,
    HttpStatusCodeHashCtx,
    true,
);
pub const HttpStatusCodeHashCtx = struct {
    pub fn hash(ctx: HttpStatusCodeHashCtx, key: std.http.Status) u32 {
        _ = ctx;
        return @intFromEnum(key);
    }
    pub fn eql(ctx: HttpStatusCodeHashCtx, a: std.http.Status, b: std.http.Status, b_index: usize) bool {
        _ = b_index;
        _ = ctx;
        return a == b;
    }
};

pub fn deinit(responses: *Responses, allocator: std.mem.Allocator) void {
    if (responses.default) |*default|
        default.deinit(allocator);
    if (responses.http_responses) |*http_responses| {
        for (http_responses.values()) |*resp|
            resp.deinit(allocator);
        http_responses.deinit(allocator);
    }
}

pub fn jsonStringify(
    resp: Responses,
    options: std.json.StringifyOptions,
    writer: anytype,
) @TypeOf(writer).Error!void {
    try writer.writeByte('{');
    var field_output = false;
    var child_options = options;
    child_options.whitespace.indent_level += 1;

    if (resp.default) |default| {
        field_output = true;
        try child_options.whitespace.outputIndent(writer);

        try std.json.stringify("default", options, writer);
        try writer.writeByte(':');
        if (child_options.whitespace.separator) {
            try writer.writeByte(' ');
        }
        try std.json.stringify(default, child_options, writer);
    }

    if (resp.http_responses) |http_responses| {
        var iter = http_responses.iterator();
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
    }

    if (field_output) {
        try options.whitespace.outputIndent(writer);
    }
    try writer.writeByte('}');
}

pub fn jsonParseRealloc(
    result: *Responses,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    if (try source.next() != .object_begin) {
        return error.UnexpectedToken;
    }

    var default = result.default orelse ResponseOrRef.empty;
    errdefer default.deinit(allocator);
    result.default = ResponseOrRef.empty;

    var old_fields = if (result.http_responses) |*ptr| ptr.move() else HttpResponses{};
    defer for (old_fields.values()) |*value| {
        value.deinit(allocator);
    } else old_fields.deinit(allocator);

    var new_fields = HttpResponses{};
    defer for (new_fields.values()) |*value| {
        value.deinit(allocator);
    } else new_fields.deinit(allocator);
    try new_fields.ensureUnusedCapacity(allocator, old_fields.count());

    var key_buffer = std.ArrayList(u8).init(allocator);
    defer key_buffer.deinit();

    while (true) {
        switch (try source.peekNextTokenType()) {
            else => unreachable,
            .object_end => {
                _ = try source.next();
                break;
            },
            .string => {},
        }

        key_buffer.clearRetainingCapacity();
        const new_key: []const u8 = (try source.allocNextIntoArrayListMax(
            &key_buffer,
            .alloc_if_needed,
            options.max_value_len orelse std.json.default_max_value_len,
        )) orelse key_buffer.items;

        if (std.mem.eql(u8, new_key, "default")) {
            try default.jsonParseRealloc(allocator, source, options);
        }
        if (new_key.len != 3) return error.UnknownField;
        const key_int = std.fmt.parseInt(@typeInfo(std.http.Status).Enum.tag_type, new_key, 10) catch return error.UnknownField;

        const gop = try new_fields.getOrPut(allocator, @enumFromInt(key_int));
        if (gop.found_existing) {
            assert(!old_fields.contains(@enumFromInt(key_int)));
            switch (options.duplicate_field_behavior) {
                .@"error" => return error.DuplicateField,
                .use_first => {
                    try source.skipValue();
                    continue;
                },
                .use_last => {},
            }
        } else if (old_fields.fetchSwapRemove(@enumFromInt(key_int)) orelse old_fields.popOrNull()) |old| {
            gop.value_ptr.* = old.value;
        } else {
            gop.value_ptr.* = ResponseOrRef.empty;
        }

        try ResponseOrRef.jsonParseRealloc(gop.value_ptr, allocator, source, options);
    }

    result.* = .{
        .http_responses = new_fields.move(),
        .default = default,
    };
}

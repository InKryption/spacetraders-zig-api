const std = @import("std");
const assert = std.debug.assert;
const util = @import("util");

pub fn FieldEnumSet(comptime T: type) type {
    return std.EnumSet(std.meta.FieldEnum(T));
}
pub inline fn requiredFieldSetBasedOnOptionals(
    comptime T: type,
    values: std.enums.EnumFieldStruct(std.meta.FieldEnum(T), ?bool, @as(?bool, null)),
) FieldEnumSet(T) {
    var result = FieldEnumSet(T).initEmpty();
    inline for (@typeInfo(T).Struct.fields) |field| {
        const is_required = @field(values, field.name) orelse (@typeInfo(field.type) != .Optional);
        const tag = @field(std.meta.FieldEnum(T), field.name);
        result.setPresent(tag, is_required);
    }
    return result;
}
pub fn requiredFieldSet(
    comptime T: type,
    values: std.enums.EnumFieldStruct(std.meta.FieldEnum(T), bool, null),
) FieldEnumSet(T) {
    var result = FieldEnumSet(T).initEmpty();
    inline for (@typeInfo(T).Struct.fields) |field| {
        const is_required = @field(values, field.name);
        const tag = @field(std.meta.FieldEnum(T), field.name);
        result.setPresent(tag, is_required);
    }
    return result;
}

pub fn generateMappedStringify(
    comptime T: type,
    comptime field_names: ZigToJsonFieldNameMap(T),
) @TypeOf(GenerateMappedStringify(T, field_names).stringify) {
    return GenerateMappedStringify(T, field_names).stringify;
}
fn GenerateMappedStringify(
    comptime T: type,
    comptime field_names: ZigToJsonFieldNameMap(T),
) type {
    return struct {
        pub fn stringify(
            structure: T,
            options: std.json.StringifyOptions,
            writer: anytype,
        ) !void {
            var mapped: Mapped = undefined;
            inline for (@typeInfo(T).Struct.fields) |field| {
                const json_field_name = @field(field_names, field.name);
                @field(mapped, json_field_name) = @field(structure, field.name);
            }
            try std.json.stringify(mapped, options, writer);
        }

        const Mapped = @Type(.{ .Struct = blk: {
            var fields = @typeInfo(T).Struct.fields[0..].*;
            for (&fields) |*field| {
                field.name = @field(field_names, field.name);
            }
            break :blk std.builtin.Type.Struct{
                .layout = .Auto,
                .backing_integer = null,
                .is_tuple = false,
                .decls = &.{},
                .fields = &fields,
            };
        } });
    };
}

pub fn ZigToJsonFieldNameMap(comptime T: type) type {
    const field_infos = std.meta.fields(T);
    var fields = [_]std.builtin.Type.StructField{undefined} ** field_infos.len;
    for (&fields, field_infos) |*field, ref| {
        field.* = .{
            .name = ref.name,
            .type = []const u8,
            .default_value = @ptrCast(&@as([]const u8, ref.name)),
            .is_comptime = false,
            .alignment = 0,
        };
    }
    return @Type(.{ .Struct = std.builtin.Type.Struct{
        .layout = .Auto,
        .is_tuple = false,
        .backing_integer = null,
        .decls = &.{},
        .fields = &fields,
    } });
}

pub fn JsonToZigFieldNameMap(
    comptime T: type,
    comptime map: ZigToJsonFieldNameMap(T),
) type {
    const info = @typeInfo(@TypeOf(map)).Struct;
    var fields = [_]std.builtin.Type.StructField{undefined} ** info.fields.len;
    for (&fields, info.fields) |*field, ref| field.* = .{
        .name = @field(map, ref.name),
        .type = []const u8,
        .default_value = @ptrCast(&ref.name),
        .is_comptime = true,
        .alignment = 0,
    };
    return @Type(.{ .Struct = std.builtin.Type.Struct{
        .layout = .Auto,
        .is_tuple = false,
        .backing_integer = null,
        .decls = &.{},
        .fields = &fields,
    } });
}

pub fn jsonParseReallocString(
    str: *std.ArrayList(u8),
    source: anytype,
    options: std.json.ParseOptions,
) !void {
    str.clearRetainingCapacity();
    assert(try source.allocNextIntoArrayListMax(
        str,
        .alloc_always,
        options.max_value_len orelse std.json.default_max_value_len,
    ) == null);
}

/// parses the tokens from `source` into `results`,
/// re-using the memory of any elements already present in `results`.
/// `results` may be modified on error - caller must ensure that each `T`
/// is deinitialised properly regardless.
pub fn jsonParseInPlaceArrayListTemplate(
    comptime T: type,
    results: *std.ArrayListUnmanaged(T),
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) !void {
    if (try source.next() != .array_begin) {
        return error.UnexpectedToken;
    }

    var overwritten_count: usize = 0;
    const overwritable_count = results.items.len;
    while (true) : (overwritten_count += 1) {
        switch (try source.peekNextTokenType()) {
            .array_end => {
                assert(try source.next() == .array_end);
                break;
            },
            else => {},
        }
        if (overwritten_count < overwritable_count) {
            try results.items[overwritten_count].jsonParseRealloc(allocator, source, options);
            overwritten_count += 1;
            continue;
        }
        try results.ensureUnusedCapacity(allocator, 1);
        results.appendAssumeCapacity(try T.jsonParse(allocator, source, options));
    }

    if (overwritten_count < overwritable_count) {
        for (results.items[overwritten_count..]) |*left_over| {
            left_over.deinit(allocator);
        }
        results.shrinkRetainingCapacity(overwritten_count);
    }
}

pub fn ParseArrayHashMapInPlaceObjCtx(comptime V: type) type {
    return struct {
        pub inline fn deinit(allocator: std.mem.Allocator, value: *V) void {
            value.deinit(allocator);
        }
        pub inline fn empty() V {
            return comptime V.empty;
        }

        pub inline fn jsonParseRealloc(
            result: *V,
            allocator: std.mem.Allocator,
            source: anytype,
            options: std.json.ParseOptions,
        ) !void {
            return V.jsonParseRealloc(result, allocator, source, options);
        }
    };
}
pub const ParseArrayHashMapInPlaceStrCtx = struct {
    pub inline fn deinit(allocator: std.mem.Allocator, value: *[]const u8) void {
        allocator.free(value.*);
    }
    pub inline fn empty() []const u8 {
        return "";
    }
    pub inline fn jsonParseRealloc(
        result: *[]const u8,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !void {
        var new_str = std.ArrayList(u8).fromOwnedSlice(allocator, result.*);
        defer new_str.deinit();

        result.* = "";
        try jsonParseReallocString(&new_str, source, options);

        result.* = try new_str.toOwnedSlice();
    }
};

pub fn jsonParseInPlaceArrayHashMapTemplate(
    comptime V: type,
    hm: *std.json.ArrayHashMap(V),
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
    comptime Ctx: type,
) !void {
    if (try source.next() != .object_begin) {
        return error.UnexpectedToken;
    }

    var old_fields = hm.map.move();
    defer for (old_fields.keys(), old_fields.values()) |key, *value| {
        allocator.free(key);
        Ctx.deinit(allocator, value);
    } else old_fields.deinit(allocator);

    var new_fields = std.StringArrayHashMapUnmanaged(V){};
    defer for (new_fields.keys(), new_fields.values()) |key, *value| {
        allocator.free(key);
        Ctx.deinit(allocator, value);
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

        const gop = try new_fields.getOrPut(allocator, new_key);

        if (gop.found_existing) {
            assert(!old_fields.contains(new_key));
            switch (options.duplicate_field_behavior) {
                .@"error" => return error.DuplicateField,
                .use_first => {
                    try source.skipValue();
                    continue;
                },
                .use_last => {},
            }
        } else if (old_fields.fetchSwapRemove(new_key)) |old| {
            gop.key_ptr.* = old.key;
            gop.value_ptr.* = old.value;
        } else if (old_fields.popOrNull()) |any_old| {
            errdefer assert(new_fields.orderedRemove(new_key));

            var new_str = std.ArrayList(u8).fromOwnedSlice(allocator, @constCast(any_old.key));
            defer new_str.deinit();

            new_str.clearRetainingCapacity();
            try new_str.appendSlice(new_key);

            gop.key_ptr.* = try new_str.toOwnedSlice();
            gop.value_ptr.* = any_old.value;
        } else {
            errdefer assert(new_fields.orderedRemove(new_key));
            gop.key_ptr.* = try allocator.dupe(u8, new_key);
            gop.value_ptr.* = Ctx.empty();
        }

        try Ctx.jsonParseRealloc(gop.value_ptr, allocator, source, options);
    }

    hm.map = new_fields.move();
}

pub fn jsonParseInPlaceStringSet(
    set: *std.StringArrayHashMapUnmanaged(void),
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) !void {
    if (try source.next() != .array_begin) {
        return error.UnexpectedToken;
    }

    var old_set = set.move();
    defer for (old_set.keys()) |str| {
        allocator.free(str);
    } else old_set.deinit(allocator);

    var new_set = std.StringArrayHashMapUnmanaged(void){};
    defer for (new_set.keys()) |str| {
        allocator.free(str);
    } else new_set.deinit(allocator);

    var string_buffer = std.ArrayList(u8).init(allocator);
    defer string_buffer.deinit();

    while (true) {
        switch (try source.peekNextTokenType()) {
            .array_end => {
                assert(try source.next() == .array_end);
                break;
            },
            else => return error.UnexpectedToken,
            .string => {},
        }

        const string = (try source.allocNextIntoArrayListMax(
            &string_buffer,
            .alloc_if_needed,
            options.max_value_len orelse std.json.default_max_value_len,
        )) orelse string_buffer.items;

        const gop = try new_set.getOrPut(allocator, string);
        if (gop.found_existing) {
            assert(old_set.contains(string));
            if (options.duplicate_field_behavior == .@"error") {
                return error.DuplicateField;
            } else continue;
        } else if (old_set.fetchSwapRemove(string)) |old| {
            gop.key_ptr.* = old.key;
        } else if (old_set.popOrNull()) |any_old| {
            errdefer assert(new_set.orderedRemove(string));

            var new_str = std.ArrayList(u8).fromOwnedSlice(allocator, @constCast(any_old.key));
            defer new_str.deinit();

            new_str.clearRetainingCapacity();
            try jsonParseReallocString(&new_str, source, options);

            gop.key_ptr.* = try new_str.toOwnedSlice();
        } else {
            errdefer assert(new_set.orderedRemove(string));
            gop.key_ptr.* = try allocator.dupe(u8, string);
        }
    }
}

pub fn nextMappedField(
    comptime T: type,
    source: anytype,
    options: std.json.ParseOptions,
    /// the result should be inserted into this set for subsequent calls
    field_set: FieldEnumSet(T),
    comptime zig_to_json_field_names: ZigToJsonFieldNameMap(T),
) !?std.meta.FieldEnum(T) {
    const JsonToZigFieldNames = JsonToZigFieldNameMap(T, zig_to_json_field_names);
    const json_to_zig_field_names = JsonToZigFieldNames{};

    const ZigFieldName = std.meta.FieldEnum(T);
    const JsonFieldName = std.meta.FieldEnum(JsonToZigFieldNames);

    var pse: util.ProgressiveStringToEnum(JsonFieldName) = .{};
    while (try util.json.nextProgressiveFieldToEnum(source, JsonFieldName, &pse)) : (pse = .{}) {
        const json_field_name: JsonFieldName = pse.getMatch() orelse {
            if (options.ignore_unknown_fields) continue;
            return error.UnknownField;
        };
        const zig_field_name: ZigFieldName = switch (json_field_name) {
            inline else => |tag| blk: {
                const zig_field_name = @field(json_to_zig_field_names, @tagName(tag));
                break :blk @field(ZigFieldName, zig_field_name);
            },
        };
        if (field_set.contains(zig_field_name)) switch (options.duplicate_field_behavior) {
            .@"error" => return error.UnknownField,
            .use_first => {
                try source.skipValue();
                continue;
            },
            .use_last => {},
        };
        return zig_field_name;
    }

    return null;
}

pub fn parseObjectMappedTemplate(
    comptime T: type,
    result: *T,
    //
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
    //
    field_set: *FieldEnumSet(T),
    comptime zig_to_json_field_names: ZigToJsonFieldNameMap(T),
    /// fn (
    ///     comptime field_tag: std.meta.FieldEnum(T),
    ///     field_ptr: *std.meta.FieldType(T, field_tag),
    ///     is_new: bool,
    ///     alloctor: std.mem.Allocator,
    ///     source: anytype,
    ///     options: std.json.ParseOptions,
    /// ) std.json.ParseError(@TypeOf(source.*))!void
    comptime parseFieldInPlace: anytype,
) std.json.ParseError(@TypeOf(source.*))!void {
    field_set.* = FieldEnumSet(T).initEmpty();

    if (try source.next() != .object_begin) {
        return error.UnexpectedToken;
    }

    while (try nextMappedField(T, source, options, field_set.*, zig_to_json_field_names)) |zig_field_name| {
        field_set.insert(zig_field_name);
        const is_duplicate = field_set.contains(zig_field_name);
        if (is_duplicate) switch (options.duplicate_field_behavior) {
            .@"error" => return error.DuplicateField,
            .use_first => {
                try source.skipValue();
                continue;
            },
            .use_last => {},
        };

        switch (zig_field_name) {
            inline else => |tag| try parseFieldInPlace(
                tag,
                &@field(result, @tagName(tag)),
                !is_duplicate,
                allocator,
                source,
                options,
            ),
        }
    }
}

fn jsonParseInPlaceTemplate_(
    comptime T: type,
    result: *T,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
    field_set: *FieldEnumSet(T),
    /// The type that is effectively expected is:
    /// ```zig
    /// fn (
    ///     comptime field_tag: std.meta.FieldEnum(T),
    ///     field_ptr: anytype,
    ///     is_new: bool,
    ///     allocator: std.mem.Allocator,
    ///     source: @TypeOf(source),
    ///     options: std.json.ParseOptions,
    /// ) std.json.ParseError(@TypeOf(source.*))!void
    /// ```
    comptime parseFieldValueFn: anytype,
) std.json.ParseError(@TypeOf(source.*))!void {
    const json_field_name_map: ZigToJsonFieldNameMap(T) = T.json_field_names;
    const json_field_name_map_reverse: JsonToZigFieldNameMap(T, json_field_name_map) = .{};

    const JsonFieldName = std.meta.FieldEnum(@TypeOf(json_field_name_map_reverse));
    const FieldName = std.meta.FieldEnum(T);
    field_set.* = FieldEnumSet(T).initEmpty();

    const required_fields: std.EnumSet(FieldName) = T.json_required_fields;

    if (try source.next() != .object_begin) {
        return error.UnexpectedToken;
    }

    var pse: util.ProgressiveStringToEnum(JsonFieldName) = .{};
    while (try util.json.nextProgressiveFieldToEnum(source, JsonFieldName, &pse)) : (pse = .{}) {
        const json_field_name: JsonFieldName = pse.getMatch() orelse {
            if (options.ignore_unknown_fields) {
                try source.skipValue();
                continue;
            }
            return error.UnknownField;
        };
        const field_name: FieldName = switch (json_field_name) {
            inline else => |tag| comptime blk: {
                const str: []const u8 = @field(json_field_name_map_reverse, @tagName(tag));
                break :blk @field(FieldName, str);
            },
        };
        const is_new = if (field_set.contains(field_name)) switch (options.duplicate_field_behavior) {
            .@"error" => return error.DuplicateField,
            .use_first => {
                try source.skipValue();
                continue;
            },
            .use_last => false,
        } else true;
        field_set.insert(field_name);
        switch (field_name) {
            inline else => |tag| try parseFieldValueFn(
                tag,
                &@field(result, @tagName(tag)),
                is_new,
                allocator,
                source,
                options,
            ),
        }
    }

    if (!required_fields.subsetOf(field_set.*)) {
        return error.MissingField;
    }

    // ensure that any fields that were present in the old `result` value are
    // not present in the resulting `result` value if they are not present.
    var to_free = T.empty;
    defer to_free.deinit(allocator);
    inline for (@typeInfo(T).Struct.fields) |field| cont: {
        const tag = @field(FieldName, field.name);
        if (field_set.contains(tag)) break :cont;
        const Field = std.meta.FieldType(T, tag);
        std.mem.swap(Field, &@field(result, field.name), &@field(to_free, field.name));
    }
}

pub const ParseDynValueInPlaceTryNTimesCtx = struct {
    n: usize,
    limit: ?usize = null,

    pub inline fn resetMode(ctx: @This()) std.heap.ArenaAllocator.ResetMode {
        if (ctx.limit) |limit|
            return .{ .retain_with_limit = limit };
        return .retain_capacity;
    }
    pub inline fn tryAgain(ctx: *@This()) bool {
        const try_again = ctx.n != 0;
        ctx.n -= @intFromBool(try_again);
        return try_again;
    }
};

pub fn parseDynValueInPlace(
    value: *std.json.Parsed(std.json.Value),
    source: anytype,
    options: std.json.ParseOptions,
    on_reset_fail_ctx: anytype,
) std.json.ParseError(@TypeOf(source.*))!void {
    while (true) {
        if (value.arena.reset(on_reset_fail_ctx.resetMode())) break;
        if (on_reset_fail_ctx.tryAgain()) continue;
        assert(value.arena.reset(.free_all));
        break;
    }
    value.value = .null;
    value.value = try std.json.parseFromTokenSourceLeaky(
        std.json.Value,
        value.arena.allocator(),
        source,
        options,
    );
}

pub fn stringifyArrayHashMap(
    comptime V: type,
    hm: *const std.json.ArrayHashMap(V),
    writer: anytype,
    options: std.json.StringifyOptions,
) !void {
    try writer.writeByte('{');
    var field_output = false;
    var child_options = options;
    child_options.whitespace.indent_level += 1;

    var iter = hm.map.iterator();
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

pub fn deinitStringSet(
    allocator: std.mem.Allocator,
    set: *std.StringArrayHashMapUnmanaged(void),
) void {
    for (set.keys()) |str|
        allocator.free(str);
    set.deinit(allocator);
}

/// frees all the keys, deinitialises all the values, and then deinitialises the map
pub fn deinitArrayHashMap(
    allocator: std.mem.Allocator,
    comptime V: type,
    hm: *std.json.ArrayHashMap(V),
) void {
    for (hm.map.keys(), hm.map.values()) |key, *value| {
        allocator.free(key);
        value.deinit(allocator);
    }
    hm.deinit(allocator);
}

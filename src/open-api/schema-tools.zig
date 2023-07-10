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
        const is_required = @field(values, field.name) orelse @typeInfo(field.type) != .Optional;
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

pub fn generateJsonStringifyStructWithoutNullsFn(
    comptime T: type,
    comptime field_names: ZigToJsonFieldNameMap(T),
) @TypeOf(GenerateJsonStringifyStructWithoutNullsFnImpl(T, field_names).stringify) {
    return GenerateJsonStringifyStructWithoutNullsFnImpl(T, field_names).stringify;
}
fn GenerateJsonStringifyStructWithoutNullsFnImpl(
    comptime T: type,
    comptime field_names: ZigToJsonFieldNameMap(T),
) type {
    return struct {
        pub fn stringify(
            structure: T,
            options: std.json.StringifyOptions,
            writer: anytype,
        ) !void {
            try writer.writeByte('{');
            var field_output = false;
            var child_options = options;
            child_options.whitespace.indent_level += 1;

            inline for (@typeInfo(@TypeOf(structure)).Struct.fields, 0..) |field, i| @"continue": { // <- block label is a hack around the fact we can't continue or break an inline loop based on a runtime condition
                const value = switch (@typeInfo(field.type)) {
                    .Optional => @field(structure, field.name) orelse break :@"continue",
                    else => @field(structure, field.name),
                };
                if (@typeInfo(field.type) == .Optional) {
                    if (@field(structure, field.name) == null)
                        break :@"continue";
                }
                if (i != 0 and field_output) {
                    try writer.writeByte(',');
                } else {
                    field_output = true;
                }
                try child_options.whitespace.outputIndent(writer);

                try std.json.stringify(@field(field_names, field.name), options, writer);
                try writer.writeByte(':');
                if (child_options.whitespace.separator) {
                    try writer.writeByte(' ');
                }
                try std.json.stringify(value, child_options, writer);
            }
            if (field_output) {
                try options.whitespace.outputIndent(writer);
            }
            try writer.writeByte('}');
        }
    };
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

pub fn jsonParseInPlaceTemplate(
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
    var to_free = T{};
    defer to_free.deinit(allocator);
    inline for (@typeInfo(T).Struct.fields) |field| cont: {
        const tag = @field(FieldName, field.name);
        if (field_set.contains(tag)) break :cont;
        const Field = std.meta.FieldType(T, tag);
        std.mem.swap(Field, &@field(result, field.name), &@field(to_free, field.name));
    }
}

pub fn ZigToJsonFieldNameMap(comptime T: type) type {
    const info = @typeInfo(T).Struct;
    var fields = [_]std.builtin.Type.StructField{undefined} ** info.fields.len;
    for (&fields, info.fields) |*field, ref| {
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

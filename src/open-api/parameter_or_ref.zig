const std = @import("std");
const assert = std.debug.assert;

const util = @import("util");

const schema_tools = @import("schema-tools.zig");
const Parameter = @import("Parameter.zig");
const Reference = @import("Reference.zig");

pub const ParameterOrRef = union(enum) {
    parameter: Parameter,
    reference: Reference,

    pub const empty = ParameterOrRef{ .reference = .{} };

    pub fn deinit(param: *ParameterOrRef, allocator: std.mem.Allocator) void {
        switch (param.*) {
            inline else => |*ptr| ptr.deinit(allocator),
        }
    }

    pub fn jsonStringify(
        param: ParameterOrRef,
        options: std.json.StringifyOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        try switch (param) {
            inline else => |val| val.jsonStringify(options, writer),
        };
    }

    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !ParameterOrRef {
        var result: ParameterOrRef = .{ .reference = .{} };
        errdefer result.deinit(allocator);
        try result.jsonParseRealloc(allocator, source, options);
        return result;
    }

    pub fn jsonParseRealloc(
        result: *ParameterOrRef,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!void {
        const Resolution = @typeInfo(ParameterOrRef).Union.tag_type.?;
        var resolution: ?Resolution = null;

        var shared: struct {
            description: ?[]const u8,
        } = .{
            .description = switch (result.*) {
                inline else => |*ptr| blk: {
                    const val = ptr.description;
                    ptr.description = null;
                    break :blk val;
                },
            },
        };
        errdefer allocator.free(shared.description orelse "");

        var field_set = std.EnumSet(AnyFieldTag).initEmpty();

        if (try source.next() != .object_begin) {
            return error.UnexpectedToken;
        }

        var pse: util.ProgressiveStringToEnum(AnyFieldTag) = .{};
        while (try util.json.nextProgressiveFieldToEnum(source, AnyFieldTag, &pse)) : (pse = .{}) {
            const json_field_match: AnyFieldTag = pse.getMatch() orelse {
                if (options.ignore_unknown_fields) {
                    try source.skipValue();
                    continue;
                }
                return error.UnknownField;
            };
            const is_duplicate = field_set.contains(json_field_match);
            if (is_duplicate) switch (options.duplicate_field_behavior) {
                .@"error" => return error.DuplicateField,
                .use_first => {
                    try source.skipValue();
                    continue;
                },
                .use_last => {},
            };
            field_set.insert(json_field_match);

            const field_resolution: ?Resolution = switch (json_field_match) {
                .name,
                .in,
                .required,
                .deprecated,
                .allowEmptyValue,
                => .parameter,

                .@"$ref",
                .summary,
                => .reference,

                .description => null,
            };
            const field_res = field_resolution orelse {
                assert(json_field_match == .description);
                // NOTE: this assumes it is parsed the same as `Reference.parseFieldValue`
                switch (try source.peekNextTokenType()) {
                    .string => {},
                    else => return error.UnexpectedToken,
                }
                var new_str = std.ArrayList(u8).fromOwnedSlice(allocator, @constCast(shared.description orelse ""));
                defer new_str.deinit();

                shared.description = null;
                new_str.clearRetainingCapacity();

                try schema_tools.jsonParseReallocString(&new_str, source, options);
                shared.description = try new_str.toOwnedSlice();
                continue;
            };
            const res: Resolution = if (resolution) |res| blk: {
                if (field_res == res) break :blk res;
                if (options.ignore_unknown_fields) {
                    try source.skipValue();
                    continue;
                }
                return error.UnknownField;
            } else blk: {
                if (result.* != field_res) {
                    result.deinit(allocator);
                    result.* = switch (field_res) {
                        inline else => |tag| @unionInit(ParameterOrRef, @tagName(tag), .{}),
                    };
                }
                resolution = field_res;
                break :blk field_res;
            };

            const JsonToZigFNM = schema_tools.JsonToZigFieldNameMap;
            switch (res) {
                inline //
                .parameter,
                .reference,
                => |res_tag| switch (json_field_match) {
                    inline else => |tag| {
                        const T = std.meta.FieldType(ParameterOrRef, res_tag);
                        const ZigFieldNames = JsonToZigFNM(T, T.json_field_names);
                        if (!@hasField(ZigFieldNames, @tagName(tag))) {
                            unreachable;
                        }
                        const FieldTag = std.meta.FieldEnum(T);
                        const field_tag = @field(FieldTag, @field(ZigFieldNames{}, @tagName(tag)));
                        const union_field_ptr = &@field(result, @tagName(res_tag));
                        const result_field_ptr = &@field(union_field_ptr, @tagName(field_tag));
                        try T.parseFieldValue(
                            field_tag,
                            result_field_ptr,
                            !is_duplicate,
                            allocator,
                            source,
                            options,
                        );
                    },
                },
            }
        }

        switch (result.*) {
            inline else => |*ptr, res_tag| {
                const T = std.meta.FieldType(ParameterOrRef, res_tag);
                const zig_fields = schema_tools.JsonToZigFieldNameMap(T, T.json_field_names){};
                inline for (@typeInfo(@TypeOf(shared)).Struct.fields) |field| {
                    const zig_field = @field(zig_fields, field.name);
                    @field(ptr, zig_field) = @field(shared, field.name);
                }
            },
        }
    }

    const AnyFieldTag = enum {
        // exclusive to `Parameter`
        name,
        in,
        required,
        deprecated,
        allowEmptyValue,

        // exclusive to `Reference`
        @"$ref",
        summary,

        // shared
        description,

        comptime {
            const JsonToZigFNM = schema_tools.JsonToZigFieldNameMap;
            const parameter_fields = @typeInfo(JsonToZigFNM(Parameter, Parameter.json_field_names)).Struct.fields;
            const reference_fields = @typeInfo(JsonToZigFNM(Reference, Reference.json_field_names)).Struct.fields;

            for (parameter_fields ++ reference_fields) |field| {
                if (@hasField(AnyFieldTag, field.name)) continue;
                const zig_name = util.transmuteComptimePtr([]const u8, field.default_value.?);
                @compileError("Missing field '" ++ field.name ++ "' for '" ++ zig_name ++ "'");
            }
        }
    };
};

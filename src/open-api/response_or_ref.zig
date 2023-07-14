const std = @import("std");
const assert = std.debug.assert;

const util = @import("util");

const schema_tools = @import("schema-tools.zig");
const HeaderOrRef = @import("header_or_ref.zig").HeaderOrRef;
const MediaType = @import("MediaType.zig");
const Response = @import("Response.zig");
const Reference = @import("Reference.zig");

pub const ResponseOrRef = union(enum) {
    response: Response,
    reference: Reference,

    pub const empty = ResponseOrRef{ .reference = .{} };

    pub fn deinit(resp: *ResponseOrRef, allocator: std.mem.Allocator) void {
        switch (resp.*) {
            inline else => |*ptr| ptr.deinit(allocator),
        }
    }

    pub fn jsonStringify(
        resp: ResponseOrRef,
        options: std.json.StringifyOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        try switch (resp) {
            inline else => |val| val.jsonStringify(options, writer),
        };
    }

    pub fn jsonParseRealloc(
        result: *ResponseOrRef,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!void {
        const Resolution = @typeInfo(ResponseOrRef).Union.tag_type.?;
        var resolution: ?Resolution = null;

        var shared: struct {
            description: []const u8,
        } = .{
            .description = switch (result.*) {
                inline else => |*ptr| blk: {
                    const val = ptr.description;
                    ptr.description = "";
                    break :blk @as(?[]const u8, val) orelse "";
                },
            },
        };
        errdefer allocator.free(@as(?[]const u8, shared.description) orelse "");

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
                .headers,
                .content,
                => .response,

                .ref,
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
                var new_str = std.ArrayList(u8).fromOwnedSlice(allocator, @constCast(@as(?[]const u8, shared.description) orelse ""));
                defer new_str.deinit();

                shared.description = "";
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
                        inline else => |tag| @unionInit(ResponseOrRef, @tagName(tag), .{}),
                    };
                }
                resolution = field_res;
                break :blk field_res;
            };

            const JsonToZigFNM = schema_tools.JsonToZigFieldNameMap;
            switch (res) {
                inline //
                .response,
                .reference,
                => |res_tag| switch (json_field_match) {
                    inline else => |tag| {
                        const T = std.meta.FieldType(ResponseOrRef, res_tag);
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
                const T = std.meta.FieldType(ResponseOrRef, res_tag);
                const zig_fields = schema_tools.JsonToZigFieldNameMap(T, T.json_field_names){};
                inline for (@typeInfo(@TypeOf(shared)).Struct.fields) |field| {
                    const zig_field = @field(zig_fields, field.name);
                    @field(ptr, zig_field) = @field(shared, field.name);
                }
            },
        }
    }
};

pub const AnyFieldTag = enum {
    // exclusive to `Response`
    headers,
    content,

    // exclusive to `Reference`
    ref,
    summary,

    // shared
    description,
};

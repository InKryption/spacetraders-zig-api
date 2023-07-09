const std = @import("std");
const assert = std.debug.assert;
const util = @import("util");

const schema_tools = @import("schema-tools.zig");

const Parameter = @This();
name: []const u8 = "",
in: In = undefined,
description: ?[]const u8 = null,
required: ?bool = null,
deprecated: ?bool = null,
allow_empty_value: ?bool = null,

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Parameter, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Parameter){
    .allow_empty_value = "allowEmptyValue",
};

pub fn deinit(param: Parameter, allocator: std.mem.Allocator) void {
    allocator.free(param.name);
    allocator.free(param.description orelse "");
}

pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(
    Parameter,
    Parameter.json_field_names,
);

pub fn jsonParseRealloc(
    result: *Parameter,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    try schema_tools.jsonParseInPlaceTemplate(Parameter, result, allocator, source, options, Parameter.parseFieldValue);
}
pub inline fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(Parameter),
    field_ptr: *std.meta.FieldType(Parameter, field_tag),
    is_new: bool,
    ally: std.mem.Allocator,
    src: anytype,
    json_opt: std.json.ParseOptions,
) !void {
    _ = is_new;
    switch (field_tag) {
        .name, .description => {
            var new_str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
            defer new_str.deinit();
            new_str.clearRetainingCapacity();
            field_ptr.* = "";
            try schema_tools.jsonParseReallocString(&new_str, src, json_opt);
            field_ptr.* = try new_str.toOwnedSlice();
        },
        .in => {
            var pse = util.ProgressiveStringToEnum(Parameter.In){};
            try util.json.nextProgressiveStringToEnum(src, Parameter.In, &pse);
            field_ptr.* = pse.getMatch() orelse return error.UnexpectedToken;
        },
        .required, .deprecated, .allow_empty_value => {
            field_ptr.* = switch (try src.next()) {
                .true => true,
                .false => false,
                else => return error.UnexpectedToken,
            };
        },
    }
}

pub const In = enum {
    query,
    header,
    path,
    cookie,

    pub fn jsonStringify(
        in: In,
        options: std.json.StringifyOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        _ = options;
        switch (in) {
            inline else => |tag| try writer.writeAll("\"" ++ @tagName(tag) ++ "\""),
        }
    }
};

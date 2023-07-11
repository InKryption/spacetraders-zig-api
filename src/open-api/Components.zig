const std = @import("std");
const assert = std.debug.assert;

const schema_tools = @import("schema-tools.zig");
const PathItem = @import("Paths.zig").Item;

const Components = @This();
// schemas           Map[string, Schema Object]                               An object to hold reusable Schema Objects.
// responses         Map[string, Response Object | Reference Object]          An object to hold reusable Response Objects.
// parameters        Map[string, Parameter Object | Reference Object]         An object to hold reusable Parameter Objects.
// examples          Map[string, Example Object | Reference Object]           An object to hold reusable Example Objects.
// requestBodies     Map[string, Request Body Object | Reference Object]      An object to hold reusable Request Body Objects.
// headers           Map[string, Header Object | Reference Object]            An object to hold reusable Header Objects.
// securitySchemes   Map[string, Security Scheme Object | Reference Object]   An object to hold reusable Security Scheme Objects.
// links             Map[string, Link Object | Reference Object]              An object to hold reusable Link Objects.
// callbacks         Map[string, Callback Object | Reference Object]          An object to hold reusable Callback Objects.
// Map[string, Path Item Object | Reference Object]         An object to hold reusable Path Item Object.
path_items: ?std.json.ArrayHashMap(PathItem) = null,

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Components, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Components){
    .path_items = "pathItems",
};

pub fn deinit(components: Components, allocator: std.mem.Allocator) void {
    _ = allocator;
    _ = components;
}

pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(
    Components,
    Components.json_field_names,
);

pub fn jsonParseRealloc(
    result: *Components,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    var field_set = schema_tools.FieldEnumSet(Components).initEmpty();
    try schema_tools.jsonParseInPlaceTemplate(Components, result, allocator, source, options, &field_set, Components.parseFieldValue);
}
pub inline fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(Components),
    field_ptr: anytype,
    is_new: bool,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) !void {
    _ = field_tag;
    _ = field_ptr;
    _ = is_new;
    _ = allocator;
    _ = source;
    _ = options;
    @panic("TODO");
}

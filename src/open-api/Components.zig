const std = @import("std");
const assert = std.debug.assert;

const schema_tools = @import("schema-tools.zig");
const PathItem = @import("PathItem.zig");
const Schema = @import("Schema.zig");
const RequestBodyOrRef = @import("request_body_or_ref.zig").RequestBodyOrRef;
const ResponseOrRef = @import("response_or_ref.zig").ResponseOrRef;
const SecuritySchemeOrRef = @import("security_scheme_or_ref.zig").SecuritySchemeOrRef;

const Components = @This();
schemas: ?std.json.ArrayHashMap(Schema) = null,
responses: ?std.json.ArrayHashMap(ResponseOrRef) = null,
// parameters        Map[string, Parameter Object | Reference Object]         An object to hold reusable Parameter Objects.
// examples          Map[string, Example Object | Reference Object]           An object to hold reusable Example Objects.
// requestBodies     Map[string, Request Body Object | Reference Object]      An object to hold reusable Request Body Objects.
request_bodies: ?std.json.ArrayHashMap(RequestBodyOrRef) = null,
// headers           Map[string, Header Object | Reference Object]            An object to hold reusable Header Objects.
// securitySchemes   Map[string, Security Scheme Object | Reference Object]   An object to hold reusable Security Scheme Objects.
security_schemes: ?std.json.ArrayHashMap(SecuritySchemeOrRef) = null,
// links             Map[string, Link Object | Reference Object]              An object to hold reusable Link Objects.
// callbacks         Map[string, Callback Object | Reference Object]          An object to hold reusable Callback Objects.
// Map[string, Path Item Object | Reference Object]         An object to hold reusable Path Item Object.
path_items: ?std.json.ArrayHashMap(PathItem) = null,

pub const empty = Components{};

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Components, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Components){
    .path_items = "pathItems",
    .request_bodies = "requestBodies",
    .security_schemes = "securitySchemes",
};

pub fn deinit(components: *Components, allocator: std.mem.Allocator) void {
    if (components.schemas) |*schemas|
        schema_tools.deinitArrayHashMap(allocator, Schema, schemas);
    if (components.request_bodies) |*request_bodies|
        schema_tools.deinitArrayHashMap(allocator, RequestBodyOrRef, request_bodies);
    if (components.security_schemes) |*security_schemes|
        schema_tools.deinitArrayHashMap(allocator, SecuritySchemeOrRef, security_schemes);
    if (components.path_items) |*path_items|
        schema_tools.deinitArrayHashMap(allocator, PathItem, path_items);
}

pub const jsonStringify = schema_tools.generateMappedStringify(Components, json_field_names);

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
    field_ptr: *std.meta.FieldType(Components, field_tag),
    is_new: bool,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) !void {
    _ = is_new;
    switch (field_tag) {
        .schemas,
        .request_bodies,
        .path_items,
        .security_schemes,
        .responses,
        => {
            const T = switch (field_tag) {
                .schemas => Schema,
                .request_bodies => RequestBodyOrRef,
                .path_items => PathItem,
                .security_schemes => SecuritySchemeOrRef,
                .responses => ResponseOrRef,
            };
            if (field_ptr.* == null) {
                field_ptr.* = .{};
            }
            try schema_tools.jsonParseInPlaceArrayHashMapTemplate(
                T,
                &field_ptr.*.?,
                allocator,
                source,
                options,
                schema_tools.ParseArrayHashMapInPlaceObjCtx(T),
            );
        },
    }
}

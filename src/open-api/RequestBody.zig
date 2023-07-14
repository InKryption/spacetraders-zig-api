const std = @import("std");
const assert = std.debug.assert;

const schema_tools = @import("schema-tools.zig");

const RequestBody = @This();
description: ?[]const u8 = null,

// content       Map[string, Media Type Object]
// REQUIRED.
// The content of the request body.
// The key is a media type or media type range and the value describes it.
// For requests that match multiple keys, only the most specific key is applicable.
// e.g. text/plain overrides text/*

required: bool = false,

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(RequestBody, .{
    .required = false,
});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(RequestBody){};

pub fn deinit(reqbody: *RequestBody, allocator: std.mem.Allocator) void {
    allocator.free(reqbody.description orelse "");
}

pub const jsonStringify = schema_tools.generateMappedStringify(RequestBody, json_field_names);

pub fn jsonParseRealloc(
    result: *RequestBody,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    _ = options;
    _ = allocator;
    _ = result;
    @panic("TODO");
}

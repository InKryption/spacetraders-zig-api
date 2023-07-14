const std = @import("std");

const schema_tools = @import("schema-tools.zig");
const Encoding = @import("Encoding.zig");
const ExampleOrRef = @import("example-or-ref.zig").ExampleOrRef;
const Schema = @import("Schema.zig");

const MediaType = @This();
schema: ?Schema = null,
example: ?std.json.Parsed(std.json.Value) = null,
examples: ?std.json.ArrayHashMap(ExampleOrRef) = null,
encoding: ?std.json.ArrayHashMap(Encoding) = null,

pub const empty = MediaType{};

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(MediaType, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(MediaType){};

pub fn deinit(media: *MediaType, allocator: std.mem.Allocator) void {
    if (media.schema) |*schema| schema.deinit(allocator);
    if (media.example) |*example| example.deinit();
    if (media.examples) |*examples| schema_tools.deinitArrayHashMap(allocator, ExampleOrRef, examples);
    if (media.encoding) |*encoding| schema_tools.deinitArrayHashMap(allocator, Encoding, encoding);
}

pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(
    MediaType,
    MediaType.json_field_names,
);

pub fn jsonParseRealloc(
    result: *MediaType,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    var field_set = schema_tools.FieldEnumSet(MediaType).initEmpty();
    try schema_tools.jsonParseInPlaceTemplate(
        MediaType,
        result,
        allocator,
        source,
        options,
        &field_set,
        MediaType.parseFieldValue,
    );
}

pub inline fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(MediaType),
    field_ptr: *std.meta.FieldType(MediaType, field_tag),
    is_new: bool,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) !void {
    _ = options;
    _ = source;
    _ = allocator;
    _ = is_new;
    _ = field_ptr;
    switch (field_tag) {}
    @panic("TODO");
}

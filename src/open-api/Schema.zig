const std = @import("std");

const schema_tools = @import("schema-tools.zig");
const Discriminator = @import("Discriminator.zig");
const ExternalDocs = @import("ExternalDocs.zig");
const Xml = @import("Xml.zig");

const Schema = @This();
discriminator: ?Discriminator = null,
xml: ?Xml = null,
external_docs: ?ExternalDocs = null,

pub const empty = Schema{};

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Schema, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Schema){
    .external_docs = "externalDocs",
};

pub fn deinit(schema: *Schema, allocator: std.mem.Allocator) void {
    if (schema.discriminator) |*discriminator|
        discriminator.deinit(allocator);
    if (schema.xml) |*xml|
        xml.deinit(allocator);
    if (schema.external_docs) |*docs|
        docs.deinit(allocator);
}

pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(
    Schema,
    Schema.json_field_names,
);

pub fn jsonParseRealloc(
    result: *Schema,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    _ = options;
    _ = allocator;
    _ = result;
    @panic("TODO");
}

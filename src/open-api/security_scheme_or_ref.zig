const std = @import("std");

const util = @import("util");

const schema_tools = @import("schema-tools.zig");
const SecurityScheme = @import("SecurityScheme.zig");
const OAuthFlows = @import("OAuthFlows.zig");
const Reference = @import("Reference.zig");

pub const SecuritySchemeOrRef = union(enum) {
    security_scheme: SecurityScheme,
    reference: Reference,

    pub const empty = SecuritySchemeOrRef{ .reference = .{} };

    pub fn deinit(param: *SecuritySchemeOrRef, allocator: std.mem.Allocator) void {
        switch (param.*) {
            inline else => |*ptr| ptr.deinit(allocator),
        }
    }

    pub fn jsonStringify(
        param: SecuritySchemeOrRef,
        options: std.json.StringifyOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        try switch (param) {
            inline else => |val| val.jsonStringify(options, writer),
        };
    }

    pub fn jsonParseRealloc(
        result: *SecuritySchemeOrRef,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!void {
        _ = result;

        var glob = JsonGlob{};
        defer glob.deinit(allocator);

        var field_set = schema_tools.FieldEnumSet(JsonGlob).initEmpty();
        try schema_tools.jsonParseInPlaceTemplate(
            JsonGlob,
            &glob,
            allocator,
            source,
            options,
            &field_set,
            JsonGlob.parseFieldValue,
        );

        // @panic("TODO");
    }
};

pub const JsonGlob = struct {
    // exclusive to `Reference`
    ref: ?[]const u8 = null,
    summary: ?[]const u8 = null,

    // exclusive to `SecurityScheme`
    type: ?SecurityScheme.Type = null,
    name: ?[]const u8 = null,
    in: ?SecurityScheme.ApiKey.In = null,
    scheme: ?[]const u8 = null,
    bearer_format: ?[]const u8 = null,
    flows: ?OAuthFlows = null,
    open_id_connect_url: ?[]const u8 = null,

    // shared
    description: ?[]const u8 = null,

    pub const empty = JsonGlob{};

    pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(JsonGlob, .{});
    pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(JsonGlob){
        .ref = "$ref",
        .bearer_format = "bearerFormat",
        .open_id_connect_url = "openIdConnectUrl",
    };

    pub fn deinit(glob: *JsonGlob, allocator: std.mem.Allocator) void {
        allocator.free(glob.ref orelse "");
        allocator.free(glob.summary orelse "");

        allocator.free(glob.name orelse "");
        allocator.free(glob.scheme orelse "");
        allocator.free(glob.bearer_format orelse "");
        if (glob.flows) |*flows| flows.deinit(allocator);
        allocator.free(glob.open_id_connect_url orelse "");

        allocator.free(glob.description orelse "");
    }

    pub inline fn parseFieldValue(
        comptime field_tag: std.meta.FieldEnum(JsonGlob),
        field_ptr: *std.meta.FieldType(JsonGlob, field_tag),
        is_new: bool,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !void {
        _ = is_new;
        switch (field_tag) {
            .ref,
            .summary,
            .name,
            .scheme,
            .bearer_format,
            .open_id_connect_url,
            .description,
            => {
                var new_str = std.ArrayList(u8).fromOwnedSlice(allocator, @constCast(field_ptr.* orelse ""));
                defer new_str.deinit();

                new_str.clearRetainingCapacity();
                field_ptr.* = null;

                try schema_tools.jsonParseReallocString(&new_str, source, options);
                field_ptr.* = try new_str.toOwnedSlice();
            },

            .type => field_ptr.* = try SecurityScheme.Type.jsonParse(util.failing_allocator, source, options),
            .in => field_ptr.* = try SecurityScheme.ApiKey.In.jsonParse(util.failing_allocator, source, options),
            .flows => try OAuthFlows.jsonParseRealloc(&field_ptr.*.?, allocator, source, options),
        }
    }
};

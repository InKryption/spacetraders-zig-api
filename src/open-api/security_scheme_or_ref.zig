const std = @import("std");
const assert = std.debug.assert;

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
        var glob = JsonGlob{};
        defer glob.deinit(allocator);

        switch (result.*) {
            .security_scheme => |*sec_scheme| {
                errdefer @compileError("There should be no error beyond this point");

                glob.description = sec_scheme.description;
                sec_scheme.description = null;
                switch (sec_scheme.data) {
                    .api_key => |*api_key| {
                        glob.name = api_key.name;
                        glob.in = api_key.in;
                        api_key.* = SecurityScheme.ApiKey.empty;
                    },
                    .http => |*http| {
                        glob.scheme = http.scheme;
                        glob.bearer_format = http.bearer_format;
                        http.* = SecurityScheme.Http.empty;
                    },
                    .mutual_tls => |v| comptime assert(@TypeOf(v) == void),
                    .oauth2 => |*oauth2| {
                        glob.flows = oauth2.flows;
                        oauth2.* = SecurityScheme.OAuth2.empty;
                    },
                    .open_id_connect => |*oic| {
                        glob.open_id_connect_url = oic.url;
                        oic.* = SecurityScheme.OpenIdConnect.empty;
                    },
                }
            },
            .reference => |*reference| {
                glob.ref = reference.ref;
                glob.summary = reference.summary;
                glob.description = reference.description;
                reference.* = Reference.empty;
            },
        }

        const FieldSet = schema_tools.FieldEnumSet(JsonGlob);
        var field_set = FieldSet.initEmpty();
        try schema_tools.jsonParseInPlaceTemplate(
            JsonGlob,
            &glob,
            allocator,
            source,
            options,
            &field_set,
            JsonGlob.parseFieldValue,
        );

        if (field_set.contains(.ref)) {
            if (!field_set.subsetOf(FieldSet.initMany(&.{ .ref, .summary, .description }))) {
                return error.UnknownField;
            }
            result.* = .{ .reference = Reference.empty };
            const p_ref: *[]const u8 = if (glob.ref) |*ref| ref else return error.MissingField;
            // zig fmt: off
            std.mem.swap([]const u8,  p_ref,             &result.reference.ref);
            std.mem.swap(?[]const u8, &glob.summary,     &result.reference.summary);
            std.mem.swap(?[]const u8, &glob.description, &result.reference.description);
            // zig fmt: on

            return;
        } else if (field_set.contains(.summary)) {
            return error.UnknownField;
        }

        if (field_set.contains(.type)) {
            result.* = .{ .security_scheme = SecurityScheme.empty };
            std.mem.swap(?[]const u8, &glob.description, &result.security_scheme.description);

            const ty = glob.type.?;
            switch (ty) {
                .api_key => {
                    if (!field_set.subsetOf(FieldSet.initMany(&.{ .type, .description, .name, .in }))) {
                        return error.UnknownField;
                    }
                    result.security_scheme.data = .{ .api_key = SecurityScheme.ApiKey.empty };
                    const p_name = if (glob.name) |*ptr| ptr else return error.MissingField;
                    const p_in = if (glob.in) |*ptr| ptr else return error.MissingField;
                    // zig fmt: off
                    std.mem.swap([]const u8,               p_name, &result.security_scheme.data.api_key.name);
                    std.mem.swap(SecurityScheme.ApiKey.In, p_in, &result.security_scheme.data.api_key.in);
                    // zig fmt: on
                    return;
                },
                .http => {
                    if (!field_set.subsetOf(FieldSet.initMany(&.{ .type, .description, .scheme, .bearer_format }))) {
                        return error.UnknownField;
                    }
                    result.security_scheme.data = .{ .http = SecurityScheme.Http.empty };

                    const p_scheme = if (glob.scheme) |*ptr| ptr else return error.MissingField;
                    // zig fmt: off
                    std.mem.swap([]const u8,  p_scheme,            &result.security_scheme.data.http.scheme);
                    std.mem.swap(?[]const u8, &glob.bearer_format, &result.security_scheme.data.http.bearer_format);
                    // zig fmt: on
                    return;
                },
                .mutual_tls => {
                    if (!field_set.subsetOf(FieldSet.initMany(&.{ .type, .description }))) {
                        return error.UnknownField;
                    }
                    result.security_scheme.data = .mutual_tls;
                    return;
                },
                .oauth2 => {
                    if (!field_set.subsetOf(FieldSet.initMany(&.{ .type, .description, .flows }))) {
                        return error.UnknownField;
                    }
                    result.security_scheme.data = .{ .oauth2 = SecurityScheme.OAuth2.empty };

                    const p_flows = if (glob.flows) |*ptr| ptr else return error.MissingField;
                    std.mem.swap(OAuthFlows, p_flows, &result.security_scheme.data.oauth2.flows);
                    return;
                },
                .open_id_connect => {
                    if (!field_set.subsetOf(FieldSet.initMany(&.{ .type, .description, .open_id_connect_url }))) {
                        return error.UnknownField;
                    }
                    result.security_scheme.data = .{ .open_id_connect = SecurityScheme.OpenIdConnect.empty };

                    const p_url = if (glob.open_id_connect_url) |*ptr| ptr else return error.UnknownField;
                    std.mem.swap([]const u8, p_url, &result.security_scheme.data.open_id_connect.url);
                    return;
                },
            }
        }

        return error.MissingField;
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

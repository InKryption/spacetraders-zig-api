const std = @import("std");

const util = @import("util");

const schema_tools = @import("schema-tools.zig");
const OAuthFlows = @import("OAuthFlows.zig");

const SecurityScheme = @This();
description: ?[]const u8 = null,
data: Data,

pub fn deinit(sec_scheme: *SecurityScheme, allocator: std.mem.Allocator) void {
    allocator.free(sec_scheme.description orelse "");
    switch (sec_scheme.data) {
        inline else => |*ptr| if (@TypeOf(ptr.*) != void) {
            ptr.deinit(allocator);
        },
    }
}

pub fn jsonStringify(
    sec_scheme: SecurityScheme,
    options: std.json.StringifyOptions,
    writer: anytype,
) @TypeOf(writer).Error!void {
    try sec_scheme.asJsonGlob().jsonStringify(options, writer);
}

pub fn jsonParseRealloc(
    result: *SecurityScheme,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    _ = options;
    _ = allocator;
    _ = result;
    @panic("TODO");
}

pub inline fn asJsonGlob(sec_scheme: SecurityScheme) JsonGlob {
    return JsonGlob{
        .type = sec_scheme.data,
        .description = sec_scheme.description,
        .name = switch (sec_scheme.data) {
            .api_key => |api_key| api_key.name,
            else => null,
        },
        .in = switch (sec_scheme.data) {
            .api_key => |api_key| api_key.in,
            else => null,
        },
        .scheme = switch (sec_scheme.data) {
            .http => |http| http.scheme,
            else => null,
        },
        .bearer_format = switch (sec_scheme.data) {
            .http => |http| http.bearer_format,
            else => null,
        },
        .flows = switch (sec_scheme.data) {
            .oauth2 => |oauth2| oauth2.flows,
            else => null,
        },
        .open_id_connect_url = switch (sec_scheme.data) {
            .open_id_connect => |open_id_connect| open_id_connect.url,
            else => null,
        },
    };
}

pub const JsonGlob = struct {
    type: Type,
    description: ?[]const u8 = null,
    name: ?[]const u8 = null,
    in: ?ApiKey.In = null,
    scheme: ?[]const u8 = null,
    bearer_format: ?[]const u8 = null,
    flows: ?OAuthFlows = null,
    open_id_connect_url: ?[]const u8 = null,

    pub const empty = JsonGlob{
        .type = undefined,
    };

    pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(JsonGlob, .{});
    pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(JsonGlob){
        .bearer_format = "bearerFormat",
        .open_id_connect_url = "openIdConnectUrl",
    };

    pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(
        JsonGlob,
        JsonGlob.json_field_names,
    );

    pub fn jsonParseRealloc(
        result: *JsonGlob,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!void {
        var field_set = schema_tools.FieldEnumSet(JsonGlob).initEmpty();
        try schema_tools.jsonParseInPlaceTemplate(
            JsonGlob,
            result,
            allocator,
            source,
            options,
            &field_set,
            JsonGlob.parseFieldValue,
        );
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
            .type => field_ptr.* = try Type.jsonParse(allocator, source, options),
            .description,
            .name,
            .scheme,
            .bearer_format,
            .open_id_connect_url,
            => {
                var new_str = std.ArrayList(u8).fromOwnedSlice(allocator, @constCast(field_ptr.* orelse ""));
                defer new_str.deinit();

                new_str.clearRetainingCapacity();
                field_ptr.* = "";

                try schema_tools.jsonParseReallocString(&new_str, source, options);
                field_ptr.* = try new_str.toOwnedSlice();
            },
            .in => field_ptr.* = try ApiKey.In.jsonParse(allocator, source, options),
            .flows => {
                if (field_ptr.* == null) {
                    field_ptr.* = .{};
                }
                OAuthFlows.jsonParseRealloc();
            },
        }
    }
};

pub const Data = union(Type) {
    api_key: ApiKey,
    http: Http,
    mutual_tls,
    oauth2: OAuth2,
    open_id_connect: OpenIdConnect,
};

pub const ApiKey = struct {
    name: []const u8 = "",
    in: In,

    pub const empty = ApiKey{
        .in = undefined,
    };

    pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(ApiKey, .{});
    pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(ApiKey){};

    pub fn deinit(api_key: ApiKey, allocator: std.mem.Allocator) void {
        allocator.free(api_key.name);
    }

    pub const In = enum {
        query,
        header,
        cookie,

        pub fn jsonParse(
            allocator: std.mem.Allocator,
            source: anytype,
            options: std.json.ParseOptions,
        ) std.json.ParseError(@TypeOf(source.*))!In {
            _ = options;
            _ = allocator;
            var pse: util.ProgressiveStringToEnum(In) = .{};
            try util.json.nextProgressiveStringToEnum(source, In, &pse);
            return pse.getMatch() orelse error.UnknownField;
        }
    };
};

pub const Http = struct {
    scheme: []const u8 = "",
    bearer_format: ?[]const u8 = null,

    pub const empty = Http{};

    pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Http, .{});
    pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Http){
        .bearer_format = "bearer_format",
    };

    pub fn deinit(http: Http, allocator: std.mem.Allocator) void {
        allocator.free(http.scheme);
        allocator.free(http.bearer_format orelse "");
    }
};

pub const OAuth2 = struct {
    flows: OAuthFlows = .{},

    pub const empty = OAuth2{};

    pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(OAuth2, .{});
    pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(OAuth2){};

    pub fn deinit(oauth2: *OAuth2, allocator: std.mem.Allocator) void {
        oauth2.flows.deinit(allocator);
    }
};
pub const OpenIdConnect = struct {
    url: []const u8 = "",

    pub const empty = OpenIdConnect{};

    pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(OpenIdConnect, .{});
    pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(OpenIdConnect){
        .url = "openIdConnectUrl",
    };

    pub fn deinit(open_id_connect: OpenIdConnect, allocator: std.mem.Allocator) void {
        allocator.free(open_id_connect.url);
    }
};

pub const Type = enum {
    api_key,
    http,
    mutual_tls,
    oauth2,
    open_id_connect,

    pub const json_tag_names = schema_tools.ZigToJsonFieldNameMap(Type){
        .api_key = "apiKey",
        .http = "http",
        .mutual_tls = "mutualTLS",
        .oauth2 = "oauth2",
        .open_id_connect = "openIdConnect",
    };

    pub inline fn jsonStringify(
        ty: Type,
        options: std.json.StringifyOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        const str = switch (ty) {
            inline else => |tag| @field(json_tag_names, @tagName(tag)),
        };
        try std.json.stringify(str, options, writer);
    }

    pub inline fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!Type {
        _ = allocator;
        _ = options;
        var pse: util.ProgressiveStringToEnum(JsonTag) = .{};
        try util.json.nextProgressiveStringToEnum(source, JsonTag, &pse);
        const match = try pse.getMatch() orelse error.UnknownField;
        return @enumFromInt(@intFromEnum(match));
    }

    pub const JsonTag = @Type(.{ .Enum = blk: {
        const info = @typeInfo(Type).Enum;
        var fields = info.fields[0..].*;
        for (&fields) |*field| {
            field.name = @field(json_tag_names, field.name);
        }
        break :blk std.builtin.Type.Enum{
            .tag_type = info.tag_type,
            .is_exhaustive = info.is_exhaustive,
            .decls = &.{},
            .fields = &fields,
        };
    } });
};

const std = @import("std");
const assert = std.debug.assert;
const util = @import("util");

const Schema = @This();
/// REQUIRED.
/// This string MUST be the version number of the OpenAPI Specification that the OpenAPI document uses.
/// The openapi field SHOULD be used by tooling to interpret the OpenAPI document.
/// This is not related to the API info.version string.
openapi: []const u8,

/// REQUIRED.
/// Provides metadata about the API.
/// The metadata MAY be used by tooling as required.
info: Info,

/// The default value for the $schema keyword within Schema Objects contained within this OAS document.
/// This MUST be in the form of a URI.
///
/// real name: jsonSchemaDialect
json_schema_dialect: ?[]const u8,
// servers                  [Server Object]                                                    An array of Server Objects, which provide connectivity information to a target server. If the servers property is not provided, or is an empty array, the default value would be a Server Object with a url value of /.
// paths                    Paths Object                                                       The available paths and operations for the API.
// webhooks                 Map[string, Path Item Object | Reference Object] ]                 The incoming webhooks that MAY be received as part of this API and that the API consumer MAY choose to implement. Closely related to the callbacks feature, this section describes requests initiated other than by an API call, for example by an out of band registration. The key name is a unique string to refer to each webhook, while the (optionally referenced) Path Item Object describes a request that may be initiated by the API provider and the expected responses. An example is available.
// components               Components Object                                                  An element to hold various schemas for the document.
// security                 [Security Requirement Object]                                      A declaration of which security mechanisms can be used across the API. The list of values includes alternative security requirement objects that can be used. Only one of the security requirement objects need to be satisfied to authorize a request. Individual operations can override this definition. To make security optional, an empty security requirement ({}) can be included in the array.
// tags                     [Tag Object]                                                       A list of tags used by the document with additional metadata. The order of the tags can be used to reflect on their order by the parsing tools. Not all tags that are used by the Operation Object must be declared. The tags that are not declared MAY be organized randomly or based on the tools’ logic. Each tag name in the list MUST be unique.
// externalDocs             External Documentation Object                                      Additional external documentation.

pub fn deinit(self: Schema, allocator: std.mem.Allocator) void {
    allocator.free(self.openapi);
    self.info.deinit(allocator);
    allocator.free(self.json_schema_dialect orelse "");
}

pub fn jsonStringify(
    self: Schema,
    options: std.json.StringifyOptions,
    writer: anytype,
) @TypeOf(writer).Error!void {
    if (self.json_schema_dialect) |json_schema_dialect| {
        try std.json.stringify(.{
            .openapi = self.openapi,
            .info = self.info,
            .jsonSchemaDialect = json_schema_dialect,
        }, options, writer);
    } else try std.json.stringify(.{
        .openapi = self.openapi,
        .info = self.info,
    }, options, writer);
}

pub fn jsonParse(
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!Schema {
    var result: Schema = .{
        .openapi = "",
        .info = Info{
            .title = "",
        },
        .json_schema_dialect = null,
    };
    errdefer result.deinit(allocator);

    const FieldName = enum {
        openapi,
        info,
        jsonSchemaDialect,
        // servers,
        // paths,
        // webhooks,
        // components,
        // security,
        // tags,
        // externalDocs,

        inline fn toFieldName(name: @This()) []const u8 {
            const FieldEnum = std.meta.FieldEnum(Schema);
            return switch (name) {
                .jsonSchemaDialect => @tagName(FieldEnum.json_schema_dialect),
                else => |tag| @tagName(tag),
            };
        }
    };
    const FieldSet = std.EnumSet(FieldName);
    var field_set: FieldSet = FieldSet.initEmpty();

    if (try source.next() != .object_begin) {
        return error.UnexpectedToken;
    }

    var pse = util.ProgressiveStringToEnum(FieldName){};
    while (try util.json.nextProgressiveFieldToEnum(source, FieldName, &pse)) : (pse = .{}) {
        const field_name: FieldName = pse.getMatch() orelse {
            if (options.ignore_unknown_fields) continue;
            return error.UnknownField;
        };
        if (field_set.contains(field_name)) switch (options.duplicate_field_behavior) {
            .@"error" => return error.DuplicateField,
            .use_first => {
                try source.skipValue();
                continue;
            },
            .use_last => {},
        };
        field_set.insert(field_name);
        switch (field_name) {
            inline .openapi, .jsonSchemaDialect => |tag| {
                const maybe_str_ptr = &@field(result, tag.toFieldName());
                const str_ptr: *[]const u8 = switch (@TypeOf(maybe_str_ptr)) {
                    *[]const u8 => maybe_str_ptr,
                    *?[]const u8 => if (maybe_str_ptr.*) |*str_ptr| str_ptr else blk: {
                        maybe_str_ptr.* = "";
                        break :blk if (maybe_str_ptr.*) |*ptr| ptr else unreachable;
                    },
                    else => |T| @compileError("Unhandled: " ++ @typeName(T)),
                };
                var new_str = std.ArrayList(u8).fromOwnedSlice(allocator, @constCast(str_ptr.*));
                defer new_str.deinit();
                new_str.clearRetainingCapacity();
                assert(try source.allocNextIntoArrayListMax(
                    &new_str,
                    .alloc_always,
                    options.max_value_len orelse std.json.default_max_value_len,
                ) == null);
                str_ptr.* = try new_str.toOwnedSlice();
            },
            .info => {
                if (field_set.contains(.info)) {
                    result.info.deinit(allocator);
                }
                result.info = try Info.jsonParse(allocator, source, options);
            },
        }
    }

    const required: FieldSet = comptime FieldSet.initMany(blk: {
        var required: []const FieldName = &.{};
        const all = std.enums.values(FieldName);
        @setEvalBranchQuota(all.len * 2);
        for (all) |field_name| {
            const is_required = switch (field_name) {
                .openapi => true,
                .info => true,
                .jsonSchemaDialect => false,
            };
            if (!is_required) continue;
            required = required ++ &[_]FieldName{field_name};
        }
        break :blk required;
    });
    if (!required.intersectWith(field_set).eql(required)) {
        return error.MissingField;
    }

    return result;
}

test Schema {
    const src =
        \\{
        \\    "openapi": "3.0.0",
        \\    "info": {
        \\        "title": "foo"
        \\    },
        \\    "jsonSchemaDialect": "example schema"
        \\}
    ;
    const expected_src: []const u8 = blk: {
        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, src, .{});
        defer parsed.deinit();
        break :blk try std.json.stringifyAlloc(std.testing.allocator, parsed.value, .{ .whitespace = .{} });
    };
    defer std.testing.allocator.free(expected_src);

    const openapi_json = try std.json.parseFromSliceLeaky(Schema, std.testing.allocator, src, std.json.ParseOptions{});
    defer openapi_json.deinit(std.testing.allocator);
    try std.testing.expectFmt(expected_src, "{}", .{util.json.fmtStringify(openapi_json, .{ .whitespace = .{} })});
}

pub const Info = struct {
    /// REQUIRED.
    /// The title of the API.
    title: []const u8,
    // summary          string                        A short summary of the API.
    // description      string                        A description of the API. CommonMark syntax MAY be used for rich text representation.
    // termsOfService   string                        A URL to the Terms of Service for the API. This MUST be in the form of a URL.
    // contact          Contact Object                The contact information for the exposed API.
    // license          License Object                The license information for the exposed API.
    // version          string            REQUIRED.   The version of the OpenAPI document (which is distinct from the OpenAPI Specification version or the API implementation version).

    pub fn deinit(self: Info, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
    }

    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!Info {
        const FieldName = enum {
            title,
            inline fn toFieldName(name: @This()) []const u8 {
                const FieldEnum = std.meta.FieldEnum(Info);
                _ = FieldEnum;
                return switch (name) {
                    else => |tag| @tagName(tag),
                };
            }
        };
        var result: Info = .{
            .title = "",
        };
        errdefer result.deinit(allocator);

        const FieldSet = std.EnumSet(FieldName);
        var field_set: FieldSet = FieldSet.initEmpty();

        if (try source.next() != .object_begin) {
            return error.UnexpectedToken;
        }

        var pse = util.ProgressiveStringToEnum(FieldName){};
        while (try util.json.nextProgressiveFieldToEnum(source, FieldName, &pse)) : (pse = .{}) {
            const field_name: FieldName = pse.getMatch() orelse {
                if (options.ignore_unknown_fields) continue;
                return error.UnknownField;
            };
            if (field_set.contains(field_name)) switch (options.duplicate_field_behavior) {
                .@"error" => return error.DuplicateField,
                .use_first => {
                    try source.skipValue();
                    continue;
                },
                .use_last => {},
            };
            field_set.insert(field_name);
            switch (field_name) {
                inline .title => |tag| {
                    const maybe_str_ptr = &@field(result, tag.toFieldName());
                    const str_ptr: *[]const u8 = switch (@TypeOf(maybe_str_ptr)) {
                        *[]const u8 => maybe_str_ptr,
                        *?[]const u8 => if (maybe_str_ptr.*) |*str_ptr| str_ptr else blk: {
                            maybe_str_ptr.* = "";
                            break :blk if (maybe_str_ptr.*) |*ptr| ptr else unreachable;
                        },
                        else => |T| @compileError("Unhandled: " ++ @typeName(T)),
                    };
                    var new_str = std.ArrayList(u8).fromOwnedSlice(allocator, @constCast(str_ptr.*));
                    defer new_str.deinit();
                    new_str.clearRetainingCapacity();
                    assert(try source.allocNextIntoArrayListMax(
                        &new_str,
                        .alloc_always,
                        options.max_value_len orelse std.json.default_max_value_len,
                    ) == null);
                    str_ptr.* = try new_str.toOwnedSlice();
                },
            }
        }

        const required: FieldSet = comptime FieldSet.initMany(blk: {
            var required: []const FieldName = &.{};
            const all = std.enums.values(FieldName);
            @setEvalBranchQuota(all.len * 2);
            for (all) |field_name| {
                const is_required = switch (field_name) {
                    .title => true,
                };
                if (!is_required) continue;
                required = required ++ &[_]FieldName{field_name};
            }
            break :blk required;
        });
        if (!required.intersectWith(field_set).eql(required)) {
            return error.MissingField;
        }

        return result;
    }
};

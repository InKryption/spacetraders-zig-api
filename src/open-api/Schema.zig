const std = @import("std");
const assert = std.debug.assert;
const util = @import("util");

const Schema = @This();
/// string
/// REQUIRED.
/// This string MUST be the version number of the OpenAPI Specification that the OpenAPI document uses.
/// The openapi field SHOULD be used by tooling to interpret the OpenAPI document.
/// This is not related to the API info.version string.
openapi: []const u8,
/// Info Object
/// REQUIRED.
/// Provides metadata about the API.
/// The metadata MAY be used by tooling as required.
info: Info,
/// string
/// The default value for the $schema keyword within Schema Objects contained within this OAS document.
/// This MUST be in the form of a URI.
///
/// real name: 'jsonSchemaDialect'
json_schema_dialect: ?[]const u8,

/// [Server Object]
/// An array of Server Objects, which provide connectivity information to a target server.
/// If the servers property is not provided, or is an empty array, the default value would be
/// a Server Object with a url value of /.
servers: ?[]const Server,

// /// Paths Object
// /// The available paths and operations for the API.
// paths: Paths,

// /// Map[string, Path Item Object | Reference Object] ]
// ///  The incoming webhooks that MAY be received as part of this API and that the API consumer MAY choose to implement. Closely related to the callbacks feature, this section describes requests initiated other than by an API call, for example by an out of band registration. The key name is a unique string to refer to each webhook, while the (optionally referenced) Path Item Object describes a request that may be initiated by the API provider and the expected responses. An example is available.
// webhooks,

// /// Components Object
// ///  An element to hold various schemas for the document.
// components,

// /// [Security Requirement Object]
// ///  A declaration of which security mechanisms can be used across the API. The list of values includes alternative security requirement objects that can be used. Only one of the security requirement objects need to be satisfied to authorize a request. Individual operations can override this definition. To make security optional, an empty security requirement ({}) can be included in the array.
// security,

// /// [Tag Object]
// ///  A list of tags used by the document with additional metadata. The order of the tags can be used to reflect on their order by the parsing tools. Not all tags that are used by the Operation Object must be declared. The tags that are not declared MAY be organized randomly or based on the tools’ logic. Each tag name in the list MUST be unique.
// tags,

// /// External Documentation Object
// ///  Additional external documentation.
// externalDocs,

/// this should always be safe to deinitialse
const empty = Schema{
    .openapi = "",
    .info = Info.empty,
    .json_schema_dialect = null,
    .servers = null,
};
pub const json_required_fields = requiredFieldSet(Schema, .{
    .openapi = true,
    .info = true,
    .json_schema_dialect = false,
    .servers = false,
});
pub const json_field_names = JsonStringifyFieldNameMap(Schema){
    .json_schema_dialect = "jsonSchemaDialect",
};
pub const jsonStringify = generateJsonStringifyStructWithoutNullsFn(Schema, Schema.json_field_names);

pub fn deinit(self: Schema, allocator: std.mem.Allocator) void {
    allocator.free(self.openapi);
    self.info.deinit(allocator);
    allocator.free(self.json_schema_dialect orelse "");
    if (self.servers) |servers| {
        for (servers) |*server| {
            @constCast(server).deinit(allocator);
        }
        allocator.free(servers);
    }
}

pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Schema {
    var result: Schema = Schema.empty;
    errdefer result.deinit(allocator);
    try jsonParseRealloc(&result, allocator, source, options);
    return result;
}
pub fn jsonParseRealloc(
    result: *Schema,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    const helper = struct {
        inline fn parseFieldValue(
            comptime field_tag: std.meta.FieldEnum(Schema),
            field_ptr: anytype,
            is_new: bool,
            ally: std.mem.Allocator,
            src: @TypeOf(source),
            json_opt: std.json.ParseOptions,
        ) !void {
            _ = is_new;
            switch (field_tag) {
                inline .openapi, .json_schema_dialect => {
                    const str_ptr: *[]const u8 = switch (@TypeOf(field_ptr.*)) {
                        []const u8 => field_ptr,
                        ?[]const u8 => blk: {
                            if (field_ptr.* == null) {
                                field_ptr.* = "";
                            }
                            break :blk &field_ptr.*.?;
                        },
                        else => |T| @compileError("Unhandled string type: " ++ @typeName(T)),
                    };
                    var new_str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(str_ptr.*));
                    defer new_str.deinit();

                    new_str.clearRetainingCapacity();
                    str_ptr.* = "";

                    assert(try src.allocNextIntoArrayListMax(
                        &new_str,
                        .alloc_always,
                        json_opt.max_value_len orelse std.json.default_max_value_len,
                    ) == null);
                    str_ptr.* = try new_str.toOwnedSlice();
                },
                .info => try Info.jsonParseRealloc(field_ptr, ally, src, json_opt),
                .servers => {
                    var list = std.ArrayList(Server).fromOwnedSlice(ally, @constCast(field_ptr.* orelse &.{}));
                    defer list.deinit();
                    field_ptr.* = null;

                    if (try src.next() != .array_begin) {
                        return error.UnexpectedToken;
                    }

                    var overwritten_count: usize = 0;
                    const overwritable_count = list.items.len;
                    while (true) : (overwritten_count += 1) {
                        switch (try src.peekNextTokenType()) {
                            .array_end => {
                                assert(try src.next() == .array_end);
                                break;
                            },
                            else => {},
                        }
                        if (overwritten_count < overwritable_count) {
                            try list.items[overwritten_count].jsonParseRealloc(ally, src, json_opt);
                            overwritten_count += 1;
                            continue;
                        }
                        try list.append(try Server.jsonParse(ally, src, json_opt));
                    }

                    field_ptr.* = try list.toOwnedSlice();
                },
            }
        }
    };

    try jsonParseInPlaceTemplate(Schema, result, allocator, source, options, helper.parseFieldValue);
}

test Schema {
    const src =
        @embedFile("../../SpaceTraders.json")
    // \\{
    // \\    "openapi": "3.0.0",
    // \\    "info": {
    // \\        "title": "foo",
    // \\        "version": "1.0.1"
    // \\    },
    // \\    "jsonSchemaDialect": "example schema"
    // \\}
    ;

    var scanner = std.json.Scanner.initCompleteInput(std.testing.allocator, src);
    defer scanner.deinit();

    // const expected_src: []const u8 = blk: {
    //     const parsed = try std.json.parseFromTokenSource(std.json.Value, std.testing.allocator, &scanner, .{});
    //     defer parsed.deinit();
    //     break :blk try std.json.stringifyAlloc(std.testing.allocator, parsed.value, .{ .whitespace = .{} });
    // };
    // defer std.testing.allocator.free(expected_src);

    scanner.deinit();
    scanner = std.json.Scanner.initCompleteInput(std.testing.allocator, src);
    var diag = std.json.Diagnostics{};
    scanner.enableDiagnostics(&diag);

    const openapi_json = std.json.parseFromTokenSourceLeaky(Schema, std.testing.allocator, &scanner, std.json.ParseOptions{ .ignore_unknown_fields = true }) catch |err| {
        const start = std.mem.lastIndexOfScalar(u8, src[0 .. std.mem.lastIndexOfScalar(u8, src[0..diag.getByteOffset()], '\n') orelse 0], '\n') orelse 0;
        const end = std.mem.indexOfScalarPos(u8, src[0..], diag.getByteOffset(), '\n') orelse src.len;

        std.log.err("{s} at {d}:{d}:\n{s}", .{ @errorName(err), diag.getLine(), diag.getColumn(), src[start..end] });
        return err;
    };
    defer openapi_json.deinit(std.testing.allocator);
    // try std.testing.expectFmt(expected_src, "{}", .{util.json.fmtStringify(openapi_json, .{ .whitespace = .{} })});
}

pub const Info = struct {
    /// REQUIRED.
    /// The title of the API.
    title: []const u8,
    /// string
    /// A short summary of the API.
    summary: ?[]const u8,
    /// string
    /// A description of the API.
    ///  CommonMark syntax MAY be used for rich text representation.
    description: ?[]const u8,
    /// string
    /// A URL to the Terms of Service for the API.
    /// This MUST be in the form of a URL.
    ///
    /// real name: 'termsOfService'
    terms_of_service: ?[]const u8,
    /// Contact Object
    /// The contact information for the exposed API.
    contact: ?Contact,
    /// License Object
    /// The license information for the exposed API.
    license: ?License,
    /// string
    /// REQUIRED.
    /// The version of the OpenAPI document (which is distinct from
    /// the OpenAPI Specification version or the API implementation version).
    version: []const u8,

    /// this should always be safe to deinitialse
    const empty = Info{
        .title = "",
        .summary = null,
        .description = null,
        .terms_of_service = null,
        .contact = null,
        .license = null,
        .version = "",
    };
    pub const json_required_fields = requiredFieldSet(Info, .{
        .title = true,
        .summary = false,
        .description = false,
        .terms_of_service = false,
        .contact = false,
        .license = false,
        .version = true,
    });
    pub const json_field_names = JsonStringifyFieldNameMap(Info){
        .terms_of_service = "termsOfService",
    };
    pub const jsonStringify = generateJsonStringifyStructWithoutNullsFn(Info, Info.json_field_names);

    pub fn deinit(self: Info, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.summary orelse "");
        allocator.free(self.description orelse "");
        allocator.free(self.terms_of_service orelse "");
        if (self.contact) |contact| contact.deinit(allocator);
        if (self.license) |license| license.deinit(allocator);
        allocator.free(self.version);
    }

    pub inline fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Info {
        var result: Info = Info.empty;
        errdefer result.deinit(allocator);
        try Info.jsonParseRealloc(&result, allocator, source, options);
        return result;
    }
    pub fn jsonParseRealloc(
        result: *Info,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!void {
        const helper = struct {
            inline fn parseFieldValue(
                comptime field_tag: std.meta.FieldEnum(Info),
                field_ptr: anytype,
                is_new: bool,
                ally: std.mem.Allocator,
                src: @TypeOf(source),
                json_opt: std.json.ParseOptions,
            ) !void {
                _ = is_new;
                switch (field_tag) {
                    .title,
                    .summary,
                    .description,
                    .terms_of_service,
                    .version,
                    => {
                        const str_ptr: *[]const u8 = switch (@TypeOf(field_ptr.*)) {
                            []const u8 => field_ptr,
                            ?[]const u8 => blk: {
                                if (field_ptr.* == null) {
                                    field_ptr.* = "";
                                }
                                break :blk &field_ptr.*.?;
                            },
                            else => |T| @compileError("Unhandled string type: " ++ @typeName(T)),
                        };

                        var new_str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(str_ptr.*));
                        defer new_str.deinit();

                        new_str.clearRetainingCapacity();
                        str_ptr.* = "";

                        assert(try src.allocNextIntoArrayListMax(
                            &new_str,
                            .alloc_always,
                            json_opt.max_value_len orelse std.json.default_max_value_len,
                        ) == null);
                        str_ptr.* = try new_str.toOwnedSlice();
                    },
                    .contact => {
                        if (field_ptr.* == null) {
                            field_ptr.* = Contact.empty;
                        }
                        const ptr = &field_ptr.*.?;
                        try Contact.jsonParseRealloc(ptr, ally, src, json_opt);
                    },
                    .license => {
                        if (field_ptr.* == null) {
                            field_ptr.* = License.empty;
                        }
                        const ptr = &field_ptr.*.?;
                        try License.jsonParseRealloc(ptr, ally, src, json_opt);
                    },
                }
            }
        };

        try jsonParseInPlaceTemplate(Info, result, allocator, source, options, helper.parseFieldValue);
    }
    pub const Contact = struct {
        /// string
        /// The identifying name of the contact person/organization.
        name: ?[]const u8,
        /// string
        /// The URL pointing to the contact information.
        /// This MUST be in the form of a URL.
        url: ?[]const u8,
        /// string
        /// The email address of the contact person/organization.
        /// This MUST be in the form of an email address.
        email: ?[]const u8,

        /// this should always be safe to deinitialse
        const empty = Contact{
            .name = null,
            .email = null,
            .url = null,
        };
        pub const json_required_fields = requiredFieldSet(Contact, .{
            .name = false,
            .url = false,
            .email = false,
        });
        pub const json_field_names = JsonStringifyFieldNameMap(Contact){};
        pub const jsonStringify = generateJsonStringifyStructWithoutNullsFn(Contact, Contact.json_field_names);

        pub fn deinit(contact: Contact, allocator: std.mem.Allocator) void {
            allocator.free(contact.name orelse "");
            allocator.free(contact.url orelse "");
            allocator.free(contact.email orelse "");
        }

        pub inline fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Contact {
            var result: Contact = Contact.empty;
            errdefer result.deinit(allocator);
            try Contact.jsonParseRealloc(&result, allocator, source, options);
            return result;
        }
        pub fn jsonParseRealloc(
            result: *Contact,
            allocator: std.mem.Allocator,
            source: anytype,
            options: std.json.ParseOptions,
        ) std.json.ParseError(@TypeOf(source.*))!void {
            const helper = struct {
                inline fn parseFieldValue(
                    comptime field_tag: std.meta.FieldEnum(Contact),
                    field_ptr: *std.meta.FieldType(Contact, field_tag),
                    is_new: bool,
                    ally: std.mem.Allocator,
                    src: @TypeOf(source),
                    json_opt: std.json.ParseOptions,
                ) !void {
                    _ = is_new;
                    var new_str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(field_ptr.* orelse ""));
                    defer new_str.deinit();

                    new_str.clearRetainingCapacity();
                    field_ptr.* = "";

                    assert(try src.allocNextIntoArrayListMax(
                        &new_str,
                        .alloc_always,
                        json_opt.max_value_len orelse std.json.default_max_value_len,
                    ) == null);
                    field_ptr.* = try new_str.toOwnedSlice();
                }
            };

            try jsonParseInPlaceTemplate(Contact, result, allocator, source, options, helper.parseFieldValue);
        }
    };
    pub const License = struct {
        /// string
        /// REQUIRED.
        /// The license name used for the API.
        name: []const u8,
        /// string
        /// An SPDX license expression for the API.
        /// The identifier field is mutually exclusive of the url field.
        identifier: ?[]const u8,
        /// string
        /// A URL to the license used for the API.
        /// This MUST be in the form of a URL.
        /// The url field is mutually exclusive of the identifier field.
        url: ?[]const u8,

        pub const empty = License{
            .name = "",
            .identifier = null,
            .url = null,
        };
        pub const json_required_fields = requiredFieldSet(License, .{
            .name = true,
            .identifier = false,
            .url = false,
        });
        pub const json_field_names = JsonStringifyFieldNameMap(License){};
        pub const jsonStringify = generateJsonStringifyStructWithoutNullsFn(License, License.json_field_names);

        pub fn deinit(license: License, allocator: std.mem.Allocator) void {
            allocator.free(license.name);
            allocator.free(license.identifier orelse "");
            allocator.free(license.url orelse "");
        }

        pub inline fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !License {
            var result: License = License.empty;
            errdefer result.deinit(allocator);
            try License.jsonParseRealloc(&result, allocator, source, options);
            return result;
        }
        pub fn jsonParseRealloc(
            result: *License,
            allocator: std.mem.Allocator,
            source: anytype,
            options: std.json.ParseOptions,
        ) std.json.ParseError(@TypeOf(source.*))!void {
            const helper = struct {
                inline fn parseFieldValue(
                    comptime field_tag: std.meta.FieldEnum(License),
                    field_ptr: *std.meta.FieldType(License, field_tag),
                    is_new: bool,
                    ally: std.mem.Allocator,
                    src: @TypeOf(source),
                    json_opt: std.json.ParseOptions,
                ) !void {
                    comptime assert( //
                        @TypeOf(field_ptr.*) == []const u8 or
                        @TypeOf(field_ptr.*) == ?[]const u8);
                    _ = is_new;
                    var new_str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
                    defer new_str.deinit();

                    new_str.clearRetainingCapacity();
                    field_ptr.* = "";

                    assert(try src.allocNextIntoArrayListMax(
                        &new_str,
                        .alloc_always,
                        json_opt.max_value_len orelse std.json.default_max_value_len,
                    ) == null);
                    field_ptr.* = try new_str.toOwnedSlice();
                }
            };

            try jsonParseInPlaceTemplate(License, result, allocator, source, options, helper.parseFieldValue);
        }
    };
};

pub const Server = struct {
    /// string
    /// REQUIRED.
    /// A URL to the target host. This URL supports Server Variables and MAY be relative,
    /// to indicate that the host location is relative to the location where the OpenAPI document is being served.
    /// Variable substitutions will be made when a variable is named in {brackets}.
    url: []const u8,
    /// string
    /// An optional string describing the host designated by the URL.
    /// CommonMark syntax MAY be used for rich text representation.
    description: ?[]const u8,
    /// Map[string, Server Variable Object]
    /// A map between a variable name and its value.
    /// The value is used for substitution in the server’s URL template.
    variables: ?VariableMap,

    pub const empty = Server{
        .url = "",
        .description = null,
        .variables = null,
    };
    pub const json_required_fields = requiredFieldSet(Server, .{
        .url = true,
        .description = false,
        .variables = false,
    });
    pub const json_field_names = JsonStringifyFieldNameMap(Server){};
    pub fn jsonStringify(
        server: Server,
        options: std.json.StringifyOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        try writer.writeByte('{');
        var child_options = options;
        child_options.whitespace.indent_level += 1;

        try child_options.whitespace.outputIndent(writer);

        try std.json.stringify(@as([]const u8, "url"), options, writer);
        try writer.writeByte(':');
        if (child_options.whitespace.separator) {
            try writer.writeByte(' ');
        }
        try std.json.stringify(server.url, options, writer);

        if (server.description) |description| {
            try writer.writeByte(',');
            try std.json.stringify(@as([]const u8, "description"), options, writer);
            try writer.writeByte(':');
            if (child_options.whitespace.separator) {
                try writer.writeByte(' ');
            }
            try std.json.stringify(description, options, writer);
        }

        if (server.variables) |*variables| {
            try writer.writeByte(',');
            try std.json.stringify(@as([]const u8, "variables"), options, writer);
            try writer.writeByte(':');
            if (child_options.whitespace.separator) {
                try writer.writeByte(' ');
            }
            try jsonStringifyVariableMap(variables, child_options, writer);
        }

        try options.whitespace.outputIndent(writer);
        try writer.writeByte('}');
    }

    pub fn deinit(server: *Server, allocator: std.mem.Allocator) void {
        allocator.free(server.url);
        allocator.free(server.description orelse "");
        if (server.variables) |*variables| {
            for (variables.keys(), variables.values()) |key, *value| {
                allocator.free(key);
                value.deinit(allocator);
            }
            variables.deinit(allocator);
        }
    }

    pub inline fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Server {
        var result: Server = Server.empty;
        errdefer result.deinit(allocator);
        try Server.jsonParseRealloc(&result, allocator, source, options);
        return result;
    }
    pub fn jsonParseRealloc(
        result: *Server,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!void {
        const helper = struct {
            inline fn parseFieldValue(
                comptime field_tag: std.meta.FieldEnum(Server),
                field_ptr: *std.meta.FieldType(Server, field_tag),
                is_new: bool,
                ally: std.mem.Allocator,
                src: @TypeOf(source),
                json_opt: std.json.ParseOptions,
            ) !void {
                _ = is_new;
                switch (field_tag) {
                    .url, .description => {
                        const str_ptr: *[]const u8 = switch (@TypeOf(field_ptr.*)) {
                            []const u8 => field_ptr,
                            ?[]const u8 => blk: {
                                if (field_ptr.* == null) {
                                    field_ptr.* = "";
                                }
                                break :blk &field_ptr.*.?;
                            },
                            else => |T| @compileError("Unhandled string type: " ++ @typeName(T)),
                        };
                        var new_str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(str_ptr.*));
                        defer new_str.deinit();

                        new_str.clearRetainingCapacity();
                        str_ptr.* = "";

                        assert(try src.allocNextIntoArrayListMax(
                            &new_str,
                            .alloc_always,
                            json_opt.max_value_len orelse std.json.default_max_value_len,
                        ) == null);
                        str_ptr.* = try new_str.toOwnedSlice();
                    },
                    .variables => {
                        if (field_ptr.* == null) {
                            field_ptr.* = .{};
                        }
                        const variables: *VariableMap = &field_ptr.*.?;
                        for (variables.keys(), variables.values()) |key, *value| {
                            ally.free(key);
                            value.deinit(ally);
                        }
                        variables.clearRetainingCapacity();

                        if (try src.next() != .array_begin) {
                            return error.UnexpectedToken;
                        }

                        while (true) {}

                        unreachable;
                    },
                }
            }
        };

        try jsonParseInPlaceTemplate(Server, result, allocator, source, options, helper.parseFieldValue);
    }

    pub const VariableMap = std.ArrayHashMapUnmanaged([]const u8, Variable, std.array_hash_map.StringContext, true);
    pub const Variable = struct {
        /// [string]
        /// An enumeration of string values to be used if the substitution options are from a limited set.
        /// The array MUST NOT be empty.
        ///
        /// real name: 'enum'
        enumeration: ?Enum,
        /// string
        /// REQUIRED.
        /// The default value to use for substitution,
        /// which SHALL be sent if an alternate value is not supplied.
        /// Note this behavior is different than the Schema Object’s treatment of default values,
        /// because in those cases parameter values are optional.
        /// If the enum is defined, the value MUST exist in the enum’s values.
        default: []const u8,
        /// string
        /// An optional description for the server variable.
        /// CommonMark syntax MAY be used for rich text representation.
        description: ?[]const u8,

        pub const empty = Variable{
            .enumeration = null,
            .default = "",
            .description = null,
        };
        pub const json_required_fields = requiredFieldSet(Variable, .{
            .default = true,
        });
        pub const json_field_names = .{
            .enumeration = "enum",
        };
        pub fn jsonStringify(
            server: Variable,
            options: std.json.StringifyOptions,
            writer: anytype,
        ) @TypeOf(writer).Error!void {
            const simpler = .{
                .enumeration = if (server.enumeration) |enumeration| enumeration.keys() else null,
                .default = server.default,
                .description = server.description,
            };
            const generatedStringify = generateJsonStringifyStructWithoutNullsFn(@TypeOf(simpler), Variable.json_field_names);
            try generatedStringify(simpler, options, writer);
        }

        pub fn deinit(variable: *Variable, allocator: std.mem.Allocator) void {
            if (variable.enumeration) |*enumeration| {
                for (enumeration.keys()) |value| {
                    allocator.free(value);
                }
                enumeration.deinit(allocator);
            }
        }

        pub inline fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Variable {
            var result: Variable = Variable.empty;
            errdefer result.deinit(allocator);
            try Variable.jsonParseRealloc(&result, allocator, source, options);
            return result;
        }
        pub fn jsonParseRealloc(
            result: *Variable,
            allocator: std.mem.Allocator,
            source: anytype,
            options: std.json.ParseOptions,
        ) std.json.ParseError(@TypeOf(source.*))!void {
            const helper = struct {
                inline fn parseFieldValue(
                    comptime field_tag: std.meta.FieldEnum(Variable),
                    field_ptr: *std.meta.FieldType(Variable, field_tag),
                    is_new: bool,
                    ally: std.mem.Allocator,
                    src: @TypeOf(source),
                    json_opt: std.json.ParseOptions,
                ) !void {
                    _ = field_ptr;
                    _ = json_opt;
                    _ = src;
                    _ = ally;
                    _ = is_new;
                    unreachable;
                }
            };

            try jsonParseInPlaceTemplate(Variable, result, allocator, source, options, helper.parseFieldValue);
        }

        pub const Enum = std.ArrayHashMapUnmanaged([]const u8, void, std.array_hash_map.StringContext, true);
    };

    fn jsonStringifyVariableMap(
        variables: *const VariableMap,
        options: std.json.StringifyOptions,
        writer: anytype,
    ) !void {
        try writer.writeByte('{');
        var field_output = false;
        var child_options = options;
        child_options.whitespace.indent_level += 1;

        for (variables.keys(), variables.values(), 0..) |key, value, i| {
            if (i != 0 and field_output) {
                try writer.writeByte(',');
            } else {
                field_output = true;
            }
            try child_options.whitespace.outputIndent(writer);

            try std.json.stringify(key, options, writer);
            try writer.writeByte(':');
            if (child_options.whitespace.separator) {
                try writer.writeByte(' ');
            }
            try std.json.stringify(value, child_options, writer);
        }
        if (field_output) {
            try options.whitespace.outputIndent(writer);
        }
        try writer.writeByte('}');
    }
};

fn JsonStringifyFieldNameMap(comptime T: type) type {
    const info = @typeInfo(T).Struct;
    var fields = [_]std.builtin.Type.StructField{undefined} ** info.fields.len;
    for (&fields, info.fields) |*field, ref| {
        field.* = .{
            .name = ref.name,
            .type = []const u8,
            .default_value = @ptrCast(&@as([]const u8, ref.name)),
            .is_comptime = false,
            .alignment = 0,
        };
    }
    return @Type(.{ .Struct = std.builtin.Type.Struct{
        .layout = .Auto,
        .is_tuple = false,
        .backing_integer = null,
        .decls = &.{},
        .fields = &fields,
    } });
}

fn JsonStringifyFieldNameMapReverse(
    comptime T: type,
    comptime map: JsonStringifyFieldNameMap(T),
) type {
    const info = @typeInfo(@TypeOf(map)).Struct;
    var fields = [_]std.builtin.Type.StructField{undefined} ** info.fields.len;
    for (&fields, info.fields) |*field, ref| field.* = .{
        .name = @field(map, ref.name),
        .type = []const u8,
        .default_value = @ptrCast(&ref.name),
        .is_comptime = true,
        .alignment = 0,
    };
    return @Type(.{ .Struct = std.builtin.Type.Struct{
        .layout = .Auto,
        .is_tuple = false,
        .backing_integer = null,
        .decls = &.{},
        .fields = &fields,
    } });
}

fn FieldEnumSet(comptime T: type) type {
    return std.EnumSet(std.meta.FieldEnum(T));
}
inline fn requiredFieldSet(
    comptime T: type,
    values: std.enums.EnumFieldStruct(std.meta.FieldEnum(T), bool, null),
) FieldEnumSet(T) {
    var result = FieldEnumSet(T).initEmpty();
    inline for (@typeInfo(T).Struct.fields) |field| {
        if (@field(values, field.name)) {
            result.insert(@field(std.meta.FieldEnum(T), field.name));
        }
    }
    return result;
}

fn generateJsonStringifyStructWithoutNullsFn(
    comptime T: type,
    comptime field_names: JsonStringifyFieldNameMap(T),
) @TypeOf(GenerateJsonStringifyStructWithoutNullsFnImpl(T, field_names).stringify) {
    return GenerateJsonStringifyStructWithoutNullsFnImpl(T, field_names).stringify;
}
fn GenerateJsonStringifyStructWithoutNullsFnImpl(
    comptime T: type,
    comptime field_names: JsonStringifyFieldNameMap(T),
) type {
    return struct {
        pub fn stringify(
            structure: T,
            options: std.json.StringifyOptions,
            writer: anytype,
        ) !void {
            try writer.writeByte('{');
            var field_output = false;
            var child_options = options;
            child_options.whitespace.indent_level += 1;

            inline for (@typeInfo(@TypeOf(structure)).Struct.fields, 0..) |field, i| @"continue": { // <- block label is a hack around the fact we can't continue or break an inline loop based on a runtime condition
                const value = switch (@typeInfo(field.type)) {
                    .Optional => @field(structure, field.name) orelse break :@"continue",
                    else => @field(structure, field.name),
                };
                if (@typeInfo(field.type) == .Optional) {
                    if (@field(structure, field.name) == null)
                        break :@"continue";
                }
                if (i != 0 and field_output) {
                    try writer.writeByte(',');
                } else {
                    field_output = true;
                }
                try child_options.whitespace.outputIndent(writer);

                try std.json.stringify(@field(field_names, field.name), options, writer);
                try writer.writeByte(':');
                if (child_options.whitespace.separator) {
                    try writer.writeByte(' ');
                }
                try std.json.stringify(value, child_options, writer);
            }
            if (field_output) {
                try options.whitespace.outputIndent(writer);
            }
            try writer.writeByte('}');
        }
    };
}

fn jsonParseInPlaceTemplate(
    comptime T: type,
    result: *T,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
    /// The type that is effectively expected is:
    /// ```zig
    /// fn (
    ///     comptime field_tag: std.meta.FieldEnum(T),
    ///     field_ptr: anytype,
    ///     is_new: bool,
    ///     allocator: std.mem.Allocator,
    ///     source: @TypeOf(source),
    ///     options: std.json.ParseOptions,
    /// ) std.json.ParseError(@TypeOf(source.*))!void
    /// ```
    comptime parseFieldValue: anytype,
) std.json.ParseError(@TypeOf(source.*))!void {
    const json_field_name_map: JsonStringifyFieldNameMap(T) = T.json_field_names;
    const json_field_name_map_reverse: JsonStringifyFieldNameMapReverse(T, json_field_name_map) = .{};

    const JsonFieldName = std.meta.FieldEnum(@TypeOf(json_field_name_map_reverse));
    const FieldName = std.meta.FieldEnum(T);
    var field_set = FieldEnumSet(T).initEmpty();

    const required_fields: std.EnumSet(FieldName) = T.json_required_fields;

    if (try source.next() != .object_begin) {
        return error.UnexpectedToken;
    }

    var pse: util.ProgressiveStringToEnum(JsonFieldName) = .{};
    while (try util.json.nextProgressiveFieldToEnum(source, JsonFieldName, &pse)) : (pse = .{}) {
        const json_field_name: JsonFieldName = pse.getMatch() orelse {
            if (options.ignore_unknown_fields) {
                try source.skipValue();
                continue;
            }
            return error.UnknownField;
        };
        const field_name: FieldName = switch (json_field_name) {
            inline else => |tag| comptime blk: {
                const str: []const u8 = @field(json_field_name_map_reverse, @tagName(tag));
                break :blk @field(FieldName, str);
            },
        };
        const is_new = if (field_set.contains(field_name)) switch (options.duplicate_field_behavior) {
            .@"error" => return error.DuplicateField,
            .use_first => {
                try source.skipValue();
                continue;
            },
            .use_last => false,
        } else true;
        field_set.insert(field_name);
        switch (field_name) {
            inline else => |tag| try parseFieldValue(
                tag,
                &@field(result, @tagName(tag)),
                is_new,
                allocator,
                source,
                options,
            ),
        }
    }

    if (!required_fields.subsetOf(field_set)) {
        return error.MissingField;
    }
}

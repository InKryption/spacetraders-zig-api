//! OpenAPI Specification Version 3.1.0
const std = @import("std");
const assert = std.debug.assert;
const util = @import("util");

const Schema = @This();
openapi: []const u8,
info: Info,
json_schema_dialect: ?[]const u8,
servers: ?[]const Server,
paths: ?Paths,
// webhooks: ?Webhooks,
// components: ?Components,
// security: ?Security,

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
    .paths = Paths.empty,
};
pub const json_required_fields = requiredFieldSetBasedOnOptionals(Schema, .{});
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
    try jsonParseInPlaceTemplate(Schema, result, allocator, source, options, Schema.parseFieldValue);
}
inline fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(Schema),
    field_ptr: anytype,
    is_new: bool,
    ally: std.mem.Allocator,
    src: anytype,
    json_opt: std.json.ParseOptions,
) !void {
    _ = is_new;
    switch (field_tag) {
        inline .openapi, .json_schema_dialect => {
            var str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
            defer str.deinit();
            field_ptr.* = "";
            try jsonParseReallocString(&str, src, json_opt);
            field_ptr.* = try str.toOwnedSlice();
        },
        .info => try Info.jsonParseRealloc(field_ptr, ally, src, json_opt),
        .servers => {
            var list = std.ArrayListUnmanaged(Server).fromOwnedSlice(@constCast(field_ptr.* orelse &.{}));
            defer {
                for (list.items) |*server|
                    server.deinit(ally);
                list.deinit(ally);
            }
            field_ptr.* = null;
            try jsonParseInPlaceArrayListTemplate(Server, &list, ally, src, json_opt);
            field_ptr.* = try list.toOwnedSlice(ally);
        },
        .paths => {
            if (field_ptr.* == null) {
                field_ptr.* = Paths.empty;
            }
            try Paths.jsonParseRealloc(&field_ptr.*.?, ally, src, json_opt);
        },
    }
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
    title: []const u8,
    summary: ?[]const u8,
    description: ?[]const u8,
    terms_of_service: ?[]const u8,
    contact: ?Contact,
    license: ?License,
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
    pub const json_required_fields = requiredFieldSetBasedOnOptionals(Info, .{});
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
        try jsonParseInPlaceTemplate(Info, result, allocator, source, options, Info.parseFieldValue);
    }
    inline fn parseFieldValue(
        comptime field_tag: std.meta.FieldEnum(Info),
        field_ptr: anytype,
        is_new: bool,
        ally: std.mem.Allocator,
        src: anytype,
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
                var str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
                defer str.deinit();
                field_ptr.* = "";
                try jsonParseReallocString(&str, src, json_opt);
                field_ptr.* = try str.toOwnedSlice();
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
    pub const Contact = struct {
        /// string
        ///
        /// The identifying name of the contact person/organization.
        name: ?[]const u8,
        /// string
        ///
        /// The URL pointing to the contact information.
        /// This MUST be in the form of a URL.
        url: ?[]const u8,
        /// string
        ///
        /// The email address of the contact person/organization.
        /// This MUST be in the form of an email address.
        email: ?[]const u8,

        /// this should always be safe to deinitialse
        const empty = Contact{
            .name = null,
            .email = null,
            .url = null,
        };
        pub const json_required_fields = requiredFieldSetBasedOnOptionals(Contact, .{});
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
            try jsonParseInPlaceTemplate(Contact, result, allocator, source, options, Contact.parseFieldValue);
        }
        inline fn parseFieldValue(
            comptime field_tag: std.meta.FieldEnum(Contact),
            field_ptr: *std.meta.FieldType(Contact, field_tag),
            is_new: bool,
            ally: std.mem.Allocator,
            src: anytype,
            json_opt: std.json.ParseOptions,
        ) !void {
            _ = is_new;
            var str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
            defer str.deinit();
            field_ptr.* = "";
            try jsonParseReallocString(&str, src, json_opt);
            field_ptr.* = try str.toOwnedSlice();
        }
    };
    pub const License = struct {
        /// string
        ///
        /// REQUIRED.
        ///
        /// The license name used for the API.
        name: []const u8,
        /// string
        ///
        /// An SPDX license expression for the API.
        /// The identifier field is mutually exclusive of the url field.
        identifier: ?[]const u8,
        /// string
        ///
        /// A URL to the license used for the API.
        /// This MUST be in the form of a URL.
        /// The url field is mutually exclusive of the identifier field.
        url: ?[]const u8,

        pub const empty = License{
            .name = "",
            .identifier = null,
            .url = null,
        };
        pub const json_required_fields = requiredFieldSetBasedOnOptionals(License, .{});
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
            try jsonParseInPlaceTemplate(License, result, allocator, source, options, License.parseFieldValue);
        }
        inline fn parseFieldValue(
            comptime field_tag: std.meta.FieldEnum(License),
            field_ptr: *std.meta.FieldType(License, field_tag),
            is_new: bool,
            ally: std.mem.Allocator,
            src: anytype,
            json_opt: std.json.ParseOptions,
        ) !void {
            _ = is_new;
            var str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
            defer str.deinit();
            field_ptr.* = @field(License.empty, @tagName(field_tag));
            try jsonParseReallocString(&str, src, json_opt);
            field_ptr.* = try str.toOwnedSlice();
        }
    };
};

pub const Server = struct {
    /// string
    ///
    /// REQUIRED.
    ///
    /// A URL to the target host. This URL supports Server Variables and MAY be relative,
    /// to indicate that the host location is relative to the location where the OpenAPI document is being served.
    /// Variable substitutions will be made when a variable is named in {brackets}.
    url: []const u8,
    /// string
    ///
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
    pub const json_required_fields = requiredFieldSetBasedOnOptionals(Server, .{});
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
        const helper = struct {};
        _ = helper;

        try jsonParseInPlaceTemplate(Server, result, allocator, source, options, Server.parseFieldValue);
    }
    inline fn parseFieldValue(
        comptime field_tag: std.meta.FieldEnum(Server),
        field_ptr: *std.meta.FieldType(Server, field_tag),
        is_new: bool,
        ally: std.mem.Allocator,
        src: anytype,
        json_opt: std.json.ParseOptions,
    ) !void {
        _ = is_new;
        switch (field_tag) {
            .url, .description => {
                var str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
                defer str.deinit();
                field_ptr.* = "";
                try jsonParseReallocString(&str, src, json_opt);
                field_ptr.* = try str.toOwnedSlice();
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

    pub const VariableMap = std.ArrayHashMapUnmanaged([]const u8, Variable, std.array_hash_map.StringContext, true);
    pub const Variable = struct {
        /// [string]
        /// An enumeration of string values to be used if the substitution options are from a limited set.
        /// The array MUST NOT be empty.
        ///
        /// real name: 'enum'
        enumeration: ?Enum,
        /// string
        ///
        /// REQUIRED.
        ///
        /// The default value to use for substitution,
        /// which SHALL be sent if an alternate value is not supplied.
        /// Note this behavior is different than the Schema Object’s treatment of default values,
        /// because in those cases parameter values are optional.
        /// If the enum is defined, the value MUST exist in the enum’s values.
        default: []const u8,
        /// string
        ///
        /// An optional description for the server variable.
        /// CommonMark syntax MAY be used for rich text representation.
        description: ?[]const u8,

        pub const empty = Variable{
            .enumeration = null,
            .default = "",
            .description = null,
        };
        pub const json_required_fields = requiredFieldSetBasedOnOptionals(Variable, .{});
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
            try jsonParseInPlaceTemplate(Variable, result, allocator, source, options, Variable.parseFieldValue);
        }
        inline fn parseFieldValue(
            comptime field_tag: std.meta.FieldEnum(Variable),
            field_ptr: *std.meta.FieldType(Variable, field_tag),
            is_new: bool,
            ally: std.mem.Allocator,
            src: anytype,
            json_opt: std.json.ParseOptions,
        ) !void {
            _ = field_ptr;
            _ = json_opt;
            _ = src;
            _ = ally;
            _ = is_new;
            unreachable;
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

pub const Paths = struct {
    fields: Fields,

    pub const empty = Paths{
        .fields = .{},
    };

    pub fn deinit(paths: *Paths, allocator: std.mem.Allocator) void {
        for (paths.fields.keys(), paths.fields.values()) |path, *item| {
            allocator.free(path);
            item.deinit(allocator);
        }
        paths.fields.deinit(allocator);
    }

    pub fn jsonStringify(
        paths: Paths,
        options: std.json.StringifyOptions,
        writer: anytype,
    ) !void {
        _ = writer;
        _ = options;
        _ = paths;
        @panic("TODO");
    }

    pub fn jsonParseRealloc(
        result: *Paths,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!void {
        if (try source.next() != .object_begin) return error.UnexpectedToken;

        var old_fields = result.fields.move();
        defer {
            for (old_fields.keys(), old_fields.values()) |path, *item| {
                allocator.free(path);
                item.deinit(allocator);
            }
            old_fields.deinit(allocator);
        }

        var new_fields = Fields{};
        defer {
            for (new_fields.keys(), new_fields.values()) |path, *item| {
                allocator.free(path);
                item.deinit(allocator);
            }
            new_fields.deinit(allocator);
        }
        try new_fields.ensureUnusedCapacity(allocator, old_fields.count());

        var path_buffer = std.ArrayList(u8).init(allocator);
        defer path_buffer.deinit();

        while (true) {
            switch (try source.peekNextTokenType()) {
                else => unreachable,
                .object_end => {
                    _ = try source.next();
                    break;
                },
                .string => {},
            }

            path_buffer.clearRetainingCapacity();
            const new_path: []const u8 = (try source.allocNextIntoArrayListMax(
                &path_buffer,
                .alloc_if_needed,
                options.max_value_len orelse std.json.default_max_value_len,
            )) orelse path_buffer.items;

            const gop = try new_fields.getOrPut(allocator, new_path);
            if (gop.found_existing) switch (options.duplicate_field_behavior) {
                .@"error" => return error.DuplicateField,
                .use_first => {
                    try source.skipValue();
                    continue;
                },
                .use_last => {
                    try gop.value_ptr.jsonParseRealloc(allocator, source, options);
                    continue;
                },
            };

            gop.key_ptr.* = "";
            if (old_fields.fetchSwapRemove(new_path)) |old| {
                gop.key_ptr.* = old.key;
                gop.value_ptr.* = old.value;
            } else {
                gop.key_ptr.* = try allocator.dupe(u8, new_path);
                gop.value_ptr.* = Item.empty;
            }
            assert(gop.key_ptr.len != 0);

            try gop.value_ptr.jsonParseRealloc(allocator, source, options);
        }
        result.fields = new_fields;
    }

    pub const Fields = std.ArrayHashMapUnmanaged([]const u8, Item, std.array_hash_map.StringContext, true);
    pub const Item = struct {
        ref: ?[]const u8,
        summary: ?[]const u8,
        description: ?[]const u8,

        get: ?Operation,
        put: ?Operation,
        post: ?Operation,
        delete: ?Operation,
        options: ?Operation,
        head: ?Operation,
        patch: ?Operation,
        trace: ?Operation,

        servers: ?[]const Server,

        // /// [Parameter Object | Reference Object]
        // ///
        // /// A list of parameters that are applicable for all the operations described under this path.
        // /// These parameters can be overridden at the operation level, but cannot be removed there.
        // /// The list MUST NOT include duplicated parameters. A unique parameter is defined by a combination of a name and location.
        // /// The list can use the Reference Object to link to parameters that are defined at the OpenAPI Object’s components/parameters.
        parameters: ?[]const Param,

        pub const empty = Item{
            .ref = null,
            .summary = null,
            .description = null,

            .get = null,
            .put = null,
            .post = null,
            .delete = null,
            .options = null,
            .head = null,
            .patch = null,
            .trace = null,

            .servers = null,
            .parameters = null,
        };
        pub const json_required_fields = requiredFieldSetBasedOnOptionals(Item, .{});
        pub const json_field_names = JsonStringifyFieldNameMap(Item){
            .ref = "$ref",
        };

        pub fn deinit(item: *Item, allocator: std.mem.Allocator) void {
            allocator.free(item.ref orelse "");
            allocator.free(item.summary orelse "");
            allocator.free(item.description orelse "");

            inline for (.{ "get", "put", "post", "delete", "options", "head", "patch", "trace" }) |method_name| {
                if (@field(item, method_name)) |*operation| {
                    Operation.deinit(operation, allocator);
                }
            }

            if (item.servers) |servers| {
                for (@constCast(servers)) |*server| {
                    server.deinit(allocator);
                }
                allocator.free(servers);
            }
            if (item.parameters) |parameters| {
                for (@constCast(parameters)) |*parameter| {
                    parameter.deinit(allocator);
                }
                allocator.free(parameters);
            }
        }

        pub fn jsonParseRealloc(
            result: *Item,
            allocator: std.mem.Allocator,
            source: anytype,
            options: std.json.ParseOptions,
        ) std.json.ParseError(@TypeOf(source.*))!void {
            try jsonParseInPlaceTemplate(Item, result, allocator, source, options, Item.parseFieldValue);
        }

        inline fn parseFieldValue(
            comptime field_tag: std.meta.FieldEnum(Item),
            field_ptr: *std.meta.FieldType(Item, field_tag),
            is_new: bool,
            ally: std.mem.Allocator,
            src: anytype,
            json_opt: std.json.ParseOptions,
        ) !void {
            _ = is_new;
            switch (field_tag) {
                .ref, .summary, .description => {
                    var str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(field_ptr.* orelse ""));
                    defer str.deinit();
                    field_ptr.* = null;
                    try jsonParseReallocString(&str, src, json_opt);
                    field_ptr.* = try str.toOwnedSlice();
                },

                .get,
                .put,
                .post,
                .delete,
                .options,
                .head,
                .patch,
                .trace,
                => {
                    if (field_ptr.* == null) {
                        field_ptr.* = Operation.empty;
                    }
                    try Operation.jsonParseRealloc(&field_ptr.*.?, ally, src, json_opt);
                },

                .servers, .parameters => {
                    const FieldElem = @typeInfo(@TypeOf(field_ptr.*.?)).Pointer.child;
                    var list = std.ArrayListUnmanaged(FieldElem).fromOwnedSlice(@constCast(field_ptr.* orelse &.{}));
                    defer {
                        for (list.items) |*server|
                            server.deinit(ally);
                        list.deinit(ally);
                    }
                    field_ptr.* = null;
                    try jsonParseInPlaceArrayListTemplate(FieldElem, &list, ally, src, json_opt);
                    field_ptr.* = try list.toOwnedSlice(ally);
                },
            }
        }

        pub const Param = union(enum) {
            parameter: Parameter,
            reference: Reference,

            pub fn deinit(param: *Param, allocator: std.mem.Allocator) void {
                switch (param.*) {
                    inline else => |*ptr| ptr.deinit(allocator),
                }
            }

            pub fn jsonParse(
                allocator: std.mem.Allocator,
                source: anytype,
                options: std.json.ParseOptions,
            ) !Param {
                var result: Param = .{ .reference = Reference.empty };
                errdefer result.deinit(allocator);
                try result.jsonParseRealloc(allocator, source, options);
                return result;
            }

            pub fn jsonParseRealloc(
                result: *Param,
                allocator: std.mem.Allocator,
                source: anytype,
                options: std.json.ParseOptions,
            ) std.json.ParseError(@TypeOf(source.*))!void {
                _ = options;
                _ = allocator;
                _ = result;
                @panic("TODO");
            }
        };

        pub const Operation = struct {
            tags: ?[]const []const u8,
            summary: ?[]const u8,
            description: ?[]const u8,
            // externalDocs   External Documentation Object                     Additional external documentation for this operation.
            // operationId    string                                            Unique string used to identify the operation. The id MUST be unique among all operations described in the API. The operationId value is case-sensitive. Tools and libraries MAY use the operationId to uniquely identify an operation, therefore, it is RECOMMENDED to follow common programming naming conventions.
            // parameters     [Parameter Object | Reference Object]             A list of parameters that are applicable for this operation. If a parameter is already defined at the Path Item, the new definition will override it but can never remove it. The list MUST NOT include duplicated parameters. A unique parameter is defined by a combination of a name and location. The list can use the Reference Object to link to parameters that are defined at the OpenAPI Object’s components/parameters.
            // requestBody    Request Body Object | Reference Object            The request body applicable for this operation. The requestBody is fully supported in HTTP methods where the HTTP 1.1 specification [RFC7231] has explicitly defined semantics for request bodies. In other cases where the HTTP spec is vague (such as GET, HEAD and DELETE), requestBody is permitted but does not have well-defined semantics and SHOULD be avoided if possible.
            // responses      Responses Object                                  The list of possible responses as they are returned from executing this operation.
            // callbacks      Map[string, Callback Object | Reference Object]   A map of possible out-of band callbacks related to the parent operation. The key is a unique identifier for the Callback Object. Each value in the map is a Callback Object that describes a request that may be initiated by the API provider and the expected responses.
            // deprecated     boolean                                           Declares this operation to be deprecated. Consumers SHOULD refrain from usage of the declared operation. Default value is false.
            // security       [Security Requirement Object]                     A declaration of which security mechanisms can be used for this operation. The list of values includes alternative security requirement objects that can be used. Only one of the security requirement objects need to be satisfied to authorize a request. To make security optional, an empty security requirement ({}) can be included in the array. This definition overrides any declared top-level security. To remove a top-level security declaration, an empty array can be used.
            // servers        [Server Object]                                   An alternative server array to service this operation. If an alternative server object is specified at the Path Item Object or Root level, it will be overridden by this value.

            pub const empty = Operation{
                .tags = null,
                .summary = null,
                .description = null,
            };
            pub const json_required_fields = requiredFieldSetBasedOnOptionals(Operation, .{});
            pub const json_field_names = JsonStringifyFieldNameMap(Operation){};

            pub fn deinit(op: *Operation, allocator: std.mem.Allocator) void {
                if (op.tags) |tags| {
                    for (tags) |tag| allocator.free(tag);
                    allocator.free(tags);
                }
                allocator.free(op.summary orelse "");
                allocator.free(op.description orelse "");
            }

            pub fn jsonParseRealloc(
                result: *Operation,
                allocator: std.mem.Allocator,
                source: anytype,
                options: std.json.ParseOptions,
            ) std.json.ParseError(@TypeOf(source.*))!void {
                try jsonParseInPlaceTemplate(Operation, result, allocator, source, options, Operation.parseFieldValue);
            }

            inline fn parseFieldValue(
                comptime field_tag: std.meta.FieldEnum(Operation),
                field_ptr: *std.meta.FieldType(Operation, field_tag),
                is_new: bool,
                ally: std.mem.Allocator,
                src: anytype,
                json_opt: std.json.ParseOptions,
            ) !void {
                _ = is_new;
                switch (field_tag) {
                    .tags => {
                        var list = std.ArrayList([]const u8).fromOwnedSlice(ally, @constCast(field_ptr.* orelse &.{}));
                        defer {
                            for (list.items) |str| ally.free(str);
                            list.deinit();
                        }

                        field_ptr.* = null;

                        var overwritten_count: usize = 0;
                        const overwritable_count = list.items.len;

                        if (try src.next() != .array_begin) {
                            return error.UnexpectedToken;
                        }
                        while (true) {
                            switch (try src.peekNextTokenType()) {
                                else => return error.UnexpectedToken,
                                .array_end => {
                                    _ = try src.next();
                                    break;
                                },
                                .string => {},
                            }
                            if (overwritten_count < overwritable_count) {
                                defer overwritten_count += 1;
                                var new_str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(list.items[overwritten_count]));
                                defer new_str.deinit();
                                list.items[overwritten_count] = "";
                                try jsonParseReallocString(&new_str, src, json_opt);
                                list.items[overwritten_count] = try new_str.toOwnedSlice();
                                continue;
                            }
                            const new_str = try src.nextAllocMax(
                                ally,
                                .alloc_always,
                                json_opt.max_value_len orelse std.json.default_max_value_len,
                            );
                            try list.append(new_str.allocated_string);
                        }

                        field_ptr.* = try list.toOwnedSlice();
                    },
                    .summary, .description => {
                        var str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(field_ptr.* orelse ""));
                        defer str.deinit();
                        field_ptr.* = null;
                        try jsonParseReallocString(&str, src, json_opt);
                        field_ptr.* = try str.toOwnedSlice();
                    },
                }
            }
        };
    };
};

pub const Parameter = struct {
    name: []const u8,
    in: In,
    description: ?[]const u8,
    required: ?bool,
    deprecated: ?bool,
    allow_empty_value: ?bool,

    pub const empty = Parameter{
        .name = "",
        .in = undefined,
        .description = null,
        .required = null,
        .deprecated = null,
        .allow_empty_value = null,
    };
    pub const json_required_fields = requiredFieldSetBasedOnOptionals(Parameter, .{});
    pub const json_field_names = JsonStringifyFieldNameMap(Parameter){
        .allow_empty_value = "allowEmptyValue",
    };

    pub fn deinit(param: Parameter, allocator: std.mem.Allocator) void {
        allocator.free(param.name);
        allocator.free(param.description orelse "");
    }

    pub fn jsonParseRealloc(
        result: *Parameter,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!void {
        try jsonParseInPlaceTemplate(Parameter, result, allocator, source, options);
    }
    inline fn parseFieldValue(
        comptime field_tag: std.meta.FieldEnum(Schema),
        field_ptr: anytype,
        is_new: bool,
        ally: std.mem.Allocator,
        src: anytype,
        json_opt: std.json.ParseOptions,
    ) !void {
        _ = is_new;
        switch (field_tag) {
            .name, .description => {
                var new_str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
                defer new_str.deinit();
                field_ptr.* = "";
                try jsonParseReallocString(&new_str, src, json_opt);
                field_ptr.* = try new_str.toOwnedSlice();
            },
            .in => {
                var pse = util.ProgressiveStringToEnum(Parameter.In){};
                try util.json.nextProgressiveStringToEnum(src, Parameter.In, &pse);
                field_ptr.* = pse.getMatch() orelse return error.UnexpectedToken;
            },
            .required, .deprecated, .allow_empty_value => {
                field_ptr.* = switch (try src.next()) {
                    .true => true,
                    .false => false,
                    else => return error.UnexpectedToken,
                };
            },
        }
    }

    pub const In = enum {
        query,
        header,
        path,
        cookie,
    };
};

pub const Reference = struct {
    ref: []const u8,
    summary: ?[]const u8,
    description: ?[]const u8,

    pub const empty = Reference{
        .ref = "",
        .summary = null,
        .description = null,
    };
    pub const json_required_fields = requiredFieldSetBasedOnOptionals(Reference, .{});
    pub const json_field_names = JsonStringifyFieldNameMap(Reference){
        .ref = "$ref",
    };

    pub fn deinit(ref: Reference, allocator: std.mem.Allocator) void {
        allocator.free(ref.ref);
        allocator.free(ref.summary orelse "");
        allocator.free(ref.description orelse "");
    }

    pub fn jsonParseRealloc(
        result: *Reference,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!void {
        try jsonParseInPlaceTemplate(Reference, result, allocator, source, options, Reference.parseFieldValue);
    }
    inline fn parseFieldValue(
        comptime field_tag: std.meta.FieldEnum(Reference),
        field_ptr: anytype,
        is_new: bool,
        ally: std.mem.Allocator,
        src: anytype,
        json_opt: std.json.ParseOptions,
    ) !void {
        _ = is_new;
        _ = field_tag;
        var new_str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(field_ptr.* orelse ""));
        defer new_str.deinit();
        field_ptr.* = "";
        try jsonParseReallocString(&new_str, src, json_opt);
        field_ptr.* = try new_str.toOwnedSlice();
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
inline fn requiredFieldSetBasedOnOptionals(
    comptime T: type,
    values: std.enums.EnumFieldStruct(std.meta.FieldEnum(T), ?bool, @as(?bool, null)),
) FieldEnumSet(T) {
    var result = FieldEnumSet(T).initEmpty();
    inline for (@typeInfo(T).Struct.fields) |field| {
        const is_required = @field(values, field.name) orelse @typeInfo(field.type) != .Optional;
        const tag = @field(std.meta.FieldEnum(T), field.name);
        result.setPresent(tag, is_required);
    }
    return result;
}
fn requiredFieldSet(
    comptime T: type,
    values: std.enums.EnumFieldStruct(std.meta.FieldEnum(T), bool, null),
) FieldEnumSet(T) {
    var result = FieldEnumSet(T).initEmpty();
    inline for (@typeInfo(T).Struct.fields) |field| {
        const is_required = @field(values, field.name);
        const tag = @field(std.meta.FieldEnum(T), field.name);
        result.setPresent(tag, is_required);
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

fn jsonParseReallocString(
    str: *std.ArrayList(u8),
    source: anytype,
    options: std.json.ParseOptions,
) !void {
    str.clearRetainingCapacity();
    assert(try source.allocNextIntoArrayListMax(
        str,
        .alloc_always,
        options.max_value_len orelse std.json.default_max_value_len,
    ) == null);
}

/// parses the tokens from `source` into `results`,
/// re-using the memory of any elements already present in `results`.
/// `results` may be modified on error - caller must ensure that each `T`
/// is deinitialised properly regardless.
fn jsonParseInPlaceArrayListTemplate(
    comptime T: type,
    results: *std.ArrayListUnmanaged(T),
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) !void {
    if (try source.next() != .array_begin) {
        return error.UnexpectedToken;
    }

    var overwritten_count: usize = 0;
    const overwritable_count = results.items.len;
    while (true) : (overwritten_count += 1) {
        switch (try source.peekNextTokenType()) {
            .array_end => {
                assert(try source.next() == .array_end);
                break;
            },
            else => {},
        }
        if (overwritten_count < overwritable_count) {
            try results.items[overwritten_count].jsonParseRealloc(allocator, source, options);
            overwritten_count += 1;
            continue;
        }
        try results.append(allocator, try T.jsonParse(allocator, source, options));
    }

    if (overwritten_count < overwritable_count) {
        results.shrinkRetainingCapacity(overwritten_count);
    }
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
    comptime parseFieldValueFn: anytype,
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
            inline else => |tag| try parseFieldValueFn(
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

    // ensure that any fields that were present in the old `result` value are
    // not present in the resulting `result` value if they are not present.
    var to_free = T.empty;
    defer to_free.deinit(allocator);
    inline for (@typeInfo(T).Struct.fields) |field| cont: {
        const tag = @field(FieldName, field.name);
        if (field_set.contains(tag)) break :cont;
        const Field = std.meta.FieldType(T, tag);
        std.mem.swap(Field, &@field(result, field.name), &@field(to_free, field.name));
    }
}

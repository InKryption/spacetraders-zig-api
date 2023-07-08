const std = @import("std");
const assert = std.debug.assert;
const util = @import("util");

const schema_tools = @import("schema-tools.zig");

const Server = @import("Server.zig");
const Parameter = @import("Parameter.zig");
const Reference = @import("Reference.zig");

const Paths = @This();
fields: Fields = .{},

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
            gop.value_ptr.* = .{};
        }
        assert(gop.key_ptr.len != 0);

        try gop.value_ptr.jsonParseRealloc(allocator, source, options);
    }
    result.fields = new_fields;
}

pub const Fields = std.ArrayHashMapUnmanaged([]const u8, Item, std.array_hash_map.StringContext, true);
pub const Item = struct {
    ref: ?[]const u8 = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,

    get: ?Operation = null,
    put: ?Operation = null,
    post: ?Operation = null,
    delete: ?Operation = null,
    options: ?Operation = null,
    head: ?Operation = null,
    patch: ?Operation = null,
    trace: ?Operation = null,

    servers: ?[]const Server = null,
    parameters: ?[]const Param = null,

    pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Item, .{});
    pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Item){
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
        try schema_tools.jsonParseInPlaceTemplate(Item, result, allocator, source, options, Item.parseFieldValue);
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
                try schema_tools.jsonParseReallocString(&str, src, json_opt);
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
                    field_ptr.* = .{};
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
                try schema_tools.jsonParseInPlaceArrayListTemplate(FieldElem, &list, ally, src, json_opt);
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

        pub fn jsonStringify(
            param: Param,
            options: std.json.StringifyOptions,
            writer: anytype,
        ) @TypeOf(writer).Error!void {
            try switch (param) {
                inline else => |val| val.jsonStringify(options, writer),
            };
        }

        pub fn jsonParse(
            allocator: std.mem.Allocator,
            source: anytype,
            options: std.json.ParseOptions,
        ) !Param {
            var result: Param = .{ .reference = .{} };
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
            _ = allocator;
            _ = result;

            var resolution: ?@typeInfo(Param).Union.tag_type.? = null;
            _ = resolution;

            var pse: util.ProgressiveStringToEnum(AnyFieldTag) = .{};
            while (try util.json.nextProgressiveFieldToEnum(source, AnyFieldTag, &pse)) : (pse = .{}) {
                const json_field_match: AnyFieldTag = pse.getMatch() orelse {
                    if (options.ignore_unknown_fields) continue;
                    return error.UnknownField;
                };

                if (!json_field_match.exclusiveTo(null)) {}
            }
        }

        const AnyFieldTag = enum {
            // exclusive to `Parameter`
            name,
            in,
            required,
            deprecated,
            allowEmptyValue,

            // exclusive to `Reference`
            ref,
            summary,
            description,

            // shared
            description,

            inline fn exclusiveTo(
                tag: AnyFieldTag,
                /// pass null to check if it's exclusive to either, such that
                /// false means it's shared, and true means it is exclusive
                maybe_which: ?@typeInfo(Param).Union.tag_type,
            ) bool {
                const ParameterJson = @TypeOf(Parameter.json_field_names);
                const ReferenceJson = @TypeOf(Reference.json_field_names);
                switch (tag) {
                    inline else => |itag| {
                        const field_name = @tagName(itag);
                        if (maybe_which) |which| switch (which) {
                            .parameter => {
                                if (!@hasField(ParameterJson, field_name)) return false;
                            },
                            .reference => {
                                if (!@hasField(ReferenceJson, field_name)) return false;
                            },
                        } else if (@hasField(ParameterJson, field_name) and @hasField(ReferenceJson, field_name)) {
                            return false;
                        }
                    },
                }
                return true;
            }

            comptime {
                const parameter_fields = @typeInfo(@TypeOf(Parameter.json_field_names)).Struct.fields;
                const reference_fields = @typeInfo(@TypeOf(Reference.json_field_names)).Struct.fields;

                for (parameter_fields ++ reference_fields) |field| {
                    if (@hasField(AnyFieldTag, field.name)) continue;
                    @compileError("Missing field '" ++ field.name ++ "'");
                }
            }
        };
    };

    pub const Operation = struct {
        tags: ?[]const []const u8 = null,
        summary: ?[]const u8 = null,
        description: ?[]const u8 = null,
        // externalDocs   External Documentation Object                     Additional external documentation for this operation.
        // operationId    string                                            Unique string used to identify the operation. The id MUST be unique among all operations described in the API. The operationId value is case-sensitive. Tools and libraries MAY use the operationId to uniquely identify an operation, therefore, it is RECOMMENDED to follow common programming naming conventions.
        // parameters     [Parameter Object | Reference Object]             A list of parameters that are applicable for this operation. If a parameter is already defined at the Path Item, the new definition will override it but can never remove it. The list MUST NOT include duplicated parameters. A unique parameter is defined by a combination of a name and location. The list can use the Reference Object to link to parameters that are defined at the OpenAPI Object’s components/parameters.
        // requestBody    Request Body Object | Reference Object            The request body applicable for this operation. The requestBody is fully supported in HTTP methods where the HTTP 1.1 specification [RFC7231] has explicitly defined semantics for request bodies. In other cases where the HTTP spec is vague (such as GET, HEAD and DELETE), requestBody is permitted but does not have well-defined semantics and SHOULD be avoided if possible.
        // responses      Responses Object                                  The list of possible responses as they are returned from executing this operation.
        // callbacks      Map[string, Callback Object | Reference Object]   A map of possible out-of band callbacks related to the parent operation. The key is a unique identifier for the Callback Object. Each value in the map is a Callback Object that describes a request that may be initiated by the API provider and the expected responses.
        // deprecated     boolean                                           Declares this operation to be deprecated. Consumers SHOULD refrain from usage of the declared operation. Default value is false.
        // security       [Security Requirement Object]                     A declaration of which security mechanisms can be used for this operation. The list of values includes alternative security requirement objects that can be used. Only one of the security requirement objects need to be satisfied to authorize a request. To make security optional, an empty security requirement ({}) can be included in the array. This definition overrides any declared top-level security. To remove a top-level security declaration, an empty array can be used.
        // servers        [Server Object]                                   An alternative server array to service this operation. If an alternative server object is specified at the Path Item Object or Root level, it will be overridden by this value.

        pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Operation, .{});
        pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Operation){};

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
            try schema_tools.jsonParseInPlaceTemplate(Operation, result, allocator, source, options, Operation.parseFieldValue);
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
                            try schema_tools.jsonParseReallocString(&new_str, src, json_opt);
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
                    try schema_tools.jsonParseReallocString(&str, src, json_opt);
                    field_ptr.* = try str.toOwnedSlice();
                },
            }
        }
    };
};

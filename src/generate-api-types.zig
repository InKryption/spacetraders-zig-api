const std = @import("std");
const assert = std.debug.assert;

const util = @import("util.zig");
const Params = @import("Params.zig");

const number_as_string_subst_decl_name = "NumberString";

pub fn main() !void {
    const log = std.log.default;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params: Params = try Params.parseCurrentProcess(allocator, .params);
    defer params.deinit(allocator);

    const output_file_unbuffered = try std.fs.cwd().createFile(params.output_path, .{});
    defer output_file_unbuffered.close();

    var output_file = std.io.bufferedWriter(output_file_unbuffered.writer());
    const output_writer = output_file.writer();
    defer util.attemptFlush(&output_file, .output, .{
        .max_retries = 3,
    });

    var models_dir_contents: util.DirectoryFilesContents = blk: {
        var models_dir = try std.fs.cwd().openIterableDir(params.models, .{});
        defer models_dir.close();
        var it = models_dir.iterateAssumeFirstIteration();

        break :blk try util.jsonDirectoryFilesContents(
            allocator,
            models_dir,
            &it,
            .@"collect-models",
        );
    };
    defer models_dir_contents.deinit(allocator);

    var models_arena = std.heap.ArenaAllocator.init(allocator);
    defer models_arena.deinit();

    var models_json = std.StringArrayHashMap(std.json.Value).init(allocator);
    defer models_json.deinit();
    try models_json.ensureUnusedCapacity(models_dir_contents.fileCount());

    { // populate models_json
        var parser = std.json.Parser.init(models_arena.allocator(), true);
        defer parser.deinit();

        var it = models_dir_contents.iterator();
        while (it.next()) |entry| {
            parser.reset();

            var value_tree = try parser.parse(entry.value);
            errdefer value_tree.deinit();

            const gop = models_json.getOrPutAssumeCapacity(entry.key);
            assert(!gop.found_existing);
            gop.value_ptr.* = value_tree.root;
        }
    }

    var required_set_buf = RequiredSet.init(allocator);
    defer required_set_buf.deinit();

    var struct_typedef_stack_buf = std.ArrayList(StructTypedefStackItem).init(allocator);
    defer struct_typedef_stack_buf.deinit();

    if (params.number_as_string) try output_writer.print(
        \\/// Represents a floating point number in string representation.
        \\pub const {s} = []const u8;
        \\
    , .{number_as_string_subst_decl_name});

    for (models_json.keys(), models_json.values()) |model_name, *value| {
        const model_basename = std.fs.path.stem(model_name);
        const obj: *const std.json.ObjectMap = &value.Object;

        const model_type = getTypeRecordFieldValue(obj) catch |err| {
            switch (err) {
                error.NotPresent => log.err("Top level model '{s}' missing field 'type'", .{model_name}),
                error.NotAString => log.err("Top level model '{s}' has a field 'type', which isn't a string", .{model_name}),
                error.UnrecognizedType => log.err("Top level model '{s}' has a field 'type' with an unrecognized value", .{model_name}),
            }
            continue;
        };

        try writeDescriptionAsCommentIfAvailable(output_writer, obj);
        try output_writer.print("pub const {s} = ", .{std.zig.fmtId(model_basename)});
        switch (model_type) {
            .object => try writeStructTypeDef(output_writer, obj, &struct_typedef_stack_buf, &required_set_buf, params.number_as_string, .default),
            .array => blk: {
                const nest_unwrapped_res = (try writeArrayNestingGetChild(output_writer, obj, .default)) orelse continue;
                const items_type = switch (nest_unwrapped_res.kind) {
                    .type => |data_type| data_type,
                    .model => |model_ref| {
                        try output_writer.writeAll(std.fs.path.stem(model_ref));
                        break :blk;
                    },
                };
                switch (items_type) {
                    .object => {
                        try struct_typedef_stack_buf.appendSlice(&.{
                            .{ .start = 0, .obj = nest_unwrapped_res.items },
                        });
                        continue;
                    },
                    .array => unreachable, // calling `writeArrayNestingGetChild` already handles nested array child types
                    .string => try output_writer.writeAll("u8"),
                    .integer => try writeIntegerTypeDef(output_writer, nest_unwrapped_res.items),
                    .number => try writeNumberTypeDef(output_writer, nest_unwrapped_res.items, params.number_as_string),
                    .boolean => try output_writer.writeAll("bool"),
                }
            },
            .string => {
                if (!obj.contains("enum")) log.warn(
                    "Top level model '{s}' of type 'string' missing expected field 'enum', and will be an alias for '[]const u8'",
                    .{model_name},
                );
                try writeStringTypeDef(output_writer, obj);
            },
            .integer => try writeIntegerTypeDef(output_writer, obj),
            .number => try writeNumberTypeDef(output_writer, obj, params.number_as_string),
            .boolean => {
                log.warn("Top level model '{s}' is of type 'boolean', and thus will be an alias for 'bool'", .{model_name});
                try output_writer.writeAll("bool");
            },
        }
        try output_writer.writeAll(";\n");
    }
}

const DataType = enum {
    object,
    array,
    string,
    integer,
    number,
    boolean,
};
const TypeOrModelRef = union(enum) {
    model: []const u8,
    type: DataType,
};
inline fn getTypeOrModelRef(
    type_record: *const std.json.ObjectMap,
    comptime log_scope: @TypeOf(.enum_literal),
) ?TypeOrModelRef {
    const log = std.log.scoped(log_scope);
    if (type_record.get("$ref")) |model_ref_path| {
        if (type_record.count() != 1) {
            log.warn("Property has both a '$ref' field and other fields", .{});
        }
        const ref = util.stripPrefix(u8, model_ref_path.String, "./") orelse return blk: {
            log.err("Expected relative path, got '{s}'.", .{model_ref_path.String});
            break :blk null;
        };
        return .{ .model = ref };
    }

    return .{ .type = getTypeRecordFieldValue(type_record) catch |err| {
        switch (err) {
            error.NotPresent => log.err("Property missing expected field 'type', and also has no '$ref' field", .{}),
            error.NotAString => log.err("Property has a field 'type' which is not a string", .{}),
            error.UnrecognizedType => log.err("Property has a field 'type' with an unrecognized value", .{}),
        }
        return null;
    } };
}

inline fn getTypeRecordFieldValue(
    type_record: *const std.json.ObjectMap,
) error{ NotPresent, NotAString, UnrecognizedType }!DataType {
    const untyped_value = type_record.get("type") orelse
        return error.NotPresent;
    const string_value = switch (untyped_value) {
        .String => |val| val,
        else => return error.NotAString,
    };
    return std.meta.stringToEnum(DataType, string_value) orelse
        error.UnrecognizedType;
}

inline fn getNestedArrayChildAndCountNesting(
    array_type_meta: *const std.json.ObjectMap,
    depth: *usize,
    comptime log_scope: @TypeOf(.enum_literal),
) ?*const std.json.ObjectMap {
    depth.* = 0;
    var current = array_type_meta;
    while (true) {
        const type_or_model = getTypeOrModelRef(current, log_scope) orelse return null;
        const data_type: DataType = switch (type_or_model) {
            .model => return current,
            .type => |data_type| data_type,
        };
        switch (data_type) {
            .array => {
                depth.* += 1;
                current = switch ((current.getPtr("items") orelse return null).*) {
                    .Object => |*next| next,
                    else => return null,
                };
            },
            .object,
            .string,
            .integer,
            .number,
            .boolean,
            => return current,
        }
    }
}

inline fn writeDescriptionAsCommentIfAvailable(out_writer: anytype, relevant_object: *const std.json.ObjectMap) !void {
    const desc = if (relevant_object.get("description")) |desc_val| desc_val.String else return;
    if (desc.len == 0) return;
    var line_it = std.mem.tokenize(u8, desc, "\r\n");
    while (line_it.next()) |line| {
        try out_writer.print("/// {s}\n", .{line});
    }
}

const StructTypedefStackItem = struct {
    start: usize,
    obj: *const std.json.ObjectMap,
};
const RequiredSetCtx = struct {
    pub fn hash(ctx: @This(), key: std.json.Value) u64 {
        _ = ctx;
        return std.hash_map.hashString(key.String);
    }
    pub fn eql(ctx: @This(), a: std.json.Value, b: std.json.Value) bool {
        _ = ctx;
        return std.hash_map.eqlString(a.String, b.String);
    }
};

inline fn writeArrayNestingGetChild(
    output_writer: anytype,
    array_type_meta: *const std.json.ObjectMap,
    comptime log_scope: @TypeOf(.enum_literal),
) !?struct {
    items: *const std.json.ObjectMap,
    kind: TypeOrModelRef,
} {
    const log = std.log.scoped(log_scope);

    var depth: usize = 0;
    const nested_items_record = getNestedArrayChildAndCountNesting(array_type_meta, &depth, log_scope) orelse {
        log.err("Array type missing valid 'items' field", .{});
        return null;
    };
    assert(depth > 0);

    const items_kind = getTypeOrModelRef(nested_items_record, log_scope) orelse return null;
    for (0..depth) |_| try output_writer.writeAll("[]const ");
    return .{
        .items = nested_items_record,
        .kind = items_kind,
    };
}

const RequiredSet = std.HashMap(std.json.Value, void, RequiredSetCtx, std.hash_map.default_max_load_percentage);
inline fn writeStructTypeDef(
    output_writer: anytype,
    record_type_meta: *const std.json.ObjectMap,
    struct_typedef_stack_buf: *std.ArrayList(StructTypedefStackItem),
    required_set_buf: *RequiredSet,
    number_as_string: bool,
    comptime log_scope: @TypeOf(.enum_literal),
) !void {
    const log = std.log.scoped(log_scope);

    try struct_typedef_stack_buf.append(.{
        .start = 0,
        .obj = record_type_meta,
    });

    mainloop: while (struct_typedef_stack_buf.popOrNull()) |stack_item| {
        const start: usize = stack_item.start;
        const current_obj: *const std.json.ObjectMap = stack_item.obj;
        const properties_obj: *const std.json.ObjectMap = if (current_obj.getPtr("properties")) |val| &val.Object else {
            log.err("'object' missing expected field 'properties'", .{});
            return;
        };

        required_set_buf.clearRetainingCapacity();
        if (current_obj.get("required")) |list_val| {
            for (list_val.Array.items) |val| {
                try required_set_buf.putNoClobber(val, {});
            }
        }

        if (start == 0) try output_writer.writeAll("struct {");
        if (properties_obj.count() - start > 0) try output_writer.writeAll("\n");

        for (properties_obj.keys()[start..], properties_obj.values()[start..], start..) |prop_name, *prop_val, i| {
            if (i != 0) try output_writer.writeAll(",\n");

            const prop: *const std.json.ObjectMap = &prop_val.Object;
            const prop_type = if (getTypeOrModelRef(prop, .default)) |kind| switch (kind) {
                .type => |prop_type| prop_type,
                .model => |model_ref| {
                    try output_writer.print("    {s}: {s}{s}", .{
                        std.zig.fmtId(prop_name),
                        if (!required_set_buf.contains(.{ .String = prop_name })) "?" else "",
                        std.zig.fmtId(std.fs.path.stem(model_ref)),
                    });
                    continue;
                },
            } else {
                log.err("Property '{s}' missing expected field 'type', and also has no '$ref' field.", .{prop_name});
                continue;
            };

            if (prop_type == .object) {
                try writeDescriptionAsCommentIfAvailable(output_writer, prop);
            }
            try output_writer.print("    {s}: ", .{std.zig.fmtId(prop_name)});

            if (!required_set_buf.contains(std.json.Value{ .String = prop_name })) {
                try output_writer.writeAll("?");
            }
            switch (prop_type) {
                .object => {
                    try struct_typedef_stack_buf.appendSlice(&.{
                        .{ .start = i + 1, .obj = current_obj },
                        .{ .start = 0, .obj = prop },
                    });
                    continue :mainloop;
                },
                .array => {
                    const nest_unwrapped_res = (try writeArrayNestingGetChild(output_writer, prop, log_scope)) orelse continue;
                    const items_type = switch (nest_unwrapped_res.kind) {
                        .type => |data_type| data_type,
                        .model => |model_ref| {
                            try output_writer.writeAll(std.fs.path.stem(model_ref));
                            continue;
                        },
                    };
                    switch (items_type) {
                        .object => {
                            try struct_typedef_stack_buf.appendSlice(&.{
                                .{ .start = i + 1, .obj = current_obj },
                                .{ .start = 0, .obj = nest_unwrapped_res.items },
                            });
                            continue :mainloop;
                        },
                        .array => unreachable, // calling `writeArrayNestingGetChild` already handles nested array child types
                        .string => try output_writer.writeAll("u8"),
                        .integer => try writeIntegerTypeDef(output_writer, nest_unwrapped_res.items),
                        .number => try writeNumberTypeDef(output_writer, nest_unwrapped_res.items, number_as_string),
                        .boolean => try output_writer.writeAll("bool"),
                    }
                },
                .string => try writeStringTypeDef(output_writer, prop),
                .integer => try writeIntegerTypeDef(output_writer, prop),
                .number => try writeNumberTypeDef(output_writer, prop, number_as_string),
                .boolean => try output_writer.writeAll("bool"),
            }

            if (prop.get("default")) |default_val| {
                switch (prop_type) {
                    .object, .array => |tag| log.err(
                        "Default value '{}' for type '{s}' unhandled",
                        .{ util.fmtJson(default_val, .{}), @tagName(tag) },
                    ),
                    .string => |tag| switch (default_val) {
                        .String => |val| try output_writer.print(" = \"{s}\"", .{val}),
                        else => log.err(
                            "Can't convert '{s}' to '{s}'",
                            .{ @tagName(default_val), @tagName(tag) },
                        ),
                    },
                    .integer,
                    .number,
                    => |tag| switch (default_val) {
                        .NumberString => |val| try output_writer.print(" = {s}", .{val}),
                        .Integer => |val| try output_writer.print(" = {d}", .{val}),
                        .Float => |val| try output_writer.print(" = {d}", .{val}),
                        else => log.err(
                            "Can't convert '{s}' to '{s}'",
                            .{ @tagName(default_val), @tagName(tag) },
                        ),
                    },
                    .boolean => |tag| switch (default_val) {
                        .Bool => |val| try output_writer.print(" = {}", .{val}),
                        else => log.err(
                            "Can't convert '{s}' to '{s}'",
                            .{ @tagName(default_val), @tagName(tag) },
                        ),
                    },
                }
            }
        }
        if (properties_obj.count() > 0) {
            try output_writer.writeAll(",\n");
        }
        try output_writer.writeAll("}");
    }
}

inline fn writeStringTypeDef(out_writer: anytype, string_type_meta: *const std.json.ObjectMap) !void {
    assert(std.mem.eql(u8, string_type_meta.get("type").?.String, "string"));
    const enum_list: []const std.json.Value = if (string_type_meta.get("enum")) |val| val.Array.items else {
        try out_writer.writeAll("[]const u8");
        return;
    };
    try out_writer.writeAll("enum {\n");
    for (enum_list) |val| {
        try out_writer.print("    {s},\n", .{val.String});
    }
    try out_writer.writeAll("}");
}

inline fn writeIntegerTypeDef(out_writer: anytype, int_type_meta: *const std.json.ObjectMap) !void {
    assert(std.mem.eql(u8, int_type_meta.get("type").?.String, "integer"));
    try out_writer.writeAll("i64");
}

inline fn writeNumberTypeDef(out_writer: anytype, num_type_meta: *const std.json.ObjectMap, num_as_string: bool) !void {
    assert(std.mem.eql(u8, num_type_meta.get("type").?.String, "number"));
    if (num_as_string) {
        try out_writer.writeAll(number_as_string_subst_decl_name);
    } else {
        try out_writer.writeAll("f64");
    }
}

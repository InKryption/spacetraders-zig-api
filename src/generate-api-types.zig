const std = @import("std");
const assert = std.debug.assert;

const Params = struct {
    models: []const u8,
    output_path: []const u8,
    number_as_string: bool,

    const ParamId = enum {
        @"num-as-string",
        models,
        @"output-path",

        inline fn isFlag(id: ParamId) bool {
            return switch (id) {
                .models,
                .@"output-path",
                => false,
                .@"num-as-string" => true,
            };
        }
    };

    pub fn deinit(params: Params, ally: std.mem.Allocator) void {
        ally.free(params.output_path);
        ally.free(params.models);
    }

    pub fn parseCurrentProcess(
        allocator: std.mem.Allocator,
        comptime log_scope: @TypeOf(.enum_literal),
    ) (ParseError || error{EmptyArgv})!Params {
        var argv = try std.process.argsWithAllocator(allocator);
        defer argv.deinit();
        if (!argv.skip()) return error.EmptyArgv;
        return try Params.parse(allocator, log_scope, &argv);
    }

    pub const ParseError = std.mem.Allocator.Error || error{
        MissingDashDashPrefix,
        UnrecognizedParameterName,
        MissingArgumentValue,
        InvalidParameterFlagValue,
        MissingArgument,
    };

    pub fn parse(
        allocator: std.mem.Allocator,
        comptime log_scope: @TypeOf(.enum_literal),
        argv: anytype,
    ) ParseError!Params {
        const log = std.log.scoped(log_scope);

        var results: struct {
            models: ?[]const u8 = null,
            @"output-path": ?[]const u8 = null,
            @"num-as-string": ?bool = null,
        } = .{};

        while (true) {
            var maybe_next_tok: ?[]const u8 = null;
            const id: Params.ParamId = id: {
                const str = std.mem.trim(u8, argv.next() orelse break, &std.ascii.whitespace);
                const maybe_name = util.stripPrefix(u8, str, "--") orelse {
                    log.err("Expected parameter id preceeded by '--', found '{s}'", .{str});
                    return error.MissingDashDashPrefix;
                };
                const name: []const u8 = if (std.mem.indexOfScalar(u8, maybe_name, '=')) |eql_idx| name: {
                    const next_tok = std.mem.trim(u8, maybe_name[eql_idx + 1 ..], &std.ascii.whitespace);
                    if (next_tok.len != 0) {
                        maybe_next_tok = next_tok;
                    }
                    break :name maybe_name[0..eql_idx];
                } else maybe_name;

                break :id std.meta.stringToEnum(Params.ParamId, name) orelse {
                    log.err("Unrecognized parameter name '{s}'", .{str});
                    return error.UnrecognizedParameterName;
                };
            };
            const next_tok: []const u8 = if (maybe_next_tok) |next_tok|
                std.mem.trim(u8, next_tok, &std.ascii.whitespace)
            else if (argv.next()) |next_tok| next_tok else blk: {
                if (id.isFlag()) break :blk "true";
                log.err("Expected value for parameter '{s}'", .{@tagName(id)});
                return error.MissingArgumentValue;
            };
            switch (id) {
                inline //
                .models,
                .@"output-path",
                => |tag| {
                    const field_ptr = &@field(results, @tagName(tag));
                    const new_slice = try allocator.realloc(@constCast(field_ptr.* orelse ""), next_tok.len);
                    @memcpy(new_slice, next_tok);
                    field_ptr.* = new_slice;
                },
                .@"num-as-string" => |tag| {
                    const bool_tag = std.meta.stringToEnum(enum { false, true }, next_tok) orelse {
                        log.err("Expected '{s}' to be a boolean, instead got '{s}'.", .{ @tagName(tag), next_tok });
                        return error.InvalidParameterFlagValue;
                    };
                    results.@"num-as-string" = switch (bool_tag) {
                        .false => false,
                        .true => true,
                    };
                },
            }
        }

        return Params{
            .models = results.models orelse {
                log.err("Missing argument 'models'.", .{});
                return error.MissingArgument;
            },
            .output_path = results.@"output-path" orelse {
                log.err("Missing argument 'output-path'.", .{});
                return error.MissingArgument;
            },
            .number_as_string = results.@"num-as-string" orelse false,
        };
    }
};

const number_as_string_subst_decl_name = "NumberString";

pub fn main() !void {
    const log = std.log.default;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params: Params = try Params.parseCurrentProcess(allocator, .params);
    defer params.deinit(allocator);

    const output_file_unbuffered = try std.fs.createFileAbsolute(params.output_path, .{});
    defer output_file_unbuffered.close();

    var output_file = std.io.bufferedWriter(output_file_unbuffered.writer());
    const output_writer = output_file.writer();
    defer {
        const max_retries = 3;
        for (0..max_retries) |_| {
            output_file.flush() catch |err| {
                log.warn("{s}, failed to flush output", .{@errorName(err)});
                continue;
            };
            break;
        } else log.err("Failed to flush output after {d} attempts", .{max_retries});
    }

    var json_contents_buffer = std.ArrayList(u8).init(allocator);
    defer json_contents_buffer.deinit();

    var json_content_map = std.StringArrayHashMap(struct { usize, usize }).init(allocator);
    defer for (json_content_map.keys()) |key| {
        allocator.free(key);
    } else json_content_map.deinit();

    { // collect models file contents
        var models_dir = try std.fs.openIterableDirAbsolute(params.models, .{});
        defer models_dir.close();

        var it = models_dir.iterateAssumeFirstIteration();
        while (try it.next()) |entry| {
            switch (entry.kind) {
                .File => {},

                .BlockDevice,
                .CharacterDevice,
                .Directory,
                .NamedPipe,
                .SymLink,
                .UnixDomainSocket,
                .Whiteout,
                .Door,
                .EventPort,
                .Unknown,
                => |tag| {
                    log.err("Unhandled file kind '{s}'.", .{@tagName(tag)});
                },
            }

            const ext = std.fs.path.extension(entry.name);
            if (!std.mem.eql(u8, ext, ".json")) continue;

            const gop = try json_content_map.getOrPut(entry.name);
            if (gop.found_existing) {
                log.err("Encountered '{s}' more than once", .{entry.name});
                continue;
            }
            errdefer assert(json_content_map.swapRemove(entry.name));

            const name = try allocator.dupe(u8, entry.name);
            errdefer allocator.free(name);
            gop.key_ptr.* = name; // safe, because they will have the same hash (same string content)

            const file = try models_dir.dir.openFile(name, .{});
            defer file.close();

            const start = json_contents_buffer.items.len;
            try file.reader().readAllArrayList(&json_contents_buffer, 1 << 21);
            const end = json_contents_buffer.items.len;
            gop.value_ptr.* = .{ start, end };
        }
    }

    var models_arena = std.heap.ArenaAllocator.init(allocator);
    defer models_arena.deinit();

    var models_json = std.StringArrayHashMap(std.json.Value).init(allocator);
    defer models_json.deinit();
    try models_json.ensureUnusedCapacity(json_content_map.count());

    { // populate models_json
        var parser = std.json.Parser.init(models_arena.allocator(), false);
        defer parser.deinit();

        for (json_content_map.keys(), json_content_map.values()) |key, value| {
            parser.reset();
            const gop = try models_json.getOrPut(key);
            assert(!gop.found_existing);
            errdefer assert(models_json.swapRemove(key));
            const contents = json_contents_buffer.items[value[0]..value[1]];
            const value_tree = try parser.parse(contents);
            gop.value_ptr.* = value_tree.root;
        }
    }

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

    const RequiredSet = std.HashMap(std.json.Value, void, RequiredSetCtx, std.hash_map.default_max_load_percentage);
    var required_set_buf = RequiredSet.init(allocator);
    defer required_set_buf.deinit();

    const StructTypedefStackItem = struct {
        start: usize,
        obj: *const std.json.ObjectMap,
    };
    var struct_typedef_stack_buf = std.ArrayList(StructTypedefStackItem).init(allocator);
    defer struct_typedef_stack_buf.deinit();

    if (params.number_as_string) {
        try output_writer.print(
            \\/// Represents a floating point number in string representation.
            \\pub const {s} = []const u8;
            \\
        , .{number_as_string_subst_decl_name});
    }

    for (models_json.keys(), @as([]const std.json.Value, models_json.values())) |model_name, *value| {
        const model_basename = std.fs.path.stem(model_name);
        const obj: *const std.json.ObjectMap = &value.Object;

        const model_type_str = if (obj.get("type")) |val| val.String else {
            log.err("Model '{s}' missing field 'type'", .{model_name});
            continue;
        };
        const model_type = std.meta.stringToEnum(DataType, model_type_str) orelse {
            log.err("Model '{s}' has unexpected type '{s}'", .{ model_name, model_type_str });
            continue;
        };

        try writeDescriptionAsCommentIfAvailable(output_writer, obj);
        try output_writer.print("pub const {s} = ", .{std.zig.fmtId(model_basename)});
        switch (model_type) {
            .object => {
                try struct_typedef_stack_buf.append(.{
                    .start = 0,
                    .obj = obj,
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

                    prop_loop: for (properties_obj.keys()[start..], properties_obj.values()[start..], start..) |prop_name, *prop_val, i| {
                        if (i != 0) try output_writer.writeAll(",\n");

                        const prop: *const std.json.ObjectMap = &prop_val.Object;
                        const prop_type = switch (typeOrModelRef(prop, .default) orelse {
                            log.err("Property '{s}' missing expected field 'type', and also has no '$ref' field.", .{prop_name});
                            continue;
                        }) {
                            .type => |prop_type| prop_type,
                            .model => |model_ref| {
                                try output_writer.print("    {s}: {s}{s}", .{
                                    std.zig.fmtId(prop_name),
                                    if (!required_set_buf.contains(.{ .String = prop_name })) "?" else "",
                                    std.zig.fmtId(std.fs.path.stem(model_ref)),
                                });
                                continue;
                            },
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
                                const items_val = prop.getPtr("items") orelse {
                                    log.err("array missing expected field 'items'", .{});
                                    try output_writer.writeAll("@compileError(\"unresolved array type\")");
                                    continue;
                                };
                                var items: *const std.json.ObjectMap = &items_val.Object;

                                while (true) {
                                    const items_type = switch (typeOrModelRef(items, .default) orelse {
                                        log.err("Property '{s}' missing expected field 'type', and also has no '$ref' field.", .{prop_name});
                                        continue :prop_loop;
                                    }) {
                                        .type => |items_type| items_type,
                                        .model => |model_ref| {
                                            try output_writer.print(
                                                "[]const {s}",
                                                .{std.zig.fmtId(std.fs.path.stem(model_ref))},
                                            );
                                            continue :prop_loop;
                                        },
                                    };
                                    try output_writer.writeAll("[]const ");
                                    switch (items_type) {
                                        .object => {
                                            try struct_typedef_stack_buf.appendSlice(&.{
                                                .{ .start = i + 1, .obj = current_obj },
                                                .{ .start = 0, .obj = items },
                                            });
                                            continue :mainloop;
                                        },
                                        .array => {
                                            const sub_items_val = items.getPtr("items") orelse {
                                                log.err("array missing expected field 'items'", .{});
                                                try output_writer.writeAll("@compileError(\"unresolved array type\")");
                                                continue :prop_loop;
                                            };
                                            items = &sub_items_val.Object;
                                            continue;
                                        },
                                        .string => try output_writer.writeAll("u8"),
                                        .integer => try writeIntegerTypeDef(output_writer, items),
                                        .number => try writeNumberTypeDef(output_writer, prop, params.number_as_string),
                                        .boolean => try output_writer.writeAll("bool"),
                                    }
                                    break;
                                }
                            },
                            .string => try writeStringTypeDef(output_writer, prop),
                            .integer => try writeIntegerTypeDef(output_writer, prop),
                            .number => try writeNumberTypeDef(output_writer, prop, params.number_as_string),
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
            },
            .string => {
                if (!obj.contains("enum")) {
                    log.warn("Model '{s}' of type 'string' missing expected field 'enum'", .{model_name});
                }
                try writeStringTypeDef(output_writer, obj);
            },
            .integer => try writeIntegerTypeDef(output_writer, obj),
            .number => try writeNumberTypeDef(output_writer, obj, params.number_as_string),
            .array, // <- TODO: would have to move the code just above this in the 'object' branch into a function to do this correctly. but that's going to be very annoying
            .boolean,
            => |tag| log.err(
                "Top level model '{s}' has unexpected type '{s}'.",
                .{ model_name, @tagName(tag) },
            ),
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
inline fn typeOrModelRef(type_record: *const std.json.ObjectMap, comptime log_scope: @TypeOf(.enum_literal)) ?TypeOrModelRef {
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
    const prop_type_str: []const u8 = if (type_record.get("type")) |type_val|
        type_val.String
    else
        return null;
    const prop_type = std.meta.stringToEnum(DataType, prop_type_str) orelse return null;
    return .{ .type = prop_type };
}

inline fn writeDescriptionAsCommentIfAvailable(out_writer: anytype, relevant_object: *const std.json.ObjectMap) !void {
    const desc = if (relevant_object.get("description")) |desc_val| desc_val.String else return;
    if (desc.len == 0) return;
    var line_it = std.mem.tokenize(u8, desc, "\r\n");
    while (line_it.next()) |line| {
        try out_writer.print("/// {s}\n", .{line});
    }
}

inline fn writeStringTypeDef(out_writer: anytype, string_type_meta: *const std.json.ObjectMap) !void {
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
    _ = int_type_meta;
    // log.info("int meta: {}", .{fmtJson(.{ .Object = int_type_meta.* }, .{})});
    try out_writer.writeAll("i64");
}

inline fn writeNumberTypeDef(out_writer: anytype, num_type_meta: *const std.json.ObjectMap, num_as_string: bool) !void {
    _ = num_type_meta;
    if (num_as_string) {
        try out_writer.writeAll(number_as_string_subst_decl_name);
    } else {
        try out_writer.writeAll("f64");
    }
}

const util = struct {
    inline fn stripPrefix(comptime T: type, str: []const u8, prefix: []const T) ?[]const u8 {
        if (!std.mem.startsWith(T, str, prefix)) return null;
        return str[prefix.len..];
    }

    inline fn fmtJson(value: std.json.Value, options: std.json.StringifyOptions) FmtJson {
        return .{
            .value = value,
            .options = options,
        };
    }
    const FmtJson = struct {
        value: std.json.Value,
        options: std.json.StringifyOptions,

        pub fn format(
            self: FmtJson,
            comptime fmt_str: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) @TypeOf(writer).Error!void {
            _ = options;
            if (fmt_str.len != 0) std.fmt.invalidFmtError(fmt_str, self);
            try self.value.jsonStringify(self.options, writer);
        }
    };
};

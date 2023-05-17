const std = @import("std");
const assert = std.debug.assert;

const util = @import("util.zig");
const Params = @import("Params.zig");

const number_as_string_subst_decl_name = "NumberString";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params: Params = try Params.parseCurrentProcess(allocator, .params);
    defer params.deinit(allocator);

    const output_file = try std.fs.cwd().createFile(params.output_path, .{});
    defer output_file.close();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();

    const out_writer = output_buffer.writer();
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

    if (params.number_as_string) try out_writer.print(
        \\/// Represents a floating point number in string representation.
        \\pub const {s} = []const u8;
        \\
    , .{number_as_string_subst_decl_name});

    var render_stack = std.ArrayList(RenderStackCmd).init(allocator);
    defer for (render_stack.items) |item| switch (item) {
        inline .type_decl => |decl| allocator.free(decl.name),
        else => {},
    } else render_stack.deinit();

    for (models_json.keys(), models_json.values()) |model_name, *value| {
        const model_basename = std.fs.path.stem(model_name);
        const json_obj: *const JsonObj = &value.Object;

        render_stack.clearRetainingCapacity();
        try render_stack.append(.{ .type_decl = .{
            .name = try allocator.dupe(u8, model_basename),
            .json_obj = json_obj,
        } });
        try renderApiType(allocator, out_writer, &render_stack, params.number_as_string, true);
    }

    // null terminator needed for formatting
    try out_writer.writeByte('\x00');

    var ast = try std.zig.Ast.parse(allocator, output_buffer.items[0 .. output_buffer.items.len - 1 :0], .zig);
    defer ast.deinit(allocator);

    if (ast.errors.len > 0) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll(output_buffer.items);
        for (ast.errors) |ast_error| {
            const location = ast.tokenLocation(0, ast_error.token);
            try stderr.print("location: {}\n", .{location});
            try stderr.print("snippet: '{s}'\n", .{output_buffer.items[location.line_start..location.line_end]});
            try ast.renderError(ast_error, stderr);
            try stderr.writeByte('\n');
        }

        return error.InternalCodeGen;
    }

    const formatted = try ast.render(allocator);
    defer allocator.free(formatted);

    try output_file.writer().writeAll(formatted);
}

const JsonObj = std.json.ObjectMap;

const DataType = enum {
    object,
    array,
    string,
    number,
    integer,
    boolean,
};

const RenderStackCmd = union(enum) {
    type_decl: TypeDecl,
    type_decl_end,
    obj_def: *const JsonObj,
    obj_def_end,

    const TypeDecl = struct {
        name: []const u8,
        json_obj: *const JsonObj,
    };
};

const RenderApiTypeError = error{
    ObjectMissingPropertiesField,
    NonObjectPropertiesField,
    NonArrayItemsField,
    NonArrayEnumField,
    NonStringEnumFieldElement,
    TooManyRequiredFields,
    NonObjectProperty,
    DefaultValueTypeMismatch,
} || std.mem.Allocator.Error ||
    GetRefFieldValueError ||
    GetTypeFieldValueError ||
    GetNestedArrayChildError ||
    WriteDescriptionAsCommentIfAvailableError;

fn renderApiType(
    allocator: std.mem.Allocator,
    out_writer: anytype,
    render_stack: *std.ArrayList(RenderStackCmd),
    number_as_string: bool,
    comptime print_json_as_comment: bool,
) (@TypeOf(out_writer).Error || RenderApiTypeError)!void {
    var json_comment_buf = if (print_json_as_comment) std.ArrayList(u8).init(allocator);
    defer if (print_json_as_comment) json_comment_buf.deinit();

    while (true) {
        const current: RenderStackCmd = render_stack.popOrNull() orelse return;
        switch (current) {
            .type_decl => |decl| {
                defer allocator.free(decl.name);

                if (print_json_as_comment) {
                    json_comment_buf.clearRetainingCapacity();
                    try json_comment_buf.writer().print("{}", .{util.fmtJson(
                        .{ .Object = decl.json_obj.* },
                        std.json.StringifyOptions{ .whitespace = .{ .indent = .Tab } },
                    )});
                    try util.writePrefixedLines(out_writer, "\n// ", json_comment_buf.items);
                    try out_writer.writeAll("\n");
                }

                try writeDescriptionAsCommentIfAvailable(out_writer, decl.json_obj);
                try out_writer.print("pub const {s} = ", .{std.zig.fmtId(decl.name)});

                assert((getRefFieldValue(decl.json_obj) catch unreachable) == null); // I believe there's no logic that would lead to this
                switch (try getTypeFieldValue(decl.json_obj)) {
                    .object => {
                        try render_stack.append(.type_decl_end);
                        try render_stack.append(.{ .obj_def = decl.json_obj });
                        continue;
                    },
                    .array => @panic("TODO: consider top level array type aliases"),
                    inline //
                    .string,
                    .number,
                    .integer,
                    .boolean,
                    => |tag| try writeSimpleType(out_writer, tag, decl.json_obj, number_as_string),
                }
                try out_writer.writeAll(";\n\n");
            },
            .type_decl_end => try out_writer.writeAll(";\n\n"),

            .obj_def => |obj| {
                try out_writer.writeAll("struct {\n");
                render_stack.appendAssumeCapacity(.obj_def_end); // we just popped so we can assume there's capacity

                const properties: *const JsonObj = if (obj.getPtr("properties")) |val| switch (val.*) {
                    .Object => |*properties| properties,
                    else => return error.NonObjectPropertiesField,
                } else return error.ObjectMissingPropertiesField;

                const required: []const std.json.Value = if (obj.get("required")) |val| switch (val) {
                    .Array => |array| array.items,
                    else => return error.NonArrayItemsField,
                } else &.{};

                if (properties.count() < required.len) {
                    return error.TooManyRequiredFields;
                }

                try render_stack.ensureUnusedCapacity(properties.count());
                const prop_cmd_insert_start = render_stack.items.len;

                for (properties.keys(), properties.values()) |prop_name, *prop_val| {
                    const prop: *const JsonObj = switch (prop_val.*) {
                        .Object => |*prop| prop,
                        else => return error.NonObjectProperty,
                    };
                    const default_val = prop.get("default");

                    const is_required = for (required) |req| {
                        if (std.mem.eql(u8, prop_name, req.String)) break true;
                    } else false;

                    if (try getRefFieldValue(prop)) |ref| {
                        try writeDescriptionAsCommentIfAvailable(out_writer, prop);
                        const name = modelRefToName(ref);

                        if (default_val != null) { // TODO: hate. how would I even implement this as-is. Probably need to make the model json data accessible here
                            std.log.err("Encountered default value for $ref'd field", .{});
                        }

                        try out_writer.print("{s}: {s}{s},\n", .{
                            std.zig.fmtId(prop_name),
                            if (is_required) "" else "?",
                            std.zig.fmtId(name),
                        });
                        continue;
                    }

                    const data_type = try getTypeFieldValue(prop);

                    switch (data_type) {
                        .object => {},

                        .number,
                        .integer,
                        .boolean,
                        .array,
                        => try writeDescriptionAsCommentIfAvailable(out_writer, prop),

                        .string => if (!prop.contains("enum")) {
                            try writeDescriptionAsCommentIfAvailable(out_writer, prop);
                        },
                    }

                    try out_writer.print("{s}: ", .{std.zig.fmtId(prop_name)});
                    if (!is_required) try out_writer.writeAll("?");
                    switch (data_type) {
                        .object => {
                            const new_decl_name = try std.mem.concat(allocator, u8, &.{
                                &[1]u8{std.ascii.toUpper(prop_name[0])},
                                prop_name[1..],
                            });
                            errdefer allocator.free(new_decl_name);

                            render_stack.insertAssumeCapacity(prop_cmd_insert_start, .{ .type_decl = .{
                                .name = new_decl_name,
                                .json_obj = prop,
                            } });

                            try out_writer.print("{s}", .{std.zig.fmtId(new_decl_name)});
                            // TODO: implement this?
                            if (default_val != null) {
                                std.log.err("Encountered default value for object", .{});
                            }
                        },
                        .array => {
                            var depth: usize = 0;
                            const items = try getNestedArrayChild(prop, &depth);
                            try out_writer.writeAll("[]const ");
                            for (0..depth) |_| try out_writer.writeAll("[]const ");

                            if (try getRefFieldValue(items)) |ref| {
                                const name = modelRefToName(ref);
                                try out_writer.print("{s},\n", .{std.zig.fmtId(name)});
                                continue;
                            }

                            const new_decl_name = try std.mem.concat(allocator, u8, &.{
                                &[1]u8{std.ascii.toUpper(prop_name[0])},
                                prop_name[1..],
                                "Item",
                            });
                            errdefer allocator.free(new_decl_name);

                            render_stack.appendAssumeCapacity(.{ .type_decl = .{
                                .name = new_decl_name,
                                .json_obj = items,
                            } });
                            try out_writer.print("{s}", .{std.zig.fmtId(new_decl_name)});
                        },
                        .string => {
                            const enum_list_val = prop.get("enum") orelse {
                                try out_writer.writeAll("[]const u8");
                                if (default_val) |val| switch (val) {
                                    .String => |str| try out_writer.print(" = \"{s}\"", .{str}),
                                    else => return error.DefaultValueTypeMismatch,
                                };
                                try out_writer.writeAll(",\n");
                                continue;
                            };
                            const enum_list: []const std.json.Value = switch (enum_list_val) {
                                .Array => |array| array.items,
                                else => return error.NonArrayEnumField,
                            };
                            for (enum_list) |val| {
                                if (val != .String) {
                                    return error.NonStringEnumFieldElement;
                                }
                            }

                            const new_decl_name = try std.mem.concat(allocator, u8, &.{
                                &[1]u8{std.ascii.toUpper(prop_name[0])},
                                prop_name[1..],
                            });
                            errdefer allocator.free(new_decl_name);

                            render_stack.appendAssumeCapacity(.{ .type_decl = .{
                                .name = new_decl_name,
                                .json_obj = prop,
                            } });

                            try out_writer.print("{s}", .{std.zig.fmtId(new_decl_name)});

                            if (default_val) |val| switch (val) {
                                .String => |str| for (enum_list) |enum_val| {
                                    if (!std.mem.eql(u8, enum_val.String, str)) continue;
                                    try out_writer.print(" = .{s}", .{std.zig.fmtId(str)});
                                    break;
                                } else return error.DefaultValueTypeMismatch,
                                else => return error.DefaultValueTypeMismatch,
                            };
                        },
                        inline .number, .integer, .boolean => |tag| {
                            try writeSimpleType(out_writer, tag, prop, number_as_string);

                            if (default_val) |val| {
                                switch (tag) {
                                    .number, .integer => switch (val) {
                                        .Integer => |int_val| try out_writer.print(" = {d}", .{int_val}),
                                        .Float => |float_val| try out_writer.print(" = {d}", .{float_val}),
                                        .NumberString => |num_str_val| try out_writer.print(" = {s}", .{num_str_val}),
                                        else => return error.DefaultValueTypeMismatch,
                                    },
                                    .boolean => switch (val) {
                                        .Bool => |bool_val| try out_writer.print(" = {}", .{bool_val}),
                                        else => return error.DefaultValueTypeMismatch,
                                    },
                                    else => comptime unreachable,
                                }
                            }
                        },
                    }
                    try out_writer.writeAll(",\n");
                }
            },

            .obj_def_end => try out_writer.writeAll("}"),
        }
    }
}

fn writeSimpleType(
    out_writer: anytype,
    comptime tag: DataType,
    json_obj: *const JsonObj,
    number_as_string: bool,
) !void {
    switch (tag) {
        .string => {
            const enum_list_val = json_obj.get("enum") orelse {
                try out_writer.writeAll("[]const u8");
                return;
            };
            const enum_list: []const std.json.Value = switch (enum_list_val) {
                .Array => |array| array.items,
                else => return error.NonArrayEnumField,
            };
            try out_writer.writeAll("enum {\n");
            for (enum_list) |val| {
                const str = switch (val) {
                    .String => |str| str,
                    else => return error.NonStringEnumFieldElement,
                };
                try out_writer.print("{s},\n", .{std.zig.fmtId(str)});
            }
            try out_writer.writeAll("}");
        },
        .number => {
            // TODO: handle other parts of number information (min/max/format)
            if (number_as_string) {
                try out_writer.writeAll(number_as_string_subst_decl_name);
            } else {
                try out_writer.writeAll("f64");
            }
        },
        .integer => {
            // TODO: handle other parts of integer information (min/max/format)
            try out_writer.writeAll("i64");
        },
        .boolean => {
            // TODO: are there edge cases to this?
            try out_writer.writeAll("bool");
        },
        else => comptime unreachable,
    }
}

inline fn modelRefToName(ref: []const u8) []const u8 {
    const file_name = util.stripPrefix(u8, ref, "./") orelse ref;
    return std.fs.path.stem(file_name);
}

const GetRefFieldValueError = error{
    NotAlone,
    NotAString,
};
fn getRefFieldValue(json_obj: *const JsonObj) GetRefFieldValueError!?[]const u8 {
    const val = json_obj.get("$ref") orelse return null;
    if (json_obj.count() != 1) return error.NotAlone;
    const str = switch (val) {
        .String => |str| str,
        else => return error.NotAString,
    };
    return str;
}

const GetTypeFieldValueError = error{
    NotPresent,
    NotAString,
    UnrecognizedType,
};
fn getTypeFieldValue(json_obj: *const JsonObj) GetTypeFieldValueError!DataType {
    const untyped_value = json_obj.get("type") orelse
        return error.NotPresent;
    const string_value = switch (untyped_value) {
        .String => |val| val,
        else => return error.NotAString,
    };
    return std.meta.stringToEnum(DataType, string_value) orelse
        error.UnrecognizedType;
}

const GetNestedArrayChildError = error{
    NoItemsField,
    NonObjectItemsField,
} || GetRefFieldValueError || GetTypeFieldValueError;
fn getNestedArrayChild(json_obj: *const JsonObj, depth: *usize) GetNestedArrayChildError!*const JsonObj {
    depth.* = 0;

    var current = json_obj;
    while (true) {
        const items = if (current.getPtr("items")) |val| switch (val.*) {
            .Object => |*obj| obj,
            else => return error.NonObjectItemsField,
        } else return error.NoItemsField;

        if ((try getRefFieldValue(items)) != null) {
            return items;
        }
        switch (try getTypeFieldValue(items)) {
            .array => {
                depth.* += 1;
                current = items;
            },
            .object,
            .string,
            .integer,
            .number,
            .boolean,
            => return items,
        }
    }
}

const WriteDescriptionAsCommentIfAvailableError = error{
    NonStringDescriptionValue,
} || GetRefFieldValueError;
inline fn writeDescriptionAsCommentIfAvailable(
    out_writer: anytype,
    json_obj: *const JsonObj,
) (@TypeOf(out_writer).Error || WriteDescriptionAsCommentIfAvailableError)!void {
    if ((try getRefFieldValue(json_obj)) != null) return;
    const desc_val = json_obj.get("description") orelse return;
    const desc = switch (desc_val) {
        .String => |str| str,
        else => return error.NonStringDescriptionValue,
    };
    if (desc.len == 0) return;
    try util.writePrefixedLines(out_writer, "/// ", desc);
    try out_writer.writeAll("\n");
}

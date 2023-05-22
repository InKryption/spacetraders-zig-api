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

    const apidocs_path: []const u8 = params.apidocs_path orelse return error.MissingModelsParam;
    const output_path: []const u8 = params.output_path orelse return error.MissingOutputPathParam;
    const number_as_string: bool = params.number_as_string;
    const json_as_comment: bool = params.json_as_comment;

    const output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();

    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();

    var apidocs_dir = try std.fs.cwd().openDir(apidocs_path, .{});
    defer apidocs_dir.close();

    const out_writer = output_buffer.writer();

    var render_stack = std.ArrayList(RenderStackCmd).init(allocator);
    defer for (render_stack.items) |item| switch (item) {
        .type_decl => |decl| allocator.free(decl.name),
        else => {},
    } else render_stack.deinit();

    var json_comment_buf = std.ArrayList(u8).init(allocator);
    defer json_comment_buf.deinit();

    { // write model types
        try out_writer.writeAll("pub const models = struct {\n");

        var models_dir_contents: util.DirectoryFilesContents = blk: {
            var models_dir = try apidocs_dir.openIterableDir("models", .{});
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
            var parser = std.json.Parser.init(models_arena.allocator(), .alloc_if_needed);
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

        if (number_as_string) try out_writer.print(
            \\/// Represents a floating point number in string representation.
            \\pub const {s} = []const u8;
            \\
        , .{number_as_string_subst_decl_name});

        for (models_json.keys(), models_json.values()) |model_name, *value| {
            const json_obj: *const JsonObj = &value.object;

            const model_basename = try allocator.dupe(u8, std.fs.path.stem(model_name));
            errdefer allocator.free(model_basename);

            render_stack.clearRetainingCapacity();
            try render_stack.append(.{ .type_decl = .{
                .name = model_basename,
                .json_obj = json_obj,
            } });
            try renderApiType(out_writer, .{
                .allocator = allocator,
                .render_stack = &render_stack,
                .number_as_string = number_as_string,
                .json_comment_buf = if (json_as_comment) &json_comment_buf else null,
            });
        }

        try out_writer.writeAll("};\n\n");
    }

    { // write reference
        try out_writer.writeAll("pub const ref = struct {\n");

        const ref_json_content = try apidocs_dir.readFileAlloc(allocator, "reference/SpaceTraders.json", 1 << 21);
        defer allocator.free(ref_json_content);

        var parser = std.json.Parser.init(allocator, .alloc_if_needed);
        defer parser.deinit();

        var ref_json_root = try parser.parse(ref_json_content);
        defer ref_json_root.deinit();

        const ref_obj: *const JsonObj = switch (ref_json_root.root) {
            .object => |*object| object,
            else => return error.NonObjectReferenceFile,
        };

        const paths_obj: *const JsonObj = try (try getObjField(ref_obj, "paths", .object, null) orelse error.MissingPathsField);

        var operation_id_buf = std.ArrayList(u8).init(allocator);
        defer operation_id_buf.deinit();

        const TopLevelParam = struct {
            description: ?[]const u8,
            in: []const u8,
            name: []const u8,
            required: bool,
            schema: *const JsonObj,
        };

        var top_level_params_buf = std.ArrayList(TopLevelParam).init(allocator);
        defer top_level_params_buf.deinit();

        var zig_fmt_path_buf = std.ArrayList(u8).init(allocator);
        defer zig_fmt_path_buf.deinit();

        for (paths_obj.keys(), paths_obj.values()) |path, *path_info_val| {
            const path_info: *const JsonObj = switch (path_info_val.*) {
                .object => |*object| object,
                else => return error.NonObjectPathField,
            };

            { // path parameters and stuff
                const top_parameters: []const std.json.Value = if (try getObjField(path_info, "parameters", .array, null)) |array| array.items else &.{};
                top_level_params_buf.clearRetainingCapacity();
                try top_level_params_buf.ensureUnusedCapacity(top_parameters.len);
                for (top_parameters) |*top_param_val| {
                    const top_param: *const JsonObj = switch (top_param_val.*) {
                        .object => |*object| object,
                        else => return error.NonObjectTopParam,
                    };

                    if (top_param.count() != @typeInfo(TopLevelParam).Struct.fields.len - @boolToInt(!top_param.contains("description"))) {
                        return error.UnhandledFields;
                    }

                    top_level_params_buf.appendAssumeCapacity(.{
                        .description = try getObjField(top_param, "description", .string, null),
                        .in = (try getObjField(top_param, "in", .string, null)) orelse return error.MissingInParamField,
                        .name = (try getObjField(top_param, "name", .string, null)) orelse return error.MissingNameParamField,
                        .required = (try getObjField(top_param, "required", .bool, null)) orelse return error.MissingRequiredParamField,
                        .schema = (try getObjField(top_param, "schema", .object, null)) orelse return error.MissingSchemaParamField,
                    });
                }

                zig_fmt_path_buf.clearRetainingCapacity();
                var path_iter = std.mem.tokenize(u8, path, "/");
                while (path_iter.next()) |component| {
                    assert(component.len >= 1);
                    try zig_fmt_path_buf.append('/');
                    if (!std.mem.startsWith(u8, component, "{")) {
                        try zig_fmt_path_buf.appendSlice(component);
                        continue;
                    }
                    if (!std.mem.endsWith(u8, component, "}")) {
                        std.log.err("Unclosed brace in path '{s}'", .{path});
                        return error.UnclosedBraceInPath;
                    }
                    const param_name = component[1 .. component.len - 1];

                    try zig_fmt_path_buf.appendSlice("{[");
                    try zig_fmt_path_buf.appendSlice(param_name);
                    try zig_fmt_path_buf.appendSlice("]s}"); // assume string parameter

                    const param: TopLevelParam = for (top_level_params_buf.items) |param| {
                        if (std.mem.eql(u8, param.name, param_name)) break param;
                    } else {
                        std.log.err("Found substitution '{s}' in path '{s}' which is not defined as a parameter", .{ param_name, path });
                        return error.UnboundSubstitutionInPath;
                    };
                    if (!std.mem.eql(u8, param.in, "path")) {
                        return error.NonPathTopLevelParameter;
                    }

                    const data_type = try getTypeFieldValue(param.schema);
                    if (data_type != .string) {
                        return error.NonStringPathParameter;
                    }
                }
            }

            inline for (@typeInfo(std.http.Method).Enum.fields) |method_field| {
                cont: { // <- just a hack to get around not being able to do runtime 'continue'
                    const lowercase: []const u8 = comptime blk: {
                        var lowercase = method_field.name[0..].*;
                        break :blk std.ascii.lowerString(&lowercase, &lowercase);
                    };
                    const path_method_info: *const JsonObj = try getObjField(path_info, lowercase, .object, null) orelse break :cont;
                    const operation_id: []const u8 = try (try getObjField(path_method_info, "operationId", .string, null) orelse error.PathMethodMissingOperationId);
                    const method_parameters: []const std.json.Value = if (try getObjField(path_method_info, "parameters", .array, null)) |array| array.items else &.{};
                    _ = method_parameters;

                    operation_id_buf.clearRetainingCapacity();
                    try operation_id_buf.appendSlice(operation_id);
                    std.mem.replaceScalar(u8, operation_id_buf.items, '-', '_');
                    const op_name: []const u8 = operation_id_buf.items;

                    if (json_as_comment) {
                        try out_writer.writeAll("// ```\n");
                        try writeJsonAsComment(out_writer, path_method_info, "// ", &json_comment_buf);
                        try out_writer.writeAll("// ```\n");
                    }

                    if (try getObjField(path_method_info, "summary", .string, null)) |summary| {
                        try util.writeLinesSurrounded(out_writer, "/// ", summary, "\n");
                        try out_writer.writeAll("///\n");
                    }
                    try writeStringFieldAsCommentIfAvailable(out_writer, path_method_info, "description");
                    try out_writer.print("pub const {s} = struct {{\n", .{std.zig.fmtId(op_name)});
                    try out_writer.print("    pub const method = .{s};\n", .{std.zig.fmtId(method_field.name)});
                    try out_writer.print("    pub const path_fmt = \"{}\";\n", .{std.zig.fmtEscapes(zig_fmt_path_buf.items)});

                    try out_writer.writeAll("    pub const PathParams = struct {");
                    render_stack.clearRetainingCapacity();
                    for (top_level_params_buf.items) |param| {
                        const type_name = try std.mem.concat(allocator, u8, &.{ &.{std.ascii.toUpper(param.name[0])}, param.name[1..] });
                        errdefer allocator.free(type_name);
                        try render_stack.append(RenderStackCmd{ .type_decl = .{
                            .name = type_name,
                            .json_obj = param.schema,
                        } });
                        try out_writer.print("        {s}: {s},\n", .{ std.zig.fmtId(param.name), std.zig.fmtId(type_name) });
                    }
                    try out_writer.writeAll("\n");
                    try renderApiType(out_writer, .{
                        .allocator = allocator,
                        .render_stack = &render_stack,
                        .number_as_string = number_as_string,
                        .json_comment_buf = null,
                    });
                    try out_writer.writeAll("    };\n\n");

                    const maybe_request_body: ?*const JsonObj = try getObjField(path_method_info, "requestBody", .object, null);

                    if (maybe_request_body) |request_body| {
                        try writeStringFieldAsCommentIfAvailable(out_writer, request_body, "description");
                        const schema = try getContentApplicationJsonSchema(request_body);

                        render_stack.clearRetainingCapacity();
                        try render_stack.append(RenderStackCmd{ .type_decl = .{
                            .name = try allocator.dupe(u8, "RequestBody"),
                            .json_obj = schema,
                        } });

                        try renderApiType(out_writer, .{
                            .allocator = allocator,
                            .render_stack = &render_stack,
                            .number_as_string = number_as_string,
                            .json_comment_buf = null,
                        });
                    } else {
                        try out_writer.writeAll("        pub const RequestBody = struct {};\n");
                    }

                    try out_writer.writeAll("        pub const responses = struct {\n");

                    const responses: *const JsonObj = try (try getObjField(path_method_info, "responses", .object, null) orelse error.NoResponses);

                    for (responses.keys(), responses.values()) |response_code_str, *response_info_val| {
                        const response_info: *const JsonObj = switch (response_info_val.*) {
                            .object => |*object| object,
                            else => return error.NonObjectResponseField,
                        };

                        const response_code_int = std.fmt.parseInt(u32, response_code_str, 10) catch |err| {
                            std.log.err("{s}, couldn't parse '{s}' response code value", .{ @errorName(err), response_code_str });
                            return err;
                        };
                        const HttpStatus = std.http.Status;
                        const response_code = try std.meta.intToEnum(HttpStatus, response_code_int);

                        switch (response_code) {
                            .ok,
                            .created,
                            => |tag| {
                                render_stack.clearRetainingCapacity();
                                try render_stack.append(RenderStackCmd{ .type_decl = .{
                                    .name = try allocator.dupe(u8, @tagName(tag)),
                                    .json_obj = try getContentApplicationJsonSchema(response_info),
                                } });
                                try renderApiType(out_writer, .{
                                    .allocator = allocator,
                                    .render_stack = &render_stack,
                                    .number_as_string = number_as_string,
                                    .json_comment_buf = null,
                                });
                            },
                            .no_content => |tag| try out_writer.print("pub const {s} = void;\n\n", .{@tagName(tag)}),
                            else => |tag| {
                                std.log.err("Unhandled HTTP status '{s}' ({d})", .{ @tagName(tag), @enumToInt(tag) });
                                return error.UnhandledHttpStatus;
                            },
                        }
                    }
                    try out_writer.writeAll("        };\n\n");

                    try out_writer.writeAll("    };\n\n");
                }
            }
        }

        try out_writer.writeAll("};\n\n");
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
    NonObjectPropertiesFieldValue,
    NonArrayRequiredFieldValue,
    NonArrayEnumField,
    NonStringEnumFieldElement,
    TooManyRequiredFields,
    NonObjectProperty,
    DefaultValueTypeMismatch,
} || std.mem.Allocator.Error ||
    GetRefFieldValueError ||
    GetTypeFieldValueError ||
    GetNestedArrayChildError ||
    WriteStringFieldAsCommentIfAvailableError ||
    WriteRefPathAsZigNamespaceAccessError;

fn writeJsonAsComment(
    out_writer: anytype,
    json_obj: *const JsonObj,
    comment_prefix: []const u8,
    json_comment_buf: *std.ArrayList(u8),
) !void {
    json_comment_buf.clearRetainingCapacity();
    try json_comment_buf.writer().print("{}", .{util.fmtJson(
        .{ .object = json_obj.* },
        std.json.StringifyOptions{ .whitespace = .{ .indent = .{ .space = 4 } } },
    )});
    try util.writeLinesSurrounded(out_writer, comment_prefix, json_comment_buf.items, "\n");
}

fn renderApiType(
    out_writer: anytype,
    params: struct {
        allocator: std.mem.Allocator,
        render_stack: *std.ArrayList(RenderStackCmd),
        number_as_string: bool,
        json_comment_buf: ?*std.ArrayList(u8),
    },
) (@TypeOf(out_writer).Error || RenderApiTypeError)!void {
    const allocator = params.allocator;
    const render_stack = params.render_stack;
    const number_as_string = params.number_as_string;
    var maybe_json_comment_buf = params.json_comment_buf;

    while (true) {
        const current: RenderStackCmd = render_stack.popOrNull() orelse return;
        switch (current) {
            .type_decl => |decl| {
                defer allocator.free(decl.name);

                if (maybe_json_comment_buf) |json_comment_buf| {
                    try out_writer.writeAll("// ```\n");
                    try writeJsonAsComment(out_writer, decl.json_obj, "// ", json_comment_buf);
                    try out_writer.writeAll("// ```\n");
                    maybe_json_comment_buf = null;
                }

                try writeStringFieldAsCommentIfAvailable(out_writer, decl.json_obj, "description");
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

                const properties: *const JsonObj = try (try getObjField(obj, "properties", .object, null) orelse error.ObjectMissingPropertiesField);
                const required: []const std.json.Value = if (try getObjField(obj, "required", .array, null)) |array| array.items else &.{};

                if (properties.count() < required.len) {
                    return error.TooManyRequiredFields;
                }

                try render_stack.ensureUnusedCapacity(properties.count());
                const prop_cmd_insert_start = render_stack.items.len;

                for (properties.keys(), properties.values()) |prop_name, *prop_val| {
                    const prop: *const JsonObj = switch (prop_val.*) {
                        .object => |*prop| prop,
                        else => return error.NonObjectProperty,
                    };
                    const default_val = prop.get("default");

                    const is_required = for (required) |req| {
                        if (std.mem.eql(u8, prop_name, req.string)) break true;
                    } else false;

                    if (try getRefFieldValue(prop)) |ref| {
                        try writeStringFieldAsCommentIfAvailable(out_writer, prop, "description");

                        try out_writer.print("{s}: ", .{std.zig.fmtId(prop_name)});
                        if (!is_required) try out_writer.writeAll("?");
                        try writeRefPathAsZigNamespaceAccess(out_writer, ref);

                        if (default_val != null) { // TODO: hate. how would I even implement this as-is. Probably need to make the model json data accessible here
                            std.log.err("Encountered default value for $ref'd field", .{});
                        }

                        try out_writer.writeAll(",\n");
                        continue;
                    }

                    const data_type = try getTypeFieldValue(prop);

                    switch (data_type) {
                        .object => {},

                        .number,
                        .integer,
                        .boolean,
                        .array,
                        => try writeStringFieldAsCommentIfAvailable(out_writer, prop, "description"),

                        .string => if (!prop.contains("enum")) {
                            try writeStringFieldAsCommentIfAvailable(out_writer, prop, "description");
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

                            try out_writer.print("{s}", .{std.zig.fmtId(new_decl_name)});

                            if (default_val != null) {
                                std.log.err("Encountered default value for object", .{});
                            }

                            render_stack.insertAssumeCapacity(prop_cmd_insert_start, .{ .type_decl = .{
                                .name = new_decl_name,
                                .json_obj = prop,
                            } });
                        },
                        .array => {
                            var depth: usize = 0;
                            const items = try getNestedArrayChild(prop, &depth);
                            try out_writer.writeAll("[]const ");
                            for (0..depth) |_| try out_writer.writeAll("[]const ");

                            if (try getRefFieldValue(items)) |ref| {
                                try writeRefPathAsZigNamespaceAccess(out_writer, ref);
                                try out_writer.writeAll(",\n");
                                continue;
                            }

                            const new_decl_name = try std.mem.concat(allocator, u8, &.{
                                &[1]u8{std.ascii.toUpper(prop_name[0])},
                                prop_name[1..],
                                "Item",
                            });
                            errdefer allocator.free(new_decl_name);

                            try out_writer.print("{s}", .{std.zig.fmtId(new_decl_name)});

                            if (default_val != null) {
                                std.log.err("Encountered default value for array", .{});
                            }

                            render_stack.appendAssumeCapacity(.{ .type_decl = .{
                                .name = new_decl_name,
                                .json_obj = items,
                            } });
                        },
                        .string => {
                            const enum_list_val = prop.get("enum") orelse {
                                try out_writer.writeAll("[]const u8");
                                if (default_val) |val| switch (val) {
                                    .string => |str| try out_writer.print(" = \"{s}\"", .{str}),
                                    else => return error.DefaultValueTypeMismatch,
                                };
                                try out_writer.writeAll(",\n");
                                continue;
                            };
                            const enum_list: []const std.json.Value = switch (enum_list_val) {
                                .array => |array| array.items,
                                else => return error.NonArrayEnumField,
                            };
                            for (enum_list) |val| if (val != .string) {
                                return error.NonStringEnumFieldElement;
                            };

                            const new_decl_name = try std.mem.concat(allocator, u8, &.{
                                &[1]u8{std.ascii.toUpper(prop_name[0])},
                                prop_name[1..],
                            });
                            errdefer allocator.free(new_decl_name);

                            try out_writer.print("{s}", .{std.zig.fmtId(new_decl_name)});

                            render_stack.appendAssumeCapacity(.{ .type_decl = .{
                                .name = new_decl_name,
                                .json_obj = prop,
                            } });

                            if (default_val) |val| switch (val) {
                                .string => |str| for (enum_list) |enum_val| {
                                    if (!std.mem.eql(u8, enum_val.string, str)) continue;
                                    try out_writer.print(" = .{s}", .{std.zig.fmtId(str)});
                                    break;
                                } else return error.DefaultValueTypeMismatch,
                                else => return error.DefaultValueTypeMismatch,
                            };
                        },
                        inline .number, .integer, .boolean => |tag| {
                            try writeSimpleType(out_writer, tag, prop, number_as_string);
                            if (default_val) |val| switch (tag) {
                                .number, .integer => switch (val) {
                                    .integer => |int_val| try out_writer.print(" = {d}", .{int_val}),
                                    .float => |float_val| try out_writer.print(" = {d}", .{float_val}),
                                    .number_string => |num_str_val| try out_writer.print(" = {s}", .{num_str_val}),
                                    else => return error.DefaultValueTypeMismatch,
                                },
                                .boolean => switch (val) {
                                    .bool => |bool_val| try out_writer.print(" = {}", .{bool_val}),
                                    else => return error.DefaultValueTypeMismatch,
                                },
                                else => comptime unreachable,
                            };
                        },
                    }
                    try out_writer.writeAll(",\n");
                }

                try out_writer.writeAll("\n");
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
                .array => |array| array.items,
                else => return error.NonArrayEnumField,
            };
            try out_writer.writeAll("enum {\n");
            for (enum_list) |val| {
                const str = switch (val) {
                    .string => |str| str,
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

const WriteRefPathAsZigNamespaceAccessError = error{EmptyRefPath};
fn writeRefPathAsZigNamespaceAccess(out_writer: anytype, ref: []const u8) !void {
    var iter = std.mem.tokenize(u8, ref, "\\/");
    const first_component: []const u8 = while (iter.next()) |first| {
        if (std.mem.eql(u8, first, ".")) continue;
        if (std.mem.eql(u8, first, "..")) continue;
        break first;
    } else return error.EmptyRefPath;

    try out_writer.print("{s}", .{std.zig.fmtId(std.fs.path.stem(first_component))});
    while (iter.next()) |component| {
        try out_writer.print(".{s}", .{std.zig.fmtId(std.fs.path.stem(component))});
    }
}

const GetRefFieldValueError = error{
    NotAlone,
    NotAString,
};
fn getRefFieldValue(json_obj: *const JsonObj) GetRefFieldValueError!?[]const u8 {
    const val = json_obj.get("$ref") orelse return null;
    if (json_obj.count() != 1) return error.NotAlone;
    const str = switch (val) {
        .string => |str| str,
        else => return error.NotAString,
    };
    return str;
}

const GetTypeFieldValueError = error{
    NotPresent,
    NotAString,
    UnrecognizedType,
};
/// NOTE: returns `.string` if `json_obj` contains
/// an 'enum' field.
fn getTypeFieldValue(json_obj: *const JsonObj) GetTypeFieldValueError!DataType {
    const untyped_value = json_obj.get("type") orelse {
        if (json_obj.contains("enum")) {
            return .string;
        }
        return error.NotPresent;
    };
    const string_value = switch (untyped_value) {
        .string => |val| val,
        else => return error.NotAString,
    };
    return std.meta.stringToEnum(DataType, string_value) orelse
        error.UnrecognizedType;
}

const GetNestedArrayChildError = error{
    NoItemsField,
    NonObjectItemsFieldValue,
} || GetRefFieldValueError || GetTypeFieldValueError;
fn getNestedArrayChild(json_obj: *const JsonObj, depth: *usize) GetNestedArrayChildError!*const JsonObj {
    depth.* = 0;

    var current = json_obj;
    while (true) {
        const items = try (try getObjField(current, "items", .object, null) orelse error.NoItemsField);
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

const WriteStringFieldAsCommentIfAvailableError = error{
    NonStringFieldValue,
} || GetRefFieldValueError;
inline fn writeStringFieldAsCommentIfAvailable(
    out_writer: anytype,
    json_obj: *const JsonObj,
    field: []const u8,
) (@TypeOf(out_writer).Error || WriteStringFieldAsCommentIfAvailableError)!void {
    const desc_val = json_obj.get(field) orelse return;
    const desc = switch (desc_val) {
        .string => |str| str,
        else => return error.NonStringFieldValue,
    };
    if (desc.len == 0) return;
    try util.writeLinesSurrounded(out_writer, "/// ", desc, "\n");
}

const GetContentApplicationJsonSchemaError = error{
    MissingContentField,
    NonObjectContentFieldValue,

    MissingApplicationJsonField,
    @"NonObject'application/json'FieldValue",

    MissingSchemaField,
    NonObjectSchemaFieldValue,
};
/// returns the equivalent of `json_obj["content"]["application/json"]["schema"]`
fn getContentApplicationJsonSchema(json_obj: *const JsonObj) !*const JsonObj {
    const content: *const JsonObj = try (try getObjField(json_obj, "content", .object, null) orelse error.MissingContentField);
    const application_json: *const JsonObj = try (try getObjField(
        content,
        "application/json",
        .object,
        "'application/json'",
    ) orelse error.MissingApplicationJsonField);
    return try getObjField(application_json, "schema", .object, null) orelse error.MissingSchemaField;
}

inline fn getFieldTagMismatchErrorName(comptime tag: @typeInfo(std.json.Value).Union.tag_type.?) []const u8 {
    comptime return switch (tag) {
        .null => "NonNullFieldValue",
        .bool => "NonBoolFieldValue",
        .integer => "NonIntegerFieldValue",
        .float => "NonFloatFieldValue",
        .number_string => "NonNumberStringFieldValue",
        .string => "NonStringFieldValue",
        .array => "NonArrayFieldValue",
        .object => "NonObjectFieldValue",
    };
}

inline fn getObjField(
    json_obj: *const JsonObj,
    comptime name: []const u8,
    comptime tag: @typeInfo(std.json.Value).Union.tag_type.?,
    comptime name_in_err: ?[]const u8,
) !?switch (tag) {
    .null => void,
    .bool => bool,
    .integer => i64,
    .float => f64,
    .number_string => []const u8,
    .string => []const u8,
    .array => *const std.ArrayList(std.json.Value),
    .object => *const JsonObj,
} {
    const ptr = json_obj.getPtr(name) orelse return null;
    if (ptr.* != tag) {
        const subject = comptime name_in_err orelse &[_]u8{std.ascii.toUpper(name[0])} ++ name[1..];
        return comptime @field(anyerror, switch (tag) {
            .null => "NonNull" ++ subject ++ "FieldValue",
            .bool => "NonBool" ++ subject ++ "FieldValue",
            .integer => "NonInteger" ++ subject ++ "FieldValue",
            .float => "NonFloat" ++ subject ++ "FieldValue",
            .number_string => "NonNumberString" ++ subject ++ "FieldValue",
            .string => "NonString" ++ subject ++ "FieldValue",
            .array => "NonArray" ++ subject ++ "FieldValue",
            .object => "NonObject" ++ subject ++ "FieldValue",
        });
    }
    const field_ptr = &@field(ptr, @tagName(tag));
    return switch (tag) {
        .null,
        .bool,
        .integer,
        .float,
        .number_string,
        .string,
        => field_ptr.*,
        .array,
        .object,
        => field_ptr,
    };
}

const std = @import("std");
const assert = std.debug.assert;

const util = @import("util.zig");
const Params = @import("Params.zig");

const NumberFormat = @import("number-format.zig").NumberFormat;
const number_format_subst_decl_name = "Number";

var runtime_log_level: std.log.Level = .debug;

pub const std_options = struct {
    pub const log_level: std.log.Level = .debug;
    pub fn logFn(
        comptime msg_level: std.log.Level,
        comptime scope: @TypeOf(.enum_literal),
        comptime fmt_str: []const u8,
        args: anytype,
    ) void {
        if (@enumToInt(msg_level) <= @enumToInt(runtime_log_level)) {
            std.log.defaultLog(msg_level, scope, fmt_str, args);
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params: Params = try Params.parseCurrentProcess(allocator, .params);
    defer params.deinit(allocator);

    runtime_log_level = params.log_level orelse return error.MissingLogLevelParam; // set log level before first log
    std.log.debug(
        \\parameters: {{
        \\    .apidocs_path = "{?s}",
        \\    .output_path = "{?s}",
        \\    .number_format = {s},
        \\    .json_as_comment = {?},
        \\    .log_level = {s},
        \\}}
    , .{
        params.apidocs_path,
        params.output_path,
        if (params.number_format) |nfmt| switch (nfmt) {
            inline else => |tag| "." ++ @tagName(tag),
        } else "null",
        params.json_as_comment,
        if (params.log_level) |ll| switch (ll) {
            inline else => |tag| "." ++ @tagName(tag),
        } else "null",
    });

    const apidocs_path: []const u8 = params.apidocs_path orelse return error.MissingModelsParam;
    const output_path: []const u8 = params.output_path orelse return error.MissingOutputPathParam;
    const number_format: NumberFormat = params.number_format orelse return error.MissingNumberFormatParam;
    const json_as_comment: bool = params.json_as_comment orelse return error.MissingJsonAsCommentParam;

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

    try out_writer.print(
        \\/// Represents a floating point number.
        \\pub const Number = {s};
        \\
        \\
    , .{switch (number_format) {
        .number_string => "[]const u8",
        .f128, .f64 => |tag| @tagName(tag),
    }});

    var required_model_refs = std.BufSet.init(allocator);
    defer required_model_refs.deinit();

    // this should only be used in loops, and reset every iteration.
    var loop_arena_state = std.heap.ArenaAllocator.init(allocator);
    defer loop_arena_state.deinit();
    const loop_arena = loop_arena_state.allocator();

    var json_parser = std.json.Parser.init(allocator, .alloc_if_needed);
    defer json_parser.deinit();

    { // write reference
        try out_writer.writeAll("pub const ref = struct {\n");

        const ref_json_content = try apidocs_dir.readFileAlloc(allocator, "reference/SpaceTraders.json", 1 << 21);
        defer allocator.free(ref_json_content);

        var ref_json_root = try json_parser.parse(ref_json_content);
        defer ref_json_root.deinit();

        const ref_obj: *const JsonObj = switch (ref_json_root.root) {
            .object => |*object| object,
            else => return error.NonObjectReferenceFile,
        };

        const paths_obj: *const JsonObj = try (try getObjField(ref_obj, "paths", .object, null) orelse error.MissingPathsField);

        const TopLevelParam = struct {
            description: ?[]const u8,
            in: []const u8,
            name: []const u8,
            required: bool,
            schema: *const JsonObj,
        };

        for (paths_obj.keys(), paths_obj.values()) |path, *path_info_val| {
            for (0..3) |_| if (loop_arena_state.reset(.retain_capacity)) break;

            const path_info: *const JsonObj = switch (path_info_val.*) {
                .object => |*object| object,
                else => return error.NonObjectPathField,
            };

            const top_params: []const TopLevelParam = blk: {
                const top_parameters: []const std.json.Value = if (try getObjField(path_info, "parameters", .array, null)) |array| array.items else &.{};
                const top_params: []TopLevelParam = try loop_arena.alloc(TopLevelParam, top_parameters.len);
                errdefer loop_arena.free(top_params);

                for (top_params, top_parameters) |*param, *parameter_val| {
                    const parameter: *const JsonObj = switch (parameter_val.*) {
                        .object => |*object| object,
                        else => return error.NonObjectTopParam,
                    };

                    if (parameter.count() != @typeInfo(TopLevelParam).Struct.fields.len - @boolToInt(!parameter.contains("description"))) {
                        return error.UnhandledFields;
                    }

                    param.* = .{
                        .description = try getObjField(parameter, "description", .string, null),
                        .in = (try getObjField(parameter, "in", .string, null)) orelse return error.MissingInParamField,
                        .name = (try getObjField(parameter, "name", .string, null)) orelse return error.MissingNameParamField,
                        .required = (try getObjField(parameter, "required", .bool, null)) orelse return error.MissingRequiredParamField,
                        .schema = (try getObjField(parameter, "schema", .object, null)) orelse return error.MissingSchemaParamField,
                    };
                }

                break :blk top_params;
            };
            defer loop_arena.free(top_params);

            const zig_fmt_path: []const u8 = blk: {
                var zig_fmt_path = std.ArrayList(u8).init(loop_arena);
                defer zig_fmt_path.deinit();

                var path_iter = std.mem.tokenize(u8, path, "/");
                while (path_iter.next()) |component| {
                    assert(component.len >= 1);
                    try zig_fmt_path.append('/');
                    if (!std.mem.startsWith(u8, component, "{")) {
                        try zig_fmt_path.appendSlice(component);
                        continue;
                    }
                    if (!std.mem.endsWith(u8, component, "}")) {
                        std.log.err("Unclosed brace in path '{s}'", .{path});
                        return error.UnclosedBraceInPath;
                    }
                    const param_name = component[1 .. component.len - 1];

                    try zig_fmt_path.appendSlice("{[");
                    try zig_fmt_path.appendSlice(param_name);
                    try zig_fmt_path.appendSlice("]}");

                    const param: TopLevelParam = for (top_params) |param| {
                        if (std.mem.eql(u8, param.name, param_name)) break param;
                    } else {
                        std.log.err("Found substitution '{s}' in path '{s}' which is not defined as a parameter", .{ param_name, path });
                        return error.UnboundSubstitutionInPath;
                    };
                    if (!std.mem.eql(u8, param.in, "path")) {
                        return error.NonPathTopLevelParameter;
                    }
                    if (!param.required) {
                        return error.OptionalPathParameter;
                    }

                    const data_type = try getTypeFieldValue(param.schema);
                    if (data_type != .string) {
                        return error.NonStringPathParameter;
                    }
                }

                if (zig_fmt_path.items.len == 0) {
                    try zig_fmt_path.append('/');
                }

                break :blk try zig_fmt_path.toOwnedSlice();
            };
            defer loop_arena.free(zig_fmt_path);

            inline for (@typeInfo(std.http.Method).Enum.fields) |method_field| {
                cont: { // <- just a hack to get around not being able to do runtime 'continue'
                    const lowercase: []const u8 = comptime blk: {
                        var lowercase = method_field.name[0..].*;
                        break :blk std.ascii.lowerString(&lowercase, &lowercase);
                    };
                    const path_method_info: *const JsonObj = try getObjField(path_info, lowercase, .object, null) orelse break :cont;
                    const operation_id: []const u8 = try (try getObjField(path_method_info, "operationId", .string, null) orelse error.PathMethodMissingOperationId);

                    // TODO: deduplicate this from `TopLevelParam` somehow? Or at least
                    // make a function that deduplicates the below procedure
                    const MethodParam = struct {
                        description: ?[]const u8,
                        in: []const u8,
                        name: []const u8,
                        schema: *const JsonObj,
                    };

                    // TODO: generate code representing method parameters (long over-due)
                    const method_params: []const MethodParam = blk: {
                        const method_parameters: []const std.json.Value = if (try getObjField(path_method_info, "parameters", .array, null)) |array| array.items else &.{};
                        const method_params: []MethodParam = try loop_arena.alloc(MethodParam, method_parameters.len);
                        errdefer loop_arena.free(method_params);

                        for (method_params, method_parameters) |*param, *parameter_val| {
                            const parameter: *const JsonObj = switch (parameter_val.*) {
                                .object => |*object| object,
                                else => return error.NonObjectTopParam,
                            };

                            if (parameter.count() != @typeInfo(MethodParam).Struct.fields.len - @boolToInt(!parameter.contains("description"))) {
                                return error.UnhandledFields;
                            }

                            param.* = .{
                                .description = try getObjField(parameter, "description", .string, null),
                                .in = (try getObjField(parameter, "in", .string, null)) orelse return error.MissingInParamField,
                                .name = (try getObjField(parameter, "name", .string, null)) orelse return error.MissingNameParamField,
                                .schema = (try getObjField(parameter, "schema", .object, null)) orelse return error.MissingSchemaParamField,
                            };
                        }

                        break :blk method_params;
                    };
                    defer loop_arena.free(method_params);

                    const op_name: []const u8 = blk: {
                        const op_name = try loop_arena.dupe(u8, operation_id);
                        errdefer loop_arena.free(op_name);
                        std.mem.replaceScalar(u8, op_name, '-', '_');
                        break :blk op_name;
                    };
                    defer loop_arena.free(op_name);

                    if (json_as_comment) {
                        try out_writer.writeAll("// ```\n");
                        try writeJsonAsComment(out_writer, .{ .object = path_method_info.* }, "// ", &json_comment_buf);
                        try out_writer.writeAll("// ```\n");
                    }

                    if (try getObjField(path_method_info, "summary", .string, null)) |summary| {
                        try util.writeLinesSurrounded(out_writer, "/// ", summary, "\n");
                    }
                    if (try getObjField(path_method_info, "description", .string, null)) |desc| {
                        if (path_method_info.contains("summary"))
                            try out_writer.writeAll("///\n");
                        try util.writeLinesSurrounded(out_writer, "/// ", desc, "\n");
                    }
                    try out_writer.print("pub const {s} = struct {{\n", .{std.zig.fmtId(op_name)});
                    try out_writer.print("    pub const method = .{s};\n", .{std.zig.fmtId(method_field.name)});
                    try out_writer.print("    pub const path_fmt = \"{}\";\n", .{std.zig.fmtEscapes(zig_fmt_path)});

                    const maybe_request_body: ?*const JsonObj = try getObjField(path_method_info, "requestBody", .object, null);
                    const empty_request_body_str = "        pub const RequestBody = struct {};\n";
                    if (maybe_request_body) |request_body| blk: {
                        if (try getObjField(request_body, "description", .string, null)) |desc| {
                            try util.writeLinesSurrounded(out_writer, "/// ", desc, "\n");
                        }

                        const schema = try getContentApplicationJsonSchema(request_body);
                        if (schema.count() == 0) {
                            std.log.warn("Encountered empty RequestBody schema inside path '{s}'. Outputting as empty struct.", .{path});
                            try out_writer.writeAll(empty_request_body_str);
                            break :blk;
                        }

                        render_stack.clearRetainingCapacity();
                        try renderApiTypeWith(
                            out_writer,
                            RenderStackCmd.TypeDecl{
                                .name = "RequestBody",
                                .json_obj = schema,
                            },
                            RenderApiTypeParams{
                                .allocator = allocator,
                                .render_stack = &render_stack,
                                .current_dir_path = "./reference",
                                .required_refs = &required_model_refs,
                                .json_comment_buf = null,
                            },
                        );
                    } else {
                        try out_writer.writeAll(empty_request_body_str);
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
                                try renderApiTypeWith(
                                    out_writer,
                                    RenderStackCmd.TypeDecl{
                                        .name = @tagName(tag),
                                        .json_obj = try getContentApplicationJsonSchema(response_info),
                                    },
                                    RenderApiTypeParams{
                                        .allocator = allocator,
                                        .render_stack = &render_stack,
                                        .current_dir_path = "./reference",
                                        .required_refs = &required_model_refs,
                                        .json_comment_buf = null,
                                    },
                                );
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

    { // write required model types
        try out_writer.writeAll("pub const models = struct {\n");

        var iter = required_model_refs.iterator();

        var finished_set = std.BufSet.init(allocator);
        defer finished_set.deinit();
        while (true) {
            for (0..3) |_| if (loop_arena_state.reset(.retain_capacity)) break;

            const ref: []const u8 = (iter.next() orelse break).*;
            defer {
                required_model_refs.remove(ref);
                iter = required_model_refs.iterator();
            }

            if (finished_set.contains(ref)) continue;
            try finished_set.insert(ref);

            const model_file_contents = try apidocs_dir.readFileAlloc(loop_arena, ref, 1 << 21);
            defer loop_arena.free(model_file_contents);

            json_parser.reset();
            var model_json = try json_parser.parse(model_file_contents);
            defer model_json.deinit();

            render_stack.clearRetainingCapacity();
            try renderApiTypeWith(
                out_writer,
                RenderStackCmd.TypeDecl{
                    .name = std.fs.path.stem(ref),
                    .json_obj = &model_json.root.object,
                },
                RenderApiTypeParams{
                    .allocator = allocator,
                    .render_stack = &render_stack,
                    .current_dir_path = "./models",
                    .required_refs = &required_model_refs,
                    .json_comment_buf = if (json_as_comment) &json_comment_buf else null,
                },
            );
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
    NonStringDescriptionFieldValue,
    NonStringExampleFieldValue,
} || std.mem.Allocator.Error ||
    GetRefFieldValueError ||
    GetTypeFieldValueError ||
    GetNestedArrayChildError ||
    WriteRefPathAsZigNamespaceAccessError ||
    WriteSimpleTypeError;

fn writeJsonAsComment(
    out_writer: anytype,
    json_value: std.json.Value,
    comment_prefix: []const u8,
    json_comment_buf: *std.ArrayList(u8),
) !void {
    json_comment_buf.clearRetainingCapacity();
    try json_comment_buf.writer().print("{}", .{util.fmtJson(
        json_value,
        std.json.StringifyOptions{ .whitespace = .{ .indent = .{ .space = 4 } } },
    )});
    try util.writeLinesSurrounded(out_writer, comment_prefix, json_comment_buf.items, "\n");
}

inline fn renderApiTypeWith(
    out_writer: anytype,
    root: RenderStackCmd.TypeDecl,
    params: RenderApiTypeParams,
) (@TypeOf(out_writer).Error || RenderApiTypeError)!void {
    assert(params.render_stack.items.len == 0);
    try params.render_stack.ensureUnusedCapacity(1);

    params.render_stack.appendAssumeCapacity(.{ .type_decl = .{
        .name = try params.allocator.dupe(u8, root.name),
        .json_obj = root.json_obj,
    } });

    return try renderApiType(out_writer, params);
}

const RenderApiTypeParams = struct {
    allocator: std.mem.Allocator,
    render_stack: *std.ArrayList(RenderStackCmd),
    /// directory in which the current file is,
    /// used to resolve relative '$ref' fields.
    /// Should be a relative path to the root directory
    /// of the api-docs.
    current_dir_path: []const u8,
    required_refs: *std.BufSet,
    json_comment_buf: ?*std.ArrayList(u8),
};

fn renderApiType(
    out_writer: anytype,
    params: RenderApiTypeParams,
) (@TypeOf(out_writer).Error || RenderApiTypeError)!void {
    const allocator = params.allocator;
    const render_stack = params.render_stack;
    const required_refs = params.required_refs;
    const current_dir_path = params.current_dir_path;
    var maybe_json_comment_buf = params.json_comment_buf;

    while (true) {
        const current: RenderStackCmd = render_stack.popOrNull() orelse return;
        switch (current) {
            .type_decl => |decl| {
                defer allocator.free(decl.name);

                if (maybe_json_comment_buf) |json_comment_buf| {
                    try out_writer.writeAll("// ```\n");
                    try writeJsonAsComment(out_writer, .{ .object = decl.json_obj.* }, "// ", json_comment_buf);
                    try out_writer.writeAll("// ```\n");
                    maybe_json_comment_buf = null;
                }

                if (try getObjField(decl.json_obj, "description", .string, null)) |desc| {
                    try util.writeLinesSurrounded(out_writer, "/// ", desc, "\n");
                }

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
                    => |tag| try writeSimpleType(out_writer, tag, decl.json_obj),
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
                        if (try getObjField(prop, "description", .string, null)) |desc| {
                            try util.writeLinesSurrounded(out_writer, "/// ", desc, "\n");
                        }
                        if (try getObjField(prop, "example", .string, null)) |example| {
                            if (prop.contains("description")) try out_writer.writeAll("///\n/// Example:");
                            try util.writeLinesSurrounded(out_writer, "/// ", example, "\n");
                        }

                        try out_writer.print("{s}: ", .{std.zig.fmtId(prop_name)});
                        if (!is_required) try out_writer.writeAll("?");

                        const resolved_ref = try std.fs.path.resolve(allocator, &.{ current_dir_path, ref });
                        defer allocator.free(resolved_ref);

                        try writeRefPathAsZigNamespaceAccess(out_writer, resolved_ref);
                        try required_refs.insert(resolved_ref);

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
                        => {
                            const maybe_min = try getObjField(prop, "minimum", .integer, null);
                            const maybe_max = try getObjField(prop, "maximum", .integer, null);
                            if (try getObjField(prop, "description", .string, null)) |desc| {
                                try util.writeLinesSurrounded(out_writer, "/// ", desc, "\n");
                                if (maybe_min != null or maybe_max != null)
                                    try out_writer.writeAll("///\n");
                            }
                            if (maybe_min) |min| {
                                try out_writer.print("/// minimum: {d}\n", .{min});
                            }
                            if (maybe_max) |max| {
                                try out_writer.print("/// maximum: {d}\n", .{max});
                            }
                        },
                        .boolean,
                        .array,
                        => if (try getObjField(prop, "description", .string, null)) |desc| {
                            try util.writeLinesSurrounded(out_writer, "/// ", desc, "\n");
                        },

                        .string => if (!prop.contains("enum")) {
                            if (try getObjField(prop, "description", .string, null)) |desc| {
                                try util.writeLinesSurrounded(out_writer, "/// ", desc, "\n");
                            }
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
                                if (try getObjField(items, "description", .string, null)) |desc| {
                                    try util.writeLinesSurrounded(out_writer, "/// ", desc, "\n");
                                }
                                if (try getObjField(items, "example", .string, null)) |example| {
                                    if (prop.contains("description")) try out_writer.writeAll("///\n/// Example:");
                                    try util.writeLinesSurrounded(out_writer, "/// ", example, "\n");
                                }

                                const resolved_ref = try std.fs.path.resolve(allocator, &.{ current_dir_path, ref });
                                defer allocator.free(resolved_ref);

                                try writeRefPathAsZigNamespaceAccess(out_writer, resolved_ref);
                                try required_refs.insert(resolved_ref);

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
                            try writeSimpleType(out_writer, tag, prop);
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

const WriteSimpleTypeError = error{
    NonArrayEnumFieldValue,
    NonStringEnumFieldElement,
    NonStringFormatFieldValue,
    UnrecognizedIntegerFormat,
    NonIntegerMinimumFieldValue,
    NonIntegerMaximumFieldValue,
    IntegerMinGreaterThanMax,
    MinSmallerThanFormatMin,
    MaxGreaterThanFormatMax,
    IntegerRangeOverflow,
};
fn writeSimpleType(
    out_writer: anytype,
    comptime tag: DataType,
    json_obj: *const JsonObj,
) (@TypeOf(out_writer).Error || WriteSimpleTypeError)!void {
    switch (tag) {
        .string => {
            const enum_list: []const std.json.Value = (try getObjField(json_obj, "enum", .array, null) orelse return).items;
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
            try out_writer.writeAll(number_format_subst_decl_name);
        },
        .integer => {
            const Format = enum {
                int32,
                int64,

                inline fn writeType(format: @This(), writer: @TypeOf(out_writer)) !void {
                    switch (format) {
                        .int32 => try writer.writeAll("i32"),
                        .int64 => try writer.writeAll("i64"),
                    }
                }

                inline fn min(format: @This()) i64 {
                    return switch (format) {
                        .int32 => std.math.minInt(i32),
                        .int64 => std.math.minInt(i64),
                    };
                }
                inline fn max(format: @This()) i64 {
                    return switch (format) {
                        .int32 => std.math.maxInt(i32),
                        .int64 => std.math.maxInt(i64),
                    };
                }
            };
            const maybe_format: ?Format = if (try getObjField(json_obj, "format", .string, null)) |format_str|
                std.meta.stringToEnum(Format, format_str) orelse
                    return error.UnrecognizedIntegerFormat
            else
                null;
            const maybe_min = try getObjField(json_obj, "minimum", .integer, null);
            const maybe_max = try getObjField(json_obj, "maximum", .integer, null);

            if (maybe_min != null and maybe_max != null and
                maybe_min.? > maybe_max.?)
            {
                return error.IntegerMinGreaterThanMax;
            }

            const format = maybe_format orelse .int64;
            const min = maybe_min orelse format.min();
            const max = maybe_max orelse format.max();
            if (min < format.min()) return error.MinSmallerThanFormatMin;
            if (max > format.max()) return error.MaxGreaterThanFormatMax;

            const ranged_info = util.intInfoFittingRange(min, max) orelse {
                return error.IntegerRangeOverflow;
            };
            try util.writeIntTypeName(out_writer, ranged_info);
            return;
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

    // this is a couple of special-cases.
    // not sure if there's a better way to handle this,
    // but hopefully this is enough.
    const expected_count = @as(usize, 1) +
        @boolToInt(json_obj.contains("example")) +
        @boolToInt(json_obj.contains("description"));
    if (json_obj.count() != expected_count) {
        std.debug.print("{}", .{util.fmtJson(.{ .object = json_obj.* }, .{})});
        return error.NotAlone;
    }
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

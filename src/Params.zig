const std = @import("std");
const util = @import("util.zig");

const Params = @This();
models: []const u8,
output_path: []const u8,
number_as_string: bool,
json_as_comment: bool,

const ParamId = std.meta.FieldEnum(Params);
inline fn paramIsFlag(id: ParamId) bool {
    return switch (id) {
        .models,
        .output_path,
        => false,

        .number_as_string,
        .json_as_comment,
        => true,
    };
}

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

    var results: @Type(.{ .Struct = .{
        .is_tuple = false,
        .layout = .Auto,
        .backing_integer = null,
        .decls = &.{},
        .fields = fields: {
            var fields = @typeInfo(Params).Struct.fields[0..].*;
            for (&fields) |*field| {
                field.type = ?field.type;
                field.default_value = &@as(field.type, null);
                field.alignment = 0;
            }
            break :fields &fields;
        },
    } }) = .{};

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

            inline for (@typeInfo(ParamId).Enum.fields) |field| {
                const kebab_case: []const u8 = comptime blk: {
                    var kebab_case = field.name[0..].*;
                    std.mem.replaceScalar(u8, &kebab_case, '_', '-');
                    break :blk &kebab_case;
                };
                if (std.mem.eql(u8, name, kebab_case)) {
                    break :id @intToEnum(ParamId, field.value);
                }
            }

            log.err("Unrecognized parameter name '{s}'", .{str});
            return error.UnrecognizedParameterName;
        };
        const next_tok: []const u8 = if (maybe_next_tok) |next_tok|
            std.mem.trim(u8, next_tok, &std.ascii.whitespace)
        else if (argv.next()) |next_tok| next_tok else blk: {
            if (paramIsFlag(id)) break :blk "true";
            log.err("Expected value for parameter '{s}'", .{@tagName(id)});
            return error.MissingArgumentValue;
        };
        switch (id) {
            inline //
            .models,
            .output_path,
            => |tag| {
                const field_ptr = &@field(results, @tagName(tag));
                const new_slice = try allocator.realloc(@constCast(field_ptr.* orelse ""), next_tok.len);
                @memcpy(new_slice, next_tok);
                field_ptr.* = new_slice;
            },
            inline //
            .number_as_string,
            .json_as_comment,
            => |tag| {
                const field_ptr = &@field(results, @tagName(tag));
                field_ptr.* = if (std.mem.eql(u8, next_tok, "true")) true else if (std.mem.eql(u8, next_tok, "false")) false else {
                    log.err("Expected '{s}' to be a boolean, instead got '{s}'.", .{ @tagName(tag), next_tok });
                    return error.InvalidParameterFlagValue;
                };
            },
        }
    }

    return Params{
        .models = results.models orelse {
            log.err("Missing argument 'models'.", .{});
            return error.MissingArgument;
        },
        .output_path = results.output_path orelse {
            log.err("Missing argument 'output_path'.", .{});
            return error.MissingArgument;
        },
        .number_as_string = results.number_as_string orelse false,
        .json_as_comment = results.json_as_comment orelse false,
    };
}

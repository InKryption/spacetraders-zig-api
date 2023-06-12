const std = @import("std");
const util = @import("util.zig");

const Params = @This();
apidocs_path: ?[]const u8 = null,
output_path: ?[]const u8 = null,
number_format: NumberFormat = .number_string,
json_as_comment: bool = false,

const NumberFormat = @import("number-format.zig").NumberFormat;

const ParamId = std.meta.FieldEnum(Params);
inline fn paramIsFlag(id: ParamId) bool {
    return switch (id) {
        .apidocs_path,
        .output_path,
        => false,

        .number_format => false,

        .json_as_comment => true,
    };
}

pub fn deinit(params: Params, ally: std.mem.Allocator) void {
    ally.free(params.output_path orelse "");
    ally.free(params.apidocs_path orelse "");
}

pub const ParseError = std.mem.Allocator.Error || error{
    MissingDashDashPrefix,
    UnrecognizedParameterName,
    MissingArgumentValue,
    InvalidParameterFlagValue,
};

pub fn parseCurrentProcess(
    allocator: std.mem.Allocator,
    comptime log_scope: @TypeOf(.enum_literal),
) (ParseError || error{EmptyArgv})!Params {
    var argv = try std.process.argsWithAllocator(allocator);
    defer argv.deinit();
    if (!argv.skip()) return error.EmptyArgv;
    return try Params.parse(allocator, log_scope, &argv);
}

pub fn parse(
    allocator: std.mem.Allocator,
    comptime log_scope: @TypeOf(.enum_literal),
    argv: anytype,
) ParseError!Params {
    const log = std.log.scoped(log_scope);
    var result: Params = .{};

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
                const kebab_case = util.replaceScalarComptime(u8, field.name, '_', '-');
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

        const id_kebab_name: []const u8 = switch (id) {
            inline else => |tag| util.replaceScalarComptime(u8, @tagName(tag), '_', '-'),
        };

        switch (id) {
            inline //
            .apidocs_path,
            .output_path,
            => |tag| {
                const field_ptr = &@field(result, @tagName(tag));
                const new_slice = try allocator.realloc(@constCast(field_ptr.* orelse ""), next_tok.len);
                @memcpy(new_slice, next_tok);
                field_ptr.* = new_slice;
            },
            inline //
            .json_as_comment => |tag| {
                const field_ptr = &@field(result, @tagName(tag));
                field_ptr.* = if (std.mem.eql(u8, next_tok, "true")) true else if (std.mem.eql(u8, next_tok, "false")) false else {
                    log.err("Expected '{s}' to be a boolean, instead got '{s}'.", .{ id_kebab_name, next_tok });
                    return error.InvalidParameterFlagValue;
                };
            },
            inline //
            .number_format => |tag| blk: {
                const field_ptr = &@field(result, @tagName(tag));
                const Enum = @TypeOf(field_ptr.*);
                inline for (@typeInfo(Enum).Enum.fields) |enum_field| {
                    const kebab_name = util.replaceScalarComptime(u8, enum_field.name, '_', '-');
                    if (std.mem.eql(u8, kebab_name, next_tok)) {
                        field_ptr.* = @intToEnum(Enum, enum_field.value);
                        break :blk;
                    }
                }

                log.err("'{s}' was passed invalid value '{s}' - must be one of:\n{}", .{
                    id_kebab_name,
                    next_tok,
                    struct {
                        pub fn format(
                            _: @This(),
                            comptime _: []const u8,
                            _: std.fmt.FormatOptions,
                            writer: anytype,
                        ) !void {
                            inline for (@typeInfo(Enum).Enum.fields) |e_field|
                                try writer.print("   * '{s}'\n", .{util.replaceScalarComptime(u8, e_field.name, '_', '-')});
                        }
                    }{},
                });
            },
        }
    }

    return result;
}

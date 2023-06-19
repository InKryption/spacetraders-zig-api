const std = @import("std");
const util = @import("util.zig");

const Params = @This();
apidocs_path: ?[]const u8 = null,
output_path: ?[]const u8 = null,
number_format: ?NumberFormat = null,
json_as_comment: ?bool = null,
log_level: ?std.log.Level = null,

const NumberFormat = @import("number-format.zig").NumberFormat;

const ParamId = std.meta.FieldEnum(Params);
inline fn paramIsFlag(id: ParamId) bool {
    return switch (id) {
        .apidocs_path => false,
        .output_path => false,
        .number_format => false,
        .json_as_comment => true,
        .log_level => false,
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
    InvalidParameterEnumValue,
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
    const log_err = std.log.scoped(log_scope).err;
    var result: Params = .{};
    errdefer result.deinit(allocator);

    while (true) {
        var maybe_next_tok: ?[]const u8 = null;

        const kebab_param_id = util.ReplaceEnumTagScalar(ParamId, '_', '-');
        const id: Params.ParamId = id: {
            const str = std.mem.trim(u8, argv.next() orelse break, &std.ascii.whitespace);
            const maybe_name = util.stripPrefix(u8, str, "--") orelse {
                log_err("Expected parameter id preceeded by '--', found '{s}'", .{str});
                return error.MissingDashDashPrefix;
            };
            const name: []const u8 = if (std.mem.indexOfScalar(u8, maybe_name, '=')) |eql_idx| name: {
                const next_tok = std.mem.trim(u8, maybe_name[eql_idx + 1 ..], &std.ascii.whitespace);
                if (next_tok.len != 0) {
                    maybe_next_tok = next_tok;
                }
                break :name maybe_name[0..eql_idx];
            } else maybe_name;

            const kebab_id = std.meta.stringToEnum(kebab_param_id.WithReplacement, name) orelse {
                log_err("Unrecognized parameter name '{s}'", .{str});
                return error.UnrecognizedParameterName;
            };
            break :id kebab_param_id.unmake(kebab_id);
        };

        const next_tok: []const u8 = if (maybe_next_tok) |next_tok|
            std.mem.trim(u8, next_tok, &std.ascii.whitespace)
        else if (argv.next()) |next_tok| next_tok else blk: {
            if (paramIsFlag(id)) break :blk "true";
            log_err("Expected value for parameter '{s}'", .{@tagName(id)});
            return error.MissingArgumentValue;
        };

        const id_kebab_name: []const u8 = @tagName(kebab_param_id.make(id));
        switch (id) {
            inline //
            .apidocs_path,
            .output_path,
            => |tag| {
                const field_ptr = &@field(result, @tagName(tag));
                const new_slice = try allocator.realloc(@constCast(field_ptr.* orelse &.{}), next_tok.len);
                @memcpy(new_slice, next_tok);
                field_ptr.* = new_slice;
            },
            inline //
            .json_as_comment => |tag| {
                const field_ptr = &@field(result, @tagName(tag));
                const BoolTag = enum(u1) {
                    false = @boolToInt(false),
                    true = @boolToInt(true),
                };
                field_ptr.* = if (std.meta.stringToEnum(BoolTag, next_tok)) |bool_tag| @bitCast(bool, @enumToInt(bool_tag)) else {
                    log_err("Expected '{s}' to be a boolean, instead got '{s}'.", .{ id_kebab_name, next_tok });
                    return error.InvalidParameterFlagValue;
                };
            },
            inline //
            .number_format,
            .log_level,
            => |tag| {
                const field_ptr = &@field(result, @tagName(tag));
                const Enum = @TypeOf(field_ptr.*.?);
                const kebab_enum = util.ReplaceEnumTagScalar(Enum, '_', '-');
                if (std.meta.stringToEnum(kebab_enum.WithReplacement, next_tok)) |kebab_tag| {
                    field_ptr.* = kebab_enum.unmake(kebab_tag);
                    continue;
                }
                const MemberListFmt = struct {
                    pub fn format(_: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                        inline for (@typeInfo(Enum).Enum.fields) |e_field|
                            try writer.print("   * '{s}'\n", .{util.replaceScalarComptime(u8, e_field.name, '_', '-')});
                    }
                };
                log_err("'{s}' was passed invalid value '{s}' - must be one of:\n{}", .{
                    id_kebab_name, next_tok, MemberListFmt{},
                });
                return error.InvalidParameterEnumValue;
            },
        }
    }

    return result;
}

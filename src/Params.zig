const std = @import("std");
const util = @import("util.zig");

const Params = @This();
apidocs_path: ?[]const u8 = null,
output_path: ?[]const u8 = null,
number_format: ?NumberFormat = null,
json_as_comment: ?bool = null,
log_level: ?std.log.Level = null,

const NumberFormat = @import("number-format.zig").NumberFormat;

pub const Id = std.meta.FieldEnum(Params);
inline fn paramIsFlag(id: Params.Id) bool {
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
    diag: ?*ParseDiagnostic,
) (ParseError || error{EmptyArgv})!Params {
    var argv = try std.process.argsWithAllocator(allocator);
    defer argv.deinit();
    if (!argv.skip()) return error.EmptyArgv;
    return try Params.parse(allocator, &argv, diag);
}

/// permutations:
/// + last_param == null, last_arg == null: nothing returned from arg_iter
/// + last_param != null, last_arg == null: valid param obtained, and then no argument following that
/// + last_param == null, last_arg != null: error obtaining parameter id, last_arg represents the of the expected pair of args
/// + last_param != null, last_arg != null: error in parsing said argument into expected type of param
pub const ParseDiagnostic = struct {
    last_param: ?Params.Id,
    last_arg: ?[]const u8,
};

pub fn parse(
    allocator: std.mem.Allocator,
    argv: anytype,
    maybe_diag: ?*ParseDiagnostic,
) ParseError!Params {
    var result: Params = .{};
    errdefer result.deinit(allocator);

    while (true) {
        var maybe_next_tok: ?[]const u8 = null;

        const kebab_param_id = util.ReplaceEnumTagScalar(Params.Id, '_', '-');
        const id: Params.Params.Id = id: {
            const full_str = argv.next() orelse break;
            const str = std.mem.trim(u8, full_str, &std.ascii.whitespace);
            const maybe_name = util.stripPrefix(u8, str, "--") orelse {
                if (maybe_diag) |diag| diag.* = .{
                    .last_param = null,
                    .last_arg = full_str,
                };
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
                if (maybe_diag) |diag| diag.* = .{
                    .last_param = null,
                    .last_arg = full_str,
                };
                return error.UnrecognizedParameterName;
            };
            break :id kebab_param_id.unmake(kebab_id);
        };

        const next_arg = argv.next();
        const next_tok: []const u8 = if (maybe_next_tok) |next_tok| blk: {
            break :blk std.mem.trim(u8, next_tok, &std.ascii.whitespace);
        } else next_arg orelse blk: {
            if (paramIsFlag(id)) break :blk "true";
            if (maybe_diag) |diag| diag.* = .{
                .last_param = id,
                .last_arg = null,
            };
            return error.MissingArgumentValue;
        };

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
                    false = @intFromBool(false),
                    true = @intFromBool(true),
                };
                field_ptr.* = if (std.meta.stringToEnum(BoolTag, next_tok)) |bool_tag|
                    @bitCast(bool, @intFromEnum(bool_tag))
                else {
                    if (maybe_diag) |diag| diag.* = .{
                        .last_param = id,
                        .last_arg = next_arg,
                    };
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
                if (maybe_diag) |diag| diag.* = .{
                    .last_param = id,
                    .last_arg = next_arg,
                };
                return error.InvalidParameterEnumValue;
            },
        }
    }

    return result;
}

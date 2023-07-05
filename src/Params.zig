const std = @import("std");
const util = @import("util");

const Params = @This();
apidocs_path: ?[]const u8 = null,
output_path: ?[]const u8 = null,
number_format: ?NumberFormat = null,
json_as_comment: ?bool = null,
log_level: ?std.log.Level = null,

const NumberFormat = @import("number-format.zig").NumberFormat;

pub const Id = std.meta.FieldEnum(Params);

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

pub const ParseDiagnostic = struct {
    parsed_id: ?Params.Id,
    last_arg: []const u8,
};

pub fn parse(
    allocator: std.mem.Allocator,
    argv: anytype,
    maybe_diag: ?*ParseDiagnostic,
) ParseError!Params {
    if (maybe_diag) |diag| diag.* = .{
        .parsed_id = null,
        .last_arg = undefined,
    };

    var result: Params = .{};
    errdefer result.deinit(allocator);

    while (true) {
        var maybe_next_tok: ?[]const u8 = null;

        const id: Params.Params.Id = id: {
            const full_str = argv.next() orelse break;
            if (maybe_diag) |diag| diag.last_arg = full_str;

            const str = std.mem.trim(u8, full_str, &std.ascii.whitespace);
            const maybe_name = if (util.stripPrefix(u8, str, "--")) |stripped| blk: {
                break :blk std.mem.trimLeft(u8, stripped, &std.ascii.whitespace);
            } else return error.MissingDashDashPrefix;

            const name: []const u8 = if (std.mem.indexOfAny(u8, maybe_name, &std.ascii.whitespace)) |eql_idx| name: {
                const next_tok = std.mem.trim(u8, maybe_name[eql_idx + 1 ..], &std.ascii.whitespace);
                if (next_tok.len != 0) maybe_next_tok = next_tok;
                break :name maybe_name[0..eql_idx];
            } else maybe_name;

            const kebab_id = std.meta.stringToEnum(util.EnumSnakeToKebabCase(Params.Id), name) orelse {
                return error.UnrecognizedParameterName;
            };
            break :id util.enumKebabToSnakeCase(Params.Id, kebab_id);
        };
        if (maybe_diag) |diag| diag.parsed_id = id;

        const next_tok: []const u8 = if (maybe_next_tok) |next_tok| blk: {
            break :blk std.mem.trim(u8, next_tok, &std.ascii.whitespace);
        } else if (argv.next()) |next_arg| blk: {
            if (maybe_diag) |diag| diag.last_arg = next_arg;
            break :blk std.mem.trim(u8, next_arg, &std.ascii.whitespace);
        } else return error.MissingArgumentValue;

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
                const field_ptr: *?bool = &@field(result, @tagName(tag));
                const BoolTag = enum(u1) {
                    false = @intFromBool(false),
                    true = @intFromBool(true),
                };
                field_ptr.* = if (std.meta.stringToEnum(BoolTag, next_tok)) |bool_tag|
                    @bitCast(@intFromEnum(bool_tag))
                else
                    return error.InvalidParameterFlagValue;
            },
            inline //
            .number_format,
            .log_level,
            => |tag| {
                const field_ptr = &@field(result, @tagName(tag));
                const Enum = @TypeOf(field_ptr.*.?);
                if (std.meta.stringToEnum(util.EnumSnakeToKebabCase(Enum), next_tok)) |kebab_tag| {
                    field_ptr.* = util.enumKebabToSnakeCase(Enum, kebab_tag);
                    continue;
                }
                return error.InvalidParameterEnumValue;
            },
        }
    }

    return result;
}

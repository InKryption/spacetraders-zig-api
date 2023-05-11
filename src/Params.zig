const std = @import("std");
const util = @import("util.zig");

const Params = @This();
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

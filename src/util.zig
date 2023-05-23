const std = @import("std");
const assert = std.debug.assert;

pub inline fn stripPrefix(comptime T: type, str: []const u8, prefix: []const T) ?[]const u8 {
    if (!std.mem.startsWith(T, str, prefix)) return null;
    return str[prefix.len..];
}

pub fn writeLinesSurrounded(writer: anytype, prefix: []const u8, lines: []const u8, suffix: []const u8) !void {
    var iter = std.mem.tokenize(u8, lines, "\r\n");
    while (iter.next()) |line| {
        try writer.print("{s}{s}{s}", .{ prefix, line, suffix });
    }
}

pub inline fn fmtJson(value: std.json.Value, options: std.json.StringifyOptions) FmtJson {
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

pub inline fn replaceScalarComptime(
    comptime T: type,
    comptime input: []const T,
    comptime needle: T,
    comptime replacement: T,
) *const [input.len]T {
    comptime return replaceScalarComptimeImpl(
        T,
        input.len,
        input[0..].*,
        needle,
        replacement,
    );
}
fn replaceScalarComptimeImpl(
    comptime T: type,
    comptime input_len: comptime_int,
    comptime input: [input_len]T,
    comptime needle: T,
    comptime replacement: T,
) *const [input.len]T {
    var result = input[0..].*;
    @setEvalBranchQuota(input.len * 2);
    for (&result) |*item| {
        if (item.* == needle) {
            item.* = replacement;
        }
    }
    return &result;
}

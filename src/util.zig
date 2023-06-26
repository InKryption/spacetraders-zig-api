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

pub fn ReplaceEnumTagScalar(
    comptime T: type,
    comptime needle: u8,
    comptime replacement: u8,
) type {
    return struct {
        pub const Original = T;
        pub const WithReplacement = T: {
            if (needle == replacement) break :T T;
            const old = @typeInfo(T).Enum;
            var fields = old.fields[0..].*;
            for (&fields) |*field|
                field.name = replaceScalarComptime(u8, field.name, needle, replacement);
            break :T @Type(.{ .Enum = .{
                .tag_type = old.tag_type,
                .is_exhaustive = old.is_exhaustive,
                .decls = &.{},
                .fields = &fields,
            } });
        };
        pub inline fn make(value: Original) WithReplacement {
            return @enumFromInt(@intFromEnum(value));
        }
        pub inline fn unmake(value: WithReplacement) Original {
            return @enumFromInt(@intFromEnum(value));
        }
    };
}

/// Returns the smallest integer type that can hold both from and to.
pub fn intInfoFittingRange(from: anytype, to: anytype) ?std.builtin.Type.Int {
    assert(from <= to);
    const From = @TypeOf(from);
    // const To = @TypeOf(to);
    const Peer = @TypeOf(from, to);
    if (Peer == comptime_int) {
        return @typeInfo(std.math.IntFittingRange(from, to)).Int;
    }
    if (from == 0 and to == 0) {
        return @typeInfo(u0).Int;
    }
    const signedness: std.builtin.Signedness = if (from < 0) .signed else .unsigned;
    const largest_positive_integer = std.math.absCast(@max(to, switch (from) {
        // `-from` overflows if it's `std.math.minInt(From)`, but
        // subtracting 1 from the upcasted version of that value results in `std.math.maxInt(From)`
        std.math.minInt(From) => std.math.maxInt(From),
        std.math.minInt(From) + 1...-1 => (-from) - 1,
        0...std.math.maxInt(From) => from,
    })); // two's complement
    const base = std.math.log2_int(@TypeOf(largest_positive_integer), largest_positive_integer);
    const upper = (@as(@TypeOf(largest_positive_integer), 1) << base) - 1;
    var magnitude_bits: u16 = if (upper >= largest_positive_integer) base else base + 1;
    if (signedness == .signed) {
        magnitude_bits += 1;
    }
    // return std.meta.Int(signedness, magnitude_bits);
    return .{
        .bits = magnitude_bits,
        .signedness = signedness,
    };
}
pub inline fn writeIntTypeName(
    writer: anytype,
    info: std.builtin.Type.Int,
) !void {
    switch (info.signedness) {
        inline else => |sign| {
            const sign_prefix = switch (sign) {
                .signed => "i",
                .unsigned => "u",
            };
            try writer.print(sign_prefix ++ "{d}", .{info.bits});
        },
    }
}

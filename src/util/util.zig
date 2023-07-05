const std = @import("std");
const assert = std.debug.assert;

pub const json = @import("json.zig");

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

pub fn EnumSnakeToKebabCase(comptime E: type) type {
    return EnumReplaceNameScalar(E, '_', '-');
}
pub inline fn enumSnakeToKebabCase(value: anytype) EnumSnakeToKebabCase(@TypeOf(value)) {
    return enumReplaceNameScalar(value, '_', '-');
}
pub inline fn enumKebabToSnakeCase(comptime E: type, value: EnumSnakeToKebabCase(E)) E {
    return enumUnreplaceNameScalar(E, '_', '-', value);
}

pub fn EnumReplaceNameScalar(comptime E: type, comptime needle: u8, comptime replacement: u8) type {
    const info = @typeInfo(E).Enum;
    var fields = info.fields[0..].*;
    for (&fields) |*field| {
        field.name = replaceScalarComptime(u8, field.name, needle, replacement);
    }
    var new_info = info;
    new_info.fields = &fields;
    new_info.decls = &.{};
    return @Type(.{ .Enum = new_info });
}
pub inline fn enumReplaceNameScalar(
    value: anytype,
    comptime needle: u8,
    comptime replacement: u8,
) EnumReplaceNameScalar(@TypeOf(value), needle, replacement) {
    return @enumFromInt(@intFromEnum(value));
}
pub inline fn enumUnreplaceNameScalar(
    comptime E: type,
    comptime needle: u8,
    comptime replacement: u8,
    value: EnumReplaceNameScalar(E, needle, replacement),
) E {
    return @enumFromInt(@intFromEnum(value));
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

pub fn ProgressiveStringToEnum(comptime E: type) type {
    const info = @typeInfo(E).Enum;
    return struct {
        current_index: usize = 0,
        query_len: usize = 0,
        const Self = @This();

        pub inline fn getMatch(pse: Self) ?E {
            const candidate = pse.getClosestCandidate() orelse return null;
            const str = @tagName(candidate);
            if (str.len > pse.query_len) return null;
            assert(str.len == pse.query_len);
            return candidate;
        }

        pub inline fn getMatchedSubstring(pse: Self) ?[]const u8 {
            if (pse.current_index == sorted.tags.len) return null;
            const candidate = @tagName(sorted.tags[pse.current_index]);
            return candidate[0..pse.query_len];
        }

        pub inline fn getClosestCandidate(pse: Self) ?E {
            if (pse.current_index == sorted.tags.len) return null;
            const closest = sorted.tags[pse.current_index];
            if (pse.query_len == 0 and @tagName(closest).len != 0) return null;
            return closest;
        }

        /// asserts that `segment.len != 0`
        pub fn append(pse: *Self, segment: []const u8) bool {
            assert(segment.len != 0);
            if (pse.current_index == sorted.tags.len) return false;

            const prefix = @tagName(sorted.tags[pse.current_index])[0..pse.query_len];
            while (pse.current_index != sorted.tags.len) : (pse.current_index += 1) {
                const candidate_tag: E = sorted.tags[pse.current_index];
                if (!std.mem.startsWith(u8, @tagName(candidate_tag), prefix)) {
                    pse.current_index = sorted.tags.len;
                    return false;
                }
                const remaining = @tagName(candidate_tag)[prefix.len..];
                if (remaining.len < segment.len) continue;
                if (!std.mem.startsWith(u8, remaining, segment)) continue;
                pse.query_len += segment.len;
                return true;
            }

            pse.current_index = sorted.tags.len;
            return false;
        }

        const sorted = blk: {
            var tags: [info.fields.len]E = undefined;
            @setEvalBranchQuota(tags.len);
            for (&tags, info.fields) |*tag, field| {
                tag.* = @field(E, field.name);
            }

            // sort
            @setEvalBranchQuota(@min(std.math.maxInt(u32), tags.len * tags.len));
            for (tags[0 .. tags.len - 1], 0..) |*tag_a, i| {
                for (tags[i + 1 ..]) |*tag_b| {
                    if (!std.mem.lessThan(u8, @tagName(tag_a.*), @tagName(tag_b.*))) {
                        std.mem.swap(E, tag_a, tag_b);
                    }
                }
            }

            break :blk .{
                .tags = tags,
            };
        };
    };
}

fn testProgressiveStringToEnum(comptime E: type) !void {
    const Pse = ProgressiveStringToEnum(E);
    var pse = Pse{};
    for (comptime std.enums.values(E)) |value| {
        const field_name = @tagName(value);

        pse = .{};
        try std.testing.expectEqualStrings("", try (pse.getMatchedSubstring() orelse error.ExpectedNonNull));
        try std.testing.expectEqual(@as(?E, null), pse.getClosestCandidate());
        try std.testing.expectEqual(@as(?E, null), pse.getMatch());

        try std.testing.expect(pse.append(field_name));
        try std.testing.expectEqualStrings(field_name, try (pse.getMatchedSubstring() orelse error.ExpectedNonNull));
        try std.testing.expectEqual(@as(?E, value), pse.getClosestCandidate());
        try std.testing.expectEqual(@as(?E, value), pse.getMatch());

        try std.testing.expect(!pse.append(comptime non_matching: {
            const lexicographic_biggest = Pse.sorted.tags[Pse.sorted.tags.len - 1];
            break :non_matching @tagName(lexicographic_biggest) ++ "-no-match";
        }));
        try std.testing.expectEqual(@as(?[]const u8, null), pse.getMatchedSubstring());
        try std.testing.expectEqual(@as(?E, null), pse.getClosestCandidate());
        try std.testing.expectEqual(@as(?E, null), pse.getMatch());

        for (1..field_name.len + 1) |max_seg_size| {
            pse = .{};
            var segment_iter = std.mem.window(u8, field_name, max_seg_size, max_seg_size);
            while (segment_iter.next()) |segment| {
                try std.testing.expectStringStartsWith(field_name, try (pse.getMatchedSubstring() orelse error.ExpectedNonNull));
                try std.testing.expect(pse.append(segment));
                try std.testing.expect(pse.getClosestCandidate() != null);
            }
            try std.testing.expectEqualStrings(field_name, try (pse.getMatchedSubstring() orelse error.ExpectedNonNull));
            try std.testing.expectEqual(@as(?E, value), pse.getClosestCandidate());
            try std.testing.expectEqual(@as(?E, value), pse.getMatch());
        }
    }
}

test ProgressiveStringToEnum {
    const E = enum {
        foo,
        bar,
        baz,
        fizz,
        buzz,
    };
    var pste = ProgressiveStringToEnum(E){};
    try std.testing.expectEqual(@as(?E, null), pste.getMatch());
    try std.testing.expectEqual(@as(?E, null), pste.getClosestCandidate());
    try std.testing.expectEqualStrings("", try (pste.getMatchedSubstring() orelse error.ExpectedNonNull));

    try std.testing.expect(pste.append("ba"));
    try std.testing.expectEqualStrings("ba", try (pste.getMatchedSubstring() orelse error.ExpectedNonNull));
    _ = try (pste.getClosestCandidate() orelse error.ExpectedNonNull);

    try std.testing.expect(pste.append("z"));
    try std.testing.expectEqualStrings("baz", try (pste.getMatchedSubstring() orelse error.ExpectedNonNull));
    _ = try (pste.getClosestCandidate() orelse error.ExpectedNonNull);

    try std.testing.expectEqual(@as(?E, .baz), pste.getMatch());

    try std.testing.expect(!pste.append("z"));
    try std.testing.expectEqual(@as(?E, null), pste.getMatch());
    try std.testing.expectEqual(@as(?[]const u8, null), pste.getMatchedSubstring());
    try std.testing.expectEqual(@as(?E, null), pste.getClosestCandidate());

    try testProgressiveStringToEnum(enum { adlk, bnae, aaeg, cvxz, fadsfea, vafa, zvcxer, ep, afeap, lapqqokf });
    try testProgressiveStringToEnum(enum { a, ab, abcd, bcdefg, bcde, xy, xz, xyz, xyzzz });
}

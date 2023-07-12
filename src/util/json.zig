const std = @import("std");
const util = @import("./util.zig");
const assert = std.debug.assert;

pub inline fn fmtStringify(value: anytype, options: std.json.StringifyOptions) FmtStringify(@TypeOf(value)) {
    return .{
        .value = value,
        .options = options,
    };
}
pub fn FmtStringify(comptime T: type) type {
    return struct {
        value: T,
        options: std.json.StringifyOptions,

        const Self = @This();
        pub fn format(
            self: Self,
            comptime fmt_str: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) @TypeOf(writer).Error!void {
            _ = options;
            if (fmt_str.len != 0) std.fmt.invalidFmtError(fmt_str, self);
            try std.json.stringify(self.value, self.options, writer);
        }
    };
}

/// asserts `(try source.peekNextTokenType()) == .string`.
/// appends the string or sequence of partial strings to the `pse`.
/// if `error.BufferOverrun` occurs, this can be called again with
/// the same `pse` to continue (the `pse` is not cleared or reset
/// at any point).
pub fn nextProgressiveStringToEnum(
    source: anytype,
    comptime E: type,
    pse: *util.ProgressiveStringToEnum(E),
) (@TypeOf(source.*).PeekError || @TypeOf(source.*).NextError)!void {
    assert(try source.peekNextTokenType() == std.json.TokenType.string);

    while (true) {
        switch (try source.next()) {
            inline //
            .partial_string,
            .partial_string_escaped_1,
            .partial_string_escaped_2,
            .partial_string_escaped_3,
            .partial_string_escaped_4,
            => |str| if (!pse.append(str[0..])) {
                return;
            },
            .string => |str| {
                if (str.len != 0) {
                    _ = pse.append(str);
                }
                break;
            },
            else => unreachable,
        }
    }
}

/// returns true if a field name (a string) was encountered,
/// and false if `.object_end` was encountered.
pub fn nextProgressiveFieldToEnum(
    source: anytype,
    comptime E: type,
    pse: *util.ProgressiveStringToEnum(E),
) (@TypeOf(source.*).PeekError || @TypeOf(source.*).NextError)!bool {
    switch (try source.peekNextTokenType()) {
        else => unreachable,
        .object_end => {
            assert(try source.next() == .object_end);
            return false;
        },
        .string => {},
    }
    try nextProgressiveStringToEnum(source, E, pse);
    return true;
}

test nextProgressiveFieldToEnum {
    const FieldName = enum { foo, baz, buzz };
    var scanner = std.json.Scanner.initCompleteInput(std.testing.allocator,
        \\{ "foo": "bar", "baz": "fizz", "buzz": 0 }
    );
    defer scanner.deinit();

    const ScanErr = std.json.Scanner.PeekError || std.json.Scanner.NextError;
    try std.testing.expectEqual(@as(std.json.Scanner.NextError!std.json.Token, .object_begin), scanner.next());

    var pse = util.ProgressiveStringToEnum(FieldName){};
    try std.testing.expectEqual(@as(ScanErr!bool, true), nextProgressiveFieldToEnum(&scanner, FieldName, &pse));
    try std.testing.expectEqual(@as(?FieldName, .foo), pse.getMatch());
    try scanner.skipValue();

    pse = .{};
    try std.testing.expectEqual(@as(ScanErr!bool, true), nextProgressiveFieldToEnum(&scanner, FieldName, &pse));
    try std.testing.expectEqual(@as(?FieldName, .baz), pse.getMatch());
    try scanner.skipValue();

    pse = .{};
    try std.testing.expectEqual(@as(ScanErr!bool, true), nextProgressiveFieldToEnum(&scanner, FieldName, &pse));
    try std.testing.expectEqual(@as(?FieldName, .buzz), pse.getMatch());
    try scanner.skipValue();

    pse = .{};
    try std.testing.expectEqual(@as(ScanErr!bool, false), nextProgressiveFieldToEnum(&scanner, FieldName, &pse));
    try std.testing.expectEqualStrings("", pse.getMatchedSubstring() orelse "non-empty");
    try std.testing.expectEqual(@as(?FieldName, null), pse.getMatch());

    scanner.deinit();
    scanner = std.json.Scanner.initCompleteInput(std.testing.allocator,
        \\{ "bar": "foo" }
    );
    try std.testing.expectEqual(@as(std.json.Scanner.NextError!std.json.Token, .object_begin), scanner.next());

    try std.testing.expectEqual(@as(ScanErr!bool, true), nextProgressiveFieldToEnum(&scanner, FieldName, &pse));
    try std.testing.expectEqual(@as(?FieldName, null), pse.getMatch());
    try scanner.skipValue();

    pse = .{};
    try std.testing.expectEqual(@as(ScanErr!bool, false), nextProgressiveFieldToEnum(&scanner, FieldName, &pse));
    try std.testing.expectEqualStrings("", pse.getMatchedSubstring() orelse "non-empty");
    try std.testing.expectEqual(@as(?FieldName, null), pse.getMatch());
}

pub fn expectEqual(
    a: anytype,
    b: anytype,
    options: std.json.ParseOptions,
) (error{TestExpectedEqual} || std.json.ParseError(std.json.Scanner))!void {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    if (A != std.json.Value) {
        if (comptime !std.meta.trait.isZigString(A)) {
            const a_str = std.json.stringifyAlloc(std.testing.allocator, a, .{}) catch |err| @panic(@errorName(err));
            defer std.testing.allocator.free(a_str);
            return expectEqual(a_str, b, options);
        }
        const a_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, a, options);
        defer a_json.deinit();
        return expectEqual(a_json.value, b, options);
    }

    if (B != std.json.Value) {
        if (comptime !std.meta.trait.isZigString(B)) {
            const b_str = std.json.stringifyAlloc(std.testing.allocator, b, .{}) catch |err| @panic(@errorName(err));
            defer std.testing.allocator.free(b_str);
            return expectEqual(a, b_str, options);
        }
        const b_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, b, options);
        defer b_json.deinit();
        return expectEqual(a, b_json.value, options);
    }
    const expected_tag: @typeInfo(std.json.Value).Union.tag_type.? = a;

    try std.testing.expectEqual(expected_tag, b);
    switch (a) {
        .null => {},
        inline //
        .bool,
        .integer,
        .float,
        => |expected, tag| try std.testing.expectEqual(fmtStringify(expected, .{}), fmtStringify(@field(b, @tagName(tag)), .{})),

        inline //
        .number_string,
        .string,
        => |expected, tag| try std.testing.expectEqualStrings(expected, @field(b, @tagName(tag))),

        .array => |expected| {
            try std.testing.expectEqual(expected.items.len, b.array.items.len);
            const least = @min(expected.items.len, b.array.items.len);

            for (expected.items[0..least], b.array.items[0..least], 0..) |expected_item, actual_item, i| {
                errdefer std.log.err("Difference occurred between elements at index {d}", .{i});
                try expectEqual(expected_item, actual_item, options);
            }

            try std.testing.expectEqual(expected.items.len, b.array.items.len);
        },

        .object => |expected| {
            var iter = expected.iterator();
            while (iter.next()) |expected_entry| {
                errdefer std.log.err("Error occurred while comparing with expected field '{s}'", .{
                    expected_entry.key_ptr.*,
                });
                const actual_entry = b.object.getEntry(expected_entry.key_ptr.*) orelse {
                    return error.MissingField;
                };
                try std.testing.expectEqualStrings(expected_entry.key_ptr.*, actual_entry.key_ptr.*);
                try expectEqual(expected_entry.value_ptr.*, actual_entry.value_ptr.*, options);
            }
            try std.testing.expectEqual(expected.count(), b.object.count());
        },
    }
}

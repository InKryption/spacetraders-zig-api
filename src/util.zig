const std = @import("std");
const assert = std.debug.assert;

pub const DirectoryFilesContents = struct {
    content_buffer: std.ArrayListUnmanaged(u8) = .{},
    content_map: ContentMap = .{},

    pub const ContentRange = struct { usize, usize };
    pub const ContentMap = std.StringArrayHashMapUnmanaged(ContentRange);

    pub fn deinit(dfc: *DirectoryFilesContents, allocator: std.mem.Allocator) void {
        for (dfc.content_map.keys()) |key| allocator.free(key);
        dfc.content_map.deinit(allocator);
        dfc.content_buffer.deinit(allocator);
    }

    pub inline fn fileCount(dfc: DirectoryFilesContents) usize {
        return dfc.content_map.count();
    }

    pub inline fn get(dfc: DirectoryFilesContents, file_name: []const u8) ?[]const u8 {
        const range = dfc.content_map.get(file_name) orelse return null;
        return dfc.content_buffer.items[range[0]..range[1]];
    }

    pub inline fn iterator(dfc: *const DirectoryFilesContents) Iterator {
        return .{ .dfc = dfc };
    }
    pub const Iterator = struct {
        dfc: *const DirectoryFilesContents,
        index: usize = 0,

        pub const Entry = struct {
            key: []const u8,
            value: []const u8,
        };
        pub inline fn next(iter: *Iterator) ?Entry {
            if (iter.index >= iter.dfc.fileCount()) return null;
            defer iter.index += 1;
            const key = iter.dfc.content_map.keys()[iter.index];
            const value_range = iter.dfc.content_map.values()[iter.index];
            const value = iter.dfc.content_buffer.items[value_range[0]..value_range[1]];
            return Entry{ .key = key, .value = value };
        }
    };
};

/// Iterates and collects the contents of .json files from
/// the specified directory. The contents of said files
/// are all concatenated into a single buffer, and the ranges
/// pertaining to each file are returned as a hash map
/// alongside it.
pub inline fn jsonDirectoryFilesContents(
    allocator: std.mem.Allocator,
    dir: std.fs.IterableDir,
    it: *std.fs.IterableDir.Iterator,
    comptime log_scope: @TypeOf(.enum_literal),
) !DirectoryFilesContents {
    const log = std.log.scoped(log_scope);

    var contents_buffer = std.ArrayList(u8).init(allocator);
    defer contents_buffer.deinit();

    var content_map = std.StringArrayHashMapUnmanaged(DirectoryFilesContents.ContentRange){};
    defer for (content_map.keys()) |key| {
        allocator.free(key);
    } else content_map.deinit(allocator);

    while (try it.next()) |entry| {
        switch (entry.kind) {
            .File => {},

            .BlockDevice,
            .CharacterDevice,
            .Directory,
            .NamedPipe,
            .SymLink,
            .UnixDomainSocket,
            .Whiteout,
            .Door,
            .EventPort,
            .Unknown,
            => |tag| {
                log.warn("Encountered unexpected file type '{s}'", .{@tagName(tag)});
                continue;
            },
        }

        const ext = std.fs.path.extension(entry.name);
        if (!std.mem.eql(u8, ext, ".json")) continue;

        const gop = try content_map.getOrPut(allocator, entry.name);
        if (gop.found_existing) {
            log.err("Encountered '{s}' more than once", .{entry.name});
            continue;
        }
        errdefer assert(content_map.swapRemove(entry.name));

        const name = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(name);
        gop.key_ptr.* = name; // safe, because they will have the same hash (same string content)

        const file = try dir.dir.openFile(name, .{});
        defer file.close();

        const start = contents_buffer.items.len;
        try file.reader().readAllArrayList(&contents_buffer, 1 << 21);
        const end = contents_buffer.items.len;
        gop.value_ptr.* = .{ start, end };
    }

    return DirectoryFilesContents{
        .content_buffer = contents_buffer.moveToUnmanaged(),
        .content_map = content_map.move(),
    };
}

pub inline fn stripPrefix(comptime T: type, str: []const u8, prefix: []const T) ?[]const u8 {
    if (!std.mem.startsWith(T, str, prefix)) return null;
    return str[prefix.len..];
}

pub fn writePrefixedLines(writer: anytype, prefix: []const u8, lines: []const u8) !void {
    var iter = std.mem.tokenize(u8, lines, "\r\n");
    while (iter.next()) |line| {
        try writer.print("{s}{s}", .{ prefix, line });
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

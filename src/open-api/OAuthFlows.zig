const std = @import("std");

const util = @import("util");

const schema_tools = @import("schema-tools.zig");

const OAuthFlows = @This();

pub fn deinit(oauth_flows: OAuthFlows, allocator: std.mem.Allocator) void {
    _ = allocator;
    _ = oauth_flows;
}

pub fn jsonParseRealloc(
    result: *OAuthFlows,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    _ = options;
    _ = allocator;
    _ = result;
    @panic("TODO");
}

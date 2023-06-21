const std = @import("std");
const api = @import("api");

test {
    const get_status = api.ref.get_system_waypoints;
    try std.testing.expectFmt("/systems/system-symbol/waypoints?page=3", "{}{}", .{
        get_status.PathFmt{ .systemSymbol = "system-symbol" },
        get_status.QueryFmt{ .page = 3 },
    });
    try std.testing.expectFmt("/systems/system-symbol2/waypoints?page=3&limit=20", "{}{}", .{
        get_status.PathFmt{ .systemSymbol = "system-symbol2" },
        get_status.QueryFmt{ .page = 3, .limit = 20 },
    });
    try std.testing.expectFmt("/systems/system-symbol2/waypoints?limit=20", "{}{}", .{
        get_status.PathFmt{ .systemSymbol = "system-symbol2" },
        get_status.QueryFmt{ .limit = 20 },
    });
}

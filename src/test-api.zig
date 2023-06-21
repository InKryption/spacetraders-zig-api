const std = @import("std");
const api = @import("api");

test {
    const get_system_waypoints = api.ref.get_system_waypoints;
    try std.testing.expectFmt("/systems/system-symbol/waypoints?page=3", "{}{}", .{
        get_system_waypoints.PathFmt{ .systemSymbol = "system-symbol" },
        get_system_waypoints.QueryFmt{ .page = 3 },
    });
    try std.testing.expectFmt("/systems/system-symbol2/waypoints?page=3&limit=20", "{}{}", .{
        get_system_waypoints.PathFmt{ .systemSymbol = "system-symbol2" },
        get_system_waypoints.QueryFmt{ .page = 3, .limit = 20 },
    });
    try std.testing.expectFmt("/systems/system-symbol2/waypoints?limit=20", "{}{}", .{
        get_system_waypoints.PathFmt{ .systemSymbol = "system-symbol2" },
        get_system_waypoints.QueryFmt{ .limit = 20 },
    });
    try std.testing.expectFmt(
        \\GET /systems/system-symbol3/waypoints?limit=20 HTTP/1.1
        \\Content-Length: 0
        \\
    ,
        \\{s} {}{} {s}
        \\Content-Length: 0
        \\
    ,
        .{
            @tagName(get_system_waypoints.method),
            get_system_waypoints.PathFmt{ .systemSymbol = "system-symbol3" },
            get_system_waypoints.QueryFmt{ .limit = 20 },
            @tagName(std.http.Version.@"HTTP/1.1"),
        },
    );
}

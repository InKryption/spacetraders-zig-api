const std = @import("std");
const api = @import("api");

test {
    try std.testing.expectFmt("/systems?limit=20", "{}", .{
        api.ref.get_systems.RequestUri{
            .path = .{},
            .query = .{
                .limit = 20,
            },
        },
    });
    try std.testing.expectFmt("/systems/foo/waypoints/bar", "{}", .{
        api.ref.get_waypoint.RequestUri{
            .path = .{
                .systemSymbol = "foo",
                .waypointSymbol = "bar",
            },
            .query = .{},
        },
    });
    try std.testing.expectFmt("/factions?limit=7", "{}", .{
        api.ref.get_factions.RequestUri{
            .path = .{},
            .query = .{
                .limit = 7,
            },
        },
    });
    try std.testing.expectFmt("/my/contracts?page=3&limit=11", "{}", .{
        api.ref.get_contracts.RequestUri{
            .path = .{},
            .query = .{
                .page = 3,
                .limit = 11,
            },
        },
    });
}

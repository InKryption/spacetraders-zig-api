const std = @import("std");

const schema_tools = @import("schema-tools.zig");
const Link = @import("Link.zig");
const Reference = @import("Reference.zig");

pub const LinkOrRef = union(enum) {
    link: Link,
    reference: Reference,
};

const std = @import("std");

const schema_tools = @import("schema-tools.zig");
const Header = @import("Header.zig");
const Reference = @import("Reference.zig");

pub const HeaderOrRef = union(enum) {
    header: Header,
    reference: Reference,
};

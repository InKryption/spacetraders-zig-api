const std = @import("std");

const schema_tools = @import("schema-tools.zig");
const Example = @import("Example.zig");
const Reference = @import("Reference.zig");

pub const ExampleOrRef = union(enum) {
    example: Example,
    reference: Reference,
};

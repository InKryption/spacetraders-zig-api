const std = @import("std");

const schema_tools = @import("schema-tools.zig");

const Info = @This();
title: []const u8 = "",
summary: ?[]const u8 = null,
description: ?[]const u8 = null,
terms_of_service: ?[]const u8 = null,
contact: ?Contact = null,
license: ?License = null,
version: []const u8 = "",

pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Info, .{});
pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Info){
    .terms_of_service = "termsOfService",
};

pub fn deinit(self: Info, allocator: std.mem.Allocator) void {
    allocator.free(self.title);
    allocator.free(self.summary orelse "");
    allocator.free(self.description orelse "");
    allocator.free(self.terms_of_service orelse "");
    if (self.contact) |contact| contact.deinit(allocator);
    if (self.license) |license| license.deinit(allocator);
    allocator.free(self.version);
}

pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(
    Info,
    Info.json_field_names,
);

pub inline fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Info {
    var result: Info = Info.empty;
    errdefer result.deinit(allocator);
    try Info.jsonParseRealloc(&result, allocator, source, options);
    return result;
}
pub fn jsonParseRealloc(
    result: *Info,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!void {
    try schema_tools.jsonParseInPlaceTemplate(Info, result, allocator, source, options, Info.parseFieldValue);
}

pub inline fn parseFieldValue(
    comptime field_tag: std.meta.FieldEnum(Info),
    field_ptr: anytype,
    is_new: bool,
    ally: std.mem.Allocator,
    src: anytype,
    json_opt: std.json.ParseOptions,
) !void {
    _ = is_new;
    switch (field_tag) {
        .title,
        .summary,
        .description,
        .terms_of_service,
        .version,
        => {
            var str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
            defer str.deinit();
            field_ptr.* = "";
            try schema_tools.jsonParseReallocString(&str, src, json_opt);
            field_ptr.* = try str.toOwnedSlice();
        },
        .contact => {
            if (field_ptr.* == null) {
                field_ptr.* = .{};
            }
            const ptr = &field_ptr.*.?;
            try Contact.jsonParseRealloc(ptr, ally, src, json_opt);
        },
        .license => {
            if (field_ptr.* == null) {
                field_ptr.* = .{};
            }
            const ptr = &field_ptr.*.?;
            try License.jsonParseRealloc(ptr, ally, src, json_opt);
        },
    }
}

pub const Contact = struct {
    name: ?[]const u8 = null,
    url: ?[]const u8 = null,
    email: ?[]const u8 = null,

    pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(Contact, .{});
    pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(Contact){};

    pub fn deinit(contact: Contact, allocator: std.mem.Allocator) void {
        allocator.free(contact.name orelse "");
        allocator.free(contact.url orelse "");
        allocator.free(contact.email orelse "");
    }

    pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(Contact, Contact.json_field_names);

    pub inline fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Contact {
        var result: Contact = Contact.empty;
        errdefer result.deinit(allocator);
        try Contact.jsonParseRealloc(&result, allocator, source, options);
        return result;
    }

    pub fn jsonParseRealloc(
        result: *Contact,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!void {
        try schema_tools.jsonParseInPlaceTemplate(Contact, result, allocator, source, options, Contact.parseFieldValue);
    }

    pub inline fn parseFieldValue(
        comptime field_tag: std.meta.FieldEnum(Contact),
        field_ptr: *std.meta.FieldType(Contact, field_tag),
        is_new: bool,
        ally: std.mem.Allocator,
        src: anytype,
        json_opt: std.json.ParseOptions,
    ) !void {
        _ = is_new;
        var str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
        defer str.deinit();
        field_ptr.* = "";
        try schema_tools.jsonParseReallocString(&str, src, json_opt);
        field_ptr.* = try str.toOwnedSlice();
    }
};

pub const License = struct {
    name: []const u8 = "",
    identifier: ?[]const u8 = null,
    url: ?[]const u8 = null,

    pub const json_required_fields = schema_tools.requiredFieldSetBasedOnOptionals(License, .{});
    pub const json_field_names = schema_tools.ZigToJsonFieldNameMap(License){};

    pub fn deinit(license: License, allocator: std.mem.Allocator) void {
        allocator.free(license.name);
        allocator.free(license.identifier orelse "");
        allocator.free(license.url orelse "");
    }

    pub const jsonStringify = schema_tools.generateJsonStringifyStructWithoutNullsFn(License, License.json_field_names);

    pub inline fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !License {
        var result: License = License.empty;
        errdefer result.deinit(allocator);
        try License.jsonParseRealloc(&result, allocator, source, options);
        return result;
    }

    pub fn jsonParseRealloc(
        result: *License,
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!void {
        try schema_tools.jsonParseInPlaceTemplate(License, result, allocator, source, options, License.parseFieldValue);
    }

    pub inline fn parseFieldValue(
        comptime field_tag: std.meta.FieldEnum(License),
        field_ptr: *std.meta.FieldType(License, field_tag),
        is_new: bool,
        ally: std.mem.Allocator,
        src: anytype,
        json_opt: std.json.ParseOptions,
    ) !void {
        _ = is_new;
        var str = std.ArrayList(u8).fromOwnedSlice(ally, @constCast(@as(?[]const u8, field_ptr.*) orelse ""));
        defer str.deinit();
        field_ptr.* = @field(License{}, @tagName(field_tag));
        try schema_tools.jsonParseReallocString(&str, src, json_opt);
        field_ptr.* = try str.toOwnedSlice();
    }
};

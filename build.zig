const std = @import("std");
const Build = std.Build;

const util = @import("src/util.zig");
const NumberFormat = @import("src/number-format.zig").NumberFormat;

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const number_format = b.option(NumberFormat, "number_format", "Use '[]const u8' to represent number fields instead of 'f64'.");
    const json_as_comment = b.option(bool, "json_as_comment", "Print json schema of types as comments on the outputted types.");

    const gen_types_exe = b.addExecutable(.{
        .name = "gen-api",
        .root_source_file = Build.FileSource.relative("src/gen-api.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(gen_types_exe);

    const git_clone_api_docs = b.addSystemCommand(&.{
        "git",
        "clone",
        "https://github.com/SpaceTradersAPI/api-docs.git",
    });
    const cloned_api_docs_path = git_clone_api_docs.addOutputFileArg("api-docs");

    const gen_types_exe_run = b.addRunArtifact(gen_types_exe);
    gen_types_exe_run.addArgs(&.{
        // zig fmt: off
        "--number-format", util.replaceScalarEnumTag(number_format orelse .number_string, '_', '-'),
        "--json-as-comment", if (json_as_comment orelse false) "true" else "false",
        "--apidocs-path",
        // zig fmt: on
    });
    gen_types_exe_run.addDirectorySourceArg(cloned_api_docs_path);
    const api_src_file = gen_types_exe_run.addPrefixedOutputFileArg("--output-path=", "api.zig");

    const exe_run_step = b.step("run", "Run gen-api.zig");
    exe_run_step.dependOn(&gen_types_exe_run.step);

    _ = b.addModule("api", .{
        .source_file = api_src_file,
    });
}

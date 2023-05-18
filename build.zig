const std = @import("std");
const Build = std.Build;

pub const apidocs = @import("apidocs");

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const number_as_string = b.option(bool, "number_as_string", "Use '[]const u8' to represent number fields instead of 'f64'.");
    const json_as_comment = b.option(bool, "json_as_comment", "Print json schema of types as comments on the outputted types.");
    _ = json_as_comment;

    const gen_types_exe = b.addExecutable(.{
        .name = "gen-api",
        .root_source_file = Build.FileSource.relative("src/gen-api.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(gen_types_exe);

    const gen_types_exe_run = b.addRunArtifact(gen_types_exe);
    gen_types_exe_run.addArgs(&.{ "--number-as-string", if (number_as_string orelse false) "true" else "false" });
    gen_types_exe_run.addArgs(&.{ "--json-as-comment", if (number_as_string orelse false) "true" else "false" });
    gen_types_exe_run.addArgs(&.{ "--models", apidocs.models_path });
    const api_src_file = gen_types_exe_run.addPrefixedOutputFileArg("--output-path=", "api-types.zig");

    const api_types_module = b.addModule("api-types", Build.CreateModuleOptions{
        .source_file = api_src_file,
        .dependencies = &.{},
    });
    _ = api_types_module;

    const exe_run_step = b.step("run", "Run gen-api.zig");
    exe_run_step.dependOn(&gen_types_exe_run.step);
}

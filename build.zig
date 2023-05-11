const std = @import("std");
const Build = std.Build;

const apidocs = @import("apidocs");

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const num_as_string = b.option(bool, "num_as_string", "Use '[]const u8' to represent number fields instead of 'f64'.");

    const gen_exe = b.addExecutable(.{
        .name = "generate-api-types",
        .root_source_file = Build.FileSource.relative("src/generate-api-types.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(gen_exe);

    const exe_run = b.addRunArtifact(gen_exe);
    // exe_run.step.dependOn(b.getInstallStep());
    exe_run.addArgs(&.{ "--num-as-string", if (num_as_string orelse false) "true" else "false" });
    exe_run.addArgs(&.{ "--models", apidocs.models_path });
    const api_src_file = exe_run.addPrefixedOutputFileArg("--output-path=", "api-types.zig");

    b.getInstallStep().dependOn(&b.addInstallFile(api_src_file, "api.zig").step);

    const api_types_module = b.addModule("api-types", Build.CreateModuleOptions{
        .source_file = api_src_file,
        .dependencies = &.{},
    });
    _ = api_types_module;

    const exe_run_step = b.step("run", "Run generate-api-types.zig");
    exe_run_step.dependOn(&exe_run.step);
}

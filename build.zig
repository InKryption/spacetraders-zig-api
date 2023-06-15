const std = @import("std");
const Build = std.Build;

const util = @import("src/util.zig");
const NumberFormat = @import("src/number-format.zig").NumberFormat;

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const number_format = b.option(NumberFormat, "number_format", "Use '[]const u8' to represent number fields instead of 'f64'.");
    const json_as_comment = b.option(bool, "json_as_comment", "Print json schema of types as comments on the outputted types.");
    const log_level = b.option(std.log.Level, "log_level", "Specifies the log level of the executable") orelse .warn;

    const gen_types_exe = b.addExecutable(.{
        .name = "gen-api",
        .root_source_file = Build.FileSource.relative("src/gen-api.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(gen_types_exe);

    if (b.option([]const u8, "apidocs", "Path to api-docs directory")) |apidocs_dir| {
        const gen_types_exe_run = b.addRunArtifact(gen_types_exe);
        gen_types_exe_run.addArgs(&.{
            "--number-format",   util.replaceScalarEnumTag(number_format orelse .number_string, '_', '-'),
            "--json-as-comment", if (json_as_comment orelse false) "true" else "false",
            "--log-level",       @tagName(log_level),
            "--apidocs-path",    apidocs_dir,
        });
        const api_src_file = gen_types_exe_run.addPrefixedOutputFileArg("--output-path=", "api.zig");

        _ = b.addModule("api", Build.CreateModuleOptions{
            .source_file = api_src_file,
            .dependencies = &.{},
        });
    }

    localTesting(b, gen_types_exe, number_format orelse .number_string, json_as_comment orelse false);
}

fn localTesting(
    b: *Build,
    gen_types_exe: *Build.Step.Compile,
    number_format: NumberFormat,
    json_as_comment: bool,
) void {
    const git_clone_api_docs = b.addSystemCommand(&.{
        "git",
        "clone",
        "https://github.com/SpaceTradersAPI/api-docs.git",
    });
    const cloned_api_docs_path = git_clone_api_docs.addOutputFileArg("");

    const test_gen_types_exe_run = b.addRunArtifact(gen_types_exe);
    test_gen_types_exe_run.addArgs(&.{
        "--number-format",   util.replaceScalarEnumTag(number_format, '_', '-'),
        "--json-as-comment", if (json_as_comment) "true" else "false",
    });
    test_gen_types_exe_run.addArg("--apidocs-path");
    test_gen_types_exe_run.addDirectorySourceArg(cloned_api_docs_path);

    const api_src_file = test_gen_types_exe_run.addPrefixedOutputFileArg("--output-path=", "api.zig");

    const test_install = b.step("test-install", "Generate the API and install the file");
    test_install.dependOn(&b.addInstallFile(api_src_file, "api.zig").step);
}

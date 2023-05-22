const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const log_level = b.option(std.log.Level, "log_level", "Specifies the log level of the executable") orelse .warn;

    const number_as_string = b.option(bool, "number_as_string", "Use '[]const u8' to represent number fields instead of 'f64'.");
    const json_as_comment = b.option(bool, "json_as_comment", "Print json schema of types as comments on the outputted types.");

    const gen_types_exe = b.addExecutable(.{
        .name = "gen-api",
        .root_source_file = Build.FileSource.relative("src/gen-api.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(gen_types_exe);

    const build_options = b.addOptions();
    gen_types_exe.addOptions("build-options", build_options);
    build_options.contents.writer().print(
        \\pub const log_level = .{s};
        \\
    , .{std.zig.fmtId(@tagName(log_level))}) catch |err| @panic(@errorName(err));

    if (b.option([]const u8, "apidocs", "Path to api-docs directory")) |apidocs_dir| {
        const gen_types_exe_run = b.addRunArtifact(gen_types_exe);
        gen_types_exe_run.addArgs(&.{ "--number-as-string", if (number_as_string orelse false) "true" else "false" });
        gen_types_exe_run.addArgs(&.{ "--json-as-comment", if (json_as_comment orelse false) "true" else "false" });
        gen_types_exe_run.addArgs(&.{ "--apidocs-path", apidocs_dir });
        const api_src_file = gen_types_exe_run.addPrefixedOutputFileArg("--output-path=", "api.zig");

        const exe_run_step = b.step("run", "Run gen-api.zig");
        exe_run_step.dependOn(&gen_types_exe_run.step);

        _ = b.addModule("api", Build.CreateModuleOptions{
            .source_file = api_src_file,
            .dependencies = &.{},
        });
    }

    const cloned_api_docs_path = b.cache_root.join(b.allocator, &.{"api-docs"}) catch unreachable;
    const git_clone_api_docs = b.addSystemCommand(&.{
        "git",
        "clone",
        "https://github.com/SpaceTradersAPI/api-docs.git",
        cloned_api_docs_path,
    });

    const test_gen_types_exe_run = b.addRunArtifact(gen_types_exe);
    if (if (std.fs.cwd().access(cloned_api_docs_path, .{})) |_| false else |_| true)
        test_gen_types_exe_run.step.dependOn(&git_clone_api_docs.step);

    test_gen_types_exe_run.addArgs(&.{ "--number-as-string", if (number_as_string orelse false) "true" else "false" });
    test_gen_types_exe_run.addArgs(&.{ "--json-as-comment", if (json_as_comment orelse false) "true" else "false" });
    test_gen_types_exe_run.addArgs(&.{ "--apidocs-path", cloned_api_docs_path });
    const api_src_file = test_gen_types_exe_run.addPrefixedOutputFileArg("--output-path=", "api.zig");

    const test_install = b.step("test-install", "Generate the API and install the file");
    test_install.dependOn(&b.addInstallFile(api_src_file, "api.zig").step);
}

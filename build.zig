const std = @import("std");
const Build = std.Build;

const util = @import("src/util.zig");
pub const NumberFormat = @import("src/number-format.zig").NumberFormat;

pub const RunGeneratorArgs = struct {
    number_format: NumberFormat,
    json_as_comment: bool,
    log_level: std.log.Level,
    /// file source representing the spacetraders API spec folder
    apidocs_dir: Build.FileSource,
    /// name of the output file
    output_name: []const u8 = "api.zig",
};
pub fn runGenerator(
    /// assumed to be `b.addRunArtifact(b.dependency("<spacetraders alias>").artifact("gen-api"))`
    generator: *Build.Step.Run,
    args: RunGeneratorArgs,
) Build.FileSource {
    generator.addArg("--apidocs-path");
    generator.addDirectorySourceArg(args.apidocs_dir);

    generator.addArgs(&.{
        "--number-format",   @tagName(util.ReplaceEnumTagScalar(NumberFormat, '_', '-').make(args.number_format)),
        "--json-as-comment", if (args.json_as_comment) "true" else "false",
        "--log-level",       @tagName(args.log_level),
    });

    return generator.addPrefixedOutputFileArg("--output-path=", args.output_name);
}

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const number_format = b.option(NumberFormat, "number_format", "Use '[]const u8' to represent number fields instead of 'f64'.") orelse .number_string;
    const json_as_comment = b.option(bool, "json_as_comment", "Print json schema of types as comments on the outputted types.") orelse false;
    const log_level = b.option(std.log.Level, "log_level", "Specifies the log level of the executable") orelse .warn;

    const generate_api = b.addExecutable(.{
        .name = "gen-api",
        .root_source_file = Build.FileSource.relative("src/gen-api.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(generate_api);

    const generated_api_src =
        if (b.option([]const u8, "apidocs", "Path to api-docs directory")) |apidocs_dir|
    blk: {
        const generate_api_run = b.addRunArtifact(generate_api);
        break :blk runGenerator(generate_api_run, .{
            .number_format = number_format,
            .json_as_comment = json_as_comment,
            .log_level = log_level,
            .apidocs_dir = .{ .path = apidocs_dir },
        });
    } else b.addWriteFiles().add("error.zig",
        \\comptime {
        \\    @compileError("Pass the 'apidocs' build option in order to make the generated API available. Otherwise you should generate the API manually.");
        \\}
        \\
    );

    _ = b.addModule("api", Build.CreateModuleOptions{
        .source_file = generated_api_src,
        .dependencies = &.{},
    });

    localTesting(
        b,
        generate_api,
        number_format,
        json_as_comment,
        log_level,
        target,
        optimize,
    );
}

fn localTesting(
    b: *Build,
    generate_api: *Build.Step.Compile,
    number_format: NumberFormat,
    json_as_comment: bool,
    log_level: std.log.Level,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const git_clone_api_docs = b.addSystemCommand(&.{
        "git",
        "clone",
        "https://github.com/SpaceTradersAPI/api-docs.git",
    });
    const apidocs_dir = git_clone_api_docs.addOutputFileArg("");

    const generate_api_run = b.addRunArtifact(generate_api);
    const api_src_file = runGenerator(generate_api_run, .{
        .number_format = number_format,
        .json_as_comment = json_as_comment,
        .log_level = log_level,
        .apidocs_dir = apidocs_dir,
    });

    const test_install = b.step("test-install", "Generate the API and install the file");
    const install_file = b.addInstallFile(api_src_file, "api.zig");
    test_install.dependOn(&install_file.step);

    const test_exe = b.addTest(Build.TestOptions{
        .root_source_file = Build.FileSource.relative("src/test-api.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_exe.addAnonymousModule("api", Build.CreateModuleOptions{
        .source_file = api_src_file,
    });

    const run_test_exe = b.addRunArtifact(test_exe);
    const test_api_step = b.step("test-api", "Test the API");
    test_api_step.dependOn(&run_test_exe.step);
}

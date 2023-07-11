const std = @import("std");
const Build = std.Build;

const util = @import("src/util/util.zig");
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
        "--number-format",   @tagName(util.enumSnakeToKebabCase(args.number_format)),
        "--json-as-comment", if (args.json_as_comment) "true" else "false",
        "--log-level",       @tagName(args.log_level),
    });

    return generator.addPrefixedOutputFileArg("--output-path ", args.output_name);
}

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const number_format = b.option(NumberFormat, "number_format", "Use '[]const u8' to represent number fields instead of 'f64'.") orelse .number_string;
    const json_as_comment = b.option(bool, "json_as_comment", "Print json schema of types as comments on the outputted types.") orelse false;
    const log_level = b.option(std.log.Level, "log_level", "Specifies the log level of the executable") orelse .warn;

    const util_mod = b.createModule(Build.CreateModuleOptions{
        .source_file = Build.FileSource.relative("src/util/util.zig"),
    });

    const generate_api = b.addExecutable(.{
        .name = "gen-api",
        .root_source_file = Build.FileSource.relative("src/gen-api.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(generate_api);
    generate_api.addModule("util", util_mod);

    const generated_api_src = if (b.option([]const u8, "apidocs", "Path to api-docs directory")) |apidocs_dir|
        runGenerator(b.addRunArtifact(generate_api), .{
            .number_format = number_format,
            .json_as_comment = json_as_comment,
            .log_level = log_level,
            .apidocs_dir = .{ .path = apidocs_dir },
        })
    else
        b.addWriteFiles().add("error.zig",
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
    const test_api_step = b.step("test-api", "Test the API");
    const test_install_step = b.step("test-install", "Generate the API and install the file");
    const test_openapi_step = b.step("test-openapi", "Run tests for the in-house OpenAPI json schema");

    // git clone api-docs
    const git_clone_api_docs = b.addSystemCommand(&.{
        "git",
        "clone",
        "https://github.com/SpaceTradersAPI/api-docs.git",
    });
    git_clone_api_docs.addCheck(Build.Step.Run.StdIo.Check{
        .expect_stderr_match = b.fmt("Cloning into '{s}", .{
            b.cache_root.join(b.allocator, &.{"o"}) catch |err| @panic(@errorName(err)),
        }),
    });
    const apidocs_dir = git_clone_api_docs.addOutputFileArg("");

    // generate api
    const api_src_file = runGenerator(b.addRunArtifact(generate_api), .{
        .number_format = number_format,
        .json_as_comment = json_as_comment,
        .log_level = log_level,
        .apidocs_dir = apidocs_dir,
    });
    const api_mod = b.createModule(.{
        .source_file = api_src_file,
    });

    // test-install
    const install_file = b.addInstallFile(api_src_file, "api.zig");
    test_install_step.dependOn(&install_file.step);

    // test-api
    const test_api = b.addTest(Build.TestOptions{
        .root_source_file = Build.FileSource.relative("src/test-api.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_api.addModule("api", api_mod);
    const run_test_api = b.addRunArtifact(test_api);
    test_api_step.dependOn(&run_test_api.step);

    const test_openapi = b.addTest(Build.TestOptions{
        .root_source_file = Build.FileSource.relative("src/open-api/OpenAPI.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_openapi.addAnonymousModule("util", .{
        .source_file = Build.FileSource.relative("src/util/util.zig"),
    });
    test_openapi.addAnonymousModule("SpaceTraders.json", .{
        .source_file = relativeFileSource(b, apidocs_dir, "reference/SpaceTraders.json"),
    });
    const run_test_openapi = b.addRunArtifact(test_openapi);
    test_openapi_step.dependOn(&run_test_openapi.step);
}

fn relativeFileSource(b: *Build, path: Build.FileSource, relative: []const u8) Build.FileSource {
    const RelativeStep = struct {
        step: Build.Step,
        base: Build.FileSource,
        relative: []const u8,
        generated: Build.GeneratedFile,

        fn make(step: *Build.Step, prog_node: *std.Progress.Node) anyerror!void {
            _ = prog_node;
            const self = @fieldParentPtr(@This(), "step", step);
            self.generated.path = step.owner.pathJoin(&.{ self.base.getPath(step.owner), self.relative });
        }
    };
    const relative_step: *RelativeStep = b.allocator.create(RelativeStep) catch |err| @panic(@errorName(err));
    relative_step.* = .{
        .step = Build.Step.init(Build.Step.StepOptions{
            .id = .custom,
            .name = b.fmt("make path relative to {s}", .{path.getDisplayName()}),
            .owner = b,
            .makeFn = RelativeStep.make,
        }),
        .base = path,
        .relative = b.dupe(relative),
        .generated = Build.GeneratedFile{
            .step = &relative_step.step,
        },
    };
    path.addStepDependencies(&relative_step.step);
    return Build.FileSource{
        .generated = &relative_step.generated,
    };
}

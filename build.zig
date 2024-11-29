const std = @import("std");

pub fn build(b: *std.Build) !void {
    // Xsummer build
    const xsummer_build = b.addSystemCommand(&.{
        "cd", "xsummer", "&&", "zig", "build",
    });
    xsummer_build.setName("xsummer-build");

    // Yclient build
    const yclient_build = b.addSystemCommand(&.{
        "cargo",           "build",
        "--manifest-path", "yclient/Cargo.toml",
    });
    yclient_build.setName("yclient-build");

    // Clean commands
    const xsummer_clean = b.addSystemCommand(&.{
        "rm",                 "-rf",
        "xsummer/.zig-cache", "xsummer/zig-out",
    });

    const yclient_clean = b.addSystemCommand(&.{
        "cargo",           "clean",
        "--manifest-path", "yclient/Cargo.toml",
    });

    // Run commands
    const xsummer_run = b.addSystemCommand(&.{
        "cd", "xsummer", "&&", "zig", "build", "run",
    });

    const yclient_run = b.addSystemCommand(&.{
        "cargo",           "run",
        "--manifest-path", "yclient/Cargo.toml",
    });

    // Individual project steps
    const xsummer_step = b.step("xsummer", "Build only xsummer");
    xsummer_step.dependOn(&xsummer_build.step);

    const yclient_step = b.step("yclient", "Build only yclient");
    yclient_step.dependOn(&yclient_build.step);

    // Clean steps
    const clean_step = b.step("clean", "Clean all build artifacts");
    clean_step.dependOn(&xsummer_clean.step);
    clean_step.dependOn(&yclient_clean.step);

    // Run steps
    const run_step = b.step("run", "Run all projects");
    run_step.dependOn(&xsummer_run.step);
    run_step.dependOn(&yclient_run.step);

    // Main build step
    const build_step = b.step("build", "Build all projects");
    build_step.dependOn(&xsummer_build.step);
    build_step.dependOn(&yclient_build.step);

    // Make build the default step
    b.default_step = build_step;
}

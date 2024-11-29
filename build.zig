const std = @import("std");
const zcc = @import("compile_commands");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Keep track of targets for compile_commands
    var targets = std.ArrayList(*std.Build.Step.Compile).init(b.allocator);
    defer targets.deinit();

    // Create library
    const runtime_lib = b.addStaticLibrary(.{
        .name = "runtime",
        .target = target,
        .optimize = optimize,
    });

    try targets.append(runtime_lib);

    // Common C flags for both library and client
    const c_flags = [_][]const u8{
        "-Wall",
        "-Wextra",
        "-pedantic",
        "-I./include",
    };

    // Add library source files with flags
    runtime_lib.addCSourceFiles(.{
        .files = &.{
            "src/core.c",
            "src/messaging.c",
            "src/foundation.c",
        },
        .flags = &c_flags,
    });

    // Link with Foundation framework for macOS
    runtime_lib.linkFramework("Foundation");

    // Create client executable
    const client = b.addExecutable(.{
        .name = "client",
        .target = target,
        .optimize = optimize,
    });

    try targets.append(client);

    // Add client source files with flags
    client.addCSourceFiles(.{
        .files = &.{
            "src/client.c",
        },
        .flags = &c_flags,
    });

    // Link with our runtime library
    client.linkLibrary(runtime_lib);

    // Link with Foundation framework for client
    client.linkFramework("Foundation");

    // Install the client binary
    b.installArtifact(client);

    // Add "run" step
    const run_cmd = b.addRunArtifact(client);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the client");
    run_step.dependOn(&run_cmd.step);

    // Add compile_commands.json generation step
    zcc.createStep(b, "cdb", try targets.toOwnedSlice());
}

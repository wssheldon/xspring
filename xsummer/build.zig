const std = @import("std");
const zcc = @import("compile_commands");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Keep track of targets for compile_commands
    var targets = std.ArrayList(*std.Build.Step.Compile).init(b.allocator);
    defer targets.deinit();

    // Add obfuscation object
    const obf = b.addObject(.{
        .name = "obfuscate",
        .root_source_file = b.path("src/obf.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create library
    const runtime_lib = b.addStaticLibrary(.{
        .name = "runtime",
        .target = target,
        .optimize = optimize,
    });

    try targets.append(runtime_lib);

    const c_flags = [_][]const u8{
        "-Wall",
        "-Wextra",
        "-pedantic",
        "-fPIC",
        "-fvisibility=hidden",
        "-DDEBUG=1",
    };

    // Add include paths
    runtime_lib.addIncludePath(b.path("include"));
    runtime_lib.addIncludePath(b.path("include/runtime"));

    runtime_lib.addCSourceFiles(.{
        .files = &.{
            "src/core.c",
            "src/messaging.c",
            "src/foundation.c",
            "src/sysinfo.c",
            "src/network.c",
        },
        .flags = &c_flags,
    });

    runtime_lib.addObject(obf);
    runtime_lib.linkFramework("Foundation");

    const client = b.addExecutable(.{
        .name = "client",
        .target = target,
        .optimize = optimize,
    });

    try targets.append(client);

    // Add include paths for client
    client.addIncludePath(b.path("include"));
    client.addIncludePath(b.path("include/runtime"));

    client.addCSourceFiles(.{
        .files = &.{
            "src/client.c",
        },
        .flags = &c_flags,
    });

    client.linkLibrary(runtime_lib);
    client.linkFramework("Foundation");
    b.installArtifact(client);

    const run_cmd = b.addRunArtifact(client);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the client");
    run_step.dependOn(&run_cmd.step);

    zcc.createStep(b, "cdb", try targets.toOwnedSlice());
}

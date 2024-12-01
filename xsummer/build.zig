const std = @import("std");
const zcc = @import("compile_commands");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // keep track of targets for compile_commands
    var targets = std.ArrayList(*std.Build.Step.Compile).init(b.allocator);
    defer targets.deinit();

    // add obfuscation object
    const obf = b.addObject(.{
        .name = "obfuscate",
        .root_source_file = b.path("src/obf.zig"),
        .target = target,
        .optimize = optimize,
    });

    // create library
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
        "-std=c2x",
    };

    // add include paths
    runtime_lib.addIncludePath(b.path("include"));
    runtime_lib.addIncludePath(b.path("include/runtime"));

    // collect all C source files from src directory
    var src_files = std.ArrayList([]const u8).init(b.allocator);
    defer src_files.deinit();

    var dir = try std.fs.cwd().openDir("src", .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            const ext = std.fs.path.extension(entry.basename);
            if (std.mem.eql(u8, ext, ".c")) {
                const path = try std.fs.path.join(b.allocator, &.{ "src", entry.path });
                try src_files.append(path);
            }
        }
    }

    // use the collected files
    runtime_lib.addCSourceFiles(.{
        .files = src_files.items,
        .flags = &c_flags,
    });

    runtime_lib.addObject(obf);
    runtime_lib.linkFramework("Foundation");
    runtime_lib.linkFramework("CoreFoundation");

    const client = b.addExecutable(.{
        .name = "client",
        .target = target,
        .optimize = optimize,
    });

    try targets.append(client);

    // add include paths for client
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

